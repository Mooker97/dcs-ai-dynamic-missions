"""Player-flight start variants: one BuildPlan -> one .miz per variant (e.g. ramp / air).

``PlayerFlight.variant`` is copied to ``PlanGroup.variant``. Client groups of a given variant are
built together; client groups without a variant appear in every variant; all other groups are
shared. A plan without variants builds exactly as before (one ``<id>.miz``).
"""

from __future__ import annotations

from dms_core.schemas.plan import BuildPlan, PlanGroup

_PREFERRED_TEST_ACTIONS = ("From Parking Area", "From Parking Area Hot", "From Runway")


def plan_variants(plan: BuildPlan) -> list[str]:
    """Distinct player-flight variants in plan order (empty = no variants)."""
    out: list[str] = []
    for g in plan.groups:
        if g.client and g.variant and g.variant not in out:
            out.append(g.variant)
    return out


def variant_plan(plan: BuildPlan, variant: str | None) -> BuildPlan:
    """Deep copy of ``plan`` keeping only ``variant``'s client groups (plus variant-less ones).

    ``variant=None`` returns an unfiltered copy. Raises ``ValueError`` for an unknown variant.
    """
    vp = plan.model_copy(deep=True)
    if variant is None:
        return vp
    known = plan_variants(plan)
    if variant not in known:
        raise ValueError(f"unknown variant {variant!r}; plan has {known or 'no variants'}")
    vp.groups = [g for g in vp.groups if not g.client or g.variant in (None, variant)]
    return vp


def variant_miz_name(mission_id: str, variant: str | None) -> str:
    """``<id>-<variant>.miz`` (``<id>.miz`` without a variant)."""
    return f"{mission_id}-{variant}.miz" if variant else f"{mission_id}.miz"


def pick_test_proxy(plan: BuildPlan, variant: str | None = None) -> PlanGroup:
    """Client group the headless test replaces with its AI proxy.

    Among ``variant``'s client groups (all client groups when None), prefer one that starts on
    the ground (parking/runway) so on-deck and landing beats stay reachable; else the first.
    """
    clients = [
        g for g in plan.groups if g.client and (variant is None or g.variant in (None, variant))
    ]
    if not clients:
        where = f" in variant {variant!r}" if variant else ""
        raise ValueError(f"plan has no player (client) group{where} to replace with a proxy")
    for g in clients:
        if g.route and g.route[0].action in _PREFERRED_TEST_ACTIONS:
            return g
    return clients[0]
