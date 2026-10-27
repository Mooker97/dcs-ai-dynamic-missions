from __future__ import annotations

import importlib.util
import random
import sys
import zipfile
from pathlib import Path
from typing import Any

import pytest
from dms_gen.builder import (
    MissionBuilder,
    inspect,
    point_in_polygon,
    pylon_options,
    random_point_in_polygon,
    resolve_payload,
)
from dms_gen.builder.payloads import is_fuel_tank

EXAMPLE = Path(__file__).resolve().parents[1] / "examples" / "build_dustoff_like.py"


def _load_example() -> Any:
    spec = importlib.util.spec_from_file_location("build_dustoff_like", EXAMPLE)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules["build_dustoff_like"] = mod
    spec.loader.exec_module(mod)
    return mod


def _lua_to_py(obj: Any) -> Any:
    lupa = pytest.importorskip("lupa")
    if lupa.lua_type(obj) == "table":
        return {k: _lua_to_py(v) for k, v in obj.items()}
    return obj


def _load_lua_global(text: str, name: str) -> dict[str, Any]:
    lupa = pytest.importorskip("lupa")
    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt.execute(text)
    result: dict[str, Any] = _lua_to_py(rt.globals()[name])
    return result


def _arr(t: dict[Any, Any] | None) -> list[Any]:
    if not t:
        return []
    return [t[k] for k in sorted(k for k in t if isinstance(k, int))]


@pytest.fixture(scope="module")
def built(tmp_path_factory: pytest.TempPathFactory) -> tuple[Path, dict[str, Any], zipfile.ZipFile]:
    tmp = tmp_path_factory.mktemp("dustoff")
    out = tmp / "dustoff-like.miz"
    _load_example().build(out, tmp / "assets")
    z = zipfile.ZipFile(out)
    mission = _load_lua_global(z.read("mission").decode("utf-8"), "mission")
    return out, mission, z


def _groups(mission: dict[str, Any], coalition: str, cat: str) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for c in _arr(mission["coalition"][coalition]["country"]):
        out.extend(_arr((c.get(cat) or {}).get("group")))
    return out


def test_player_slots_are_clients_with_no_fuel_tanks(built: Any) -> None:
    _, mission, _ = built
    helos = _groups(mission, "blue", "helicopter")
    assert len(helos) == 1
    units = _arr(helos[0]["units"])
    assert len(units) == 2
    for u in units:
        assert u["type"] == "AH-64D_BLK_II"
        assert u["skill"] == "Client"
        pylons = _arr(u["payload"]["pylons"]) if u["payload"]["pylons"] else []
        clsids = [p["CLSID"] for p in pylons]
        assert len(clsids) == 4
        assert not any(is_fuel_tank(c) for c in clsids), clsids
        assert "{EFT_230GAL}" not in clsids
        assert "{M261_M151_M433}" in clsids
    assert units[0]["callsign"]["name"] == "Apache11"


def test_convoy_and_hidden_red(built: Any) -> None:
    _, mission, _ = built
    blue = _groups(mission, "blue", "vehicle")
    convoy = next(g for g in blue if g["name"] == "Convoy")
    assert len(_arr(convoy["units"])) == 6
    points = _arr(convoy["route"]["points"])
    assert len(points) == 5  # spawn point + 4
    assert all(p["action"] == "On Road" for p in points)
    red = _groups(mission, "red", "vehicle")
    assert {g["name"] for g in red} == {"Ambush North", "Ambush South"}
    assert all(g["hidden"] is True for g in red)
    assert next(g for g in red if g["name"] == "Ambush South")["lateActivation"] is True
    assert mission["forcedOptions"]["optionsView"] == "optview_allies"


def test_unique_ids_and_names(built: Any) -> None:
    _, mission, _ = built
    gids: list[int] = []
    uids: list[int] = []
    names: list[str] = []
    for coal in ("blue", "red"):
        for cat in ("plane", "helicopter", "vehicle", "ship"):
            for g in _groups(mission, coal, cat):
                gids.append(g["groupId"])
                names.append(g["name"])
                for u in _arr(g["units"]):
                    uids.append(u["unitId"])
                    names.append(u["name"])
    assert len(gids) == len(set(gids)) == 4
    assert len(uids) == len(set(uids)) == 13
    assert len(names) == len(set(names))


def test_zones(built: Any) -> None:
    _, mission, _ = built
    zones = {z["name"]: z for z in _arr(mission["triggers"]["zones"])}
    assert set(zones) == {"AMBUSH_ZONE", "CONVOY_END", "VALLEY_QUAD"}
    assert zones["AMBUSH_ZONE"]["type"] == 0
    assert zones["AMBUSH_ZONE"]["radius"] == 2500
    assert zones["VALLEY_QUAD"]["type"] == 2
    assert len(_arr(zones["VALLEY_QUAD"]["verticies"])) == 4
    ids = [z["zoneId"] for z in zones.values()]
    assert len(set(ids)) == 3


def test_scripts_in_order_with_resources(built: Any) -> None:
    _, mission, z = built
    names = z.namelist()
    res = _load_lua_global(z.read("l10n/DEFAULT/mapResource").decode("utf-8"), "mapResource")
    rules = _arr(mission["trigrules"])
    start = next(r for r in rules if r["comment"] == "DMS: load scripts")
    assert start["predicate"] == "triggerStart"
    acts = _arr(start["actions"])
    assert [a["predicate"] for a in acts] == ["a_do_script_file"] * 2
    files = [res[a["file"]] for a in acts]
    assert files == ["dms.lua", "dms_config.lua"]
    for f in [*files, "convoy_contact.ogg"]:
        assert f"l10n/DEFAULT/{f}" in names
    # compiled action string matches the rule order
    idx = rules.index(start) + 1
    compiled = mission["trig"]["actions"][idx]
    assert compiled.index(acts[0]["file"]) < compiled.index(acts[1]["file"])
    # sound keeper references the sound and never fires
    keeper = next(r for r in rules if "keep sound" in r["comment"])
    snd = _arr(keeper["actions"])[0]
    assert snd["predicate"] == "a_out_sound" and res[snd["file"]] == "convoy_contact.ogg"
    assert _arr(keeper["rules"])[0]["predicate"] == "c_flag_equals"


def test_inspect_summary(built: Any) -> None:
    out, _, _ = built
    s = inspect(out)
    assert s.theater == "Syria"
    assert len(s.player_slots) == 2
    assert len(s.groups["blue"]) == 2 and len(s.groups["red"]) == 2
    assert "dms.lua" in s.resources.values()
    assert "DMS: load scripts" in s.text()


def test_kneeboard_and_weather(tmp_path: Path) -> None:
    img = tmp_path / "card.png"
    img.write_bytes(b"\x89PNG\r\n\x1a\n" + b"\x00" * 16)
    b = MissionBuilder("Syria", seed=1)
    b.set_weather("dust")
    b.embed_kneeboard(img)
    b.embed_kneeboard(img, "AH-64D_BLK_II")
    out = b.save(tmp_path / "k.miz")
    with zipfile.ZipFile(out) as z:
        names = z.namelist()
        mission = _load_lua_global(z.read("mission").decode("utf-8"), "mission")
    assert "KNEEBOARD/IMAGES/card.png" in names
    assert "KNEEBOARD/AH-64D_BLK_II/IMAGES/card.png" in names
    w = mission["weather"]
    assert w["enable_dust"] is True and w["enable_fog"] is False and "fog" in w


@pytest.mark.parametrize("preset", ["clear", "scattered", "overcast", "rain", "dust"])
def test_weather_presets_save(tmp_path: Path, preset: Any) -> None:
    b = MissionBuilder("Caucasus", seed=1)
    b.set_weather(preset)
    b.save(tmp_path / f"{preset}.miz")


def test_ai_flights(tmp_path: Path) -> None:
    b = MissionBuilder("Syria", seed=3)
    rd = b.airbase("Ramat David").position
    a, c = (rd.x, rd.y), (rd.x + 30000, rd.y + 30000)
    b.add_ai_flight("blue", "USA", "F-16C_50", "CAP 1", "cap", (a, c), count=2)
    b.add_ai_flight("blue", "USA", "E-3A", "Darkstar", "awacs", (a, c), frequency_mhz=251)
    b.add_ai_flight("blue", "USA", "KC-135", "Texaco", "tanker", (a, c))
    b.add_ai_flight("blue", "USA", "AH-64D_BLK_II", "Gunslinger", "cas", (c, a), altitude_m=300)
    s = inspect(b.save(tmp_path / "ai.miz"))
    assert {g.name for g in s.groups["blue"]} == {"CAP 1", "Darkstar", "Texaco", "Gunslinger"}
    with pytest.raises(ValueError):
        b.add_ai_flight("blue", "USA", "F-16C_50", "CAP 1", "cap", (a, c))


def test_payload_helpers() -> None:
    from dcs.helicopters import AH_64D_BLK_II

    opts = pylon_options(AH_64D_BLK_II)
    assert set(opts) >= {1, 2, 3, 4}
    lo = resolve_payload(AH_64D_BLK_II, None)
    assert lo is not None and not any(is_fuel_tank(c) for c in lo.values())
    assert resolve_payload(AH_64D_BLK_II, {1: "{M299_4xAGM_114L}"}) == {1: "{M299_4xAGM_114L}"}
    with pytest.raises(ValueError):
        resolve_payload(AH_64D_BLK_II, {1: "{NOT_A_WEAPON}"})


def test_geo_helpers() -> None:
    b = MissionBuilder("Syria", seed=7)
    rd = b.airbase("Ramat David").position
    lat, lon = b.xy_to_latlon(rd.x, rd.y)
    assert 32.5 < lat < 32.8 and 35.1 < lon < 35.3
    x, y = b.latlon_to_xy(lat, lon)
    assert abs(x - rd.x) < 1 and abs(y - rd.y) < 1
    poly = [(0.0, 0.0), (1000.0, 0.0), (1000.0, 1000.0), (0.0, 1000.0)]
    p1 = random_point_in_polygon(poly, random.Random(5))
    assert p1 == random_point_in_polygon(poly, random.Random(5))
    assert point_in_polygon(p1, poly)
    assert b.is_on_map(rd.x, rd.y) and not b.is_on_map(9e6, 9e6)
