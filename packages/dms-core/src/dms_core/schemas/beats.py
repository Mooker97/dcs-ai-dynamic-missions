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
    "mission.end",
    "mission.result",
    "mark.changed",
    "mark.removed",
    "spawner.spawned",
    "encounter.telegraph",
    "encounter.sam_hot",
    "encounter.wave",
    "encounter.cleared",
    "encounter.proximity",
    "convoy.halted",
    "convoy.resumed",
    "ground.stuck",
    "ground.arrived",
    "intel.revealed",
    "flight.order",
    "flight.arrived",
    "flight.landed",
    "flight.lifted",
    "flight.pickup",
    "flight.weapon",
    "flight.done",
    "flight.lost",
    "player.joined_late",
]

BeatScope = Literal["mission", "flight"]

# camelCase (Lua) spellings accepted on input and mapped to the snake_case field names.
_CAMEL_KEYS: dict[str, str] = {
    "afterSec": "after_sec",
    "delaySec": "delay_sec",
    "groupPrefix": "group_prefix",
    "unitPrefix": "unit_prefix",
    "typeName": "type_name",
    "playersOnly": "players_only",
    "radiusM": "radius_m",
    "cooldownSec": "cooldown_sec",
    "setFlag": "set_flag",
    "clearFlag": "clear_flag",
    "flagValue": "flag_value",
    "startEncounter": "start_encounter",
    "spawnPool": "spawn_pool",
    "qualityDeltas": "quality_deltas",
    "endMission": "end_mission",
    "directorState": "director_state",
    "moveGroup": "move_group",
    "speedKts": "speed_kts",
    "offRoad": "off_road",
    "speedMps": "speed_mps",
}


def _snake_keys(data: dict[str, Any]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for k, v in data.items():
        key = _CAMEL_KEYS.get(k, k)
        if key in out and k != key:
            continue
        out[key] = v
    return out


_END_ALIASES: dict[str, str] = {
    "success": "success",
    "victory": "success",
    "win": "success",
    "failure": "failure",
    "defeat": "failure",
    "fail": "failure",
    "loss": "failure",
}

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
    zone: Ident | None = Field(
        default=None,
        description=(
            "Zone/area id. zone.entered: the zone entered. unit.landed/unit.takeoff: position "
            "filter, the unit must be inside this zone at the event (e.g. 'land at fob_pad')."
        ),
    )
    place: str | None = Field(
        default=None,
        description=(
            "unit.landed/unit.takeoff only: airbase/FARP/ship name the unit landed at or took "
            "off from (payload.place, case-insensitive), e.g. 'Kutaisi'. Alias: airbase."
        ),
    )
    flag: Ident | None = Field(default=None, description="Flag name (flag event).")
    beat: Ident | None = Field(default=None, description="Beat id (beat.fired).")
    encounter: Ident | None = Field(default=None, description="Encounter id (encounter.spawned).")
    state: DirectorState | None = Field(
        default=None, description="Director state (director.state)."
    )
    after_sec: float | None = Field(
        default=None, ge=0, description="Seconds after mission start (timer)."
    )
    coalition: Literal[0, 1, 2] | None = Field(
        default=None,
        description="Coalition filter: 0 = neutral (e.g. civilians), 1 = red, 2 = blue. For unit.hit it is the target's coalition.",
    )
    value: bool | int | float | str | None = Field(
        default=None,
        description="flag event: value to compare the flag with (number => equal, '>=2' style string, or true/false). Omit = 'flag is set'.",
    )
    flight: str | None = Field(
        default=None,
        description="director.state: only this player flight (group name). flight.* events: the AI flight id (payload.flight).",
    )
    unit_prefix: str | None = Field(default=None, description="Unit name prefix filter.")
    delay_sec: float | None = Field(
        default=None,
        ge=0,
        description="Per-trigger delivery delay; used only when the beat's own delay_sec is 0.",
    )
    type_name: str | None = Field(
        default=None, description="DCS unit type filter, e.g. 'ZSU-23-4 Shilka'."
    )
    players_only: bool | None = Field(
        default=None, description="Only count events caused by/affecting player aircraft."
    )

    @model_validator(mode="before")
    @classmethod
    def _shorthand(cls, data: Any) -> Any:
        """Accept Lua shorthand forms ({afterSec}, {flag}, {zone}, {director}, {beat}) and camelCase keys."""
        if not isinstance(data, dict):
            return data
        d = _snake_keys(data)
        if "airbase" in d:
            ab = d.pop("airbase")
            d.setdefault("place", ab)
        if "director_state" in d:
            d.setdefault("director", d.pop("director_state"))
        if d.get("event") is None:
            d.pop("event", None)
            if "timer" in d and "after_sec" not in d:
                d["after_sec"] = d.pop("timer")
            if d.get("after_sec") is not None:
                d["event"] = "timer"
            elif d.get("flag") is not None:
                d["event"] = "flag"
            elif d.get("zone") is not None:
                d["event"] = "zone.entered"
            elif d.get("director") is not None:
                d["event"] = "director.state"
                d["state"] = d.pop("director")
            elif d.get("beat") is not None:
                d["event"] = "beat.fired"
        elif "director" in d and d.get("state") is None:
            d["state"] = d.pop("director")
        return d

    @model_validator(mode="after")
    def _check_required(self) -> BeatTrigger:
        need = _REQUIRED_BY_EVENT.get(self.event)
        if need and all(getattr(self, f) is None for f in need):
            raise ValueError(f"event '{self.event}' requires one of: {', '.join(need)}")
        if self.place is not None and self.event not in ("unit.landed", "unit.takeoff"):
            raise ValueError("'place' filters only unit.landed / unit.takeoff")
        return self


class BeatMark(DMSModel):
    """An F10 map mark dropped when the beat fires."""

    type: Literal["circle", "text", "point"] = Field(default="circle", description="Mark shape.")
    at: str = Field(
        description=(
            "Where: 'group:<name>' (exact group name, else the first group whose name, or name "
            "without the runtime 'DMS_' prefix, starts with it), 'unit:<name>', 'zone:<id>' or "
            "'point:<x>,<y>' (DCS map x/y, meters)."
        ),
        pattern=r"^(group|unit|zone|point):.+$",
    )
    text: str | None = Field(default=None, description="Label shown on the map.")
    radius_m: float | None = Field(default=None, gt=0, description="Circle radius in meters.")
    coalition: Literal[1, 2] | None = Field(
        default=None, description="Who sees it; default players' side."
    )

    @model_validator(mode="before")
    @classmethod
    def _shorthand(cls, data: Any) -> Any:
        """Accept a bare 'zone:x' string, a {x, y} point and 'radius' (Lua spelling)."""
        if isinstance(data, str):
            return {"at": data}
        if not isinstance(data, dict):
            return data
        d = _snake_keys(data)
        if "radius" in d:
            r = d.pop("radius")
            d.setdefault("radius_m", r)
        if "at" not in d and "x" in d and "y" in d:
            x, y = d.pop("x"), d.pop("y")
            d.pop("z", None)
            d["at"] = f"point:{x},{y}"
        elif isinstance(d.get("at"), dict):
            at = d["at"]
            d["at"] = f"point:{at.get('x')},{at.get('y')}"
        return d


class BeatSpeak(DMSModel):
    """Radio call made by an effect; each field overrides the beat's own speaker / lines / text."""

    speaker: Ident | None = Field(
        default=None, description="Character id who speaks (default: the beat's speaker)."
    )
    lines: list[Ident] | None = Field(
        default=None, description="Voice line ids from lines.yaml (default: the beat's lines)."
    )
    text: str | None = Field(
        default=None, description="Subtitle / fallback text (default: the beat's text)."
    )


class BeatMoveGroup(DMSModel):
    """Send a ground group to an area on cue; the runtime emits ground.arrived {group, zone} there.

    Authors write group/to (+ optional speed_kts/off_road). `dms plan` resolves support/flight ids
    to DCS group names and fills speed_mps/action (runtime: {group, to, speedMps, action}).
    """

    group: str = Field(
        min_length=1,
        description=(
            "Support id, flight id or threat/pool id (support/flight ids are resolved to the DCS "
            "group name by `dms plan`; anything else is a group-name prefix resolved at runtime)."
        ),
    )
    to: Ident = Field(description="Area id (zone) to drive to; the group heads for its centre.")
    speed_kts: float | None = Field(
        default=None, gt=0, description="Speed in knots (default 4 m/s, about 7.8 kts)."
    )
    off_road: bool | None = Field(
        default=None,
        description="Drive cross-country ('Off Road'); null = off-road for infantry, else on road.",
    )
    speed_mps: float | None = Field(
        default=None,
        gt=0,
        description="Runtime speed in m/s (set by `dms plan` from speed_kts; don't write it).",
    )
    action: Literal["On Road", "Off Road"] | None = Field(
        default=None,
        description="Runtime DCS route action (set by `dms plan` from off_road; don't write it).",
    )

    @model_validator(mode="before")
    @classmethod
    def _camel(cls, data: Any) -> Any:
        return _snake_keys(data) if isinstance(data, dict) else data


class BeatEffects(DMSModel):
    """What the beat changes when it fires."""

    set_flag: Ident | list[Ident] | None = Field(
        default=None,
        description="Flag (or list of flags) to set (to flag_value, default 1 = true).",
    )
    flag_value: int | None = Field(
        default=None, description="Value written by set_flag; default 1 (true)."
    )
    clear_flag: Ident | list[Ident] | None = Field(
        default=None, description="Flag (or list of flags) to clear."
    )
    outcome: dict[str, OutcomeValue] = Field(
        default_factory=dict,
        description="Outcome facts to record and emit via [DMS.OUTCOME], e.g. {hvt_killed: true}.",
    )
    start_encounter: Ident | list[Ident] | None = Field(
        default=None,
        description="Encounter id (or list) from mission-spec dynamic.encounters to start (encounter chance ignored, once respected).",
    )
    spawn_pool: Ident | None = Field(
        default=None, description="Pool id to draw and spawn from once."
    )
    quality_deltas: dict[str, int] = Field(
        default_factory=dict,
        description=(
            "Campaign quality changes, e.g. {trust: 1}. Applied live for later beats' requires in "
            "this mission and reported as qualityDeltas in [DMS.OUTCOME]; the debriefer applies them."
        ),
    )
    end_mission: Literal["success", "failure"] | None = Field(
        default=None, description="Declare the mission over with this result."
    )
    speak: BeatSpeak | None = Field(
        default=None,
        description="Radio call overriding the beat's speaker/lines/text (unset = use the beat's).",
    )
    mark: BeatMark | None = Field(
        default=None, description="F10 mark dropped when the beat itself has no `mark`."
    )
    move_group: BeatMoveGroup | None = Field(
        default=None,
        description=(
            "Send a ground group to an area: {group, to, speed_kts?, off_road?}. When its lead is "
            "within max(150 m, zone radius) of the area centre the runtime emits ground.arrived "
            "{group, zone}, which beats can trigger on."
        ),
    )

    @model_validator(mode="before")
    @classmethod
    def _aliases(cls, data: Any) -> Any:
        """Accept Lua aliases: finish/end/result -> end_mission, qualities -> quality_deltas."""
        if not isinstance(data, dict):
            return data
        d = _snake_keys(data)
        for alias in ("finish", "end", "result"):
            if alias in d:
                v = d.pop(alias)
                if d.get("end_mission") is None and v is not None:
                    key = str(v).lower()
                    if key not in _END_ALIASES:
                        raise ValueError(
                            f"effects.{alias}: unknown result '{v}' (use success or failure)"
                        )
                    d["end_mission"] = _END_ALIASES[key]
        if "qualities" in d:
            merged = dict(d.pop("qualities") or {})
            merged.update(d.get("quality_deltas") or {})
            d["quality_deltas"] = merged
        return d


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
    scope: BeatScope | None = Field(
        default=None,
        description=(
            "Multiplayer scope (contract v0.9, not implemented yet): 'mission' (unset) = one "
            "fired set for the whole mission, the first flight to trip the beat consumes it; "
            "'flight' = each player flight (keyed by group name) gets its own once/cooldown, "
            "and the radio/mark go to that flight only (payload.flight)."
        ),
    )
    guaranteed: bool = Field(
        default=False,
        description=(
            "Story-spine beat that must play in every run: the runtime ignores chance, keeps it "
            "pending until its requires hold, and never drops its radio line from a full queue."
        ),
    )
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
    cue: str | None = Field(
        default=None,
        description="Watch missions (watch.cues): camera cue shown to everyone as 'CAMERA: <text>' for 10 s; ignored otherwise.",
    )
    effects: BeatEffects = Field(default_factory=BeatEffects, description="Effects on fire.")

    @model_validator(mode="before")
    @classmethod
    def _camel(cls, data: Any) -> Any:
        if isinstance(data, dict):
            return _snake_keys(data)
        return data

    @model_validator(mode="after")
    def _speaker_for_lines(self) -> Beat:
        if self.lines and self.speaker is None:
            raise ValueError(f"beat '{self.id}' has lines but no speaker")
        if self.guaranteed and self.requires.chance < 100:
            raise ValueError(
                f"beat '{self.id}' is guaranteed but has requires.chance {self.requires.chance} < 100"
            )
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
