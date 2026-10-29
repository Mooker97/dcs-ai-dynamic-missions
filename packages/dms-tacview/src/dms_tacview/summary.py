"""Recording -> :class:`FlightSummary`: lifespans, shots, kills, player track, proximity.

Everything that is not stated by the ACMI file itself is a **heuristic** and is labelled as such
in the output (``launcher_method``, ``hit_method``, ``method``/``confidence`` on kills,
``selected_by`` on the player). Thresholds live in :class:`Heuristics`.
"""

from __future__ import annotations

import itertools
import math
from collections import Counter
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from .acmi import AcmiEvent, AcmiObject, Recording, TrackPoint
from .geo import EARTH_RADIUS_M, ground_distance_m, slant_distance_m

__all__ = [
    "FlightSummary",
    "Heuristics",
    "Kill",
    "NamedPoint",
    "ObjectSummary",
    "PlayerTrack",
    "PointProximity",
    "ThreatProximity",
    "WeaponShot",
    "select_player",
    "summarize",
]

Fate = Literal["destroyed", "left_area", "removed", "present_at_end"]
FateSource = Literal["destroyed_event", "left_area_event", "removal", "removal_inferred", "none"]
LauncherMethod = Literal["parent_property", "launch_proximity", "none"]
HitMethod = Literal["timeout_event", "kill_attribution", "impact_proximity", "none"]
KillMethod = Literal["timeout_event", "nearest_weapon", "none"]
Confidence = Literal["high", "medium", "low", "none"]
SelectedBy = Literal["explicit", "heuristic_first_piloted_aircraft"]

#: Tags that make an object a projectile rather than a guided/dropped weapon.
_PROJECTILE_TAGS = ("Shell", "Bullet", "Projectile", "Shrapnel", "Grenade")
#: Tags never treated as kill victims or launchers.
_NON_COMBATANT_TAGS = (
    "Weapon",
    "Decoy",
    "Flare",
    "Chaff",
    "Misc",
    "Navaid",
    "Bullseye",
    "Waypoint",
    "Explosion",
    "Shrapnel",
    "Parachutist",
)


class _Model(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Heuristics(_Model):
    """Thresholds for everything the ACMI file does not state explicitly."""

    launch_radius_m: float = Field(
        default=500.0,
        gt=0,
        description="Max distance from a weapon's first sample to the object that launched it "
        "(used only when the weapon has no Parent property).",
    )
    hit_radius_m: float = Field(
        default=150.0,
        gt=0,
        description="Max distance from a weapon's last sample to a target for a hit/kill.",
    )
    kill_window_before_s: float = Field(
        default=15.0,
        ge=0,
        description="A weapon may end up to this many seconds before the victim is destroyed.",
    )
    kill_window_after_s: float = Field(
        default=1.0,
        ge=0,
        description="A weapon may end up to this many seconds after the victim is destroyed.",
    )
    infer_destroyed_from_removal: bool = Field(
        default=True,
        description="Treat a combatant removed before the end with no LeftArea/Landed event "
        "as destroyed (low confidence).",
    )
    count_projectiles: bool = Field(
        default=False, description="Include shells/bullets in the weapon shot list."
    )
    track_sample_s: float = Field(
        default=10.0, gt=0, description="Spacing of the player track samples in the summary."
    )


class NamedPoint(_Model):
    """A named point or circular zone to measure the player's closest approach to."""

    name: str = Field(description="Point name, e.g. a zone or target name.")
    lon: float = Field(ge=-180, le=180, description="Longitude (degrees).")
    lat: float = Field(ge=-90, le=90, description="Latitude (degrees).")
    radius_m: float | None = Field(
        default=None, gt=0, description="Zone radius (m); enables entered/time_inside."
    )


class ObjectSummary(_Model):
    id: str = Field(description="ACMI object id (lower-case hex).")
    name: str | None = Field(default=None, description="Name property (unit type in DCS [?]).")
    type: str | None = Field(default=None, description="Type tags joined by '+'.")
    coalition: str | None = Field(default=None, description="Coalition property.")
    color: str | None = Field(default=None, description="Color property.")
    country: str | None = Field(default=None, description="Country property.")
    pilot: str | None = Field(default=None, description="Pilot property.")
    group: str | None = Field(default=None, description="Group property.")
    parent: str | None = Field(default=None, description="Parent property (object id).")
    first_seen: float = Field(description="First time the object appears (s).")
    last_seen: float = Field(description="Last time the object appears or is removed (s).")
    lifespan_s: float = Field(description="last_seen - first_seen.")
    fate: Fate = Field(description="How the object's life ended.")
    fate_source: FateSource = Field(description="What the fate is based on.")


class WeaponShot(_Model):
    weapon_id: str = Field(description="Weapon object id.")
    weapon_name: str | None = Field(default=None, description="Weapon Name property.")
    weapon_type: str | None = Field(default=None, description="Weapon Type tags.")
    t_fired: float = Field(description="First time the weapon appears (s).")
    t_end: float = Field(description="Removal / last time of the weapon (s).")
    launcher_id: str | None = Field(default=None, description="Object that fired it.")
    launcher_name: str | None = Field(default=None, description="Launcher Name property.")
    launcher_method: LauncherMethod = Field(description="How the launcher was found.")
    target_id: str | None = Field(default=None, description="Object hit, if any.")
    target_name: str | None = Field(default=None, description="Target Name property.")
    hit: bool = Field(description="Whether the weapon is judged to have hit something.")
    hit_method: HitMethod = Field(description="How the hit was decided.")
    impact_distance_m: float | None = Field(
        default=None, description="Distance from the weapon's last sample to the target."
    )


class Kill(_Model):
    victim_id: str = Field(description="Destroyed object id.")
    victim_name: str | None = Field(default=None, description="Victim Name property.")
    victim_type: str | None = Field(default=None, description="Victim Type tags.")
    victim_coalition: str | None = Field(default=None, description="Victim Coalition.")
    t: float = Field(description="Destruction time (s).")
    destroy_source: Literal["destroyed_event", "removal_inferred"] = Field(
        description="Destroyed event, or removal without LeftArea (heuristic)."
    )
    weapon_id: str | None = Field(default=None, description="Weapon credited, if any.")
    weapon_name: str | None = Field(default=None, description="Weapon Name property.")
    killer_id: str | None = Field(default=None, description="Object credited with the kill.")
    killer_name: str | None = Field(default=None, description="Killer Name property.")
    killer_pilot: str | None = Field(default=None, description="Killer Pilot property.")
    method: KillMethod = Field(description="How the kill was attributed.")
    confidence: Confidence = Field(description="Attribution confidence (see docs).")
    distance_m: float | None = Field(
        default=None, description="Weapon last sample to victim distance (m)."
    )


class PointProximity(_Model):
    name: str = Field(description="NamedPoint name.")
    min_distance_m: float = Field(description="Closest ground distance of the player (m).")
    t_min: float = Field(description="Time of the closest approach (s).")
    radius_m: float | None = Field(default=None, description="Zone radius, if any.")
    entered: bool | None = Field(default=None, description="Came within radius_m (zones only).")
    first_entry_t: float | None = Field(default=None, description="First time inside (s).")
    time_inside_s: float | None = Field(
        default=None, description="Approximate time inside the zone (s), from track segments."
    )


class ThreatProximity(_Model):
    id: str = Field(description="Hostile air-defence object id.")
    name: str | None = Field(default=None, description="Name property.")
    type: str | None = Field(default=None, description="Type tags.")
    min_slant_m: float = Field(description="Closest 3-D distance to the player (m).")
    t: float = Field(description="Time of the closest approach (s).")


class PlayerTrack(_Model):
    object_id: str = Field(description="Player aircraft object id.")
    name: str | None = Field(default=None, description="Aircraft Name property.")
    pilot: str | None = Field(default=None, description="Pilot property.")
    coalition: str | None = Field(default=None, description="Coalition property.")
    selected_by: Literal["explicit", "heuristic_first_piloted_aircraft"] = Field(
        description="How the player object was chosen."
    )
    first_seen: float = Field(description="First appearance (s).")
    last_seen: float = Field(description="Last appearance (s).")
    flight_time_s: float = Field(description="last_seen - first_seen.")
    distance_km: float = Field(description="Ground distance covered (km).")
    max_alt_m: float | None = Field(default=None, description="Highest altitude MSL (m).")
    min_alt_m: float | None = Field(default=None, description="Lowest altitude MSL (m).")
    takeoffs: list[float] = Field(default_factory=list, description="TakenOff event times.")
    landings: list[float] = Field(default_factory=list, description="Landed event times.")
    fate: Fate = Field(description="How the player's aircraft ended.")
    samples: list[tuple[float, float, float, float]] = Field(
        default_factory=list, description="Downsampled track: (t, lon, lat, alt_m)."
    )


class FlightSummary(_Model):
    source: str | None = Field(default=None, description="ACMI file path.")
    title: str | None = Field(default=None, description="Global Title.")
    data_source: str | None = Field(default=None, description="Global DataSource (sim).")
    data_recorder: str | None = Field(default=None, description="Global DataRecorder.")
    reference_time: str | None = Field(default=None, description="Global ReferenceTime (UTC).")
    start_time: float = Field(description="First frame time (s).")
    end_time: float = Field(description="Last frame time (s).")
    duration_s: float = Field(description="end_time - start_time.")
    object_counts: dict[str, int] = Field(
        default_factory=dict, description="Objects by class tag (Air/Ground/Sea/Weapon/...)."
    )
    objects: list[ObjectSummary] = Field(default_factory=list, description="Every object.")
    shots: list[WeaponShot] = Field(default_factory=list, description="Weapons fired.")
    kills: list[Kill] = Field(default_factory=list, description="Destroyed combatants.")
    player: PlayerTrack | None = Field(default=None, description="Player track, if found.")
    player_shots: int = Field(default=0, description="Weapons fired by the player.")
    player_hits: int = Field(default=0, description="Player weapons judged to hit.")
    player_kills: int = Field(default=0, description="Kills credited to the player.")
    points: list[PointProximity] = Field(
        default_factory=list, description="Player closest approach to named points/zones."
    )
    threats: list[ThreatProximity] = Field(
        default_factory=list, description="Player closest approach to hostile air defences."
    )
    heuristics: Heuristics = Field(description="Thresholds used.")
    warnings: list[str] = Field(default_factory=list, description="Non-fatal issues.")
    malformed_lines: int = Field(default=0, description="ACMI lines skipped as malformed.")


# --------------------------------------------------------------------------- helpers


def _is_combatant(o: AcmiObject) -> bool:
    return not o.has_tag(*_NON_COMBATANT_TAGS) and bool(o.tags)


def _is_aircraft(o: AcmiObject) -> bool:
    return o.has_tag("FixedWing", "Rotorcraft") or (o.has_tag("Air") and not o.has_tag("Weapon"))


def _end_time(o: AcmiObject, rec: Recording) -> float:
    return o.removed_at if o.removed_at is not None else min(o.last_seen, rec.end_time)


def _alive_at(o: AcmiObject, t: float) -> bool:
    end = o.removed_at if o.removed_at is not None else math.inf
    return o.first_seen <= t <= end and bool(o.track)


def _dist(a: TrackPoint, b: TrackPoint) -> float:
    return slant_distance_m(a.lon, a.lat, a.alt, b.lon, b.lat, b.alt)


def _local_xy(lon: float, lat: float, lon0: float, lat0: float) -> tuple[float, float]:
    k = math.pi / 180 * EARTH_RADIUS_M
    return (lon - lon0) * k * math.cos(math.radians(lat0)), (lat - lat0) * k


def _match(o: AcmiObject, needle: str) -> bool:
    n = needle.strip().lower()
    if o.id == n.lstrip("0") or o.id == n:
        return True
    return any(
        (o.props.get(k) or "").strip().lower() == n for k in ("Pilot", "Name", "CallSign", "Group")
    )


def select_player(
    rec: Recording, player: str | None = None
) -> tuple[AcmiObject | None, SelectedBy]:
    """Pick the player aircraft: explicit match (id/Pilot/Name/CallSign/Group), else heuristic.

    Heuristic (labelled ``heuristic_first_piloted_aircraft``): the aircraft with a ``Pilot``
    property that appears first, longest-lived on ties.
    """
    if player:
        hits = [o for o in rec.objects.values() if _match(o, player) and _is_aircraft(o)]
        if not hits:
            hits = [o for o in rec.objects.values() if _match(o, player)]
        if hits:
            return min(hits, key=lambda o: (o.first_seen, -(o.last_seen - o.first_seen))), (
                "explicit"
            )
        return None, "explicit"
    piloted = [o for o in rec.objects.values() if _is_aircraft(o) and o.props.get("Pilot")]
    if not piloted:
        return None, "heuristic_first_piloted_aircraft"
    best = min(piloted, key=lambda o: (o.first_seen, -(o.last_seen - o.first_seen)))
    return best, "heuristic_first_piloted_aircraft"


# --------------------------------------------------------------------------- summarize


def summarize(
    rec: Recording,
    *,
    player: str | None = None,
    points: list[NamedPoint] | None = None,
    heuristics: Heuristics | None = None,
    source: str | None = None,
) -> FlightSummary:
    """Summarize a parsed recording (pure)."""
    h = heuristics or Heuristics()
    warnings: list[str] = []
    objs = rec.objects

    destroyed_ev: dict[str, float] = {}
    left_area: set[str] = set()
    landed: dict[str, list[float]] = {}
    took_off: dict[str, list[float]] = {}
    for ev in rec.events:
        for oid in ev.object_ids:
            if ev.kind == "Destroyed":
                destroyed_ev.setdefault(oid, ev.t)
            elif ev.kind == "LeftArea":
                left_area.add(oid)
            elif ev.kind == "Landed":
                landed.setdefault(oid, []).append(ev.t)
            elif ev.kind == "TakenOff":
                took_off.setdefault(oid, []).append(ev.t)
    unknown = sorted({i for e in rec.events for i in e.object_ids if i not in objs})
    if unknown:
        warnings.append(f"events reference unknown object ids: {', '.join(unknown[:10])}")

    # -- fates
    fates: dict[str, tuple[Fate, FateSource]] = {}
    victims: dict[str, tuple[float, Literal["destroyed_event", "removal_inferred"]]] = {}
    for o in objs.values():
        if o.id in destroyed_ev:
            fates[o.id] = ("destroyed", "destroyed_event")
            if not o.has_tag("Weapon"):
                victims[o.id] = (destroyed_ev[o.id], "destroyed_event")
        elif o.id in left_area:
            fates[o.id] = ("left_area", "left_area_event")
        elif o.removed_at is not None and o.removed_at < rec.end_time:
            if (
                h.infer_destroyed_from_removal
                and _is_combatant(o)
                and o.id not in landed
                and not o.has_tag("Static")
            ):
                fates[o.id] = ("destroyed", "removal_inferred")
                victims[o.id] = (o.removed_at, "removal_inferred")
            else:
                fates[o.id] = ("removed", "removal")
        else:
            fates[o.id] = ("present_at_end", "none")

    # -- shots
    timeouts = rec.events_of("Timeout")
    shots: list[WeaponShot] = []
    weapons = sorted(
        (o for o in objs.values() if o.has_tag("Weapon") and o.track),
        key=lambda o: (o.first_seen, o.id),
    )
    for w in weapons:
        if not h.count_projectiles and w.has_tag(*_PROJECTILE_TAGS):
            continue
        shots.append(_shot(w, rec, h, timeouts))

    # -- kills
    kills: list[Kill] = []
    by_weapon = {s.weapon_id: s for s in shots}
    for vid, (t_kill, src) in sorted(victims.items(), key=lambda kv: (kv[1][0], kv[0])):
        v = objs[vid]
        kill = _attribute_kill(v, t_kill, src, rec, h, by_weapon, timeouts)
        kills.append(kill)
        if kill.weapon_id and kill.weapon_id in by_weapon:
            s = by_weapon[kill.weapon_id]
            if s.hit_method != "timeout_event":
                s.hit, s.hit_method = True, "kill_attribution"
                s.target_id, s.target_name = v.id, v.name
                s.impact_distance_m = kill.distance_m

    # -- player
    p_obj, selected_by = select_player(rec, player)
    player_track: PlayerTrack | None = None
    pts_out: list[PointProximity] = []
    threats: list[ThreatProximity] = []
    p_shots = p_hits = p_kills = 0
    if p_obj is None:
        warnings.append(
            "no player aircraft found ("
            + (f"no match for {player!r}" if player else "no Pilot")
            + ")"
        )
    else:
        player_track = _player_track(p_obj, rec, h, selected_by, fates, landed, took_off)
        mine = {s.weapon_id for s in shots if s.launcher_id == p_obj.id}
        p_shots = len(mine)
        p_hits = sum(1 for s in shots if s.weapon_id in mine and s.hit)
        p_kills = sum(1 for k in kills if k.killer_id == p_obj.id)
        pts_out = [_point_proximity(p_obj, pt) for pt in points or []]
        threats = _threats(p_obj, rec)
    if points and p_obj is None:
        warnings.append("named points given but no player track to measure")

    counts: Counter[str] = Counter()
    for o in objs.values():
        cls = next(
            (
                c
                for c in ("Weapon", "Air", "Ground", "Sea", "Sensor", "Navaid", "Misc")
                if c in o.tags
            ),
            "Other",
        )
        counts[cls] += 1
    if rec.malformed_lines:
        warnings.append(f"{len(rec.malformed_lines)} malformed ACMI line(s) skipped")
    g = rec.header.globals
    return FlightSummary(
        source=source,
        title=g.get("Title"),
        data_source=g.get("DataSource"),
        data_recorder=g.get("DataRecorder"),
        reference_time=g.get("ReferenceTime"),
        start_time=rec.start_time,
        end_time=rec.end_time,
        duration_s=round(rec.end_time - rec.start_time, 3),
        object_counts=dict(sorted(counts.items())),
        objects=[
            _object_summary(o, fates[o.id], rec)
            for o in sorted(objs.values(), key=lambda o: (o.first_seen, o.id))
        ],
        shots=shots,
        kills=kills,
        player=player_track,
        player_shots=p_shots,
        player_hits=p_hits,
        player_kills=p_kills,
        points=pts_out,
        threats=threats,
        heuristics=h,
        warnings=warnings,
        malformed_lines=len(rec.malformed_lines),
    )


def _object_summary(o: AcmiObject, fate: tuple[Fate, FateSource], rec: Recording) -> ObjectSummary:
    end = _end_time(o, rec)
    p = o.props
    return ObjectSummary(
        id=o.id,
        name=p.get("Name"),
        type=p.get("Type"),
        coalition=p.get("Coalition"),
        color=p.get("Color"),
        country=p.get("Country"),
        pilot=p.get("Pilot"),
        group=p.get("Group"),
        parent=o.parent,
        first_seen=o.first_seen,
        last_seen=end,
        lifespan_s=round(end - o.first_seen, 3),
        fate=fate[0],
        fate_source=fate[1],
    )


def _shot(w: AcmiObject, rec: Recording, h: Heuristics, timeouts: list[AcmiEvent]) -> WeaponShot:
    objs = rec.objects
    t_end = _end_time(w, rec)
    launcher: AcmiObject | None = None
    method: LauncherMethod = "none"
    if w.parent and w.parent in objs:
        launcher, method = objs[w.parent], "parent_property"
    else:
        first = w.track[0]
        cands = [
            o for o in objs.values() if o.id != w.id and _is_combatant(o) and _alive_at(o, first.t)
        ]
        coal = w.props.get("Coalition")
        same = [o for o in cands if coal and o.props.get("Coalition") == coal]
        best: tuple[float, AcmiObject] | None = None
        for o in same or cands:
            pos = o.position_at(first.t)
            if pos is None:
                continue
            d = _dist(first, pos)
            if d <= h.launch_radius_m and (best is None or d < best[0]):
                best = (d, o)
        if best is not None:
            launcher, method = best[1], "launch_proximity"
    shot = WeaponShot(
        weapon_id=w.id,
        weapon_name=w.name,
        weapon_type=w.props.get("Type"),
        t_fired=w.first_seen,
        t_end=t_end,
        launcher_id=launcher.id if launcher else None,
        launcher_name=launcher.name if launcher else None,
        launcher_method=method,
        hit=False,
        hit_method="none",
    )
    # Impact proximity: any combatant (not the launcher) within hit_radius of the last sample.
    last = w.track[-1]
    best_t: tuple[float, AcmiObject] | None = None
    for o in objs.values():
        if o.id in (w.id, shot.launcher_id) or not _is_combatant(o) or not _alive_at(o, last.t):
            continue
        pos = o.position_at(last.t)
        if pos is None:
            continue
        d = _dist(last, pos)
        if d <= h.hit_radius_m and (best_t is None or d < best_t[0]):
            best_t = (d, o)
    if best_t is not None:
        shot.hit, shot.hit_method = True, "impact_proximity"
        shot.target_id, shot.target_name = best_t[1].id, best_t[1].name
        shot.impact_distance_m = round(best_t[0], 1)
    return shot


def _attribute_kill(
    v: AcmiObject,
    t_kill: float,
    src: Literal["destroyed_event", "removal_inferred"],
    rec: Recording,
    h: Heuristics,
    shots: dict[str, WeaponShot],
    timeouts: list[AcmiEvent],
) -> Kill:
    objs = rec.objects
    kill = Kill(
        victim_id=v.id,
        victim_name=v.name,
        victim_type=v.props.get("Type"),
        victim_coalition=v.props.get("Coalition"),
        t=t_kill,
        destroy_source=src,
        method="none",
        confidence="none",
    )
    # 1) Timeout weapon event naming this target with a kill/hit outcome (stated by the file).
    for ev in timeouts:
        tid = _id(ev.params.get("TargetId", ""))
        outcome = ev.params.get("Outcome", "").lower()
        if (
            tid == v.id
            and outcome in ("kill", "hit", "destroyed")
            and ev.t <= t_kill + h.kill_window_after_s
        ):
            sid = _id(ev.params.get("SourceId", "")) or None
            killer = objs.get(sid) if sid else None
            kill.killer_id = sid
            kill.killer_name = killer.name if killer else None
            kill.killer_pilot = killer.props.get("Pilot") if killer else None
            kill.weapon_name = ev.params.get("AmmoType")
            kill.method, kill.confidence = "timeout_event", "high"
            return kill
    # 2) Nearest weapon whose end is inside the window and within hit_radius of the victim.
    best: tuple[float, WeaponShot] | None = None
    for s in shots.values():
        if not (t_kill - h.kill_window_before_s <= s.t_end <= t_kill + h.kill_window_after_s):
            continue
        if s.launcher_id == v.id:
            continue
        last = objs[s.weapon_id].track[-1]
        pos = v.position_at(min(last.t, _end_time(v, rec)))
        if pos is None:
            continue
        d = _dist(last, pos)
        if d <= h.hit_radius_m and (best is None or d < best[0]):
            best = (d, s)
    if best is None:
        return kill
    d, s = best
    killer = objs.get(s.launcher_id) if s.launcher_id else None
    kill.weapon_id, kill.weapon_name = s.weapon_id, s.weapon_name
    kill.killer_id = killer.id if killer else None
    kill.killer_name = killer.name if killer else None
    kill.killer_pilot = killer.props.get("Pilot") if killer else None
    kill.method = "nearest_weapon"
    kill.confidence = "medium" if killer and s.launcher_method == "parent_property" else "low"
    kill.distance_m = round(d, 1)
    return kill


def _id(raw: str) -> str:
    s = raw.strip().lower().lstrip("0")
    return s or ("0" if raw.strip() else "")


def _player_track(
    p: AcmiObject,
    rec: Recording,
    h: Heuristics,
    selected_by: Literal["explicit", "heuristic_first_piloted_aircraft"],
    fates: dict[str, tuple[Fate, FateSource]],
    landed: dict[str, list[float]],
    took_off: dict[str, list[float]],
) -> PlayerTrack:
    dist = 0.0
    for a, b in itertools.pairwise(p.track):
        dist += ground_distance_m(a.lon, a.lat, b.lon, b.lat)
    samples: list[tuple[float, float, float, float]] = []
    next_t = -math.inf
    for i, pt in enumerate(p.track):
        if pt.t >= next_t or i == len(p.track) - 1:
            samples.append((pt.t, round(pt.lon, 6), round(pt.lat, 6), round(pt.alt, 1)))
            next_t = pt.t + h.track_sample_s
    alts = [pt.alt for pt in p.track]
    end = _end_time(p, rec)
    return PlayerTrack(
        object_id=p.id,
        name=p.name,
        pilot=p.props.get("Pilot"),
        coalition=p.props.get("Coalition"),
        selected_by=selected_by,
        first_seen=p.first_seen,
        last_seen=end,
        flight_time_s=round(end - p.first_seen, 3),
        distance_km=round(dist / 1000, 3),
        max_alt_m=round(max(alts), 1) if alts else None,
        min_alt_m=round(min(alts), 1) if alts else None,
        takeoffs=took_off.get(p.id, []),
        landings=landed.get(p.id, []),
        fate=fates[p.id][0],
        samples=samples,
    )


def _point_proximity(p: AcmiObject, pt: NamedPoint) -> PointProximity:
    track = p.track
    best_d, best_t = math.inf, p.first_seen
    entered = False
    first_entry: float | None = None
    inside = 0.0
    r = pt.radius_m

    def d_of(tp: TrackPoint) -> float:
        return ground_distance_m(tp.lon, tp.lat, pt.lon, pt.lat)

    if len(track) == 1:
        best_d, best_t = d_of(track[0]), track[0].t
    for a, b in itertools.pairwise(track):
        ax, ay = _local_xy(a.lon, a.lat, pt.lon, pt.lat)
        bx, by = _local_xy(b.lon, b.lat, pt.lon, pt.lat)
        dx, dy = bx - ax, by - ay
        seg2 = dx * dx + dy * dy
        f = 0.0 if seg2 == 0 else max(0.0, min(1.0, -(ax * dx + ay * dy) / seg2))
        d = math.hypot(ax + f * dx, ay + f * dy)
        if d < best_d:
            best_d, best_t = d, a.t + f * (b.t - a.t)
        if r is not None:
            da, db = d_of(a), d_of(b)
            ins = (da <= r) + (db <= r)
            inside += (b.t - a.t) * ins / 2
            if d <= r and not entered:
                entered = True
                first_entry = a.t if da <= r else a.t + f * (b.t - a.t)
    return PointProximity(
        name=pt.name,
        min_distance_m=round(best_d, 1),
        t_min=round(best_t, 2),
        radius_m=r,
        entered=entered if r is not None else None,
        first_entry_t=round(first_entry, 2) if first_entry is not None else None,
        time_inside_s=round(inside, 1) if r is not None else None,
    )


def _threats(p: AcmiObject, rec: Recording) -> list[ThreatProximity]:
    coal = p.props.get("Coalition")
    out: list[ThreatProximity] = []
    for o in rec.objects.values():
        if o.id == p.id or not o.has_tag("AntiAircraft") or o.has_tag("Weapon") or not o.track:
            continue
        oc = o.props.get("Coalition")
        if not coal or not oc or oc == coal:
            continue
        best: tuple[float, float] | None = None
        for tp in p.track:
            if not _alive_at(o, tp.t):
                continue
            pos = o.position_at(tp.t)
            if pos is None:
                continue
            d = _dist(tp, pos)
            if best is None or d < best[0]:
                best = (d, tp.t)
        if best is not None:
            out.append(
                ThreatProximity(
                    id=o.id,
                    name=o.name,
                    type=o.props.get("Type"),
                    min_slant_m=round(best[0], 1),
                    t=best[1],
                )
            )
    out.sort(key=lambda x: x.min_slant_m)
    return out
