"""Static tests for the DMS Arma 3 mission "Hold the OP". Run: uv run pytest arma -q"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sqf_check

MISSION = Path(__file__).resolve().parents[1] / "missions" / "dms_hold.Altis"
SQF_FILES = sorted(MISSION.rglob("*.sqf"))
CONFIG = MISSION / "functions" / "fn_config.sqf"


def _desc() -> dict:
    return sqf_check.parse_config(
        (MISSION / "description.ext").read_text(encoding="utf-8"), "description.ext"
    )


def _sqm() -> dict:
    return sqf_check.parse_config(
        (MISSION / "mission.sqm").read_text(encoding="utf-8"), "mission.sqm"
    )


def _config_src() -> str:
    return CONFIG.read_text(encoding="utf-8")


def _config_value(key: str) -> str:
    m = re.search(rf'\["{key}",\s*"([^"]+)"\]', _config_src())
    assert m, key
    return m.group(1)


def _config_list(key: str) -> list[str]:
    m = re.search(rf'\["{key}",\s*\[(.*?)\]\]', _config_src(), flags=re.DOTALL)
    assert m, key
    return re.findall(r'"([^"]+)"', m.group(1))


# ---------------------------------------------------------------- SQF files


@pytest.mark.parametrize("path", SQF_FILES, ids=lambda p: p.relative_to(MISSION).as_posix())
def test_sqf_file_clean(path: Path) -> None:
    rep = sqf_check.check_sqf(
        path.read_text(encoding="utf-8"), path.name, allow_random=path.name == "fn_rng.sqf"
    )
    assert rep.errors == []
    assert rep.warnings == []


def test_whole_mission_check_passes() -> None:
    rep = sqf_check.check_mission(MISSION)
    assert rep.errors == []
    assert rep.warnings == []


def test_expected_files_exist() -> None:
    for rel in [
        "mission.sqm",
        "description.ext",
        "initServer.sqf",
        "initPlayerLocal.sqf",
        "functions/fn_config.sqf",
        "README.md",
        "CLASSES.md",
    ]:
        assert (MISSION / rel).is_file(), rel


def test_shared_framework_matches_the_hill() -> None:
    """The proven helpers are copied verbatim from The Hill."""
    hill = MISSION.parent / "dms_the_hill.Altis" / "functions"
    for name in ["fn_rng.sqf", "fn_t.sqf", "fn_log.sqf", "fn_findPos.sqf"]:
        assert (MISSION / "functions" / name).read_text(encoding="utf-8") == (
            hill / name
        ).read_text(encoding="utf-8"), name


def test_waits_are_bounded() -> None:
    """Every waitUntil must be able to end: on DMS_over, a timeout, or a death."""
    for path in SQF_FILES:
        src = path.read_text(encoding="utf-8")
        for m in re.finditer(r"waitUntil\s*\{", src):
            depth, i = 1, m.end()
            while depth:
                depth += {"{": 1, "}": -1}.get(src[i], 0)
                i += 1
            body = src[m.end() : i]
            ok = any(k in body for k in ("DMS_over", "time -", "time >", "!alive"))
            assert ok, f"{path.name}: unbounded waitUntil: {body[:80]!r}"


# ---------------------------------------------------------------- description.ext


def test_params() -> None:
    params = _desc()["Params"]
    for name in [
        "DMS_seed",
        "DMS_site",
        "DMS_debug",
        "DMS_testMode",
        "DMS_testMinutes",
        "DMS_testTimeScale",
        "DMS_testStartDist",
        "DMS_testAssist",
        "DMS_testForce",
    ]:
        p = params[name]
        assert len(p["values"]) == len(p["texts"]), name
        assert p["default"] in p["values"], name
    sqf = "\n".join(p.read_text(encoding="utf-8") for p in SQF_FILES)
    for used in re.findall(r'\["(DMS_\w+)",\s*-?\d+\]\s*call\s+BIS_fnc_getParamValue', sqf):
        assert used in params, used
    # the harness defaults (run_mission.py) are selectable values
    assert 15 in params["DMS_testMinutes"]["values"]
    assert 15 in params["DMS_testTimeScale"]["values"]
    assert 300 in params["DMS_testStartDist"]["values"]
    assert 180 in params["DMS_testAssist"]["values"]


def test_functions_declared_and_present() -> None:
    declared = sqf_check.cfg_functions(_desc())
    files = {p.stem[3:] for p in (MISSION / "functions").glob("fn_*.sqf")}
    assert declared == files
    assert _desc()["CfgFunctions"]["DMS"]["tag"] == "DMS"


def test_comm_menu_items() -> None:
    menu = _desc()["CfgCommunicationMenu"]
    assert set(menu) == {"DMS_ArtyFire", "DMS_ArtySpot", "DMS_AirSupport"}
    for cls in menu.values():
        assert cls["removeAfterExpressionCall"] == 1
        assert "remoteExecCall" in cls["expression"]
    assert "DMS_fnc_air" in menu["DMS_AirSupport"]["expression"]


def test_debriefing_classes() -> None:
    deb = _desc()["CfgDebriefing"]
    assert {"DMS_Win", "DMS_FailDead", "DMS_FailOverrun", "DMS_FailMods", "DMS_TestEnd"} <= set(deb)
    for cls in deb.values():
        assert {"title", "subtitle", "description"} <= set(cls)


def test_no_respawn_single_player_slot() -> None:
    desc = _desc()
    assert desc["respawn"] == 0
    assert desc["Header"]["maxPlayers"] == 1


# ---------------------------------------------------------------- mission.sqm


def _count_items(entities: dict) -> None:
    items = [k for k in entities if re.fullmatch(r"Item\d+", k)]
    assert entities["items"] == len(items)
    for k in items:
        if "Entities" in entities[k]:
            _count_items(entities[k]["Entities"])


def test_mission_sqm_structure() -> None:
    sqm = _sqm()
    assert sqm["version"] >= 52
    assert sqm["binarizationWanted"] == 0
    # vanilla only, so the mission loads without the mods and can say what is missing
    assert sqm["addons"] == ["A3_Characters_F"]
    assert sqm["AddonsMetaData"]["List"]["items"] == len(sqm["addons"])
    ents = sqm["Mission"]["Entities"]
    _count_items(ents)
    group = ents["Item0"]
    assert group["dataType"] == "Group" and group["side"] == "West"
    units = [v for k, v in group["Entities"].items() if k.startswith("Item")]
    players = [u for u in units if u["Attributes"].get("isPlayer") == 1]
    assert len(players) == 1
    assert players[0]["Attributes"]["isPlayable"] == 1
    assert players[0]["type"] == _config_value("playerSlotClass")
    assert len(players[0]["PositionInfo"]["position"]) == 3
    ids = [group["id"], *(u["id"] for u in units)]
    assert len(set(ids)) == len(ids)
    assert sqm["EditorData"]["ItemIDProvider"]["nextID"] > max(ids)


# ---------------------------------------------------------------- fn_config data


def test_config_keys_unique() -> None:
    keys = re.findall(r'^\t\["(\w+)",', _config_src(), flags=re.MULTILINE)
    assert len(keys) == len(set(keys))


def test_config_sites() -> None:
    sites = re.findall(
        r'^\t\t\["([^"]+)", \[(\d+), (\d+)\], (\d+), \[([\d, ]+)\]\]',
        _config_src(),
        flags=re.MULTILINE,
    )
    assert 1 <= len(sites) <= 3
    for _name, x, y, rear, brgs in sites:
        assert 0 < int(x) < 30720 and 0 < int(y) < 30720
        assert 0 <= int(rear) < 360
        bearings = [int(b) for b in brgs.split(",")]
        assert len(bearings) >= 2
        for b in bearings:
            assert 0 <= b < 360
            # no wave may come from the friendly rear (within 45 degrees)
            assert min((b - int(rear)) % 360, (int(rear) - b) % 360) > 45, (_name, b)
    assert len(_desc()["Params"]["DMS_site"]["values"]) == len(sites) + 1


def test_config_waves() -> None:
    block = re.search(r'\["waves", \[(.*?)\n\t\]\]', _config_src(), flags=re.DOTALL)
    assert block
    waves = re.findall(r"^\t\t\[(.*)\],?$", block.group(1), flags=re.MULTILINE)
    assert 2 <= len(waves) <= 3
    for w in waves:
        groups = re.findall(r'\["(CREEP|ASSAULT)", (\d+), (-?\d+)\]', w)
        assert groups, w
        for _tactic, size, _off in groups:
            assert 4 <= int(size) <= 10
    sbf_wave = int(re.search(r'\["sbfWave", (\d+)\]', _config_src()).group(1))
    assert 1 <= sbf_wave <= len(waves)


def test_mod_classes_are_recorded() -> None:
    """Every mod class in fn_config is listed in CLASSES.md (verified from the PBOs)."""
    classes_md = (MISSION / "CLASSES.md").read_text(encoding="utf-8")
    used = (
        [_config_value(k) for k in ("playerLoadoutClass", "squadLeaderClass", "enemyLeaderClass")]
        + _config_list("squadClasses")
        + _config_list("enemyClasses")
        + _config_list("staticClasses")
        + _config_list("sbfClasses")
        + _config_list("airClasses")
        + _config_list("modFunctions")
    )
    for cls in used:
        assert f"`{cls}`" in classes_md, cls
    for _label, patch in re.findall(r'\["([^"]+)", "(\w+)"\]', _config_list_block("modPatches")):
        assert f"`{patch}`" in classes_md, patch


def _config_list_block(key: str) -> str:
    m = re.search(rf'\["{key}", \[(.*?)\]\]\],?\n', _config_src(), flags=re.DOTALL)
    assert m, key
    return m.group(1)


def test_lambs_calls_use_verified_signatures() -> None:
    sqf = "\n".join(p.read_text(encoding="utf-8") for p in SQF_FILES)
    calls = re.findall(r"\[([^\[\]]*(?:\[[^\[\]]*\][^\[\]]*)*)\]\s*spawn\s+(lambs_wp_fnc_\w+)", sqf)
    assert {fn for _, fn in calls} == {
        "lambs_wp_fnc_taskAssault",
        "lambs_wp_fnc_taskCreep",
        "lambs_wp_fnc_taskRush",
    }
    for args, fn in calls:
        if fn in ("lambs_wp_fnc_taskCreep", "lambs_wp_fnc_taskRush"):
            # group, radius, cycle, area, centre, onlyPlayers=false (the test squad is AI)
            assert args.rstrip().endswith("false"), (fn, args)


def test_test_mode_expected_checks_are_emitted() -> None:
    block = re.search(r'\["testExpected", \[(.*?)\]\]', _config_src(), flags=re.DOTALL)
    assert block
    expected = re.findall(r'"(\w+)"', block.group(1))
    sqf = "\n".join(p.read_text(encoding="utf-8") for p in SQF_FILES if p.name != "fn_config.sqf")
    for name in expected:
        if re.fullmatch(r"wave\d", name):
            assert 'format ["wave%1"' in sqf
        else:
            assert f'"{name}"' in sqf, name


def test_no_canmove_on_helicopters() -> None:
    src = (MISSION / "functions" / "fn_air.sqf").read_text(encoding="utf-8")
    assert not re.search(r"canMove\s+_", src)
