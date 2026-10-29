"""Contract checks: config schema, encounter sources, beat reachability, script order, convoy
compile, test/effects schema and campaign qualities (docs/CONTRACTS.md "dms check")."""

from __future__ import annotations

import datetime as dt
from pathlib import Path
from typing import Any

import pytest
import yaml
from dms_core import luaio
from dms_core.schemas.beats import Beat, BeatEffects
from dms_core.schemas.plan import BuildPlan, PlanGroup, PlanResource, PlanUnit, PlanWaypoint
from dms_core.schemas.runtime import (
    CircleZone,
    Encounter,
    EncounterTrigger,
    Pool,
    PoolMember,
    RuntimeConfig,
    Template,
    TemplateUnit,
    TestSettings,
    from_lua,
)
from dms_gen.builder import build_from_plan, inspect
from dms_gen.check import CheckReport, check_miz
from dms_gen.planner import (
    build_test_lua,
    load_campaign_flags,
    load_campaign_qualities,
    plan_mission,
)
from pydantic import ValidationError

REPO = Path(__file__).resolve().parents[3]


def _plan(resources: list[PlanResource], runtime: RuntimeConfig | None) -> BuildPlan:
    return BuildPlan(
        mission_id="c01",
        seed=1,
        theater="Syria",
        date=dt.date(2012, 4, 1),
        start_time_sec=3600 * 6,
        blue_countries=["USA"],
        red_countries=["Insurgents"],
        groups=[
            PlanGroup(
                name="Dusty 1",
                category="helicopter",
                coalition="blue",
                country="USA",
                client=True,
                units=[PlanUnit(name="Dusty 1-1", type="AH-64D_BLK_II", x=0, y=0, skill="Client")],
                route=[PlanWaypoint(x=0, y=0, action="From Parking Area", airbase="Hatay")],
            ),
            PlanGroup(
                name="HVT",
                category="vehicle",
                coalition="red",
                country="Insurgents",
                hidden=True,
                units=[PlanUnit(name="HVT-1", type="BMP-2", x=140000, y=60000)],
            ),
        ],
        resources=resources,
        runtime=runtime,
    )


def _build(tmp: Path, cfg_src: str, name: str = "c.miz") -> CheckReport:
    (tmp / "dms_config.lua").write_text(cfg_src, encoding="utf-8")
    (tmp / "dms.lua").write_text("x = 1", encoding="utf-8")
    res = [
        PlanResource(path="l10n/DEFAULT/dms_config.lua", source="dms_config.lua", kind="script"),
        PlanResource(path="l10n/DEFAULT/dms.lua", source="dms.lua", kind="script"),
    ]
    return check_miz(build_from_plan(_plan(res, None), tmp / name, base_dir=tmp))


def _codes(rep: CheckReport, severity: str | None = None) -> set[str]:
    return {i.code for i in rep.issues if severity is None or i.severity == severity}


def _rt(**kw: Any) -> RuntimeConfig:
    base: dict[str, Any] = {
        "mission_id": "c01",
        "templates": {
            "zu23": Template(
                country="INSURGENTS", category="ground", units=[TemplateUnit(type="ZU-23")]
            )
        },
        "zones": {"box": CircleZone(x=100, y=100, radius=1000)},
        "pools": {"aaa": Pool(members=[PoolMember(tpl="zu23")], zones=["box"])},
    }
    base.update(kw)
    return RuntimeConfig(**base)


# ---------------------------------------------------------------------------- 1. config schema


def test_config_schema_validated(tmp_path: Path) -> None:
    ok = _build(tmp_path, _rt().to_lua_source(), "ok.miz")
    assert "config_schema" not in _codes(ok) and ok.ok, ok.issues
    bad_src = _rt().to_lua_source() + "\nDMS_CONFIG.budgets.maxActiveGround = -5"
    bad_src += "\nDMS_CONFIG.bogusKey = 1\nDMS_CONFIG.players.coalition = 7\n"
    rep = _build(tmp_path, bad_src, "bad.miz")
    msgs = [i.message for i in rep.issues if i.code == "config_schema"]
    assert not rep.ok
    assert any("budgets.max_active_ground" in m for m in msgs), msgs
    assert any("bogusKey" in m for m in msgs), msgs
    assert any("players.coalition" in m for m in msgs), msgs


def test_from_lua_roundtrip_and_empty_tables() -> None:
    rt = _rt(
        encounters=[
            Encounter(
                id="c1",
                kind="convoy",
                pool="aaa",
                trigger=EncounterTrigger(type="time", after_sec=(10, 20)),
                destination="box",
                resume_after_sec=(60, 120),
            )
        ],
        beats=[
            Beat(
                id="b1",
                when={"event": "timer", "after_sec": 5},  # type: ignore[arg-type]
                requires={"flags_not": ["x"]},  # type: ignore[arg-type]
                effects=BeatEffects(
                    outcome={"done": True},
                    quality_deltas={"trust": 1},
                    speak={"speaker": "ops", "text": "Hi"},  # type: ignore[arg-type]
                    mark={"at": "zone:box", "radius_m": 500},  # type: ignore[arg-type]
                ),
            )
        ],
        test=TestSettings(player_proxy="Proxy 1", minutes=30),
    )
    table = luaio.loads(rt.to_lua_source(), "DMS_CONFIG", arrays=True)
    assert RuntimeConfig.from_lua_table(table) == rt
    # empty Lua tables may come back as {} or []
    assert RuntimeConfig.from_lua_table({"missionId": "c01", "beats": {}, "zones": []}).beats == []


# ---------------------------------------------------------------- 2. encounter sources


def test_encounter_template_or_group_is_not_a_bad_pool(tmp_path: Path) -> None:
    tr = EncounterTrigger(type="manual")
    rt = _rt(
        encounters=[
            Encounter(id="by_tpl", kind="pool", template="zu23", zone="box", trigger=tr),
            Encounter(id="by_group", kind="convoy", group="HVT", destination="box", trigger=tr),
            Encounter(id="by_pool", kind="pool", pool="aaa", trigger=tr),
        ]
    )
    rep = _build(tmp_path, rt.to_lua_source(), "ok.miz")
    assert not _codes(rep) & {"config_bad_pool", "config_bad_template", "config_no_source"}
    assert rep.ok, rep.issues

    src = rt.to_lua_source() + (
        '\nDMS_CONFIG.encounters[1].template = "nope"'
        '\nDMS_CONFIG.encounters[3].pool = "gone"'
        '\nDMS_CONFIG.encounters[4] = {id = "orphan", kind = "pool", '
        'trigger = {type = "manual"}}\n'
    )
    codes = _codes(_build(tmp_path, src, "bad.miz"))
    assert {"config_bad_template", "config_bad_pool", "config_no_source"} <= codes


# ---------------------------------------------------------------- 3. beat reachability


def _beat(bid: str, when: dict[str, Any], guaranteed: bool = True, **kw: Any) -> Beat:
    return Beat.model_validate({"id": bid, "when": when, "guaranteed": guaranteed, **kw})


def test_reachable_beats_pass(tmp_path: Path) -> None:
    beats = [
        _beat("start", {"event": "mission.start"}, effects={"set_flag": "go"}),
        _beat("chain", {"event": "beat.fired", "beat": "start"}),
        _beat("on_flag", {"event": "flag", "flag": "go"}),
        _beat("in_box", {"event": "zone.entered", "zone": "box"}, requires={"flags": ["go"]}),
        _beat("hvt_dead", {"event": "group.dead", "group": "HVT"}),
        _beat("aaa_dead", {"event": "group.dead", "group_prefix": "aaa"}),
        _beat("aaa_exact", {"event": "group.dead", "group": "DMS_aaa_1"}),
        _beat("unit_hit", {"event": "unit.hit", "unit": "HVT-1"}),
        _beat("enc", {"event": "encounter.spawned", "encounter": "popup"}),
        _beat("peak", {"event": "director.state", "state": "PEAK"}),
        _beat("later", {"event": "timer", "after_sec": 60}, requires={"beats_fired": ["chain"]}),
    ]
    enc = Encounter(id="popup", kind="pool", pool="aaa", trigger=EncounterTrigger(type="manual"))
    rep = _build(tmp_path, _rt(beats=beats, encounters=[enc]).to_lua_source())
    assert not _codes(rep) & {"guaranteed_unreachable", "beat_unreachable"}, rep.issues
    assert rep.ok, rep.issues


def test_unreachable_guaranteed_beats_fail(tmp_path: Path) -> None:
    beats = [
        _beat("bad_zone", {"event": "zone.entered", "zone": "nowhere"}),
        _beat("bad_group", {"event": "group.dead", "group": "Ghost"}),
        _beat("bad_prefix", {"event": "group.dead", "group_prefix": "zzz"}),
        _beat("bad_enc", {"event": "encounter.spawned", "encounter": "nope"}),
        _beat("bad_flag", {"event": "flag", "flag": "never_set"}),
        _beat("bad_req", {"event": "mission.start"}, requires={"flags": ["never_set"]}),
        _beat("bad_chain", {"event": "beat.fired", "beat": "bad_zone"}),
        _beat("missing_dep", {"event": "beat.fired", "beat": "does_not_exist"}),
        _beat("soft", {"event": "zone.entered", "zone": "nowhere"}, guaranteed=False),
    ]
    rep = _build(tmp_path, _rt(beats=beats).to_lua_source())
    bad = {i.where: i.message for i in rep.issues if i.code == "guaranteed_unreachable"}
    assert set(bad) == {f"beats.{b.id}" for b in beats if b.guaranteed}, bad
    assert "unknown zone 'nowhere'" in bad["beats.bad_zone"]
    assert "flag 'never_set' is never set" in bad["beats.bad_req"]
    assert "beat 'bad_zone' can never fire" in bad["beats.bad_chain"]
    assert "does not exist" in bad["beats.missing_dep"]
    assert [i.where for i in rep.warnings if i.code == "beat_unreachable"] == ["beats.soft"]
    assert not rep.ok

    # unknown events in hand-written Lua configs; director.state with the director off
    src = _rt().to_lua_source() + (
        "\nDMS_CONFIG.director.enabled = false"
        '\nDMS_CONFIG.beats = { {id = "odd", guaranteed = true, when = {event = "made.up"}},'
        ' {id = "dir", guaranteed = true, when = {director = "PEAK"}} }\n'
    )
    msgs = {
        i.where: i.message
        for i in _build(tmp_path, src, "lua.miz").issues
        if i.code == "guaranteed_unreachable"
    }
    assert "unknown event 'made.up'" in msgs["beats.odd"]
    assert "director is disabled" in msgs["beats.dir"]


# ---------------------------------------------------------------- 4. script order


def test_fallback_config_loads_before_dms_and_test_script(tmp_path: Path) -> None:
    for name in ("plugin.lua", "dms_test.lua", "dms.lua"):
        (tmp_path / name).write_text("x = 1", encoding="utf-8")
    res = [
        PlanResource(path=f"l10n/DEFAULT/{n}", source=n, kind="script")
        for n in ("plugin.lua", "dms_test.lua", "dms.lua")
    ]
    out = build_from_plan(_plan(res, _rt()), tmp_path / "o.miz", base_dir=tmp_path)
    s = inspect(out)
    start = next(t for t in s.triggers if t["comment"] == "DMS: load scripts")
    files = [s.resources[a["file"]] for a in start["actions"]]
    assert files == ["plugin.lua", "dms_config.lua", "dms_test.lua", "dms.lua"]
    assert not _codes(check_miz(out)) & {"script_order", "test_script_order"}


# ---------------------------------------------------------------- 5. convoy compile


def _load(p: Path) -> Any:
    return yaml.safe_load(p.read_text(encoding="utf-8"))


def test_spec_convoy_encounters_get_spawn_zone_and_destination() -> None:
    from dms_core.schemas import BeatSheet, MissionSpec, StoryBible

    m01 = REPO / "campaigns" / "dustoff-valley" / "missions" / "m01-first-light"
    if not (m01 / "mission-spec.yaml").is_file():
        pytest.skip("m01 not present")
    spec = MissionSpec.model_validate(_load(m01 / "mission-spec.yaml"))
    bible = StoryBible.model_validate(_load(m01.parents[1] / "bible.yaml"))
    beats = BeatSheet.model_validate(_load(m01 / "beats.yaml"))
    rt = plan_mission(spec, beats, seed=1, bible=bible).runtime
    assert rt is not None
    enc = {e.id: e for e in rt.encounters}
    # single-area pools: nearest road area outside the spawn area
    assert (enc["staging_convoy"].spawn_zone, enc["staging_convoy"].destination) == (
        "staging_farm",
        "canal_road",
    )
    assert (enc["civ_traffic"].spawn_zone, enc["civ_traffic"].destination) == (
        "canal_road",
        "kirikhan_road",
    )
    assert enc["popup_aa"].destination is None  # not a convoy

    # multi-area pool: first area -> last area
    data = _load(m01 / "mission-spec.yaml")
    for p in data["dynamic"]["pools"]:
        if p["id"] == "staging":
            p["areas"] = ["staging_farm", "kirikhan_road"]
    rt2 = plan_mission(MissionSpec.model_validate(data), beats, seed=1, bible=bible).runtime
    assert rt2 is not None
    e2 = next(e for e in rt2.encounters if e.id == "staging_convoy")
    assert (e2.spawn_zone, e2.destination) == ("staging_farm", "kirikhan_road")


# ---------------------------------------------------------------- 6. test / effects schema


def test_test_settings_and_effects_schema() -> None:
    lua = build_test_lua("Proxy 1", 30, [], ["popup"])
    tbl = luaio.loads(lua, "DMS_CONFIG", arrays=True)
    ts = TestSettings.model_validate(from_lua(TestSettings, tbl["test"]))
    assert ts.player_proxy == "Proxy 1" and ts.minutes == 30
    assert {c.kind for c in ts.checks} >= {"booted", "spawns", "encounter", "outcome"}
    assert any(c.id == "popup" and c.deadline_sec for c in ts.checks)
    with pytest.raises(ValidationError):
        TestSettings.model_validate({"checks": [{"kind": "made_up"}]})

    fx = BeatEffects.model_validate(
        {"speak": {"speaker": "ops", "lines": ["l1"]}, "mark": "zone:box", "setFlag": "a"}
    )
    assert fx.speak is not None and fx.speak.lines == ["l1"]
    assert fx.mark is not None and fx.mark.at == "zone:box"
    lua_fx = RuntimeConfig(
        mission_id="c01",
        beats=[Beat(id="b", when={"event": "mission.start"}, effects=fx)],  # type: ignore[arg-type]
    ).to_lua_table()["beats"][0]["effects"]
    assert lua_fx["speak"] == {"speaker": "ops", "lines": ["l1"]}
    assert lua_fx["mark"]["at"] == "zone:box"
    with pytest.raises(ValidationError):
        BeatEffects.model_validate({"speak": {"who": "ops"}})


# ---------------------------------------------------------------- 7. campaign qualities


def test_load_campaign_qualities(tmp_path: Path) -> None:
    mission = tmp_path / "camp" / "missions" / "m01-x"
    mission.mkdir(parents=True)
    assert load_campaign_qualities(mission) == {}
    state = tmp_path / "camp" / "state"
    state.mkdir()
    (state / "qualities.yaml").write_text(
        "values: {trust: 2, intel: 0}\nflags: {}\n", encoding="utf-8"
    )
    assert load_campaign_qualities(mission) == {"trust": 2.0, "intel": 0.0}
    (state / "qualities.yaml").write_text("values: {trust: lots}\n", encoding="utf-8")
    with pytest.raises(ValueError, match="qualities"):
        load_campaign_qualities(mission)
    real = REPO / "campaigns" / "dustoff-valley" / "missions" / "m01-first-light"
    if real.is_dir():
        assert load_campaign_qualities(real).get("enemy_aa") == 2.0


def test_load_campaign_flags(tmp_path: Path) -> None:
    mission = tmp_path / "camp" / "missions" / "m02-x"
    mission.mkdir(parents=True)
    assert load_campaign_flags(mission) == {}
    state = tmp_path / "camp" / "state"
    state.mkdir()
    (state / "qualities.yaml").write_text(
        "values: {}\nflags: {m01_success: true, m01_failure: false}\n", encoding="utf-8"
    )
    assert load_campaign_flags(mission) == {"m01_success": True, "m01_failure": False}
    (state / "qualities.yaml").write_text("flags: {m01_x: [1]}\n", encoding="utf-8")
    with pytest.raises(ValueError, match="qualities"):
        load_campaign_flags(mission)


def test_campaign_flags_count_as_set(tmp_path: Path) -> None:
    beats = [
        _beat("sa6_gone", {"event": "mission.start"}, requires={"flags": {"m01_sa6_dead": True}}),
        _beat("on_flag", {"event": "flag", "flag": "m01_success"}),
        _beat("still_up", {"event": "mission.start"}, requires={"flags": ["m01_failure"]}),
    ]
    rt = _rt(beats=beats)
    rt.flags = {"m01_sa6_dead": True, "m01_success": True, "m01_failure": False}
    rep = _build(tmp_path, rt.to_lua_source())
    bad = {i.where: i.message for i in rep.issues if i.code == "guaranteed_unreachable"}
    assert set(bad) == {"beats.still_up"}, bad
    assert "flag 'm01_failure' is never set" in bad["beats.still_up"]


def test_campaign_flag_gated_beats_are_info(tmp_path: Path) -> None:
    beats = [
        _beat(
            "cont", {"event": "mission.start"}, guaranteed=False, requires={"flags": ["m01_lost"]}
        ),
        _beat("chain", {"event": "beat.fired", "beat": "cont"}, guaranteed=False),
        _beat("own", {"event": "mission.start"}, guaranteed=False, requires={"flags": ["c01_x"]}),
        _beat("later", {"event": "mission.start"}, guaranteed=False, requires={"flags": ["m05_y"]}),
    ]
    src = _rt(mission_id="m03-third", beats=beats).to_lua_source()
    rep = _build(tmp_path, src)  # no arc above the .miz: any other mNN key counts
    info = {i.where for i in rep.issues if i.code == "beat_campaign_gated"}
    warn = {i.where for i in rep.warnings if i.code == "beat_unreachable"}
    assert info == {"beats.cont", "beats.chain", "beats.later"}, rep.issues
    assert warn == {"beats.own"}
    assert all(i.severity == "info" for i in rep.issues if i.code == "beat_campaign_gated")

    # with an arc: only missions before m03 in play order can set campaign flags
    camp = tmp_path / "camp"
    camp.mkdir()
    (camp / "arc.yaml").write_text(
        "acts:\n  - id: a1\n    missions:\n      - {id: m01-first}\n      - {id: m03-third}\n"
        "      - {id: m05-fifth}\n",
        encoding="utf-8",
    )
    rep = _build(camp, src)
    info = {i.where for i in rep.issues if i.code == "beat_campaign_gated"}
    warn = {i.where for i in rep.warnings if i.code == "beat_unreachable"}
    assert info == {"beats.cont", "beats.chain"}, rep.issues
    assert warn == {"beats.own", "beats.later"}

    # m01 already debriefed (its flags are known): a missing m01_* flag is never set
    rt = _rt(mission_id="m03-third", beats=beats)
    rt.flags = {"m01_success": True}
    rep = _build(camp, rt.to_lua_source(), "flown.miz")
    assert "beats.cont" in {i.where for i in rep.warnings if i.code == "beat_unreachable"}
