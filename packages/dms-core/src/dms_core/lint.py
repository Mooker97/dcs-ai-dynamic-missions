"""Mission-quality lint: design problems that make a mission bad, not just invalid.

Implements the checkable rules of ``docs/reference/mission-design-guide.md`` section 6 from the
YAML (mission-spec, beats, lines, bible, arc) plus the optional mission-folder files
(``briefing.md``, ``kneeboard.md``, ``voice/manifest.json``, ``out/plan.json``). Every finding is
a :class:`~dms_core.schemas.validation.Issue` with ``code`` (the rule id) and ``hint`` (the fix),
and its ``problem`` reads ``"[<code>] <message>. Fix: <hint>"`` so plain renderers show both.

Severities follow the guide; rules the guide does not mark as errors are warnings (or info), so
lint never fails a mission that only has style problems. ``dms validate --strict`` treats
warnings as errors.

Entry points: :func:`lint_mission` (one mission; arc rules scoped to that mission's arc entry),
:func:`lint_arc` (whole campaign arc) and :func:`load_mission_docs` (reads the optional files).
"""

from __future__ import annotations

import dataclasses
import itertools
import json
import re
from collections import defaultdict
from collections.abc import Iterable
from pathlib import Path
from typing import Any, Literal

import yaml

from .schemas.beats import Beat, BeatSheet
from .schemas.campaign import ArcMission, CampaignArc
from .schemas.mission import MissionSpec
from .schemas.story import StoryBible
from .schemas.validation import Issue
from .schemas.voice import VoiceLine, VoiceLineSet

Severity = Literal["error", "warning", "info"]

#: Rule id -> (severity, one-line summary). The table in docs/CONTRACTS.md mirrors this.
RULES: dict[str, tuple[Severity, str]] = {
    "spine_no_fallback": (
        "warning",
        "guaranteed beat waits on a kill/landing/flag with no timeout or sibling path",
    ),
    "guaranteed_on_takeoff": (
        "error",
        "guaranteed beat on unit.takeoff or a ramp-only zone while an air-start variant exists",
    ),
    "hook_late": ("warning", "first radio call more than 180 s after mission start"),
    "popup_no_telegraph": (
        "error",
        "ambush_sam/cap/waves encounter without a telegraph (unless notes 'no-cue:' + briefed)",
    ),
    "telegraph_too_short": (
        "warning",
        "telegraph beat delayed or gated so the 30-60 s warning can shrink or vanish",
    ),
    "line_too_long": (
        "warning",
        "line over the speaker's brevity limit (terse 12 / normal 20 / chatty 30) or over 8 s",
    ),
    "peak_chatter": ("warning", "line over 12 words on a beat that can fire mid-fight"),
    "callsign_first": ("warning", "radio line does not open with a callsign"),
    "banned_phrases": ("warning", "film-radio phrase or more than one '!'"),
    "brevity_misuse": (
        "warning",
        "'bulls', BRAA with 'for'/'at', tally/visual swapped, bingo/winchester from non-aircrew",
    ),
    "variants_too_similar": ("warning", "two variants of a beat are near-identical (Jaccard>0.8)"),
    "too_few_variants": ("warning", "repeatable beat (once: false) with fewer than 3 variants"),
    "reaction_no_cooldown": (
        "warning",
        "repeatable hit/shot/dead reaction with cooldown_sec under 30",
    ),
    "radio_density": (
        "warning",
        "more than 3 radio beats on one trigger, or over 25 s of radio in a 60 s window",
    ),
    "no_generic_fallback": (
        "info",
        "reactive event with only requires-gated beats and no generic fallback",
    ),
    "quality_swing": ("warning", "one mission can move a quality by more than +/-2"),
    "vul_overload": ("warning", "more than 6 encounters can be live in one mission"),
    "briefing_threat_mismatch": (
        "error",
        "visible or telegraphed threat not mentioned in briefing.md",
    ),
    "briefing_missing_sections": (
        "warning",
        "briefing.md lacks ## 1.-## 5., abort, bingo, expected duration or stakes",
    ),
    "kneeboard_contradiction": (
        "error",
        "laser code or frequency in briefing.md that kneeboard.md contradicts or omits",
    ),
    "kneeboard_too_long": ("warning", "kneeboard.md over 25 lines or without a comms table"),
    "transit_too_long": (
        "warning",
        "planned transit to the IP over 30 min (ramp) or 8 min (air start); needs out/plan.json",
    ),
    "failure_dead_end": (
        "error",
        "mission failure flag is read by no branch and not by the next mission",
    ),
    "branch_never_rejoins": (
        "warning",
        "optional (branch) mission does not reach a main-line mission within 2 hops",
    ),
    "intensity_streak": (
        "warning",
        "more than 2 intense missions in a row, or an act with no calm mission",
    ),
    "quality_unmoved": ("warning", "arc quality that no mission moves"),
    "quality_unread": ("warning", "arc quality that no branch, beat or briefing reads"),
}

#: Lines-per-second estimate when no voice manifest duration exists (guide: ~2.5 words/s).
WORDS_PER_SEC = 2.5
BREVITY_WORDS = {"terse": 12, "normal": 20, "chatty": 30}
MAX_LINE_SEC = 8.0
PEAK_WORDS = 12
DENSITY_WINDOW_SEC = 60.0
DENSITY_MAX_SEC = 25.0
HOOK_SEC = 180.0
MAX_ENCOUNTERS = 6
MAX_SWING = 2
TRANSIT_MAX_MIN = {"ramp": 30.0, "air": 8.0}

#: Events whose occurrence depends on what the player does (a kill, a landing, a flag set by one).
_STALL_EVENTS = {"group.dead", "unit.dead", "unit.landed", "encounter.cleared", "flag"}
#: Events that happen without player success (time, chains, positions) - fallback triggers.
_TIMELY_EVENTS = {"timer", "mission.start", "player.spawned", "beat.fired", "zone.entered"}
#: Events that typically fire mid-fight.
_FIGHT_EVENTS = {
    "unit.hit",
    "unit.shot",
    "unit.dead",
    "group.dead",
    "encounter.sam_hot",
    "encounter.wave",
    "encounter.proximity",
}
_POPUP_KINDS = {"ambush_sam", "cap", "waves"}
#: Pool roles that can engage the player's aircraft (a missing telegraph on these is an error).
_ANTI_AIR_ROLES = {"sam_short", "sam_medium", "sam_long", "aaa", "manpads", "fighters"}
_REACTION_EVENTS = {"unit.hit", "unit.shot", "unit.dead"}

_TAG_RE = re.compile(r"\[[^\]]*\]")
_WORD_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9'\-]*")
_NUMBER_WORDS = {
    "one",
    "two",
    "three",
    "four",
    "lead",
    "flight",
    "all",
    "break",
    "copy",
    "roger",
    "negative",
    "affirm",
    "check",
    "abort",
}

_BANNED: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"\bover and out\b", re.I), "'over and out' (over = reply expected, out = done)"),
    (re.compile(r"\bhell yeah\b", re.I), "'hell yeah'"),
    (re.compile(r"\blet'?s do this\b", re.I), "'let's do this'"),
    (re.compile(r"\broger that,? over\b", re.I), "'roger that, over'"),
    (re.compile(r"\bcopy that\b", re.I), "'copy that' (say 'copy' or acknowledge with callsign)"),
]
_BULLS_RE = re.compile(r"\bbulls\b(?!eye)", re.I)
_BRAA_RE = re.compile(r"\bBRAA\b[^.;]*?\b(for|at)\b", re.I)
_TALLY_FRIENDLY_RE = re.compile(r"\btally\b(?:\W+\w+){0,3}?\W+(friendl\w*|wingman|lead)\b", re.I)
_VISUAL_ENEMY_RE = re.compile(
    r"\bvisual\b(?:\W+\w+){0,3}?\W+(bandits?|hostiles?|enem\w+|targets?|sams?|tanks?)\b", re.I
)
_AIRCREW_ONLY_RE = re.compile(r"\b(winchester|bingo)\b", re.I)
_AIRCREW_ROLE_RE = re.compile(r"wingman|pilot|aircrew|lead|flight|crew|sandy|jolly|chalk", re.I)

_ROLE_WORDS: dict[str, list[str]] = {
    "aaa": ["aaa", "zu-23", "zsu", "shilka", "flak", "dshk", "s-60", "triple-a", "gun"],
    "manpads": ["manpads", "igla", "stinger", "strela", "sa-7", "sa-14", "sa-16", "sa-18"],
    "sam_short": ["sam", "sa-8", "sa-9", "sa-13", "sa-15", "sa-19", "tor", "osa", "tunguska"],
    "sam_medium": ["sam", "sa-6", "sa-11", "sa-17", "sa-3", "buk", "kub", "hawk"],
    "sam_long": ["sam", "sa-2", "sa-5", "sa-10", "sa-20", "s-300", "patriot"],
    "armor": ["armor", "armour", "tank", "t-55", "t-62", "t-72", "t-80", "bmp", "btr"],
    "ifv": ["ifv", "bmp", "btr", "apc", "armor", "armour", "bradley"],
    "technicals": ["technical", "dshk", "pickup"],
    "infantry": ["infantry", "troops", "rpg", "fighters", "teams", "squad"],
    "artillery": ["artillery", "mortar", "howitzer", "grad", "mlrs", "rocket"],
    "fighters": ["fighter", "bandit", "mig", "su-", "cap", "aircraft"],
    "attack_helicopters": ["helicopter", "helo", "hind", "mi-24", "mi-8", "ka-"],
    "ship": ["ship", "boat", "vessel", "frigate", "patrol"],
    "hvt": ["hvt", "high-value", "high value", "target"],
}


# ---- inputs -------------------------------------------------------------------------------------


@dataclasses.dataclass
class MissionDocs:
    """Optional files next to a mission that some rules read (all may be missing)."""

    briefing: str | None = None
    kneeboard: str | None = None
    durations: dict[str, float] = dataclasses.field(default_factory=dict)
    plan: dict[str, Any] | None = None
    arc: CampaignArc | None = None
    campaign_dir: Path | None = None


def _read(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8") if path.is_file() else None
    except OSError:
        return None


def _find_arc(start: Path) -> Path | None:
    for d in [start, *start.parents][:4]:
        p = d / "arc.yaml"
        if p.is_file():
            return p
    return None


def load_mission_docs(mission_dir: Path | None) -> MissionDocs:
    """Read briefing.md, kneeboard.md, voice/manifest.json, out/plan.json and the campaign arc.

    Unreadable or invalid optional files are skipped silently: schema problems in them are
    reported by ``dms validate`` on those files, not by lint.
    """
    docs = MissionDocs()
    if mission_dir is None:
        return docs
    docs.briefing = _read(mission_dir / "briefing.md")
    docs.kneeboard = _read(mission_dir / "kneeboard.md")
    manifest = _read(mission_dir / "voice" / "manifest.json")
    if manifest:
        try:
            data = json.loads(manifest)
        except ValueError:
            data = None
        if isinstance(data, dict):
            for lid, entry in data.items():
                dur = entry.get("dur_sec") if isinstance(entry, dict) else None
                if isinstance(dur, int | float) and dur > 0:
                    docs.durations[str(lid)] = float(dur)
    plan = _read(mission_dir / "out" / "plan.json")
    if plan:
        try:
            pdata = json.loads(plan)
        except ValueError:
            pdata = None
        if isinstance(pdata, dict):
            docs.plan = pdata
    arc_path = _find_arc(mission_dir.parent)
    if arc_path is not None:
        try:
            docs.arc = CampaignArc.model_validate(yaml.safe_load(arc_path.read_text("utf-8")))
            docs.campaign_dir = arc_path.parent
        except (ValueError, OSError, yaml.YAMLError):
            docs.arc = None
    return docs


# ---- helpers ------------------------------------------------------------------------------------


def _issue(
    code: str, path: str, message: str, hint: str, severity: Severity | None = None
) -> Issue:
    sev = severity or RULES[code][0]
    return Issue(
        path=path,
        problem=f"[{code}] {message}. Fix: {hint}",
        severity=sev,
        code=code,
        hint=hint,
    )


def _clean(text: str) -> str:
    return _TAG_RE.sub(" ", text)


def words(text: str) -> list[str]:
    """Spoken words of a line (v3 audio tags stripped)."""
    return _WORD_RE.findall(_clean(text))


def _as_list(v: str | list[str] | None) -> list[str]:
    if v is None:
        return []
    return [v] if isinstance(v, str) else list(v)


def _beat_texts(b: Beat, lines: dict[str, VoiceLine]) -> list[tuple[str, str]]:
    """(line id or '<text>', text) for each variant the beat can say."""
    out = [(lid, lines[lid].text) for lid in b.lines if lid in lines]
    if not out and b.text:
        out = [("text", b.text)]
    return out


def _line_sec(lid: str, text: str, durations: dict[str, float]) -> float:
    if lid in durations:
        return durations[lid]
    return len(words(text)) / WORDS_PER_SEC


def _beat_sec(b: Beat, lines: dict[str, VoiceLine], durations: dict[str, float]) -> float:
    texts = _beat_texts(b, lines)
    if not texts:
        return 0.0
    return sum(_line_sec(lid, t, durations) for lid, t in texts) / len(texts)


def _is_radio(b: Beat) -> bool:
    return bool(b.lines or b.text)


def _delay(b: Beat) -> float:
    return b.delay_sec or (b.when.delay_sec or 0.0)


def _schedule(beats: list[Beat]) -> dict[str, float]:
    """Earliest known delivery time (s from start) of beats reachable from timers via chains."""
    t: dict[str, float] = {}
    setters = _flag_setters(beats)
    for _ in range(len(beats) + 1):
        changed = False
        for b in beats:
            w = b.when
            base: float | None = None
            if w.event == "timer" and w.after_sec is not None:
                base = w.after_sec
            elif w.event in ("mission.start", "player.spawned"):
                base = 0.0
            elif w.event == "beat.fired" and w.beat in t:
                base = t[w.beat]
            elif w.event == "flag" and w.flag:
                known = [t[s.id] for s in setters.get(w.flag, []) if s.id in t]
                base = min(known) if known else None
            if base is None:
                continue
            val = base + _delay(b)
            if b.id not in t or val < t[b.id] - 1e-9:
                t[b.id] = val
                changed = True
        if not changed:
            break
    return t


def _flag_setters(beats: Iterable[Beat]) -> dict[str, list[Beat]]:
    out: dict[str, list[Beat]] = defaultdict(list)
    for b in beats:
        for f in _as_list(b.effects.set_flag):
            out[f].append(b)
    return out


def _bible_chars(bible: StoryBible | None) -> dict[str, Any]:
    return {c.id: c for c in bible.characters} if bible is not None else {}


def _mentions(text: str, needles: Iterable[str]) -> bool:
    low = text.lower()
    for n in needles:
        n = n.lower().strip()
        if len(n) < 3:
            continue
        if re.search(r"(?<![a-z0-9])" + re.escape(n), low):
            return True
    return False


def _template_words(tpl: str) -> list[str]:
    """'sa6_site' -> ['sa6_site', 'sa-6', 'sa6']; template ids written as in briefings."""
    out = [tpl, tpl.replace("_", " ")]
    m = re.match(r"^(sa)(\d+)", tpl, re.I)
    if m:
        out += [f"sa-{m.group(2)}", f"sa{m.group(2)}"]
    return out


def _threat_words(ident: str, roles: Iterable[str], templates: Iterable[str]) -> list[str]:
    out = [ident, ident.replace("_", " ")]
    out += [w for w in ident.split("_") if len(w) > 3]
    for r in roles:
        out += _ROLE_WORDS.get(r, [r.replace("_", " ")])
    for tpl in templates:
        out += _template_words(tpl)
    return out


# ---- beat / line rules --------------------------------------------------------------------------


def _rule_spine(beats: list[Beat], issues: list[Issue]) -> None:
    setters = _flag_setters(beats)
    by_id = {b.id: b for b in beats}

    def has_sibling(b: Beat) -> bool:
        flags = set(_as_list(b.effects.set_flag))
        for s in beats:
            if s.id == b.id:
                continue
            if flags & set(_as_list(s.effects.set_flag)):
                return True
            if b.id in s.requires.beats_not_fired and s.when.event in _TIMELY_EVENTS:
                return True
        return False

    def reliable(b: Beat, depth: int = 0) -> bool:
        if depth > 8:
            return True
        ev = b.when.event
        if ev == "unit.takeoff":
            return True  # a separate rule (guaranteed_on_takeoff) covers this
        if ev == "beat.fired" and b.when.beat in by_id:
            return reliable(by_id[b.when.beat], depth + 1) or has_sibling(b)
        if ev == "flag" and b.when.flag:
            src = setters.get(b.when.flag, [])
            if len(src) >= 2 or any(reliable(s, depth + 1) for s in src):
                return True
            return has_sibling(b)
        if ev in _STALL_EVENTS:
            return has_sibling(b)
        return True

    for i, b in enumerate(beats):
        if not b.guaranteed or b.when.event not in _STALL_EVENTS:
            continue
        if reliable(b):
            continue
        what = f"flag '{b.when.flag}'" if b.when.event == "flag" else f"'{b.when.event}'"
        issues.append(
            _issue(
                "spine_no_fallback",
                f"beats.yaml:beats[{i}].when",
                f"guaranteed beat '{b.id}' waits on {what} and nothing else leads past it; "
                "the mission stalls if the player never achieves it",
                "add a timeout sibling: a timer/beat.fired beat (e.g. a retask after ~8 min, with "
                f"requires.beats_not_fired: [{b.id}]) that sets the same flag",
            )
        )


def _rule_takeoff(spec: MissionSpec, beats: list[Beat], issues: list[Issue]) -> None:
    air = [f for f in spec.player_flights if f.start_type == "air"]
    if not air:
        return
    air_zones = {f.start_area for f in air}
    ramp_zones = {f.start_area for f in spec.player_flights if f.start_type != "air"} - air_zones
    by_id = {b.id: b for b in beats}
    setters = _flag_setters(beats)

    def ramp_only(b: Beat, depth: int = 0) -> str | None:
        if depth > 8:
            return None
        w = b.when
        if w.event == "unit.takeoff":
            return "unit.takeoff"
        if w.event == "zone.entered" and w.zone in ramp_zones:
            return f"ramp-only zone '{w.zone}'"
        if w.event == "beat.fired" and w.beat in by_id:
            why = ramp_only(by_id[w.beat], depth + 1)
            return f"beat '{w.beat}' ({why})" if why else None
        if w.event == "flag" and w.flag and setters.get(w.flag):
            whys = [ramp_only(s, depth + 1) for s in setters[w.flag]]
            if all(whys):
                return f"flag '{w.flag}' ({whys[0]})"
        for rb in b.requires.beats_fired:
            if rb in by_id and (why := ramp_only(by_id[rb], depth + 1)):
                return f"requires beat '{rb}' ({why})"
        return None

    for i, b in enumerate(beats):
        if not b.guaranteed:
            continue
        why = ramp_only(b)
        if why:
            issues.append(
                _issue(
                    "guaranteed_on_takeoff",
                    f"beats.yaml:beats[{i}].when",
                    f"guaranteed beat '{b.id}' depends on {why}, which the air-start variant "
                    f"({', '.join(sorted({f.variant or f.callsign for f in air}))}) never produces",
                    "trigger the spine on a zone both variants reach (push/IP zone) or a timer; "
                    "keep takeoff/Ground/Tower beats optional",
                )
            )


def _rule_hook(beats: list[Beat], sched: dict[str, float], issues: list[Issue]) -> None:
    radio = [b for b in beats if _is_radio(b)]
    if not radio:
        return
    if any(b.when.event in ("zone.entered", "unit.takeoff") for b in radio):
        unknown_early = True
    else:
        unknown_early = False
    known = [(sched[b.id], b) for b in radio if b.id in sched]
    if not known or unknown_early:
        return
    t0, first = min(known, key=lambda x: x[0])
    if t0 > HOOK_SEC:
        issues.append(
            _issue(
                "hook_late",
                "beats.yaml:beats",
                f"the first radio call ('{first.id}') comes {t0:.0f} s after mission start "
                f"(> {HOOK_SEC:.0f} s)",
                "add an early check-in or tasking call within the first 3 minutes",
            )
        )


def _rule_lines(
    beats: list[Beat],
    lines: dict[str, VoiceLine],
    bible: StoryBible | None,
    durations: dict[str, float],
    callsigns: set[str],
    issues: list[Issue],
) -> None:
    chars = _bible_chars(bible)
    by_id = {b.id: b for b in beats}
    for i, b in enumerate(beats):
        bp = f"beats.yaml:beats[{i}]"
        texts = _beat_texts(b, lines)
        if not texts:
            continue
        spk = chars.get(b.speaker or "")
        brevity = spk.voice.brevity if spk is not None and spk.voice is not None else "normal"
        limit = BREVITY_WORDS[brevity]
        long_ones = []
        for lid, t in texts:
            n = len(words(t))
            sec = _line_sec(lid, t, durations) if lid in durations else n / 2.6
            if n > limit or sec > MAX_LINE_SEC:
                long_ones.append((lid, n, sec))
        if long_ones:
            lid, n, sec = max(long_ones, key=lambda x: x[1])
            issues.append(
                _issue(
                    "line_too_long",
                    bp + ".lines",
                    f"beat '{b.id}': {len(long_ones)}/{len(texts)} variant(s) over {limit} words "
                    f"({brevity}) or {MAX_LINE_SEC:.0f} s; longest '{lid}' {n} words ~{sec:.1f} s",
                    "split it into a chain (beat.fired) or cut to the information the pilot needs",
                )
            )

        # peak chatter: mid-fight beats stay terse
        mid_fight = b.when.event in _FIGHT_EVENTS or (
            b.when.event == "director.state" and b.when.state == "PEAK"
        )
        if mid_fight:
            chatty = [(lid, len(words(t))) for lid, t in texts if len(words(t)) > PEAK_WORDS]
            if chatty:
                lid, n = max(chatty, key=lambda x: x[1])
                issues.append(
                    _issue(
                        "peak_chatter",
                        bp + ".lines",
                        f"beat '{b.id}' fires mid-fight ({b.when.event}) but {len(chatty)} "
                        f"variant(s) exceed {PEAK_WORDS} words ('{lid}': {n})",
                        "keep PEAK calls to 12 words or fewer; move story lines to a RELAX "
                        "beat (when: {event: director.state, state: RELAX}) or after the kill",
                    )
                )

        # callsign first (continuations of the same speaker's chain are exempt)
        parent = by_id.get(b.when.beat or "") if b.when.event == "beat.fired" else None
        if callsigns and not (parent is not None and parent.speaker == b.speaker):
            bad = [lid for lid, t in texts if not _starts_with_callsign(t, callsigns)]
            if bad:
                issues.append(
                    _issue(
                        "callsign_first",
                        bp + ".lines",
                        f"beat '{b.id}': {len(bad)} variant(s) do not open with a callsign "
                        f"(e.g. '{bad[0]}')",
                        "start with the station called, then your own ('Python, Magic, ...') "
                        "or a short form ('Two, ...')",
                    )
                )

        # phrases
        for lid, t in texts:
            hits = [why for rx, why in _BANNED if rx.search(t)]
            if t.count("!") > 1:
                hits.append("more than one '!'")
            if hits:
                issues.append(
                    _issue(
                        "banned_phrases",
                        f"{bp}.lines ({lid})",
                        f"line '{lid}': {', '.join(hits)}",
                        "use procedural radio: callsign, message, no film clichés or shouting",
                    )
                )
            misuse: list[str] = []
            if _BULLS_RE.search(t):
                misuse.append("'bulls' (say 'bullseye')")
            if _BRAA_RE.search(t):
                misuse.append("BRAA with 'for'/'at' (format: 'BRAA one-eight-three, ten, ...')")
            if _TALLY_FRIENDLY_RE.search(t):
                misuse.append("'tally' on a friendly (use 'visual')")
            if _VISUAL_ENEMY_RE.search(t):
                misuse.append("'visual' on an enemy (use 'tally')")
            aircrew_word = spk is not None and _AIRCREW_ONLY_RE.search(t)
            if aircrew_word and spk is not None and not _AIRCREW_ROLE_RE.search(spk.role):
                misuse.append(f"bingo/winchester from non-aircrew speaker '{spk.id}'")
            if misuse:
                issues.append(
                    _issue(
                        "brevity_misuse",
                        f"{bp}.lines ({lid})",
                        f"line '{lid}': {'; '.join(misuse)}",
                        "follow ATP 1-02.1 brevity (guide section 2)",
                    )
                )

        # variants
        toks = [set(w.lower() for w in words(t)) for _lid, t in texts]
        similar = None
        for a in range(len(toks)):
            for c in range(a + 1, len(toks)):
                union = toks[a] | toks[c]
                if union and len(toks[a] & toks[c]) / len(union) > 0.8:
                    similar = (texts[a][0], texts[c][0])
                    break
            if similar:
                break
        if similar:
            issues.append(
                _issue(
                    "variants_too_similar",
                    bp + ".lines",
                    f"beat '{b.id}': variants '{similar[0]}' and '{similar[1]}' are near-identical",
                    "vary information or rhythm, not just synonyms",
                )
            )
        if not b.once and b.lines and len(b.lines) < 3:
            issues.append(
                _issue(
                    "too_few_variants",
                    bp + ".lines",
                    f"repeatable beat '{b.id}' has {len(b.lines)} variant(s)",
                    "write at least 3 variants for beats that can fire more than once",
                )
            )


def _starts_with_callsign(text: str, callsigns: set[str]) -> bool:
    ws = [w.lower().strip("'-").removesuffix("'s") for w in words(text)[:4]]
    return any(w in callsigns or w in _NUMBER_WORDS for w in ws)


def _callsign_words(spec: MissionSpec, bible: StoryBible | None) -> set[str]:
    names: list[str] = [f.callsign for f in spec.player_flights]
    names += [f.callsign for f in spec.flights]
    names += [s.callsign for s in spec.support if s.callsign]
    for c in _bible_chars(bible).values():
        if c.callsign:
            names.append(c.callsign)
    out: set[str] = set()
    for n in names:
        for w in words(n):
            if w.isalpha() and len(w) > 2:
                out.add(w.lower())
    return out


def _rule_reactions(beats: list[Beat], issues: list[Issue]) -> None:
    by_event: dict[str, list[Beat]] = defaultdict(list)
    for i, b in enumerate(beats):
        if b.when.event in _REACTION_EVENTS:
            by_event[b.when.event].append(b)
            if not b.once and b.cooldown_sec < 30:
                issues.append(
                    _issue(
                        "reaction_no_cooldown",
                        f"beats.yaml:beats[{i}].cooldown_sec",
                        f"repeatable reaction '{b.id}' on {b.when.event} has cooldown "
                        f"{b.cooldown_sec:.0f} s",
                        "set cooldown_sec >= 30 (or once: true)",
                    )
                )
    for ev, bs in by_event.items():
        radio = [b for b in bs if _is_radio(b)]
        if radio and all(_gated(b) for b in radio):
            issues.append(
                _issue(
                    "no_generic_fallback",
                    "beats.yaml:beats",
                    f"every radio beat on {ev} ({', '.join(b.id for b in radio)}) is "
                    "requires-gated, so some runs get no reaction",
                    "add one ungated, low-priority generic beat; keep the specific ones at "
                    "higher priority",
                )
            )


def _gated(b: Beat) -> bool:
    r = b.requires
    return bool(r.flags or r.flags_not or r.qualities or r.beats_fired or r.beats_not_fired)


def _rule_density(
    beats: list[Beat],
    lines: dict[str, VoiceLine],
    durations: dict[str, float],
    sched: dict[str, float],
    issues: list[Issue],
) -> None:
    groups: dict[str, list[Beat]] = defaultdict(list)
    for b in beats:
        if not _is_radio(b):
            continue
        key = json.dumps(
            [b.when.model_dump(exclude={"delay_sec"}), b.requires.model_dump()],
            sort_keys=True,
            default=str,
        )
        groups[key].append(b)
    for bs in groups.values():
        if len(bs) > 3:
            issues.append(
                _issue(
                    "radio_density",
                    "beats.yaml:beats",
                    f"{len(bs)} radio beats share one trigger ({bs[0].when.event}): "
                    f"{', '.join(b.id for b in bs)}; they queue back to back",
                    "keep at most 3 per trigger; merge them or chain the follow-ups with delays",
                )
            )
    timed = sorted(
        (sched[b.id], _beat_sec(b, lines, durations), b)
        for b in beats
        if _is_radio(b) and b.id in sched
    )
    worst: tuple[float, float, list[str]] | None = None
    for t0, _d, _b in timed:
        window = [(d, b.id) for t, d, b in timed if t0 <= t < t0 + DENSITY_WINDOW_SEC]
        total = sum(d for d, _ in window)
        if total > DENSITY_MAX_SEC and (worst is None or total > worst[1]):
            worst = (t0, total, [i for _, i in window])
    if worst is not None:
        t0, total, ids = worst
        issues.append(
            _issue(
                "radio_density",
                "beats.yaml:beats",
                f"~{total:.0f} s of radio in the minute from T+{t0:.0f} s ({', '.join(ids)}); "
                f"over {DENSITY_MAX_SEC:.0f} s per minute is clutter",
                "spread the calls out (delay_sec), drop filler, or shorten lines",
            )
        )


def _rule_quality_beats(beats: list[Beat], issues: list[Issue]) -> None:
    pos: dict[str, int] = defaultdict(int)
    neg: dict[str, int] = defaultdict(int)
    repeat: set[str] = set()
    for b in beats:
        for q, d in b.effects.quality_deltas.items():
            if d > 0:
                pos[q] += d
            else:
                neg[q] += d
            if not b.once and d:
                repeat.add(q)
    for q in sorted(set(pos) | set(neg)):
        swing = max(pos[q], -neg[q])
        if swing > MAX_SWING or q in repeat:
            why = "a repeatable beat changes it" if q in repeat else f"up to {swing:+d}"
            issues.append(
                _issue(
                    "quality_swing",
                    "beats.yaml:beats[*].effects.quality_deltas",
                    f"beats can move quality '{q}' by more than {MAX_SWING} in one mission ({why})",
                    "cap the per-mission swing at +/-2 (make deltas exclusive or smaller)",
                )
            )


# ---- spec / encounter rules ---------------------------------------------------------------------


def _rule_encounters(
    spec: MissionSpec, beats: list[Beat], briefing: str | None, issues: list[Issue]
) -> None:
    by_id = {b.id: b for b in beats}
    pool_roles = {p.id: (list(p.roles), list(p.templates or [])) for p in spec.dynamic.pools}
    telegraphed_by_event = {
        b.when.encounter
        for b in beats
        if b.when.event == "encounter.telegraph" and b.when.encounter
    }
    live = [e for e in spec.dynamic.encounters if e.chance > 0]
    if len(live) > MAX_ENCOUNTERS:
        issues.append(
            _issue(
                "vul_overload",
                "mission-spec.yaml:dynamic.encounters",
                f"{len(live)} encounters can be live in one mission (> {MAX_ENCOUNTERS})",
                "keep one major event per 2-4 min of on-station time; merge or drop fillers",
            )
        )
    for i, e in enumerate(spec.dynamic.encounters):
        ep = f"mission-spec.yaml:dynamic.encounters[{i}]"
        roles, tpls = pool_roles.get(e.pool, ([], []))
        if e.kind in _POPUP_KINDS and not e.telegraph_beat and e.id not in telegraphed_by_event:
            notes = (e.notes or "").lower()
            briefed = briefing is not None and _mentions(
                briefing, _threat_words(e.id, roles, tpls) + _threat_words(e.pool, [], [])
            )
            if "no-cue:" in notes and briefed:
                pass
            else:
                extra = (
                    " ('no-cue:' is set but briefing.md does not mention the threat)"
                    if "no-cue:" in notes
                    else ""
                )
                anti_air = e.kind in ("ambush_sam", "cap") or bool(set(roles) & _ANTI_AIR_ROLES)
                issues.append(
                    _issue(
                        "popup_no_telegraph",
                        ep + ".telegraph_beat",
                        f"{e.kind} encounter '{e.id}' has no telegraph beat{extra}; the threat "
                        "appears from the void",
                        "add telegraph_beat (a radio/RWR cue 30-60 s before it can engage), or "
                        "for an IR threat with no cue put 'no-cue: <why>' in notes and warn in "
                        "the briefing",
                        # ground-only waves cannot shoot the player down: warn, don't fail
                        None if anti_air else "warning",
                    )
                )
        if e.telegraph_beat and e.telegraph_beat in by_id:
            tb = by_id[e.telegraph_beat]
            problems = []
            if _delay(tb) > 0:
                problems.append(f"delay_sec {_delay(tb):.0f} eats into the 30-60 s lead")
            if tb.requires.chance < 100 or _gated(tb):
                problems.append("its requires can block it")
            if not _is_radio(tb):
                problems.append("it has no radio line or text")
            if problems:
                issues.append(
                    _issue(
                        "telegraph_too_short",
                        ep + ".telegraph_beat",
                        f"telegraph '{tb.id}' of encounter '{e.id}': {'; '.join(problems)}",
                        "make the telegraph beat ungated, voiced and delay_sec 0 (the runtime "
                        "already leads by 30-60 s)",
                    )
                )


def _rule_briefing(
    spec: MissionSpec, briefing: str | None, kneeboard: str | None, issues: list[Issue]
) -> None:
    if briefing is not None:
        pool_roles = {p.id: (list(p.roles), list(p.templates or [])) for p in spec.dynamic.pools}
        for i, t in enumerate(spec.threats):
            if t.hidden_on_map or t.role == "civilian":
                continue
            if not _mentions(briefing, _threat_words(t.id, [t.role], t.templates)):
                issues.append(
                    _issue(
                        "briefing_threat_mismatch",
                        f"mission-spec.yaml:threats[{i}]",
                        f"threat '{t.id}' ({t.role}) is visible on the map but briefing.md "
                        "never mentions it",
                        "name it in the Situation/Enemy paragraph with its location and cue",
                    )
                )
        for i, e in enumerate(spec.dynamic.encounters):
            if not e.telegraph_beat:
                continue
            roles, tpls = pool_roles.get(e.pool, ([], []))
            if "civilian" in roles:
                continue
            if not _mentions(briefing, [*_threat_words(e.id, roles, tpls), e.pool]):
                issues.append(
                    _issue(
                        "briefing_threat_mismatch",
                        f"mission-spec.yaml:dynamic.encounters[{i}]",
                        f"telegraphed encounter '{e.id}' ({', '.join(roles) or e.kind}) is not "
                        "mentioned in briefing.md",
                        "brief it as possible/assessed with the cue the player will get",
                    )
                )
        missing = []
        for n in range(1, 6):
            if not re.search(rf"^##\s*{n}\.", briefing, re.M):
                missing.append(f"## {n}.")
        low = briefing.lower()
        if "abort" not in low:
            missing.append("abort criteria")
        if "bingo" not in low:
            missing.append("bingo")
        if not re.search(r"duration|flight time|expected.{0,40}\bmin|~\s*\d+\s*min", low):
            missing.append("expected duration per variant")
        if not re.search(r"stakes|if we fail|if (?:this|it|the \w+) fails|if you fail", low):
            missing.append("stakes line")
        if missing:
            issues.append(
                _issue(
                    "briefing_missing_sections",
                    "briefing.md",
                    f"briefing.md is missing: {', '.join(missing)}",
                    "follow the mission-designer briefing format (5 paragraphs, abort/bingo, "
                    "'Duration:' and 'Stakes:' lines)",
                )
            )
    if kneeboard is not None:
        rows = [ln for ln in kneeboard.splitlines() if ln.strip()]
        has_comms = any(
            ln.lstrip().startswith("|") and re.search(r"freq|mhz|\d{3}\.\d", ln, re.I)
            for ln in rows
        )
        if len(rows) > 25 or not has_comms:
            why = []
            if len(rows) > 25:
                why.append(f"{len(rows)} lines (> 25)")
            if not has_comms:
                why.append("no comms table")
            issues.append(
                _issue(
                    "kneeboard_too_long",
                    "kneeboard.md",
                    f"kneeboard.md: {', '.join(why)}",
                    "one page: lineup card + comms table (agency, callsign, freq) + key data",
                )
            )
    if briefing is not None and kneeboard is not None:
        problems = []
        laser_b = set(re.findall(r"\b1[1-7][1-8][1-8]\b", _near(briefing, r"laser|code")))
        laser_k = set(re.findall(r"\b1[1-7][1-8][1-8]\b", _near(kneeboard, r"laser|code")))
        if laser_b and laser_k and laser_b != laser_k:
            problems.append(f"laser codes {sorted(laser_b)} vs {sorted(laser_k)}")
        freq_b = set(re.findall(r"\b\d{3}\.\d{1,3}\b", briefing))
        freq_k = set(re.findall(r"\b\d{3}\.\d{1,3}\b", kneeboard))
        if freq_k and freq_b - freq_k:
            issues.append(
                _issue(
                    "kneeboard_contradiction",
                    "kneeboard.md",
                    f"frequencies {sorted(freq_b - freq_k)} in briefing.md are missing from "
                    "kneeboard.md",
                    "put every briefed frequency in the kneeboard comms table",
                    "warning",
                )
            )
        if problems:
            issues.append(
                _issue(
                    "kneeboard_contradiction",
                    "kneeboard.md",
                    f"briefing.md and kneeboard.md disagree: {'; '.join(problems)}",
                    "make the kneeboard carry exactly the briefing's codes and frequencies",
                )
            )


def _near(text: str, pattern: str) -> str:
    """Lines of `text` matching `pattern` (case-insensitive)."""
    return "\n".join(ln for ln in text.splitlines() if re.search(pattern, ln, re.I))


def _rule_transit(spec: MissionSpec, plan: dict[str, Any] | None, issues: list[Issue]) -> None:
    if not plan:
        return
    groups = plan.get("groups")
    if not isinstance(groups, list):
        return
    for g in groups:
        if not isinstance(g, dict) or not g.get("client"):
            continue
        route = g.get("route") or []
        if not isinstance(route, list) or len(route) < 2:
            continue
        idx = next(
            (k for k, wp in enumerate(route) if isinstance(wp, dict) and wp.get("name") == "IP"),
            1,
        )
        dist = 0.0
        sec = 0.0
        heli = g.get("category") == "helicopter"
        cruise = 200.0 if heli else 800.0  # km/h
        for a, b in itertools.pairwise(route[: idx + 1]):
            try:
                d = (float(b["x"]) - float(a["x"])) ** 2 + (float(b["y"]) - float(a["y"])) ** 2
            except (KeyError, TypeError, ValueError):
                return
            leg = d**0.5 / 1000.0
            dist += leg
            v = b.get("speed_kmh") or cruise
            sec += leg / float(v) * 3600.0
        variant = "air" if route[0].get("action") == "Turning Point" else "ramp"
        if g.get("variant") in TRANSIT_MAX_MIN:
            variant = str(g["variant"])
        limit = TRANSIT_MAX_MIN[variant]
        target = "IP" if route[idx].get("name") == "IP" else "first steerpoint"
        if sec / 60.0 > limit:
            issues.append(
                _issue(
                    "transit_too_long",
                    f"out/plan.json:groups[{g.get('name')}]",
                    f"{g.get('name')} ({variant}) flies ~{dist:.0f} km / ~{sec / 60:.0f} min to "
                    f"the {target} "
                    f"(> {limit:.0f} min)",
                    "start closer (air-start distance, nearer base) or move the push point",
                )
            )


# ---- arc rules ----------------------------------------------------------------------------------


_SIGNED_RE = re.compile(r"(?<![\w.])([+-])\s*(\d+)")
_SET_RE = re.compile(r"\bset\s+to\s+(-?\d+)", re.I)


def _effect_swing(text: str, qmin: int, qmax: int) -> int:
    """Largest one-mission move a free-text quality_effects entry allows (heuristic).

    Clauses are split on ';'. Alternative clauses ('+2 if A; +1 if B') count once (the largest
    per sign); 'more' clauses ('+1 more if ...') add up; 'set to N' can move the full range;
    'per'/'each' repeats are unbounded unless capped with 'max +N'.
    """
    m = _SET_RE.search(text)
    if m:
        v = int(m.group(1))
        return max(abs(qmax - v), abs(v - qmin))
    cap = re.search(r"\bmax\s*[+-]?\s*(\d+)", text, re.I)
    best = {"+": 0, "-": 0}
    more = {"+": 0, "-": 0}
    unbounded = False
    for clause in text.split(";"):
        s = _SIGNED_RE.search(clause)
        if not s:
            continue
        n = int(s.group(2))
        sign = s.group(1)
        if re.search(r"\bmore\b", clause, re.I):
            more[sign] += n
        else:
            best[sign] = max(best[sign], n)
        if re.search(r"\bper\b|\beach\b", clause, re.I):
            unbounded = True
    swing = max(best["+"] + more["+"], best["-"] + more["-"])
    if unbounded:
        swing = max(swing, qmax - qmin)
    if cap:
        swing = min(swing, int(cap.group(1)))
    return swing


def _mission_prefix(mid: str) -> str:
    return mid.split("-", 1)[0]


def _next_in_order(arc: CampaignArc, mid: str) -> ArcMission | None:
    ms = arc.all_missions()
    idx = next((k for k, m in enumerate(ms) if m.id == mid), None)
    if idx is None:
        return None
    for m in ms[idx + 1 :]:
        if not m.optional:
            return m
    return None


def _mission_text(campaign_dir: Path | None, mid: str) -> str:
    """beats.yaml + briefing.md + mission-spec.yaml text of an arc mission (empty if absent)."""
    if campaign_dir is None:
        return ""
    d = campaign_dir / "missions" / mid
    parts = [_read(d / n) or "" for n in ("beats.yaml", "briefing.md", "mission-spec.yaml")]
    return "\n".join(parts)


def _mission_intensity(campaign_dir: Path | None, mid: str) -> str | None:
    if campaign_dir is None:
        return None
    txt = _read(campaign_dir / "missions" / mid / "mission-spec.yaml")
    if not txt:
        return None
    try:
        data = yaml.safe_load(txt)
        spec = MissionSpec.model_validate(data)
    except (ValueError, yaml.YAMLError):
        return None
    return spec.dynamic.director.intensity if spec.dynamic.director.enabled else None


def _edges(arc: CampaignArc, m: ArcMission) -> list[str]:
    out = [b.goto for b in m.branches]
    ms = arc.all_missions()
    idx = next(k for k, x in enumerate(ms) if x.id == m.id)
    if idx + 1 < len(ms):
        out.append(ms[idx + 1].id)
    return out


def _rule_arc_mission(
    arc: CampaignArc,
    m: ArcMission,
    campaign_dir: Path | None,
    failure_flags: list[str],
    issues: list[Issue],
) -> None:
    ms = arc.all_missions()
    idx = next(k for k, x in enumerate(ms) if x.id == m.id)
    ap = f"arc.yaml:acts[*].missions[{m.id}]"
    qdefs = {q.id: q for q in arc.qualities}

    # failure_dead_end
    nxt = _next_in_order(arc, m.id)
    if nxt is not None:
        pre = _mission_prefix(m.id)
        flags = [f"{pre}_player_lost"] + [f"{pre}_{f}" for f in failure_flags] + failure_flags
        read_by_branch = any(
            f in b.when.flags or f in b.when.flags_not for b in m.branches for f in flags
        )
        nxt_text = _mission_text(campaign_dir, nxt.id)
        read_by_next = any(f in nxt_text for f in flags) or any(
            f in " ".join([*nxt.key_beats, nxt.synopsis]) for f in flags
        )
        if not read_by_branch and not read_by_next:
            designed = bool(nxt_text.strip())
            issues.append(
                _issue(
                    "failure_dead_end",
                    ap + ".branches",
                    f"failure of '{m.id}' ({flags[0]}) has no branch and '{nxt.id}' "
                    + ("never reads it" if designed else "(not designed yet) does not plan to")
                    + ", so losing changes nothing",
                    f"add a branch on {flags[0]} (a different recovery mission that rejoins) or "
                    f"read it in {nxt.id}'s briefing/beats requires",
                    # an undesigned next mission can still read it: warn until it exists
                    None if designed else "warning",
                )
            )

    # quality_swing (arc text)
    for q, text in m.quality_effects.items():
        qd = qdefs.get(q)
        swing = _effect_swing(text, qd.min if qd else -5, qd.max if qd else 5)
        if swing > MAX_SWING:
            issues.append(
                _issue(
                    "quality_swing",
                    f"{ap}.quality_effects.{q}",
                    f"'{m.id}' can move '{q}' by {swing} in one mission (> {MAX_SWING}): {text!r}",
                    "cap one mission's swing at +/-2; carry big world changes in flags instead",
                )
            )

    # branch_never_rejoins
    if m.optional:
        main = {x.id for x in ms if not x.optional}
        frontier = {m.id}
        seen = {m.id}
        rejoined = False
        for _hop in range(2):
            nxt_ids: set[str] = set()
            for mid in frontier:
                node = next(x for x in ms if x.id == mid)
                nxt_ids |= set(_edges(arc, node))
            if nxt_ids & main - {m.id}:
                rejoined = True
                break
            frontier = nxt_ids - seen
            seen |= nxt_ids
        if not rejoined:
            issues.append(
                _issue(
                    "branch_never_rejoins",
                    ap,
                    f"optional mission '{m.id}' does not reach a main-line mission within 2 hops",
                    "diverge in state, converge in structure: rejoin at the next main mission",
                )
            )

    # intensity_streak (this mission closes a run of 3 intense)
    if campaign_dir is not None and idx >= 2:
        run = [_mission_intensity(campaign_dir, x.id) for x in ms[idx - 2 : idx + 1]]
        if all(r == "intense" for r in run):
            issues.append(
                _issue(
                    "intensity_streak",
                    ap,
                    f"'{m.id}' is the third intense mission in a row "
                    f"({', '.join(x.id for x in ms[idx - 2 : idx + 1])})",
                    "make one of them moderate or calm; intense at most 1 in 3",
                )
            )


def lint_arc(arc: CampaignArc, campaign_dir: Path | None = None) -> list[Issue]:
    """Campaign-wide lint of an arc (every mission's arc rules plus quality and act rules)."""
    issues: list[Issue] = []
    for m in arc.all_missions():
        fflags = _failure_flags(campaign_dir, m.id)
        _rule_arc_mission(arc, m, campaign_dir, fflags, issues)
    if campaign_dir is not None:
        for a in arc.acts:
            vals = [_mission_intensity(campaign_dir, m.id) for m in a.missions]
            if vals and all(v is not None for v in vals) and "calm" not in vals:
                issues.append(
                    _issue(
                        "intensity_streak",
                        f"arc.yaml:acts[{a.id}]",
                        f"act '{a.id}' has no calm mission ({', '.join(str(v) for v in vals)})",
                        "give each act a breather (director intensity: calm)",
                    )
                )
    # quality_unmoved / quality_unread
    texts = {m.id: _mission_text(campaign_dir, m.id) for m in arc.all_missions()}
    for q in arc.qualities:
        moved = any(q.id in m.quality_effects for m in arc.all_missions()) or any(
            re.search(rf"quality_deltas[^\n]*\b{re.escape(q.id)}\b", t) for t in texts.values()
        )
        read = any(
            qc.quality == q.id
            for m in arc.all_missions()
            for b in m.branches
            for qc in b.when.qualities
        ) or any(re.search(rf"\b{re.escape(q.id)}\b", t) for t in texts.values())
        read = read or any(
            re.search(rf"\b{re.escape(q.id)}\b", " ".join([m.synopsis, *m.key_beats]))
            for m in arc.all_missions()
        )
        if not moved:
            issues.append(
                _issue(
                    "quality_unmoved",
                    f"arc.yaml:qualities[{q.id}]",
                    f"quality '{q.id}' is never changed by any mission",
                    "add quality_effects (or beat quality_deltas) or drop the quality",
                )
            )
        if not read:
            issues.append(
                _issue(
                    "quality_unread",
                    f"arc.yaml:qualities[{q.id}]",
                    f"quality '{q.id}' is never read by a branch, beat or briefing",
                    "read it somewhere (branch when, beat requires, briefing conditional) "
                    "or drop it",
                )
            )
    return issues


def _failure_flags(campaign_dir: Path | None, mid: str) -> list[str]:
    if campaign_dir is None:
        return []
    txt = _read(campaign_dir / "missions" / mid / "mission-spec.yaml")
    if not txt:
        return []
    try:
        spec = MissionSpec.model_validate(yaml.safe_load(txt))
    except (ValueError, yaml.YAMLError):
        return []
    return [o.failure_flag for o in spec.objectives if o.primary and o.failure_flag]


# ---- entry point --------------------------------------------------------------------------------


def lint_mission(
    spec: MissionSpec,
    beats: BeatSheet | list[Beat] | None = None,
    lines: VoiceLineSet | None = None,
    bible: StoryBible | None = None,
    docs: MissionDocs | None = None,
) -> list[Issue]:
    """All mission-scoped lint findings (arc rules only for this mission's arc entry)."""
    beat_list = (beats.beats if isinstance(beats, BeatSheet) else beats) or []
    line_map = (lines or VoiceLineSet()).by_id()
    d = docs or MissionDocs()
    issues: list[Issue] = []
    sched = _schedule(beat_list)

    _rule_spine(beat_list, issues)
    _rule_takeoff(spec, beat_list, issues)
    _rule_hook(beat_list, sched, issues)
    _rule_lines(beat_list, line_map, bible, d.durations, _callsign_words(spec, bible), issues)
    _rule_reactions(beat_list, issues)
    _rule_density(beat_list, line_map, d.durations, sched, issues)
    _rule_quality_beats(beat_list, issues)
    _rule_encounters(spec, beat_list, d.briefing, issues)
    _rule_briefing(spec, d.briefing, d.kneeboard, issues)
    _rule_transit(spec, d.plan, issues)
    if d.arc is not None:
        entry = next((m for m in d.arc.all_missions() if m.id == spec.id), None)
        if entry is not None:
            fflags = [o.failure_flag for o in spec.objectives if o.primary and o.failure_flag]
            _rule_arc_mission(d.arc, entry, d.campaign_dir, fflags, issues)
    return issues


def lint_mission_dir(
    mission_dir: Path | None,
    spec: MissionSpec,
    beats: BeatSheet | list[Beat] | None = None,
    lines: VoiceLineSet | None = None,
    bible: StoryBible | None = None,
) -> list[Issue]:
    """:func:`lint_mission` with the optional files read from ``mission_dir``."""
    return lint_mission(spec, beats, lines, bible, load_mission_docs(mission_dir))
