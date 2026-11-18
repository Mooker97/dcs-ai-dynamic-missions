"""Planner comms plan (CONTRACTS "Planner comms plan"): every agency gets a frequency."""

from __future__ import annotations

import zipfile
from pathlib import Path
from typing import Any

import yaml
from dms_core.luaio import loads
from dms_core.schemas import MissionSpec, StoryBible
from dms_core.schemas.plan import BuildPlan, PlanComm
from dms_gen.builder import build_from_plan
from dms_gen.builder.docs import comms_markdown, fill_plan_frequencies
from dms_gen.planner import plan_mission, write_runtime_config
from dms_gen.planner.radios import aircraft_radios, band_of, tunable_bands
from test_routes_radios_pools import spec

REPO = Path(__file__).resolve().parents[3]
BIBLE = StoryBible.model_validate(
    yaml.safe_load(
        (REPO / "campaigns" / "viper-detachment" / "bible.yaml").read_text(encoding="utf-8")
    )
)
CAST = ["ops_lindqvist", "wingman_pike", "jtac_ortiz", "awacs_magic", "tower_incirlik"]


def _bare_spec(**over: Any) -> MissionSpec:
    """Supports without frequencies; the cast includes ops, wingman, tower and an enemy."""
    base = spec()
    sup = [s.model_dump() for s in base.support]
    for s in sup:
        s["frequency_mhz"] = None
    sup[0]["speaker"] = "awacs_magic"
    sup[2]["speaker"] = "jtac_ortiz"
    data: dict[str, Any] = {"support": sup, "cast": [*CAST, "npf_commander"]}
    data.update(over)
    return spec(**data)


def _plan(s: MissionSpec) -> BuildPlan:
    return plan_mission(s, seed=3, bible=BIBLE)


def _comm(p: BuildPlan, cid: str) -> PlanComm:
    return next(c for c in p.comms if c.id == cid)


def test_radio_bands_from_pydcs() -> None:
    assert [b for _r, b, _n in aircraft_radios("F-16C_50")] == [{"uhf"}, {"vhf"}]
    assert "fm" in tunable_bands("AH-64D_BLK_II") and "fm" not in tunable_bands("F-16C_50")
    assert {"fm", "vhf"} <= tunable_bands("UH-1H")
    assert (band_of(41.5), band_of(124.0), band_of(251.0)) == ("fm", "vhf", "uhf")


def test_every_agency_gets_a_distinct_frequency_in_a_tunable_band() -> None:
    p = _plan(_bare_spec())
    kinds = {c.id: c.kind for c in p.comms}
    assert kinds == {
        "Python": "flight",
        "magic": "support",
        "shell": "support",
        "jtac": "support",
        "ops_lindqvist": "agency",
        "tower_incirlik": "tower",
    }
    freqs = [c.frequency_mhz for c in p.comms]
    assert len(set(freqs)) == len(freqs), freqs
    assert all(c.band in ("uhf", "vhf") for c in p.comms)  # F-16: no FM radio
    assert _comm(p, "magic").frequency_mhz == 251.0
    assert _comm(p, "shell").frequency_mhz == 276.0
    assert _comm(p, "jtac").band == "vhf" and _comm(p, "jtac").modulation == "AM"
    assert _comm(p, "ops_lindqvist").frequency_mhz == 124.0
    assert _comm(p, "tower_incirlik").source == "airbase"
    # written back to the groups (AWACS/tanker no longer share the builder default) and speakers
    by_src = {g.source: g for g in p.groups}
    assert by_src["magic"].frequency_mhz == 251.0 and by_src["shell"].frequency_mhz == 276.0
    sp = p.runtime.speakers if p.runtime else {}
    assert sp["ops_lindqvist"].frequency == 124.0 and sp["ops_lindqvist"].modulation == 0
    assert sp["awacs_magic"].frequency == 251.0
    flight = _comm(p, "Python").frequency_mhz
    assert sp["wingman_pike"].frequency == flight  # wingman talks on the flight frequency
    assert "npf_commander" not in kinds  # enemy voices: no frequency
    assert p.briefing is not None and "Comms:" in p.briefing.blue_task
    assert "Rook Ops: 124.000 AM" in p.briefing.blue_task
    # deterministic
    assert _plan(_bare_spec()).comms == p.comms


def test_spec_frequencies_win_and_presets_follow_bands() -> None:
    p = _plan(spec(cast=CAST))
    assert _comm(p, "magic").frequency_mhz == 255.5 and _comm(p, "magic").source == "spec"
    assert _comm(p, "jtac").frequency_mhz == 41.5 and _comm(p, "jtac").preset is None  # no FM
    client = next(g for g in p.groups if g.client)
    pre = {(r.radio, r.channel): r.frequency_mhz for r in client.radio_presets}
    assert pre[(2, 1)] == 124.0  # the command net: channel 1 of the second (VHF) radio
    assert (1, 1) not in pre  # DCS owns channel 1 of the flight-frequency radio
    assert pre[(1, 2)] == 255.5
    assert _comm(p, "ops_lindqvist").preset == "radio 2 ch 1"
    assert _comm(p, "Python").preset == "radio 1 ch 1"


def test_fill_plan_frequencies_and_comms_page() -> None:
    p = _plan(spec(cast=CAST))
    md = (
        "| Agency | Callsign | Freq |\n|---|---|---|\n"
        "| AWACS | Magic | TBD (plan) |\n| Ops | Rook Ops | tbd (plan) |\n"
        "| Mystery | Nobody | TBD (plan) |\n"
    )
    out = fill_plan_frequencies(md, p.comms)
    assert "tbd (plan)" not in out.lower()
    assert "| Magic | 255.500 AM |" in out
    assert "| Rook Ops | 124.000 AM |" in out
    assert "| Nobody | see kneeboard COMMS |" in out
    page = comms_markdown(p.comms)
    assert page.startswith("# COMMS") and "41.500 FM" in page


def _miz(path: Path) -> dict[str, Any]:
    with zipfile.ZipFile(path) as z:
        m: dict[str, Any] = loads(z.read("mission"), "mission")
        names = z.namelist()
    m["_names"] = names
    return m


def test_build_applies_presets_and_comms_kneeboard(tmp_path: Path) -> None:
    lua = tmp_path / "dms.lua"
    lua.write_text('DMS = DMS or {}\nenv.info("[DMS] dummy")\n', encoding="utf-8")
    p = plan_mission(spec(cast=CAST), seed=3, bible=BIBLE, dms_lua=str(lua))
    mdir = tmp_path / "m"
    mdir.mkdir()
    write_runtime_config(p, mdir)
    (mdir / "kneeboard.md").write_text("# CARD\n\n- Ops TBD (plan)\n", encoding="utf-8")
    out = build_from_plan(p, tmp_path / "t.miz", base_dir=mdir)
    m = _miz(out)
    assert any("kneeboard-comms" in n for n in m["_names"])
    client = next(g for g in p.groups if g.client)
    units = [
        u
        for coal in m["coalition"].values()
        for c in (coal.get("country") or {}).values()
        for g in (c.get("plane") or {}).get("group", {}).values()
        if g["name"] == client.name
        for u in g["units"].values()
    ]
    assert units
    for u in units:
        assert float(u["Radio"][2]["channels"][1]) == 124.0
        assert float(u["Radio"][1]["channels"][2]) == 255.5
