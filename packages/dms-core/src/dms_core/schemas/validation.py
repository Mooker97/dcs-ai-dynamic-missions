"""Cross-file validation for a mission bundle (spec + beats + lines [+ bible]).

Returns a list of ``Issue`` objects with a JSON-ish path, a plain-English problem and close-match
suggestions, so an LLM author can repair the files without guessing.
"""

from __future__ import annotations

import difflib
from collections.abc import Iterable
from typing import Literal

from pydantic import Field

from ._common import DMSModel
from .beats import Beat, BeatSheet
from .mission import MissionSpec
from .story import StoryBible
from .voice import VoiceLineSet


class Issue(DMSModel):
    """A problem found by validation."""

    path: str = Field(description="Location, e.g. 'beats.yaml:beats[3].lines[1]'.")
    problem: str = Field(description="What is wrong.")
    suggestions: list[str] = Field(default_factory=list, description="Likely intended values.")
    severity: Literal["error", "warning"] = Field(default="error", description="Severity.")


def suggest(value: str, choices: Iterable[str], n: int = 3) -> list[str]:
    """Close matches for `value` among `choices` (difflib, cutoff 0.5)."""
    return difflib.get_close_matches(value, list(choices), n=n, cutoff=0.5)


def _ref(issues: list[Issue], path: str, value: str, known: Iterable[str], what: str) -> None:
    known_list = list(known)
    if value not in known_list:
        issues.append(
            Issue(
                path=path,
                problem=f"unknown {what} '{value}'",
                suggestions=suggest(value, known_list),
            )
        )


def validate_mission_bundle(
    spec: MissionSpec,
    beats: BeatSheet | list[Beat],
    lines: VoiceLineSet,
    bible: StoryBible | None = None,
) -> list[Issue]:
    """Check references across mission-spec.yaml, beats.yaml and lines.yaml.

    Checks: area refs in the spec; encounter pools / telegraph / trigger beats; beat line ids,
    speakers, zones, encounter and pool refs, beat-to-beat refs; line speakers; line speaker vs
    beat speaker consistency (warning); unused lines (warning).
    """
    beat_list = beats.beats if isinstance(beats, BeatSheet) else beats
    issues: list[Issue] = []

    area_ids = spec.area_ids()
    pool_ids = [p.id for p in spec.dynamic.pools]
    encounter_ids = [e.id for e in spec.dynamic.encounters]
    beat_ids = [b.id for b in beat_list]
    line_map = lines.by_id()
    speakers = set(spec.cast)
    if bible is not None:
        bible_ids = {c.id for c in bible.characters}
        speakers |= bible_ids
        for i, c in enumerate(spec.cast):
            _ref(issues, f"mission-spec.yaml:cast[{i}]", c, bible_ids, "bible character")

    sp = "mission-spec.yaml:"
    for path, area in spec.referenced_areas():
        _ref(issues, sp + path, area, area_ids, "area")
    for i, s in enumerate(spec.support):
        if s.speaker:
            _ref(issues, f"{sp}support[{i}].speaker", s.speaker, speakers, "speaker")
    for i, e in enumerate(spec.dynamic.encounters):
        ep = f"{sp}dynamic.encounters[{i}]"
        _ref(issues, ep + ".pool", e.pool, pool_ids, "pool")
        if e.telegraph_beat:
            _ref(issues, ep + ".telegraph_beat", e.telegraph_beat, beat_ids, "beat")
        if e.trigger.beat:
            _ref(issues, ep + ".trigger.beat", e.trigger.beat, beat_ids, "beat")

    used_lines: set[str] = set()
    for i, b in enumerate(beat_list):
        bp = f"beats.yaml:beats[{i}]"
        if b.speaker:
            _ref(issues, bp + ".speaker", b.speaker, speakers, "speaker")
        for j, lid in enumerate(b.lines):
            used_lines.add(lid)
            if lid not in line_map:
                _ref(issues, f"{bp}.lines[{j}]", lid, line_map, "voice line")
            elif b.speaker and line_map[lid].speaker != b.speaker:
                issues.append(
                    Issue(
                        path=f"{bp}.lines[{j}]",
                        problem=(
                            f"line '{lid}' is spoken by '{line_map[lid].speaker}' but beat "
                            f"speaker is '{b.speaker}'"
                        ),
                        suggestions=[line_map[lid].speaker],
                        severity="warning",
                    )
                )
        w = b.when
        if w.zone:
            _ref(issues, bp + ".when.zone", w.zone, area_ids, "zone/area")
        if w.beat:
            _ref(issues, bp + ".when.beat", w.beat, beat_ids, "beat")
        if w.encounter:
            _ref(issues, bp + ".when.encounter", w.encounter, encounter_ids, "encounter")
        for j, rb in enumerate(b.requires.beats_fired):
            _ref(issues, f"{bp}.requires.beats_fired[{j}]", rb, beat_ids, "beat")
        for j, rb in enumerate(b.requires.beats_not_fired):
            _ref(issues, f"{bp}.requires.beats_not_fired[{j}]", rb, beat_ids, "beat")
        if b.effects.start_encounter:
            _ref(
                issues,
                bp + ".effects.start_encounter",
                b.effects.start_encounter,
                encounter_ids,
                "encounter",
            )
        if b.effects.spawn_pool:
            _ref(issues, bp + ".effects.spawn_pool", b.effects.spawn_pool, pool_ids, "pool")
        if b.mark and b.mark.at.startswith("zone:"):
            _ref(issues, bp + ".mark.at", b.mark.at[5:], area_ids, "zone/area")

    for i, ln in enumerate(lines.lines):
        lp = f"lines.yaml:lines[{i}]"
        _ref(issues, lp + ".speaker", ln.speaker, speakers, "speaker")
        if ln.beat:
            _ref(issues, lp + ".beat", ln.beat, beat_ids, "beat")
        if ln.id not in used_lines:
            issues.append(
                Issue(
                    path=lp,
                    problem=f"line '{ln.id}' is not used by any beat",
                    severity="warning",
                )
            )
    return issues
