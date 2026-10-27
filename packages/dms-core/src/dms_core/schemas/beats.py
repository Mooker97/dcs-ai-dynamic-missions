# ruff: noqa: E501
"""Storylet beats (beats.yaml), compiled verbatim into DMS_CONFIG.beats.

A beat is a small piece of story: *when* something happens, *if* preconditions hold, the
highest-priority eligible beat fires, plays a voice line / subtitle, maybe drops an F10 mark,
and applies effects (flags, outcomes, encounters, quality deltas).
"""

from __future__ import annotations

from typing import Any, Literal

from pydantic import Field, model_validator

from ._common import DirectorState, DMSModel, Ident, OutcomeValue, Requires

BeatEvent = Literal[
    "mission.start",
    "timer",
    "flag",
    "zone.entered",
    "group.dead",
    "unit.dead",
    "unit.hit",
    "unit.shot",
    "player.spawned",
    "player.left",
    "unit.landed",
    "unit.takeoff",
    "mark.added",
    "beat.fired",
    "encounter.spawned",
    "director.state",
]

# event -> field that must be set for the trigger to be meaningful
_REQUIRED_BY_EVENT: dict[str, tuple[str, ...]] = {
    "timer": ("after_sec",),
    "flag": ("flag",),
    "zone.entered": ("zone",),
    "group.dead": ("group", "group_prefix"),
    "beat.fired": ("beat",),
    "encounter.spawned": ("encounter",),
    "director.state": ("state",),
}


class BeatTrigger(DMSModel):
    """What wakes the beat up. Set `event` plus the matching filter fields."""

    event: BeatEvent = Field(
        description=(
            "Trigger event. timer: after_sec from mission start; flag: when `flag` becomes set; "
            "zone.entered: a player/group enters `zone`; group.dead: `group` (or any group with "
            "`group_prefix`) is destroyed; beat.fired: after another beat; encounter.spawned: an "
            "encounter spawned; director.state: director enters `state`; others mirror DCS events."
        )
    )
    group: str | None = Field(default=None, description="Exact group name filter, e.g. 'HVT'.")
    group_prefix: str | None = Field(
        default=None, description="Group name prefix filter, e.g. 'AAA_KIRK' matches AAA_KIRK_1..n."
    )
    unit: str | None = Field(default=None, description="Exact unit name filter.")
    zone: Ident | None = Field(default=None, description="Zone/area id (zone.entered).")
    flag: Ident | None = Field(default=None, description="Flag name (flag event).")
    beat: Ident | None = Field(default=None, description="Beat id (beat.fired).")
    encounter: Ident | None = Field(default=None, description="Encounter id (encounter.spawned).")
    state: DirectorState | None = Field(
        default=None, description="Director state (director.state)."
    )
    after_sec: float | None = Field(
        default=None, ge=0, description="Seconds after mission start (timer)."
    )
    coalition: Literal[1, 2] | None = Field(
        default=None, description="Coalition filter: 1 = red, 2 = blue."
    )
    type_name: str | None = Field(
        default=None, description="DCS unit type filter, e.g. 'ZSU-23-4 Shilka'."
    )
    players_only: bool | None = Field(
        default=None, description="Only count events caused by/affecting player aircraft."
    )

    @model_validator(mode="after")
    def _check_required(self) -> BeatTrigger:
        need = _REQUIRED_BY_EVENT.get(self.event)
        if need and all(getattr(self, f) is None for f in need):
            raise ValueError(f"event '{self.event}' requires one of: {', '.join(need)}")
        return self


class BeatMark(DMSModel):
    """An F10 map mark dropped when the beat fires."""

    type: Literal["circle", "text", "point"] = Field(default="circle", description="Mark shape.")
    at: str = Field(
        description="Where: 'group:<name>', 'unit:<name>' or 'zone:<id>'.",
        pattern=r"^(group|unit|zone):.+$",
    )
    text: str | None = Field(default=None, description="Label shown on the map.")
    radius_m: float | None = Field(default=None, gt=0, description="Circle radius in meters.")
    coalition: Literal[1, 2] | None = Field(
        default=None, description="Who sees it; default players' side."
    )


class BeatEffects(DMSModel):
    """What the beat changes when it fires."""

    set_flag: Ident | None = Field(default=None, description="Flag to set true.")
    clear_flag: Ident | None = Field(default=None, description="Flag to clear.")
    outcome: dict[str, OutcomeValue] = Field(
        default_factory=dict,
        description="Outcome facts to record and emit via [DMS.OUTCOME], e.g. {hvt_killed: true}.",
    )
    start_encounter: Ident | None = Field(
        default=None, description="Encounter id (from mission-spec dynamic.encounters) to start."
    )
    spawn_pool: Ident | None = Field(
        default=None, description="Pool id to draw and spawn from once."
    )
    quality_deltas: dict[str, int] = Field(
        default_factory=dict,
        description="Campaign quality changes applied in the debrief, e.g. {trust: 1}.",
    )
    end_mission: Literal["success", "failure"] | None = Field(
        default=None, description="Declare the mission over with this result."
    )


class Beat(DMSModel):
    """One storylet beat. Keep radio text short; 3-5 voice-line variants per beat."""

    id: Ident = Field(description="Beat id, e.g. 'convoy_hit'.")
    when: BeatTrigger = Field(description="Trigger.")
    requires: Requires = Field(
        default_factory=Requires, description="Preconditions (all must hold)."
    )
    priority: int = Field(
        default=50, ge=0, le=100, description="Higher wins when several beats are eligible at once."
    )
    once: bool = Field(default=True, description="Fire at most once per mission.")
    cooldown_sec: float = Field(default=0, ge=0, description="Minimum seconds between firings.")
    delay_sec: float = Field(default=0, ge=0, description="Delay between trigger and delivery.")
    speaker: Ident | None = Field(
        default=None, description="Character id who speaks (must be in the mission cast)."
    )
    lines: list[Ident] = Field(
        default_factory=list,
        description="Voice line ids from lines.yaml; one is picked at random (no immediate repeats).",
    )
    text: str | None = Field(
        default=None, description="Subtitle / fallback text shown if no audio plays."
    )
    mark: BeatMark | None = Field(default=None, description="Optional F10 mark.")
    effects: BeatEffects = Field(default_factory=BeatEffects, description="Effects on fire.")

    @model_validator(mode="after")
    def _speaker_for_lines(self) -> Beat:
        if self.lines and self.speaker is None:
            raise ValueError(f"beat '{self.id}' has lines but no speaker")
        return self


class BeatSheet(DMSModel):
    """Contents of beats.yaml. A bare YAML list of beats is also accepted."""

    mission_id: Ident | None = Field(default=None, description="Mission these beats belong to.")
    beats: list[Beat] = Field(default_factory=list, description="All beats for the mission.")

    @model_validator(mode="before")
    @classmethod
    def _accept_bare_list(cls, data: Any) -> Any:
        if isinstance(data, list):
            return {"beats": data}
        return data

    @model_validator(mode="after")
    def _unique_ids(self) -> BeatSheet:
        ids = [b.id for b in self.beats]
        dupes = {i for i in ids if ids.count(i) > 1}
        if dupes:
            raise ValueError(f"duplicate beat ids: {sorted(dupes)}")
        return self
