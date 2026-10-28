"""check_miz: structural checks on a built DMS .miz (``dms check``).

Opens the archive with :class:`dms_core.miz.MizFile` (lupa round-trip, never pydcs) and checks
ids/names, player slots, resources, script order, compiled trigger strings, DMS_CONFIG schema
(:class:`RuntimeConfig`), keys and references, beat reachability, voice files, Lua 5.1 syntax,
fog-of-war hidden flags and map bounds. See docs/CONTRACTS.md "dms check".
"""

# mypy: disallow-untyped-calls=False

from __future__ import annotations

import os
from collections import Counter
from functools import lru_cache
from pathlib import Path
from typing import Any, Literal, get_args

from dms_core import luaio
from dms_core.miz import MizFile
from dms_core.schemas.beats import BeatEvent
from dms_core.schemas.runtime import RuntimeConfig
from pydantic import BaseModel, ConfigDict, Field, ValidationError

Severity = Literal["error", "warning", "info"]
L10N = "l10n/DEFAULT/"
REQUIRED_CONFIG_KEYS = (
    "version",
    "seed",
    "missionId",
    "budgets",
    "director",
    "templates",
    "zones",
    "pools",
    "encounters",
    "beats",
    "voice",
    "intel",
    "players",
)


class CheckIssue(BaseModel):
    """One finding."""

    model_config = ConfigDict(extra="forbid")

    severity: Severity = Field(description="error fails the check; warning/info do not.")
    code: str = Field(description="Stable machine code, e.g. 'duplicate_unit_id'.")
    message: str = Field(description="Human-readable explanation.")
    where: str | None = Field(default=None, description="Group/unit/file/key concerned.")


class CheckReport(BaseModel):
    """Result of :func:`check_miz` (JSON-serializable via ``model_dump_json``)."""

    model_config = ConfigDict(extra="forbid")

    path: str = Field(description="Checked .miz path.")
    ok: bool = Field(default=True, description="True when there are no errors.")
    issues: list[CheckIssue] = Field(default_factory=list, description="All findings.")
    stats: dict[str, int] = Field(default_factory=dict, description="Counts (groups, units, ...).")

    @property
    def errors(self) -> list[CheckIssue]:
        return [i for i in self.issues if i.severity == "error"]

    @property
    def warnings(self) -> list[CheckIssue]:
        return [i for i in self.issues if i.severity == "warning"]

    def add(self, severity: Severity, code: str, message: str, where: str | None = None) -> None:
        self.issues.append(CheckIssue(severity=severity, code=code, message=message, where=where))
        if severity == "error":
            self.ok = False


@lru_cache(maxsize=1)
def _syntax_checker() -> Any:
    try:
        from lupa import lua51 as lua
    except ImportError:  # pragma: no cover - depends on lupa build
        import lupa as lua
    rt = lua.LuaRuntime(encoding=None)
    return rt.eval(
        "function(s, n) local f, e = (loadstring or load)(s, n)"
        " if f then return true, nil end return false, e end"
    )


def lua51_syntax_error(src: bytes, name: str = "chunk") -> str | None:
    """Compile-only check with Lua 5.1 (no execution). Returns the error text or None."""
    ok, err = _syntax_checker()(src, ("=" + name).encode())
    if ok:
        return None
    return err.decode("utf-8", "replace") if isinstance(err, bytes) else str(err)


def _items(t: Any) -> list[Any]:
    if isinstance(t, dict):
        return [t[k] for k in sorted(t, key=lambda k: (not isinstance(k, int), str(k).zfill(8)))]
    if isinstance(t, list):
        return list(t)
    return []


def _groups(mission: dict[Any, Any]) -> list[tuple[str, str, dict[Any, Any]]]:
    out = []
    for side, side_tbl in (mission.get("coalition") or {}).items():
        if not isinstance(side_tbl, dict):
            continue
        for country in _items(side_tbl.get("country")):
            if not isinstance(country, dict):
                continue
            for cat in ("plane", "helicopter", "vehicle", "ship", "static"):
                for g in _items((country.get(cat) or {}).get("group")):
                    if isinstance(g, dict):
                        out.append((str(side), cat, g))
    return out


def _bounds(theatre: str | None) -> tuple[float, float, float, float] | None:
    if not theatre:
        return None
    try:
        from .builder.mission import terrain_by_name

        b = terrain_by_name(theatre).bounds
    except Exception:  # unknown theatre / pydcs missing: skip the bounds check
        return None
    x0, x1 = sorted((float(b.top), float(b.bottom)))
    y0, y1 = sorted((float(b.left), float(b.right)))
    return x0, x1, y0, y1


def check_miz(path: str | os.PathLike[str]) -> CheckReport:
    """Run all checks on the .miz at ``path``. ``report.ok`` is False when any error is found."""
    rep = CheckReport(path=str(path))
    try:
        miz = MizFile.open(path)
        mission = miz.table("mission")
    except Exception as exc:
        rep.add("error", "unreadable", f"cannot open mission: {exc}")
        return rep
    files = set(miz.files())
    try:
        res: dict[str, str] = {str(k): str(v) for k, v in (miz.table("mapResource") or {}).items()}
    except KeyError:
        res = {}

    _check_groups(rep, mission)
    _check_resources(rep, res, files)
    scripts = _check_triggers(rep, mission, res, files)
    if "dms_test.lua" in scripts:
        _relax_for_test_build(rep, scripts)
    config = _check_config(rep, miz, files, scripts)
    _check_lua_syntax(rep, miz, files)
    if config is not None:
        _check_fog(rep, mission, config)
        _check_beat_reachability(rep, mission, config)
    rep.stats.update(
        resources=len(res),
        scripts=len(scripts),
        files=len(files),
        voice=len((config or {}).get("voice") or {}),
    )
    return rep


def _relax_for_test_build(rep: CheckReport, scripts: list[str]) -> None:
    """A ``dms build --test`` miz has an AI player proxy instead of a slot (headless runs)."""
    for i in rep.issues:
        if i.code == "no_player_slot":
            i.severity = "warning"
            i.message = "no Client/Player slot (test build: AI player proxy, not flyable)"
    rep.ok = not rep.errors
    if "dms.lua" in scripts and scripts.index("dms_test.lua") > scripts.index("dms.lua"):
        rep.add("error", "test_script_order", "dms_test.lua must load before dms.lua")


def _check_groups(rep: CheckReport, mission: dict[Any, Any]) -> None:
    groups = _groups(mission)
    gids: Counter[Any] = Counter()
    uids: Counter[Any] = Counter()
    gnames: Counter[str] = Counter()
    unames: Counter[str] = Counter()
    slots = 0
    n_units = 0
    bounds = _bounds(mission.get("theatre"))
    for _side, _cat, g in groups:
        gids[g.get("groupId")] += 1
        gnames[str(g.get("name"))] += 1
        for u in _items(g.get("units")):
            if not isinstance(u, dict):
                continue
            n_units += 1
            uids[u.get("unitId")] += 1
            unames[str(u.get("name"))] += 1
            if u.get("skill") in ("Client", "Player"):
                slots += 1
            x, y = u.get("x"), u.get("y")
            if not isinstance(x, int | float) or not isinstance(y, int | float):
                rep.add("error", "unit_no_position", "unit has no x/y", str(u.get("name")))
                continue
            if bounds and not (bounds[0] <= x <= bounds[1] and bounds[2] <= y <= bounds[3]):
                rep.add(
                    "error",
                    "unit_off_map",
                    f"unit at ({x:.0f}, {y:.0f}) is outside the {mission.get('theatre')} bounds",
                    str(u.get("name")),
                )
            elif x == 0 and y == 0:
                rep.add(
                    "warning",
                    "unit_at_origin",
                    "unit sits at map origin (0, 0)",
                    str(u.get("name")),
                )
    for label, counter in (
        ("group_id", gids),
        ("unit_id", uids),
        ("group_name", gnames),
        ("unit_name", unames),
    ):
        for key, n in counter.items():
            if n > 1:
                rep.add("error", f"duplicate_{label}", f"{label} {key!r} used {n} times", str(key))
    if slots == 0:
        rep.add("error", "no_player_slot", "mission has no Client/Player slot")
    rep.stats.update(groups=len(groups), units=n_units, player_slots=slots)


def _check_resources(rep: CheckReport, res: dict[str, str], files: set[str]) -> None:
    for key, fname in res.items():
        if L10N + fname not in files:
            rep.add(
                "error", "missing_resource", f"mapResource {key} -> '{fname}' not in archive", fname
            )


def _check_triggers(
    rep: CheckReport, mission: dict[Any, Any], res: dict[str, str], files: set[str]
) -> list[str]:
    """Checks compiled trig strings and DO SCRIPT FILE actions; returns script names in order."""
    trig = mission.get("trig") or {}
    actions = trig.get("actions") or {}
    conditions = trig.get("conditions") or {}
    func = trig.get("func") or {}
    func_startup = trig.get("funcStartup") or {}
    rules = mission.get("trigrules") or {}
    rule_items = sorted(rules.items()) if isinstance(rules, dict) else list(enumerate(rules, 1))
    scripts: list[str] = []
    for idx, rule in rule_items:
        if not isinstance(rule, dict):
            continue
        where = f"trigrule {idx} '{rule.get('comment', '')}'"
        act = actions.get(idx) if isinstance(actions, dict) else None
        cond = conditions.get(idx) if isinstance(conditions, dict) else None
        if not isinstance(act, str) or not act:
            rep.add("error", "trig_actions_missing", "compiled trig.actions string missing", where)
        if not isinstance(cond, str) or not cond:
            rep.add(
                "error", "trig_conditions_missing", "compiled trig.conditions string missing", where
            )
        table = func_startup if rule.get("predicate") == "triggerStart" else func
        if not isinstance(table, dict) or not isinstance(table.get(idx), str):
            rep.add(
                "error", "trig_func_missing", "compiled trig.func/funcStartup entry missing", where
            )
        for a in _items(rule.get("actions")):
            if not isinstance(a, dict) or a.get("predicate") != "a_do_script_file":
                continue
            key = str(a.get("file"))
            fname = res.get(key)
            if fname is None:
                rep.add(
                    "error",
                    "script_unregistered",
                    f"DO SCRIPT FILE {key} not in mapResource",
                    where,
                )
                continue
            if L10N + fname not in files:
                rep.add(
                    "error", "script_missing", f"DO SCRIPT FILE '{fname}' not in archive", fname
                )
            scripts.append(fname)
    if "dms.lua" not in scripts:
        rep.add("error", "no_dms_lua", "no DO SCRIPT FILE action loads dms.lua")
    if "dms_config.lua" not in scripts:
        rep.add("error", "no_dms_config", "no DO SCRIPT FILE action loads dms_config.lua")
    if (
        "dms.lua" in scripts
        and "dms_config.lua" in scripts
        and scripts.index("dms_config.lua") > scripts.index("dms.lua")
    ):
        rep.add("error", "script_order", "dms_config.lua must load before dms.lua")
    return scripts


def _check_config(
    rep: CheckReport, miz: MizFile, files: set[str], scripts: list[str]
) -> dict[str, Any] | None:
    path = L10N + "dms_config.lua"
    if path not in files:
        return None
    try:
        cfg = luaio.loads(miz.read_bytes(path), "DMS_CONFIG", arrays=True)
    except Exception as exc:
        rep.add("error", "config_parse", f"dms_config.lua does not evaluate: {exc}", path)
        return None
    if not isinstance(cfg, dict):
        rep.add("error", "config_type", "DMS_CONFIG is not a table", path)
        return None
    for key in REQUIRED_CONFIG_KEYS:
        if key not in cfg:
            rep.add("error", "config_key_missing", f"DMS_CONFIG.{key} missing", path)
    try:
        RuntimeConfig.from_lua_table(cfg)
    except ValidationError as exc:
        errs = exc.errors()
        for err in errs[:20]:
            loc = ".".join(str(p) for p in err["loc"])
            rep.add("error", "config_schema", f"DMS_CONFIG.{loc}: {err['msg']}", path)
        if len(errs) > 20:
            rep.add("error", "config_schema", f"... and {len(errs) - 20} more schema errors", path)

    def as_map(v: Any) -> dict[str, Any]:
        return v if isinstance(v, dict) else {}

    def as_list(v: Any) -> list[Any]:
        return v if isinstance(v, list) else list(as_map(v).values())

    templates, zones, pools = (
        as_map(cfg.get("templates")),
        as_map(cfg.get("zones")),
        as_map(cfg.get("pools")),
    )
    for pid, pool in pools.items():
        for m in as_list(as_map(pool).get("members")):
            if as_map(m).get("tpl") not in templates:
                rep.add(
                    "error",
                    "config_bad_template",
                    f"pool member template {m!r} missing",
                    f"pools.{pid}",
                )
        for z in as_list(as_map(pool).get("zones")):
            if z not in zones:
                rep.add("error", "config_bad_zone", f"pool zone '{z}' missing", f"pools.{pid}")
    beat_ids = {as_map(b).get("id") for b in as_list(cfg.get("beats"))}
    for e in as_list(cfg.get("encounters")):
        e = as_map(e)
        eid = f"encounters.{e.get('id')}"
        if e.get("pool") is not None:
            if e.get("pool") not in pools:
                rep.add(
                    "error", "config_bad_pool", f"encounter pool '{e.get('pool')}' missing", eid
                )
        elif e.get("template") is not None:
            if e.get("template") not in templates:
                rep.add(
                    "error",
                    "config_bad_template",
                    f"encounter template '{e.get('template')}' missing",
                    eid,
                )
        elif e.get("group") is None:
            rep.add("error", "config_no_source", "encounter needs pool, template or group", eid)
        tr = as_map(e.get("trigger"))
        if tr.get("zone") is not None and tr.get("zone") not in zones:
            rep.add("error", "config_bad_zone", f"trigger zone '{tr.get('zone')}' missing", eid)
        if tr.get("beat") is not None and tr.get("beat") not in beat_ids:
            rep.add("warning", "config_bad_beat", f"trigger beat '{tr.get('beat')}' missing", eid)
    voice = as_map(cfg.get("voice"))
    subtitle_only = sorted(str(k) for k, v in voice.items() if not as_map(v).get("file"))
    missing = sorted(
        str(k)
        for k, v in voice.items()
        if as_map(v).get("file") and L10N + str(as_map(v).get("file")) not in files
    )
    if missing:
        rep.add(
            "error",
            "voice_file_missing",
            f"{len(missing)} DMS_CONFIG.voice files are referenced but not in l10n/DEFAULT",
            ", ".join(missing[:10]) + (" ..." if len(missing) > 10 else ""),
        )
    if subtitle_only:
        rep.add(
            "warning",
            "voice_subtitle_only",
            f"{len(subtitle_only)} of {len(voice)} voice lines have no audio (subtitles only); "
            "run `dms voice` and re-plan with the manifest to add audio",
            ", ".join(subtitle_only[:10]) + (" ..." if len(subtitle_only) > 10 else ""),
        )
    for b in as_list(cfg.get("beats")):
        b = as_map(b)
        absent = [str(lid) for lid in as_list(b.get("lines")) if lid not in voice]
        if absent:
            rep.add(
                "error",
                "beat_line_missing",
                f"beat '{b.get('id')}' lines not in DMS_CONFIG.voice: {', '.join(absent)}",
                str(b.get("id")),
            )
    rep.stats.update(
        templates=len(templates),
        zones=len(zones),
        pools=len(pools),
        encounters=len(as_list(cfg.get("encounters"))),
        beats=len(beat_ids),
    )
    return cfg


def _check_lua_syntax(rep: CheckReport, miz: MizFile, files: set[str]) -> None:
    for f in sorted(files):
        if f.lower().endswith(".lua"):
            err = lua51_syntax_error(miz.read_bytes(f), Path(f).name)
            if err:
                rep.add("error", "lua_syntax", f"Lua 5.1 syntax error: {err}", f)


def _check_fog(rep: CheckReport, mission: dict[Any, Any], cfg: dict[str, Any]) -> None:
    intel_v = cfg.get("intel")
    intel: dict[str, Any] = intel_v if isinstance(intel_v, dict) else {}
    if not intel.get("fogOfWar"):
        return
    players_v = cfg.get("players")
    players: dict[str, Any] = players_v if isinstance(players_v, dict) else {}
    enemy = "red" if players.get("coalition", 2) == 2 else "blue"
    known_v = intel.get("knownGroups")
    known = {str(n) for n in known_v.values()} if isinstance(known_v, dict) else set()
    if isinstance(known_v, list):
        known = {str(n) for n in known_v}
    for side, cat, g in _groups(mission):
        if side == enemy and cat != "static" and not g.get("hidden") and g.get("name") not in known:
            rep.add(
                "warning",
                "enemy_not_hidden",
                "fog of war is on but this enemy group is visible on the F10 map",
                str(g.get("name")),
            )


KNOWN_EVENTS = frozenset(get_args(BeatEvent))


def _as_map(v: Any) -> dict[Any, Any]:
    return v if isinstance(v, dict) else {}


def _as_list(v: Any) -> list[Any]:
    if isinstance(v, list):
        return v
    if isinstance(v, dict):
        return list(v.values())
    return [] if v is None else [v]


def _set_flags(effects: dict[Any, Any]) -> set[str]:
    """Flag names a beat's effects set (setFlag string, list, or {name = value} map)."""
    sf = effects.get("setFlag")
    if isinstance(sf, dict):
        return {str(v) if isinstance(k, int) else str(k) for k, v in sf.items()}
    return {str(f) for f in _as_list(sf)}


def _me_flags(mission: dict[Any, Any]) -> set[str]:
    """Flags any mission-editor trigger action sets (a_set_flag and friends)."""
    out: set[str] = set()
    for rule in _as_list(mission.get("trigrules")):
        for a in _as_list(_as_map(rule).get("actions")):
            a = _as_map(a)
            if "flag" in str(a.get("predicate", "")) and a.get("flag") is not None:
                out.add(str(a.get("flag")))
    return out


def _me_zones(mission: dict[Any, Any]) -> set[str]:
    zones = _as_map(mission.get("triggers")).get("zones")
    return {str(_as_map(z).get("name")) for z in _as_list(zones) if _as_map(z).get("name")}


def _when_event(w: dict[Any, Any]) -> Any:
    """Canonical event of a `when` table, resolving the Lua shorthand forms."""
    if w.get("event") is not None:
        return w.get("event")
    if w.get("afterSec") is not None or w.get("timer") is not None:
        return "timer"
    if w.get("flag") is not None:
        return "flag"
    if w.get("zone") is not None:
        return "zone.entered"
    if w.get("director") is not None or w.get("directorState") is not None:
        return "director.state"
    if w.get("beat") is not None:
        return "beat.fired"
    return None


def _check_beat_reachability(
    rep: CheckReport, mission: dict[Any, Any], cfg: dict[str, Any]
) -> None:
    """Beats whose trigger can never fire (contract: guaranteed beats must be reachable)."""
    beats = [_as_map(b) for b in _as_list(cfg.get("beats"))]
    if not beats:
        return
    groups = _groups(mission)
    me_groups = {str(g.get("name")) for _s, _c, g in groups}
    me_units = {str(_as_map(u).get("name")) for _s, _c, g in groups for u in _items(g.get("units"))}
    spawn_ids = {str(k) for k in _as_map(cfg.get("pools"))} | {
        str(k) for k in _as_map(cfg.get("templates"))
    }
    zones = {str(k) for k in _as_map(cfg.get("zones"))} | _me_zones(mission)
    encounters = {str(_as_map(e).get("id")) for e in _as_list(cfg.get("encounters"))}
    director_on = _as_map(cfg.get("director")).get("enabled", True) is not False

    def runtime_name(name: str) -> bool:
        """Could a runtime spawn (DMS_<poolOrTemplate>_<n>[...]) carry this name?"""
        return name.startswith("DMS_") and any(name[4:].startswith(i + "_") for i in spawn_ids)

    def prefix_ok(prefix: str, names: set[str]) -> bool:
        if any(n.startswith(prefix) for n in names):
            return True
        bare = prefix[4:] if prefix.startswith("DMS_") else prefix
        return any(i.startswith(bare) or bare.startswith(i + "_") for i in spawn_ids)

    def static_problem(b: dict[Any, Any]) -> str | None:
        w = _as_map(b.get("when"))
        ev = _when_event(w)
        if ev is None:
            return "trigger has no event"
        if ev not in KNOWN_EVENTS:
            return f"unknown event '{ev}'"
        z = w.get("zone")
        if z is not None and str(z) not in zones:
            return f"unknown zone '{z}'"
        g = w.get("group")
        if g is not None and str(g) not in me_groups and not runtime_name(str(g)):
            return f"unknown group '{g}'"
        gp = w.get("groupPrefix")
        if gp is not None and not prefix_ok(str(gp), me_groups):
            return f"no group matches prefix '{gp}'"
        u = w.get("unit")
        if u is not None and str(u) not in me_units and not runtime_name(str(u)):
            return f"unknown unit '{u}'"
        up = w.get("unitPrefix")
        if up is not None and not prefix_ok(str(up), me_units):
            return f"no unit matches prefix '{up}'"
        enc = w.get("encounter")
        if ev == "encounter.spawned" and enc is not None and str(enc) not in encounters:
            return f"unknown encounter '{enc}'"
        if ev == "director.state" and not director_on:
            return "director.state trigger but the director is disabled"
        return None

    def needs(b: dict[Any, Any]) -> tuple[set[str], set[str]]:
        """(flags, beat ids) that must become available before the beat can fire."""
        w = _as_map(b.get("when"))
        req = _as_map(b.get("requires"))
        raw = req.get("flags")
        if isinstance(raw, dict) and not all(isinstance(k, int) for k in raw):
            flags = {str(k) for k, v in raw.items() if v is True}
        else:
            flags = {str(f) for f in _as_list(raw)}
        flags |= {str(f) for f in _as_list(req.get("flagsSet"))}
        ev = _when_event(w)
        if ev == "flag" and w.get("flag") is not None:
            value = w.get("value")
            if (
                value is None
                or value is True
                or (isinstance(value, int | float) and not isinstance(value, bool) and value != 0)
            ):
                flags.add(str(w.get("flag")))
        deps = {str(x) for x in _as_list(req.get("beatsFired"))}
        if ev == "beat.fired" and w.get("beat") is not None:
            deps.add(str(w.get("beat")))
        return flags, deps

    by_id = {str(b.get("id")): b for b in beats}
    problems = {bid: static_problem(b) for bid, b in by_id.items()}
    reachable: set[str] = set()
    flags_available = _me_flags(mission)
    changed = True
    while changed:
        changed = False
        for bid, b in by_id.items():
            if bid in reachable or problems[bid]:
                continue
            flags, deps = needs(b)
            if flags <= flags_available and deps <= reachable:
                reachable.add(bid)
                flags_available |= _set_flags(_as_map(b.get("effects")))
                changed = True
    for bid, b in by_id.items():
        if bid in reachable:
            continue
        why = problems[bid]
        if why is None:
            flags, deps = needs(b)
            parts = [f"flag '{f}' is never set" for f in sorted(flags - flags_available)]
            parts += [
                f"beat '{d}' " + ("does not exist" if d not in by_id else "can never fire")
                for d in sorted(deps - reachable)
            ]
            why = "; ".join(parts) or "unreachable"
        if b.get("guaranteed"):
            rep.add(
                "error",
                "guaranteed_unreachable",
                f"guaranteed beat '{bid}' can never fire: {why}",
                f"beats.{bid}",
            )
        else:
            rep.add(
                "warning",
                "beat_unreachable",
                f"beat '{bid}' can never fire: {why}",
                f"beats.{bid}",
            )
