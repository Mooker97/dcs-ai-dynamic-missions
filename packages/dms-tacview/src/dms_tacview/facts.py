"""FlightSummary -> flat debrief facts that can enrich a DMS ``MissionOutcome``.

Fact keys match the arc ``quality_effects`` condition grammar (``[a-z][a-z0-9_]*``) and all carry
the ``tv_`` prefix, so they never collide with Lua-reported outcome keys. Proposed integration is
in docs/ideas/tacview.md; ``dms_core.outcomes`` is not changed by this package.
"""

from __future__ import annotations

import re
from typing import Any

from dms_core.schemas import MissionOutcome

from .summary import FlightSummary, Kill

__all__ = ["FACT_PREFIX", "enrich_outcome", "fact_key", "outcome_facts"]

FACT_PREFIX = "tv_"

Fact = bool | int | float | str


def fact_key(*parts: str, prefix: str = FACT_PREFIX) -> str:
    """``fact_key("SAM Site 1", "min_m")`` -> ``tv_sam_site_1_min_m``."""
    body = "_".join(re.sub(r"[^a-z0-9]+", "_", p.lower()).strip("_") for p in parts if p)
    body = re.sub(r"_+", "_", body).strip("_") or "unnamed"
    key = f"{prefix}{body}"
    return key if key[0].isalpha() else f"tv_{key}"


def _kill_class(k: Kill) -> str:
    tags = set((k.victim_type or "").split("+"))
    for cls, name in (("Air", "air"), ("Sea", "sea"), ("Ground", "ground")):
        if cls in tags:
            return name
    return "other"


def outcome_facts(summary: FlightSummary, *, prefix: str = FACT_PREFIX) -> dict[str, Fact]:
    """Flat, deterministic facts about the player's flight (empty-ish when no player is found)."""
    f: dict[str, Fact] = {fact_key("player_found", prefix=prefix): summary.player is not None}
    f[fact_key("duration_s", prefix=prefix)] = round(summary.duration_s, 1)
    p = summary.player
    if p is None:
        return f
    coal = p.coalition
    mine = [k for k in summary.kills if k.killer_id == p.object_id]
    f.update(
        {
            fact_key("flight_time_s", prefix=prefix): round(p.flight_time_s, 1),
            fact_key("distance_km", prefix=prefix): round(p.distance_km, 1),
            fact_key("player_destroyed", prefix=prefix): p.fate == "destroyed",
            fact_key("player_landed", prefix=prefix): bool(p.landings),
            fact_key("player_shots", prefix=prefix): summary.player_shots,
            fact_key("player_hits", prefix=prefix): summary.player_hits,
            fact_key("player_kills", prefix=prefix): len(mine),
            fact_key("player_kills_confident", prefix=prefix): sum(
                1 for k in mine if k.confidence in ("high", "medium")
            ),
        }
    )
    if p.max_alt_m is not None:
        f[fact_key("max_alt_m", prefix=prefix)] = p.max_alt_m
    if p.min_alt_m is not None:
        f[fact_key("min_alt_m", prefix=prefix)] = p.min_alt_m
    for cls in ("air", "ground", "sea"):
        f[fact_key("player_kills", cls, prefix=prefix)] = sum(
            1 for k in mine if _kill_class(k) == cls
        )
    if coal:
        f[fact_key("friendly_losses", prefix=prefix)] = sum(
            1 for k in summary.kills if k.victim_coalition == coal and k.victim_id != p.object_id
        )
        f[fact_key("enemy_losses", prefix=prefix)] = sum(
            1 for k in summary.kills if k.victim_coalition and k.victim_coalition != coal
        )
    if summary.threats:
        f[fact_key("closest_threat_m", prefix=prefix)] = summary.threats[0].min_slant_m
    for pt in summary.points:
        f[fact_key(pt.name, "min_m", prefix=prefix)] = pt.min_distance_m
        if pt.entered is not None:
            f[fact_key(pt.name, "entered", prefix=prefix)] = pt.entered
        if pt.time_inside_s is not None:
            f[fact_key(pt.name, "time_inside_s", prefix=prefix)] = pt.time_inside_s
    return f


def enrich_outcome(
    outcome: MissionOutcome,
    summary: FlightSummary,
    *,
    merge_into_outcomes: bool = False,
    prefix: str = FACT_PREFIX,
) -> MissionOutcome:
    """Return a copy of ``outcome`` with Tacview facts under ``extra["tacview"]``.

    With ``merge_into_outcomes`` the facts are also added to ``outcomes`` (never overwriting a
    key the Lua runtime reported), which makes them visible to arc ``quality_effects``.
    """
    facts = outcome_facts(summary, prefix=prefix)
    block: dict[str, Any] = {
        "source": summary.source,
        "facts": facts,
        "player": summary.player.object_id if summary.player else None,
        "player_selected_by": summary.player.selected_by if summary.player else None,
        "kills": [
            {
                "victim": k.victim_name or k.victim_id,
                "killer": k.killer_pilot or k.killer_name or k.killer_id,
                "weapon": k.weapon_name,
                "t": k.t,
                "method": k.method,
                "confidence": k.confidence,
            }
            for k in summary.kills
        ],
        "warnings": list(summary.warnings),
    }
    extra = dict(outcome.extra)
    extra["tacview"] = block
    update: dict[str, Any] = {"extra": extra}
    if merge_into_outcomes:
        merged = dict(outcome.outcomes)
        for k, v in facts.items():
            merged.setdefault(k, v)
        update["outcomes"] = merged
    return outcome.model_copy(update=update)
