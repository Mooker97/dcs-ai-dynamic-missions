"""Beat ``move_group`` effects -> runtime ``moveGroup = {group, to, speedMps, action}``.

Support and flight ids resolve to their DCS group names (like flight ``pickup``); anything else
(threat/pool ids, raw names) passes through as a prefix the runtime resolves. Speed defaults to
4 m/s; the action is ``"Off Road"`` when ``off_road`` is true, or when unset and the group is
infantry (every unit an infantry type), else ``"On Road"``.
"""

from __future__ import annotations

from collections.abc import Sequence

from dcs import vehicles
from dms_core.schemas.beats import Beat, BeatMoveGroup
from dms_core.schemas.mission import MissionSpec
from dms_core.schemas.plan import PlanGroup

from .flights import KTS_MPS, pickup_group

#: Runtime default speed for moveGroup (m/s).
DEFAULT_MOVE_MPS = 4.0

_INFANTRY_TYPES: frozenset[str] = frozenset(
    v.id for v in vars(vehicles.Infantry).values() if isinstance(getattr(v, "id", None), str)
)
_INFANTRY_WORDS = ("soldier", "infantry", "paratrooper", "jtac")


def is_infantry_type(type_id: str) -> bool:
    """True for a DCS infantry unit type (pydcs Infantry, or an infantry-sounding type name)."""
    return type_id in _INFANTRY_TYPES or any(w in type_id.lower() for w in _INFANTRY_WORDS)


def is_infantry_group(group: PlanGroup) -> bool:
    """A ground group made only of infantry."""
    return (
        group.category == "vehicle"
        and bool(group.units)
        and all(is_infantry_type(u.type) for u in group.units)
    )


def compile_move(
    mv: BeatMoveGroup, spec: MissionSpec, groups: Sequence[PlanGroup]
) -> BeatMoveGroup:
    """One authored move_group -> its runtime form (group name, speed_mps, action)."""
    name = pickup_group(mv.group, spec, groups) or mv.group
    group = next((g for g in groups if g.name == name), None)
    off_road = mv.off_road
    if off_road is None:
        off_road = group is not None and is_infantry_group(group)
    speed = round(mv.speed_kts * KTS_MPS, 1) if mv.speed_kts is not None else DEFAULT_MOVE_MPS
    return BeatMoveGroup(
        group=name,
        to=mv.to,
        speed_mps=mv.speed_mps or speed,
        action=mv.action or ("Off Road" if off_road else "On Road"),
    )


def compile_moves(
    beats: Sequence[Beat], spec: MissionSpec, groups: Sequence[PlanGroup]
) -> list[Beat]:
    """Beats with every ``effects.move_group`` compiled (other beats returned unchanged)."""
    out: list[Beat] = []
    for b in beats:
        mv = b.effects.move_group
        if mv is None:
            out.append(b)
            continue
        effects = b.effects.model_copy(update={"move_group": compile_move(mv, spec, groups)})
        out.append(b.model_copy(update={"effects": effects}))
    return out
