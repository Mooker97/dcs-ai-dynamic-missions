"""Deterministic debrief: dcs.log -> ``MissionOutcome`` -> campaign state (``Qualities``).

See docs/CONTRACTS.md "Debrief". Parsing and state updates are pure functions; only
``read_log`` / ``write_debrief`` touch the filesystem.
"""

from __future__ import annotations

import dataclasses
import hashlib
import json
import os
import random
import re
from collections.abc import Callable, Iterable, Sequence
from pathlib import Path
from typing import Any

import yaml

from .schemas import CampaignArc, MissionOutcome, Qualities, Requires

__all__ = [
    "RESULT_FLAGS",
    "DebriefError",
    "EffectClause",
    "LogIssue",
    "LogSession",
    "MalformedLine",
    "QualityChange",
    "StateUpdate",
    "already_debriefed",
    "append_continuity",
    "apply_arc_effects",
    "apply_outcome",
    "build_outcome",
    "choose_next_mission",
    "commit_debrief",
    "condition_holds",
    "condition_keys",
    "continuity_entry",
    "default_log_paths",
    "derive_flags",
    "effect_facts",
    "explicit_log_paths",
    "find_mission_session",
    "load_debrief_inputs",
    "mission_key",
    "missions_match",
    "outcome_path",
    "parse_condition",
    "parse_quality_effect",
    "parse_sessions",
    "read_log",
    "requires_hold",
    "resolve_arc_mission",
    "rollback_previous",
    "session_hash",
    "upsert_continuity",
    "write_debrief",
]

#: Result flags that are mutually exclusive per mission (`<mNN>_<result>`).
RESULT_FLAGS = ("success", "failure", "partial", "aborted", "ended")

_TS_RE = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?)")
_LEVEL_RE = re.compile(r"^\S+ \S+\s+([A-Z_]+)\s")
_OUTCOME_RE = re.compile(r"\[DMS\.OUTCOME\]\s*(.*?)\s*$")
_BANNER_RE = re.compile(r"\[DMS\]\[Init\] DMS (\S+) started: mission=(\S+)")
_DMS_TAG_RE = re.compile(r"\[DMS\]\[([^\]]+)\]\s?(.*)$")
_LOG_OPENED = "=== Log opened"
_MAX_CONTINUATION = 8


class DebriefError(Exception):
    """A debrief cannot proceed (no log, no outcome for the mission, already debriefed...)."""


@dataclasses.dataclass(frozen=True)
class LogIssue:
    """A `[DMS]` WARNING/ERROR line (with any untimestamped continuation lines, e.g. tracebacks)."""

    line_no: int
    level: str
    module: str
    message: str
    timestamp: str | None

    def to_dict(self) -> dict[str, Any]:
        return {
            "line": self.line_no,
            "level": self.level,
            "module": self.module,
            "message": self.message,
            "timestamp": self.timestamp,
        }


@dataclasses.dataclass(frozen=True)
class MalformedLine:
    """A `[DMS.OUTCOME]` line whose payload could not be decoded into a MissionOutcome."""

    line_no: int
    reason: str


@dataclasses.dataclass
class LogSession:
    """One mission run inside a dcs.log (from a boundary to the next)."""

    start_line: int
    mission_id: str | None = None
    version: str | None = None
    start_timestamp: str | None = None
    records: list[MissionOutcome] = dataclasses.field(default_factory=list)
    issues: list[LogIssue] = dataclasses.field(default_factory=list)
    malformed: list[MalformedLine] = dataclasses.field(default_factory=list)

    def mission_ids(self) -> set[str]:
        ids = {r.mission_id for r in self.records if r.mission_id}
        if self.mission_id:
            ids.add(self.mission_id)
        return ids


@dataclasses.dataclass(frozen=True)
class QualityChange:
    """One applied (or skipped) quality delta."""

    quality: str
    before: int
    after: int
    delta: float
    reason: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "quality": self.quality,
            "from": self.before,
            "to": self.after,
            "delta": self.delta,
            "reason": self.reason,
        }


@dataclasses.dataclass(frozen=True)
class StateUpdate:
    """Result of folding one flown mission into the campaign state."""

    state: Qualities
    changes: list[QualityChange]
    flags_set: dict[str, bool]
    next_mission: str | None
    next_reason: str
    warnings: list[str]


# ---- log discovery ---------------------------------------------------------------------------


def default_log_paths(saved_games: Path | None = None) -> list[Path]:
    """Existing stable/openbeta ``dcs.log`` files, newest first, each followed by its ``.old``."""
    base = saved_games if saved_games is not None else Path.home() / "Saved Games"
    logs = [base / d / "Logs" / "dcs.log" for d in ("DCS", "DCS.openbeta")]
    existing = sorted((p for p in logs if p.is_file()), key=lambda p: p.stat().st_mtime)
    out: list[Path] = []
    for p in reversed(existing):
        out.append(p)
        old = p.with_name(p.name + ".old")
        if old.is_file():
            out.append(old)
    # A rotated log can exist without a current one (DCS is mid-launch).
    for p in logs:
        old = p.with_name(p.name + ".old")
        if old.is_file() and old not in out:
            out.append(old)
    return out


def explicit_log_paths(path: Path) -> list[Path]:
    """``--log PATH``: the file (or ``PATH/dcs.log`` for a directory), then its sibling ``.old``."""
    p = path / "dcs.log" if path.is_dir() else path
    out = [p] if p.is_file() else []
    old = p.with_name(p.name + ".old")
    if old.is_file() and not p.name.endswith(".old"):
        out.append(old)
    return out


def read_log(path: Path) -> str:
    """dcs.log text (UTF-8, undecodable bytes replaced)."""
    return path.read_text(encoding="utf-8", errors="replace")


# ---- parsing -----------------------------------------------------------------------------------


def missions_match(log_id: str | None, wanted: str) -> bool:
    """Exact id, or the same ``mNN`` prefix (``m01`` matches ``m01-first-light``)."""
    if not log_id:
        return False
    return log_id == wanted or mission_key(log_id) == mission_key(wanted)


def mission_key(mission_id: str) -> str:
    """``m01-first-light`` -> ``m01`` (the outcome file stem and flag prefix)."""
    return mission_id.split("-", 1)[0]


def _level(line: str) -> str | None:
    m = _LEVEL_RE.match(line)
    return m.group(1) if m else None


def parse_sessions(text: str) -> list[LogSession]:
    """Split dcs.log text into mission sessions with their outcome records and DMS issues."""
    sessions: list[LogSession] = [LogSession(start_line=1)]
    last_issue: tuple[LogSession, int] | None = None  # session + index of the issue to extend
    continuation = 0

    def new_session(line_no: int, ts: str | None) -> LogSession:
        cur = sessions[-1]
        if not cur.records and not cur.issues and not cur.malformed and cur.mission_id is None:
            cur.start_line, cur.start_timestamp = line_no, ts
            return cur
        s = LogSession(start_line=line_no, start_timestamp=ts)
        sessions.append(s)
        return s

    for line_no, line in enumerate(text.splitlines(), start=1):
        ts_m = _TS_RE.match(line)
        ts = ts_m.group(1) if ts_m else None
        if ts is None and last_issue is not None and line.strip():
            if continuation < _MAX_CONTINUATION:
                sess, idx = last_issue
                old = sess.issues[idx]
                sess.issues[idx] = dataclasses.replace(
                    old, message=old.message + "\n" + line.rstrip()
                )
                continuation += 1
            continue
        last_issue, continuation = None, 0

        if _LOG_OPENED in line:
            new_session(line_no, ts)
            continue
        banner = _BANNER_RE.search(line)
        if banner:
            s = new_session(line_no, ts)
            s.version, s.mission_id = banner.group(1), banner.group(2)
            continue
        if "[DMS.OUTCOME]" in line:
            _parse_outcome_line(line, line_no, ts, sessions, new_session)
            continue
        tag = _DMS_TAG_RE.search(line)
        if tag:
            level = _level(line) or ""
            module = tag.group(1)
            if level.startswith(("WARN", "ERROR")) or module == "safeCall":
                lvl = "ERROR" if level.startswith("ERROR") or module == "safeCall" else "WARNING"
                cur = sessions[-1]
                cur.issues.append(LogIssue(line_no, lvl, module, tag.group(2).rstrip(), ts))
                last_issue = (cur, len(cur.issues) - 1)
    return [s for s in sessions if s.records or s.issues or s.malformed or s.mission_id]


def _parse_outcome_line(
    line: str,
    line_no: int,
    ts: str | None,
    sessions: list[LogSession],
    new_session: Callable[[int, str | None], LogSession],
) -> None:
    m = _OUTCOME_RE.search(line)
    raw = m.group(1) if m else ""
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as exc:
        sessions[-1].malformed.append(MalformedLine(line_no, f"invalid JSON: {exc.msg}"))
        return
    if not isinstance(payload, dict):
        sessions[-1].malformed.append(MalformedLine(line_no, "payload is not a JSON object"))
        return
    try:
        rec = MissionOutcome.from_payload(payload, ts)
    except ValueError as exc:
        reason = str(exc).splitlines()[0]
        sessions[-1].malformed.append(MalformedLine(line_no, f"schema: {reason}"))
        return
    cur = sessions[-1]
    prev = next(
        (r for r in reversed(cur.records) if r.mission_id == rec.mission_id),
        None,
    )
    restarted = (
        prev is not None and prev.time is not None and rec.time is not None and rec.time < prev.time
    )
    other_mission = cur.mission_id is not None and rec.mission_id not in (None, cur.mission_id)
    if restarted or other_mission:
        cur = new_session(line_no, ts)
    if cur.mission_id is None:
        cur.mission_id = rec.mission_id
    cur.records.append(rec)


def find_mission_session(
    paths: Sequence[Path], mission_id: str, texts: dict[Path, str] | None = None
) -> tuple[Path, LogSession]:
    """Latest session for `mission_id` (exact id preferred) in the first log that has one.

    Raises DebriefError naming the files searched and the missions seen when nothing matches.
    """
    if not paths:
        raise DebriefError(
            "no dcs.log found (looked in Saved Games/DCS and DCS.openbeta); pass --log PATH"
        )
    seen: list[str] = []
    for path in paths:
        text = texts[path] if texts is not None and path in texts else read_log(path)
        sessions = parse_sessions(text)
        for exact in (True, False):
            for s in reversed(sessions):
                ids = s.mission_ids()
                hit = (
                    mission_id in ids if exact else any(missions_match(i, mission_id) for i in ids)
                )
                if hit:
                    if not s.records:
                        raise DebriefError(_no_records_msg(path, s, mission_id))
                    return path, s
        for s in sessions:
            seen.extend(sorted(s.mission_ids()))
    searched = ", ".join(str(p) for p in paths)
    found = ", ".join(dict.fromkeys(seen)) or "none"
    raise DebriefError(
        f"no [DMS.OUTCOME] lines for mission '{mission_id}' in: {searched} "
        f"(missions seen: {found}). Fly the mission (and debrief before relaunching DCS), "
        "pass --log, or debrief from the player questionnaire."
    )


def _no_records_msg(path: Path, s: LogSession, mission_id: str) -> str:
    errs = [i for i in s.issues if i.level == "ERROR"]
    tail = ""
    if errs:
        first = errs[0].message.splitlines()[0]
        tail = f"; {len(errs)} [DMS] error(s), first at line {errs[0].line_no}: {first}"
    if s.malformed:
        tail += f"; {len(s.malformed)} malformed [DMS.OUTCOME] line(s)"
    return (
        f"mission '{mission_id}' started in {path} (line {s.start_line}) but wrote no valid "
        f"[DMS.OUTCOME] lines{tail}"
    )


# ---- outcome -----------------------------------------------------------------------------------


def session_hash(records: Sequence[MissionOutcome]) -> str:
    """First 16 hex of the SHA-256 of ``records`` as canonical JSON (the re-debrief guard key)."""
    blob = json.dumps(
        [r.model_dump(mode="json") for r in records],
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    )
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()[:16]


def build_outcome(session: LogSession, mission_id: str, log_file: Path | None) -> MissionOutcome:
    """Merge a session's records for `mission_id` into one ``kind: summary`` MissionOutcome."""
    recs = [r for r in session.records if missions_match(r.mission_id, mission_id)]
    if not recs:
        raise DebriefError(f"session at line {session.start_line} has no outcome for {mission_id}")
    merged = recs[0]
    for r in recs[1:]:
        merged = merged.merge(r)
    ended = any(r.kind == "end" for r in recs)
    beats_fired = list(dict.fromkeys(b for r in recs for b in [*r.beats, r.beat] if b))
    extra: dict[str, Any] = {
        **merged.extra,
        "source": "dcs_log",
        "log_file": str(log_file) if log_file else None,
        "session_start": session.start_timestamp or recs[0].log_timestamp,
        "session_line": session.start_line,
        "session_hash": session_hash(recs),
        "dms_version": session.version,
        "records": len(recs),
        "ended": ended,
        "beats_fired": beats_fired,
        "log_errors": [i.to_dict() for i in session.issues if i.level == "ERROR"],
        "log_warnings": [i.to_dict() for i in session.issues if i.level != "ERROR"],
        "malformed_lines": [{"line": m.line_no, "reason": m.reason} for m in session.malformed],
    }
    return merged.model_copy(
        update={
            "kind": "summary",
            "beat": None,
            "beats": beats_fired,
            "mission_id": merged.mission_id or mission_id,
            "extra": extra,
        }
    )


# ---- arc quality_effects ---------------------------------------------------------------------

_PAREN_RE = re.compile(r"\([^)]*\)")
_ADD_RE = re.compile(r"^([+-]\d+)(?:\s+more)?\s+if\s+(.+)$")
_SET_RE = re.compile(r"^set\s+to\s+(-?\d+)\s+if\s+(.+)$")
_TERM_KEY_RE = re.compile(r"^(not\s+)?([a-z][a-z0-9_]*)$")
_TERM_CMP_RE = re.compile(r"^([a-z][a-z0-9_]*)\s*(>=|<=|==|!=|>|<)\s*(-?\d+(?:\.\d+)?)$")

#: Words of the condition grammar; never outcome keys.
_RESERVED = frozenset({"and", "or", "not"})
#: Words in a dropped parenthetical that mean it carried a limit or a condition.
_PAREN_MEANINGFUL_RE = re.compile(r"\b(min|max|only|or|and)\b", re.IGNORECASE)

#: One condition term: (outcome key, comparison op or "truthy", value, negated).
Term = tuple[str, str, float, bool]


@dataclasses.dataclass(frozen=True)
class EffectClause:
    """One machine-readable clause of an arc ``quality_effects`` value (CONTRACTS "Debrief")."""

    text: str
    op: str  # "add" | "set"
    amount: int
    any_of: tuple[tuple[Term, ...], ...]  # OR of AND-groups

    def holds(self, facts: dict[str, Any]) -> bool:
        return any(all(_term_holds(t, facts) for t in group) for group in self.any_of)


def _num(v: Any) -> float | None:
    if isinstance(v, bool | int | float):
        return float(v)
    return None


def _term_holds(term: Term, facts: dict[str, Any]) -> bool:
    key, op, value, negated = term
    v = facts.get(key)
    n = _num(v)
    if op == "truthy":
        truth = (n > 0) if n is not None else bool(v)
        return truth != negated
    return _compare(n if n is not None else 0.0, op, value)


def _parse_term(text: str) -> Term | None:
    t = text.strip()
    m = _TERM_KEY_RE.match(t)
    if m:
        if m.group(2) in _RESERVED:
            return None
        return m.group(2), "truthy", 0.0, bool(m.group(1))
    m = _TERM_CMP_RE.match(t)
    if m:
        if m.group(1) in _RESERVED:
            return None
        return m.group(1), m.group(2), float(m.group(3)), False
    return None


def _parse_condition(text: str) -> tuple[tuple[Term, ...], ...] | None:
    groups: list[tuple[Term, ...]] = []
    for alt in re.split(r"\s+or\s+", text.strip()):
        terms: list[Term] = []
        for part in re.split(r"\s+and\s+", alt.strip()):
            term = _parse_term(part)
            if term is None:
                return None
            terms.append(term)
        groups.append(tuple(terms))
    return tuple(groups)


#: A parsed condition: OR of AND-groups of terms (see :func:`parse_condition`).
Condition = tuple[tuple[Term, ...], ...]


def parse_condition(text: str) -> Condition | None:
    """Parse a ``quality_effects`` condition (``a and not b or c >= 2``); ``None`` if invalid.

    Shared with the conditional briefing blocks (``dms_gen.builder.conditional``).
    """
    if not text.strip():
        return None
    return _parse_condition(text)


def condition_holds(cond: Condition, facts: dict[str, Any]) -> bool:
    """Evaluate a :func:`parse_condition` result against ``facts`` (missing keys are false/0)."""
    return any(all(_term_holds(t, facts) for t in group) for group in cond)


def condition_keys(cond: Condition) -> list[str]:
    """The outcome keys a condition reads, in first-use order."""
    return list(dict.fromkeys(t[0] for group in cond for t in group))


def parse_quality_effect(
    text: str, notes: list[str] | None = None
) -> tuple[list[EffectClause], list[str]]:
    """Split an arc ``quality_effects`` value into applicable clauses and unparsed clause texts.

    Parentheticals are dropped; one that carries a limit or condition (``min``/``max``/``only``/
    ``or``/``and``) is reported in ``notes`` (if given) so the debriefer judges it by hand.
    """
    clauses: list[EffectClause] = []
    unparsed: list[str] = []
    for raw in text.split(";"):
        if notes is not None:
            for paren in _PAREN_RE.findall(raw):
                if _PAREN_MEANINGFUL_RE.search(paren):
                    notes.append(
                        f'dropped parenthetical {paren} in "{raw.strip()}" is not applied '
                        "by code; check it by hand"
                    )
        clause = " ".join(_PAREN_RE.sub(" ", raw).split())
        if not clause:
            continue
        op = "add"
        m = _ADD_RE.match(clause)
        if m is None:
            op, m = "set", _SET_RE.match(clause)
        cond = _parse_condition(m.group(2)) if m else None
        if m is None or cond is None:
            unparsed.append(raw.strip())
            continue
        clauses.append(EffectClause(clause, op, int(m.group(1)), cond))
    return clauses, unparsed


def apply_arc_effects(
    arc: CampaignArc,
    mission_id: str,
    facts: dict[str, Any],
    values: dict[str, int],
    skip: Iterable[str] = (),
) -> tuple[dict[str, int], list[QualityChange], list[str]]:
    """Pure: apply the flown mission's machine-readable arc ``quality_effects`` to ``values``.

    ``skip`` = qualities the beats already moved (their arc effects are not applied twice).
    Returns (new values, changes, warnings).
    """
    entry = next((m for m in arc.all_missions() if m.id == mission_id), None)
    out = dict(values)
    changes: list[QualityChange] = []
    warnings: list[str] = []
    if entry is None:
        return out, changes, warnings
    defs = {q.id: q for q in arc.qualities}
    skipped = set(skip)
    for q, text in entry.quality_effects.items():
        if q not in defs:
            warnings.append(f"arc quality_effects: quality '{q}' is not declared; not applied")
            continue
        if q in skipped:
            warnings.append(
                f"arc quality_effects for '{q}' not applied: the beats already reported a "
                f"qualityDelta for it (check by hand: {text})"
            )
            continue
        notes: list[str] = []
        clauses, unparsed = parse_quality_effect(text, notes)
        for u in unparsed:
            warnings.append(f"arc quality_effects '{q}' not machine-readable, judge by hand: {u}")
        warnings.extend(f"arc quality_effects '{q}': {n}" for n in notes)
        qd = defs[q]
        for c in clauses:
            missing = [k for k in condition_keys(c.any_of) if k not in facts]
            if missing:
                warnings.append(
                    f"arc quality_effects '{q}': key(s) {', '.join(missing)} not in this flight's "
                    f'outcome facts (counted as false/0) in "{c.text}"'
                )
            if not c.holds(facts):
                continue
            before = out.get(q, qd.initial)
            raw = c.amount if c.op == "set" else before + c.amount
            after = max(qd.min, min(qd.max, raw))
            reason = f'arc quality_effects: "{c.text}"'
            if after != raw:
                reason += f" (clamped to [{qd.min}, {qd.max}])"
            out[q] = after
            if after != before:
                changes.append(QualityChange(q, before, after, float(after - before), reason))
    return out, changes, warnings


# ---- campaign state ----------------------------------------------------------------------------


def derive_flags(mission_id: str, outcome: MissionOutcome) -> dict[str, bool]:
    """``<mNN>_<key>`` flags from outcome facts, plus ``<mNN>_<result>`` (others false)."""
    key = mission_key(mission_id)
    flags: dict[str, bool] = {}
    for k, v in outcome.outcomes.items():
        if isinstance(v, bool):
            flags[f"{key}_{k}"] = v
        elif isinstance(v, int | float):
            flags[f"{key}_{k}"] = v > 0
        else:
            flags[f"{key}_{k}"] = True
    if outcome.result:
        for r in RESULT_FLAGS:
            flags[f"{key}_{r}"] = False
        flags[f"{key}_{outcome.result}"] = True
    return flags


def effect_facts(outcome: MissionOutcome) -> dict[str, Any]:
    """Facts for arc ``quality_effects``: outcome keys + ``result``/``success``/``failure``."""
    facts: dict[str, Any] = dict(outcome.outcomes)
    if outcome.result:
        facts["result"] = outcome.result
        facts["success"] = outcome.result == "success"
        facts["failure"] = outcome.result == "failure"
    return facts


def _compare(a: float, op: str, b: float) -> bool:
    return {
        "==": a == b,
        "!=": a != b,
        ">": a > b,
        ">=": a >= b,
        "<": a < b,
        "<=": a <= b,
    }[op]


def requires_hold(
    req: Requires,
    flags: dict[str, bool],
    values: dict[str, int],
    beats: Iterable[str] = (),
    rng: random.Random | None = None,
) -> tuple[bool, str]:
    """Evaluate a branch `when` against campaign state. Returns (holds, why)."""
    fired = set(beats)
    for f in req.flags:
        if not flags.get(f, False):
            return False, f"flag {f} not set"
    for f in req.flags_not:
        if flags.get(f, False):
            return False, f"flag {f} is set"
    for qc in req.qualities:
        v = values.get(qc.quality, 0)
        if not _compare(v, qc.op, qc.value):
            return False, f"{qc.quality}={v} fails {qc.op} {qc.value:g}"
    for b in req.beats_fired:
        if b not in fired:
            return False, f"beat {b} did not fire"
    for b in req.beats_not_fired:
        if b in fired:
            return False, f"beat {b} fired"
    if req.chance < 100:
        roll = (rng or random.Random()).randint(1, 100)
        if roll > req.chance:
            return False, f"chance {req.chance}% failed (rolled {roll})"
        return True, f"chance {req.chance}% passed (rolled {roll})"
    return True, "conditions hold"


def resolve_arc_mission(arc: CampaignArc, mission: str) -> str | None:
    """Arc mission id for ``m01`` / ``m01-first-light`` (exact first, then ``mNN`` prefix)."""
    ids = [m.id for m in arc.all_missions()]
    if mission in ids:
        return mission
    hits = [i for i in ids if mission_key(i) == mission_key(mission)]
    return hits[0] if len(hits) == 1 else None


def choose_next_mission(
    arc: CampaignArc,
    mission_id: str,
    flags: dict[str, bool],
    values: dict[str, int],
    beats: Iterable[str] = (),
    rng: random.Random | None = None,
) -> tuple[str | None, str]:
    """First matching branch of the flown mission, else the next non-optional mission in order."""
    missions = arc.all_missions()
    idx = next((i for i, m in enumerate(missions) if m.id == mission_id), None)
    if idx is None:
        return None, f"mission {mission_id} is not in arc.yaml"
    beat_list = list(beats)
    for n, br in enumerate(missions[idx].branches, start=1):
        ok, why = requires_hold(br.when, flags, values, beat_list, rng)
        if ok:
            desc = f": {br.description}" if br.description else ""
            return br.goto, f"branch {n} ({why}){desc}"
    for m in missions[idx + 1 :]:
        if not m.optional:
            return m.id, "next in order"
    return None, "end of arc (see ending_notes)"


def apply_outcome(
    state: Qualities,
    outcome: MissionOutcome,
    mission_id: str,
    arc: CampaignArc | None = None,
    rng: random.Random | None = None,
    *,
    arc_effects: bool = True,
    force_arc_effects: bool = False,
) -> StateUpdate:
    """Pure: fold one flown mission into the campaign state (see CONTRACTS "Debrief").

    Beat ``qualityDeltas`` first, then (``arc_effects``) the arc's machine-readable
    ``quality_effects`` for the qualities the beats did not move. Arc effects are skipped
    (warning) when the flight did not end, unless ``force_arc_effects``.
    """
    defs = {q.id: q for q in arc.qualities} if arc else {}
    values = dict(state.values)
    for qd in defs.values():
        values.setdefault(qd.id, qd.initial)
    changes: list[QualityChange] = []
    warnings: list[str] = []
    for q, delta in sorted(outcome.quality_deltas.items()):
        if arc is not None and q not in defs:
            warnings.append(f"quality '{q}' is not declared in arc.yaml; delta {delta:+g} skipped")
            continue
        before = values.get(q, 0)
        raw = before + round(delta)
        after = raw
        reason = f"beat quality_deltas {delta:+g}"
        if q in defs:
            after = max(defs[q].min, min(defs[q].max, raw))
            if after != raw:
                reason += f" (clamped to [{defs[q].min}, {defs[q].max}])"
        if delta != 0:
            values[q] = after
            changes.append(QualityChange(q, before, after, delta, reason))
    unended = outcome.result is None or outcome.extra.get("ended") is False
    if arc is not None and arc_effects and unended and not force_arc_effects:
        warnings.append(
            "arc quality_effects not applied: the flight did not end (no end line / no result); "
            "ask the player how it ended, then judge them by hand or rerun with "
            "--force-arc-effects"
        )
    elif arc is not None and arc_effects:
        moved = {q for q, d in outcome.quality_deltas.items() if d != 0}
        values, arc_changes, arc_warnings = apply_arc_effects(
            arc, mission_id, effect_facts(outcome), values, moved
        )
        changes.extend(arc_changes)
        warnings.extend(arc_warnings)
    flags_set = derive_flags(mission_id, outcome)
    flags = {**state.flags, **flags_set}
    if outcome.result is None:
        warnings.append("no result in the log (no kind=end line?): ask the player how it ended")
    next_id: str | None = None
    next_reason = "no arc.yaml"
    if arc is not None:
        next_id, next_reason = choose_next_mission(
            arc, mission_id, flags, values, outcome.beats, rng
        )
    new_state = state.model_copy(
        update={
            "values": values,
            "flags": flags,
            "outcomes": {**state.outcomes, mission_id: dict(outcome.outcomes)},
            "updated_after": mission_id,
            "next_mission": next_id,
        }
    )
    Qualities.model_validate(new_state.model_dump())
    return StateUpdate(new_state, changes, flags_set, next_id, next_reason, warnings)


# ---- files -------------------------------------------------------------------------------------


def _load_yaml(path: Path) -> Any:
    with path.open(encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def load_debrief_inputs(campaign_dir: Path) -> tuple[CampaignArc | None, Qualities]:
    """arc.yaml (if present) and state/qualities.yaml (seeded from the arc if missing)."""
    arc_path = campaign_dir / "arc.yaml"
    arc = CampaignArc.model_validate(_load_yaml(arc_path)) if arc_path.is_file() else None
    q_path = campaign_dir / "state" / "qualities.yaml"
    if q_path.is_file():
        state = Qualities.model_validate(_load_yaml(q_path) or {})
    else:
        state = Qualities(values={q.id: q.initial for q in arc.qualities} if arc else {})
    return arc, state


_QUALITIES_HEADER = (
    "# Current story state. Schema: schemas/qualities.schema.json (Qualities).\n"
    "# Written by `dms debrief` (dms_core.outcomes); flags are <mNN>_<key> from outcomes.\n"
)
_OUTCOME_HEADER = (
    "# Written by `dms debrief` from dcs.log [DMS.OUTCOME] lines.\n"
    "# Schema: schemas/mission-outcome.schema.json (MissionOutcome).\n"
)


def _dump(data: Any) -> str:
    return str(yaml.safe_dump(data, sort_keys=False, allow_unicode=True, default_flow_style=False))


def outcome_path(campaign_dir: Path, mission_id: str) -> Path:
    return campaign_dir / "state" / "outcomes" / f"{mission_key(mission_id)}.yaml"


def write_debrief(
    campaign_dir: Path, mission_id: str, outcome: MissionOutcome, update: StateUpdate
) -> list[Path]:
    """Write state/qualities.yaml then state/outcomes/<mNN>.yaml (see :func:`commit_debrief`)."""
    return commit_debrief(campaign_dir, mission_id, outcome, update)


def _previous_outcome(campaign_dir: Path, mission_id: str) -> MissionOutcome | None:
    p = outcome_path(campaign_dir, mission_id)
    if not p.is_file():
        return None
    try:
        return MissionOutcome.model_validate(_load_yaml(p) or {})
    except (ValueError, yaml.YAMLError):
        return None


def already_debriefed(campaign_dir: Path, mission_id: str, outcome: MissionOutcome) -> bool:
    """True if state/outcomes/<mNN>.yaml records this same flight (session start + records hash).

    The log file path is not compared (``dcs.log`` -> ``dcs.log.old`` rotation, path spelling).
    A file written before ``session_hash`` existed matches on ``session_start`` alone.
    """
    old = _previous_outcome(campaign_dir, mission_id)
    if old is None:
        return False
    new_start, new_hash = outcome.extra.get("session_start"), outcome.extra.get("session_hash")
    old_start, old_hash = old.extra.get("session_start"), old.extra.get("session_hash")
    if old_hash is not None and new_hash is not None:
        return bool(old_hash == new_hash and old_start == new_start)
    return old_start is not None and old_start == new_start


def rollback_previous(
    campaign_dir: Path, mission_id: str, state: Qualities, arc: CampaignArc | None
) -> tuple[Qualities, list[str]]:
    """Undo the previous debrief of this mission (``--force``): its ``quality_changes`` and flags.

    Each recorded change's ``to - from`` is subtracted (newest first) and clamped to the arc
    ``QualityDef``; its ``flags_set`` keys are removed. Returns (state, notes).
    """
    old = _previous_outcome(campaign_dir, mission_id)
    if old is None:
        return state, []
    defs = {q.id: q for q in arc.qualities} if arc else {}
    values = dict(state.values)
    notes: list[str] = []
    for ch in reversed(old.extra.get("quality_changes") or []):
        if not isinstance(ch, dict):
            continue
        q, frm, to = ch.get("quality"), ch.get("from"), ch.get("to")
        if not isinstance(q, str) or not isinstance(frm, int) or not isinstance(to, int):
            continue
        before = values.get(q, defs[q].initial if q in defs else 0)
        after = before - (to - frm)
        if q in defs:
            after = max(defs[q].min, min(defs[q].max, after))
        values[q] = after
        notes.append(f"rolled back previous debrief: {q} {before}->{after} (undo {frm}->{to})")
    flags = dict(state.flags)
    for f in old.extra.get("flags_set") or {}:
        flags.pop(f, None)
    outcomes_ = {k: v for k, v in state.outcomes.items() if k != mission_id}
    new_state = state.model_copy(update={"values": values, "flags": flags, "outcomes": outcomes_})
    return new_state, notes


def _marker(mission_id: str, outcome: MissionOutcome) -> str:
    h = outcome.extra.get("session_hash") or outcome.extra.get("session_start") or "unknown"
    return f"<!-- dms-debrief: {mission_key(mission_id)} {h} -->"


def continuity_entry(
    mission_id: str, outcome: MissionOutcome, update: StateUpdate, date: str
) -> str:
    """The factual continuity.md entry ``dms debrief`` appends (CONTRACTS "Debrief")."""
    ex = outcome.extra
    ended = "yes" if ex.get("ended") else "no (no end line: ask the player how it ended)"
    facts = ", ".join(f"{k}={json.dumps(v)}" for k, v in outcome.outcomes.items()) or "none"
    qc = (
        "; ".join(f"{c.quality} {c.before}→{c.after} ({c.reason})" for c in update.changes)
        or "no changes"
    )
    true_flags = [k for k, v in update.flags_set.items() if v]
    lines = [
        f"### {date} — dms debrief — {mission_id} flown ({outcome.result or 'unknown'})",
        _marker(mission_id, outcome),
        f"- Source: {ex.get('log_file')} (session {ex.get('session_start')}); ended: {ended}.",
        f"- Outcome: {facts}.",
        f"- Qualities: {qc}.",
        f"- Flags set: {', '.join(true_flags) or 'none'}.",
    ]
    lines += [f"- Debriefer to check: {w}" for w in update.warnings]
    errs = ex.get("log_errors") or []
    if errs:
        lines.append(f"- dcs.log: {len(errs)} [DMS] error(s), first: {errs[0].get('message')}")
    lines.append(f"- Next: {update.next_mission or '(end of arc)'} ({update.next_reason}).")
    return "\n".join(lines) + "\n"


def _read_text_keep_newlines(p: Path) -> tuple[str, str]:
    """(text with LF line ends, the file's newline: CRLF if it has any, else LF)."""
    if not p.is_file():
        return "", "\n"
    raw = p.read_bytes().decode("utf-8")
    nl = "\r\n" if "\r\n" in raw else "\n"
    return raw.replace("\r\n", "\n"), nl


def _atomic_write(p: Path, text: str, newline: str = "\n") -> None:
    """Write ``text`` (LF line ends) to ``p`` via a temp file + rename."""
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_name(p.name + ".tmp")
    with tmp.open("w", encoding="utf-8", newline=newline) as fh:
        fh.write(text)
    os.replace(tmp, p)


def _join_entry(old: str, entry: str) -> str:
    sep = "" if not old or old.endswith("\n\n") else ("\n" if old.endswith("\n") else "\n\n")
    return old + sep + entry


def _find_entry(lines: list[str], marker: str, heading: str, session: str | None) -> range | None:
    """Line range of an existing dms debrief entry for the same flight, if any."""
    for i, line in enumerate(lines):
        if not (line.startswith("### ") and heading in line):
            continue
        end = next((j for j in range(i + 1, len(lines)) if lines[j].startswith("#")), len(lines))
        body = lines[i + 1 : end]
        if marker in body or (
            session is not None and any(f"(session {session})" in b for b in body)
        ):
            while end > i + 1 and not lines[end - 1].strip():
                end -= 1
            return range(i, end)
    return None


def _continuity_text(
    campaign_dir: Path, entry: str, mission_id: str | None, outcome: MissionOutcome | None
) -> tuple[Path, str, str]:
    p = campaign_dir / "continuity.md"
    old, nl = _read_text_keep_newlines(p)
    if mission_id is not None and outcome is not None:
        lines = old.split("\n")
        hit = _find_entry(
            lines,
            _marker(mission_id, outcome),
            f"— dms debrief — {mission_id} flown",
            outcome.extra.get("session_start"),
        )
        if hit is not None:
            new_lines = [*lines[: hit.start], *entry.rstrip("\n").split("\n"), *lines[hit.stop :]]
            return p, "\n".join(new_lines), nl
    return p, _join_entry(old, entry), nl


def upsert_continuity(
    campaign_dir: Path, entry: str, mission_id: str, outcome: MissionOutcome
) -> Path:
    """Append ``entry``, or replace the same flight's earlier ``dms debrief`` entry in place."""
    p, text, nl = _continuity_text(campaign_dir, entry, mission_id, outcome)
    _atomic_write(p, text, nl)
    return p


def append_continuity(campaign_dir: Path, entry: str) -> Path:
    """Append ``entry`` to campaign_dir/continuity.md (created if missing), keeping its newlines."""
    p, text, nl = _continuity_text(campaign_dir, entry, None, None)
    _atomic_write(p, text, nl)
    return p


def commit_debrief(
    campaign_dir: Path,
    mission_id: str,
    outcome: MissionOutcome,
    update: StateUpdate,
    entry: str | None = None,
) -> list[Path]:
    """Write a debrief in a crash-safe order; return [outcome, qualities(, continuity)].

    Each file is atomic. Order: continuity.md (idempotent: same-flight entries are replaced),
    state/qualities.yaml, then state/outcomes/<mNN>.yaml last, since that file is the re-debrief
    guard: a failure before it leaves the flight un-guarded so a rerun redoes everything.
    """
    cont: Path | None = None
    if entry is not None:
        cont = upsert_continuity(campaign_dir, entry, mission_id, outcome)
    q = campaign_dir / "state" / "qualities.yaml"
    _atomic_write(q, _QUALITIES_HEADER + _dump(update.state.model_dump(mode="json")))
    out = outcome_path(campaign_dir, mission_id)
    _atomic_write(out, _OUTCOME_HEADER + _dump(outcome.model_dump(mode="json", exclude_none=True)))
    return [out, q, *([cont] if cont else [])]
