"""Semantic validation of a MissionSpec (+ beats/lines/bible) with repair suggestions.

Schema-level checks are pydantic's job. This checks what pydantic cannot: airbases and places
exist on the theater, aircraft/unit types exist and fit era and coalition, loadouts resolve,
objectives are within plausible range, threat density is sane, and cross-file references.
"""

# mypy: disallow-untyped-calls=False

from __future__ import annotations

import math
from collections import Counter

from dms_core import catalog as cat
from dms_core.schemas.beats import Beat, BeatSheet
from dms_core.schemas.mission import MissionSpec, NearAirbase, NearNamedPlace
from dms_core.schemas.runtime import Budgets
from dms_core.schemas.story import StoryBible
from dms_core.schemas.validation import Issue, suggest, validate_mission_bundle
from dms_core.schemas.voice import VoiceLineSet

from ..builder.mission import (
    aircraft_type,
    callsign_names,
    closest_callsign,
    support_callsign_names,
)
from . import forces
from .context import (
    canonical_country,
    country_names,
    era_for_year,
    faction_map,
    on_map,
    resolve_areas,
)
from .loadouts import choose_loadout

SP = "mission-spec.yaml:"
#: Plausible radius of action (km) from the player's base, by aircraft category.
RANGE_KM = {"helicopter": 150.0, "plane": 600.0}


def _err(path: str, problem: str, sugg: list[str] | None = None) -> Issue:
    return Issue(path=SP + path, problem=problem, suggestions=sugg or [])


def _warn(path: str, problem: str, sugg: list[str] | None = None) -> Issue:
    return Issue(path=SP + path, problem=problem, suggestions=sugg or [], severity="warning")


def validate(
    spec: MissionSpec,
    beats: BeatSheet | list[Beat] | None = None,
    lines: VoiceLineSet | None = None,
    bible: StoryBible | None = None,
    *,
    extra_places: dict[str, tuple[float, float]] | None = None,
) -> list[Issue]:
    """Semantic issues (errors and warnings) with suggestions. Empty error list = plannable."""
    issues: list[Issue] = []
    c = cat.load_catalog()
    theater = spec.theater
    era = era_for_year(spec.era)
    if era is None:
        issues.append(_warn("era", f"no catalog era covers {spec.era}; unit era checks skipped"))
    factions = faction_map(bible)

    # --- countries ------------------------------------------------------------------------
    known_countries = country_names()
    for side in ("blue_countries", "red_countries"):
        for i, name in enumerate(getattr(spec, side)):
            canon = canonical_country(name)
            if canon is None:
                issues.append(
                    _err(
                        f"{side}[{i}]",
                        f"unknown DCS country '{name}'",
                        suggest(name, known_countries),
                    )
                )
            elif canon != name:
                issues.append(
                    _warn(f"{side}[{i}]", f"'{name}' is an alias of DCS country '{canon}'", [canon])
                )
    blue_c = {canonical_country(n) or n for n in spec.blue_countries}
    red_c = {canonical_country(n) or n for n in spec.red_countries}
    overlap = blue_c & red_c
    if overlap:
        issues.append(_err("red_countries", f"countries on both sides: {sorted(overlap)}"))

    # --- areas ----------------------------------------------------------------------------
    resolved, area_errors = resolve_areas(spec, extra_places)
    for i, a in enumerate(spec.areas):
        path = f"areas[{i}].where"
        if a.id in area_errors:
            w = a.where
            if isinstance(w, NearAirbase):
                issues.append(
                    _err(
                        path + ".airbase",
                        f"unknown airbase '{w.airbase}' on {theater}",
                        cat.suggest(w.airbase, "airbase", theater=theater, n=3),
                    )
                )
            elif isinstance(w, NearNamedPlace):
                from .context import airbase_names
                from .places import suggest_place

                issues.append(
                    _err(
                        path + ".place",
                        f"unknown place '{w.place}' on {theater} (not in the DMS gazetteer or "
                        "airbase list); use a latlon area or a known place",
                        suggest_place(theater, w.place, airbase_names(theater)),
                    )
                )
            else:
                issues.append(_err(path, area_errors[a.id]))
            continue
        r = resolved[a.id]
        if not on_map(theater, r.x, r.y):
            issues.append(_err(path, f"area '{a.id}' lies outside the {theater} map bounds"))

    # --- player flights -------------------------------------------------------------------
    side_num = {"blue": "blue_countries", "red": "red_countries"}
    for i, f in enumerate(spec.player_flights):
        fp = f"player_flights[{i}]"
        cat_ac = c.units.get(f.aircraft)
        category = None
        try:
            ac = aircraft_type(f.aircraft)
            category = "helicopter" if getattr(ac, "helicopter", False) else "plane"
        except (KeyError, ValueError):
            issues.append(
                _err(
                    fp + ".aircraft",
                    f"unknown aircraft type '{f.aircraft}'",
                    c.suggest(f.aircraft, "unit"),
                )
            )
        if cat_ac is None and category is not None:
            issues.append(_warn(fp + ".aircraft", f"'{f.aircraft}' is not in the DMS catalog"))
        if cat_ac is not None:
            if cat_ac.category not in ("plane", "helicopter"):
                issues.append(_err(fp + ".aircraft", f"'{f.aircraft}' is not an aircraft"))
            if era and era not in cat_ac.eras:
                issues.append(
                    _warn(
                        fp + ".aircraft",
                        f"'{f.aircraft}' is not typical for era {era} ({spec.era})",
                    )
                )
            if f.coalition not in cat_ac.coalitions:
                issues.append(
                    _warn(fp + ".aircraft", f"'{f.aircraft}' is not usually flown by {f.coalition}")
                )
            if "player" not in cat_ac.tags:
                issues.append(_warn(fp + ".aircraft", f"'{f.aircraft}' may not be player-flyable"))
        side_set = blue_c if f.coalition == "blue" else red_c
        if f.coalition in side_num and (canonical_country(f.country) or f.country) not in side_set:
            issues.append(
                _err(
                    fp + ".country",
                    f"country '{f.country}' is not in {side_num[f.coalition]}",
                    list(getattr(spec, side_num[f.coalition])),
                )
            )
        if category is not None:
            choice = choose_loadout(f.aircraft, f.loadout, spec.mission_type)
            if not choice.ok:
                issues.append(_warn(fp + ".loadout", choice.note))
            names = callsign_names(f.aircraft, canonical_country(f.country) or f.country)
            got = closest_callsign(f.callsign, names)
            if got is not None and got.lower() != f.callsign.lower():
                issues.append(
                    _warn(
                        fp + ".callsign",
                        f"callsign {f.callsign} not available for {f.aircraft} ({f.country}); "
                        f"using {got} 1-1 in the cockpit. Use the real radio callsign in the "
                        "briefing, or pick one of the valid names",
                        names,
                    )
                )
            if f.start_type == "air" and category == "helicopter" and f.air_start is not None:
                issues.append(
                    _warn(fp + ".air_start", "air_start is ignored for helicopters (low air start)")
                )
        start = resolved.get(f.start_area)
        if start is not None and f.start_type != "air" and start.airbase is None:
            issues.append(
                _warn(
                    fp + ".start_area",
                    f"start_type '{f.start_type}' needs a near_airbase area; flight will air-start",
                )
            )
        # range to objectives
        if start is not None and category is not None:
            limit = RANGE_KM[category]
            for j, o in enumerate(spec.objectives):
                if not o.area or o.area not in resolved:
                    continue
                d_km = math.dist(start.center, resolved[o.area].center) / 1000
                if d_km > 2 * limit:
                    issues.append(
                        _err(
                            f"objectives[{j}].area",
                            f"objective '{o.id}' is {d_km:.0f} km from {f.callsign}'s start; "
                            f"far beyond a {category}'s ~{limit:.0f} km radius",
                            [
                                a.name
                                for a in cat.find_airbases(
                                    theater, resolved[o.area].center, limit=3
                                )
                            ],
                        )
                    )
                elif d_km > limit:
                    issues.append(
                        _warn(
                            f"objectives[{j}].area",
                            f"objective '{o.id}' is {d_km:.0f} km from {f.callsign}'s start "
                            f"(> ~{limit:.0f} km for a {category}); consider a closer base",
                            [
                                a.name
                                for a in cat.find_airbases(
                                    theater, resolved[o.area].center, limit=3
                                )
                            ],
                        )
                    )

    # one single-player lead per variant (flights without a variant are in every variant)
    seen_player: dict[str | None, int] = {}
    for i, f in enumerate(spec.player_flights):
        if f.slot != "player":
            continue
        v = f.variant
        clash = next((j for k, j in seen_player.items() if v is None or k is None or k == v), None)
        if clash is not None:
            issues.append(
                _warn(
                    f"player_flights[{i}].slot",
                    f"player_flights[{clash}] is already the single-player 'player' flight of "
                    f"variant '{v or 'all'}'; this flight is planned as 'client' slots. Give "
                    "start options different `variant`s (e.g. ramp / air) or set slot: client",
                )
            )
        else:
            seen_player[v] = i

    # --- threats --------------------------------------------------------------------------
    roles = Counter(t.role for t in spec.threats)
    est_units = 0
    for i, t in enumerate(spec.threats):
        tp = f"threats[{i}]"
        if t.faction and bible is not None and t.faction not in factions:
            issues.append(
                _err(
                    tp + ".faction", f"unknown faction '{t.faction}'", suggest(t.faction, factions)
                )
            )
        if t.faction and t.faction in factions and factions[t.faction][1] not in ("red", "neutral"):
            issues.append(_warn(tp + ".faction", f"faction '{t.faction}' is not red"))
        ch = forces.candidates(t.role, era, factions.get(t.faction or ""), t.faction, t.strength)
        if t.templates:
            role_ids = forces.ROLE_TEMPLATES.get(t.role, [])
            ok = forces.pinned(t.role, era, t.templates)
            bad = [i for i in t.templates if i not in {x.id for x in ok}]
            if not ok:
                issues.append(
                    _err(
                        tp + ".templates",
                        f"none of {t.templates} is a '{t.role}' template for era {era}",
                        [x.id for x in forces.candidates(t.role, era)] or role_ids,
                    )
                )
            elif bad:
                issues.append(
                    _warn(
                        tp + ".templates",
                        f"ignored (not a '{t.role}' template for era {era}): {bad}",
                        [x.id for x in forces.candidates(t.role, era)],
                    )
                )
        if not ch:
            issues.append(
                _err(
                    tp + ".role",
                    f"no catalog template for role '{t.role}' in era {era}; it would be skipped",
                )
            )
            continue
        est_units += max(x.size for x in ch) * forces.group_count(t.role, t.strength)
        ta = resolved.get(t.area)
        if ta is not None and t.role != "ship" and ta.terrain_hint == "water":
            issues.append(_err(tp + ".area", f"ground threat '{t.id}' placed in a water area"))
    if roles["sam_long"] > 2:
        issues.append(_warn("threats", f"{roles['sam_long']} long-range SAMs: very dense IADS"))
    n_sam = sum(n for r, n in roles.items() if r in forces.SAM_ROLES)
    if n_sam > 6:
        issues.append(_warn("threats", f"{n_sam} SAM sites: consider fewer or use pools"))
    helo_players = any(
        c.units.get(f.aircraft) is not None and c.units[f.aircraft].category == "helicopter"
        for f in spec.player_flights
    )
    if helo_players and (roles["sam_medium"] or roles["sam_long"]):
        issues.append(
            _warn("threats", "medium/long SAMs against helicopter players are rarely survivable")
        )

    for fid, (fc, fside, _u) in factions.items():
        canon = canonical_country(fc)
        used = (
            any(t.faction == fid for t in spec.threats)
            or any(p.faction == fid for p in spec.dynamic.pools)
            or any(s.faction == fid for s in spec.support)
        )
        if not used:
            continue
        if canon is None:
            issues.append(_err("threats", f"faction '{fid}' uses unknown DCS country '{fc}'"))
        elif fside == "neutral":
            if canon in blue_c or canon in red_c:
                issues.append(
                    _warn(
                        "threats",
                        f"neutral faction '{fid}' country '{canon}' is also a blue/red country; "
                        "it stays in that coalition, not neutral",
                    )
                )
        elif canon not in (blue_c if fside == "blue" else red_c):
            issues.append(
                _warn(
                    "red_countries",
                    f"faction '{fid}' country '{canon}' is not in the spec's "
                    f"{fside} countries; the planner uses the side's first country instead",
                )
            )

    # --- pools / encounters ----------------------------------------------------------------
    pool_ids = {p.id for p in spec.dynamic.pools}
    for i, p in enumerate(spec.dynamic.pools):
        pp = f"dynamic.pools[{i}]"
        lo, hi = p.pick
        if lo > hi or lo < 0:
            issues.append(_err(pp + ".pick", f"pick {list(p.pick)} must be [min<=max], min>=0"))
        if p.faction and bible is not None and p.faction not in factions:
            issues.append(
                _err(
                    pp + ".faction", f"unknown faction '{p.faction}'", suggest(p.faction, factions)
                )
            )
        if p.templates:
            ok_ids = {x.id for role in p.roles for x in forces.pinned(role, era, p.templates)}
            bad = [i for i in p.templates if i not in ok_ids]
            role_ids = [x.id for role in p.roles for x in forces.candidates(role, era)]
            if not ok_ids:
                issues.append(
                    _err(
                        pp + ".templates",
                        f"none of {p.templates} is a template of roles {list(p.roles)} "
                        f"for era {era}",
                        role_ids,
                    )
                )
            elif bad:
                issues.append(
                    _warn(
                        pp + ".templates",
                        f"ignored (not a template of roles {list(p.roles)} for era {era}): {bad}",
                        role_ids,
                    )
                )
        biggest = 0
        for j, role in enumerate(p.roles):
            ch = forces.candidates(role, era, factions.get(p.faction or ""), p.faction, "medium")
            if not ch:
                issues.append(
                    _err(f"{pp}.roles[{j}]", f"no template for role '{role}' in era {era}")
                )
            else:
                biggest = max(biggest, max(x.size for x in ch))
        est_units += biggest * max(hi, 0)
        for j, pa in enumerate(p.areas):
            ra = resolved.get(pa)
            if ra is not None and ra.terrain_hint == "water":
                issues.append(_warn(f"{pp}.areas[{j}]", f"pool area '{pa}' is marked water"))
    budget = Budgets().max_active_ground
    if est_units > budget:
        issues.append(
            _err("threats", f"~{est_units} ground units at peak exceeds the budget of {budget}")
        )
    elif est_units > budget * 0.7:
        issues.append(
            _warn("threats", f"~{est_units} ground units at peak is close to the budget {budget}")
        )

    pool_roles = {p.id: set(p.roles) for p in spec.dynamic.pools}
    for i, e in enumerate(spec.dynamic.encounters):
        ep = f"dynamic.encounters[{i}]"
        if e.pool in pool_roles:
            if e.kind == "ambush_sam" and not (pool_roles[e.pool] & forces.AIR_DEFENSE_ROLES):
                issues.append(
                    _warn(ep + ".pool", f"ambush_sam pool '{e.pool}' has no air-defence roles")
                )
            if e.kind == "cap" and not (pool_roles[e.pool] & forces.AIR_ROLES):
                issues.append(_warn(ep + ".pool", f"cap pool '{e.pool}' has no air roles"))
        if e.kind == "ambush_sam" and not e.telegraph_beat:
            issues.append(
                _warn(ep + ".telegraph_beat", "pop-up threats should be telegraphed 30-60 s before")
            )
        if e.kind == "waves" and e.waves is None:
            issues.append(_warn(ep + ".waves", "kind=waves without 'waves'; planner uses 3"))
        if e.gap_min and e.gap_min[0] > e.gap_min[1]:
            issues.append(_err(ep + ".gap_min", "gap_min must be [min, max]"))
        if e.trigger.type == "proximity" and e.trigger.radius_nm is None:
            issues.append(_warn(ep + ".trigger.radius_nm", "no radius; planner uses 5 nm"))

    # --- objectives / support --------------------------------------------------------------
    threat_ids = [t.id for t in spec.threats]
    support_ids = [s.id for s in spec.support]
    for i, o in enumerate(spec.objectives):
        op = f"objectives[{i}]"
        if o.target:
            pool_like = threat_ids + support_ids + list(pool_ids)
            if o.target not in pool_like:
                issues.append(
                    _err(
                        op + ".target", f"unknown target '{o.target}'", suggest(o.target, pool_like)
                    )
                )
            elif o.kind in ("protect", "escort") and o.target not in support_ids:
                issues.append(
                    _warn(op + ".target", f"{o.kind} target '{o.target}' is not a support asset")
                )
        if o.kind in ("destroy", "recon", "reach", "rescue") and not o.area and not o.target:
            issues.append(_warn(op, f"{o.kind} objective without area or target"))
    for i, s in enumerate(spec.support):
        sp = f"support[{i}]"
        if s.faction and bible is not None and s.faction not in factions:
            issues.append(
                _err(
                    sp + ".faction", f"unknown faction '{s.faction}'", suggest(s.faction, factions)
                )
            )
        elif s.faction and s.faction in factions:
            fside = factions[s.faction][1]
            pside = spec.player_flights[0].coalition
            if fside != pside:
                issues.append(
                    _warn(
                        sp + ".faction",
                        f"faction '{s.faction}' is {fside}, not the players' side ({pside}); "
                        "the first country of the players' side is used",
                    )
                )
        if s.role in ("awacs", "tanker") and s.callsign:
            from .planning import _SUPPORT_AIR, split_callsign

            tpl = c.templates.get(_SUPPORT_AIR[s.role][0])
            if tpl is not None and tpl.units:
                pf = spec.player_flights[0].country
                country = canonical_country(pf) or pf
                names = support_callsign_names(tpl.units[0].type, country)
                wanted, _num = split_callsign(s.callsign)
                got = closest_callsign(wanted, names)
                if got is not None and got.lower() != wanted.lower():
                    issues.append(
                        _warn(
                            sp + ".callsign",
                            f"callsign {s.callsign} is not a DCS {s.role} callsign; "
                            f"using {got} in DCS. Use one of the valid names",
                            names,
                        )
                    )
        if s.tacan and s.role != "tanker":
            issues.append(_warn(sp + ".tacan", "tacan is only used for tankers; ignored"))
        if s.role in ("medevac", "farp"):
            issues.append(
                _warn(sp + ".role", f"support role '{s.role}' is not built yet; it is skipped")
            )
        if s.role == "convoy" and len(s.route) < 2:
            issues.append(_warn(sp + ".route", "convoy needs a route of >= 2 areas to move"))
        if s.role in ("convoy", "friendly_ground", "jtac") and not s.area and not s.route:
            issues.append(_err(sp, f"{s.role} '{s.id}' needs an area or route"))
        _types, bad = forces.parse_composition(s.composition)
        for tok in bad:
            issues.append(
                _warn(
                    sp + ".composition",
                    f"unknown unit '{tok}' in composition",
                    c.suggest(tok, "unit", n=3),
                )
            )

    # --- cross-file refs ---------------------------------------------------------------------
    if beats is not None:
        bundle = validate_mission_bundle(spec, beats, lines or VoiceLineSet(), bible)
        if lines is None:
            bundle = [x for x in bundle if "unknown voice line" not in x.problem]
        issues.extend(bundle)
        beat_list = beats.beats if isinstance(beats, BeatSheet) else beats
        prefixes = (
            threat_ids
            + support_ids
            + list(pool_ids)
            + [e.id for e in spec.dynamic.encounters]
            + [o.target or o.id for o in spec.objectives]
            + [f.callsign for f in spec.player_flights]
        )
        for i, b in enumerate(beat_list):
            ref = b.when.group or b.when.group_prefix
            if ref and not any(ref.startswith(p) or p.startswith(ref) for p in prefixes):
                issues.append(
                    Issue(
                        path=f"beats.yaml:beats[{i}].when",
                        problem=f"group filter '{ref}' matches no threat/pool/support/encounter id",
                        suggestions=suggest(ref, prefixes),
                        severity="warning",
                    )
                )
    else:
        area_ids = spec.area_ids()
        for path, area in spec.referenced_areas():
            if area not in area_ids:
                issues.append(_err(path, f"unknown area '{area}'", suggest(area, area_ids)))
        for i, e in enumerate(spec.dynamic.encounters):
            if e.pool not in pool_ids:
                issues.append(
                    _err(
                        f"dynamic.encounters[{i}].pool",
                        f"unknown pool '{e.pool}'",
                        suggest(e.pool, pool_ids),
                    )
                )
    return issues


def has_errors(issues: list[Issue]) -> bool:
    return any(i.severity == "error" for i in issues)
