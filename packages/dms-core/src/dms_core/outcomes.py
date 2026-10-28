"""Deterministic debrief: dcs.log -> ``MissionOutcome`` -> campaign state (``Qualities``).

See docs/CONTRACTS.md "Debrief". Parsing and state updates are pure functions; only
``read_log`` / ``write_debrief`` touch the filesystem.
"""

from __future__ import annotations

import dataclasses
import json
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
    "LogIssue",
    "LogSession",
    "MalformedLine",
    "QualityChange",
    "StateUpdate",
    "already_debriefed",
    "apply_outcome",
    "build_outcome",
    "choose_next_mission",
    "default_log_paths",
    "derive_flags",
    "explicit_log_paths",
    "find_mission_session",
    "load_debrief_inputs",
    "mission_key",
    "missions_match",
    "outcome_path",
    "parse_sessions",
    "read_log",
    "requires_hold",
    "resolve_arc_mission",
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
) -> StateUpdate:
    """Pure: fold one flown mission into the campaign state (see CONTRACTS "Debrief")."""
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
    """Write state/outcomes/<mNN>.yaml and state/qualities.yaml; return the paths written."""
    out = outcome_path(campaign_dir, mission_id)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        _OUTCOME_HEADER + _dump(outcome.model_dump(mode="json", exclude_none=True)),
        encoding="utf-8",
        newline="\n",
    )
    q = campaign_dir / "state" / "qualities.yaml"
    q.write_text(
        _QUALITIES_HEADER + _dump(update.state.model_dump(mode="json")),
        encoding="utf-8",
        newline="\n",
    )
    return [out, q]


def already_debriefed(campaign_dir: Path, mission_id: str, outcome: MissionOutcome) -> bool:
    """True if state/outcomes/<mNN>.yaml records this same log file + session start."""
    p = outcome_path(campaign_dir, mission_id)
    if not p.is_file():
        return False
    try:
        old = MissionOutcome.model_validate(_load_yaml(p) or {})
    except ValueError:
        return False
    keys = ("log_file", "session_start")
    return all(old.extra.get(k) is not None for k in keys) and all(
        old.extra.get(k) == outcome.extra.get(k) for k in keys
    )
