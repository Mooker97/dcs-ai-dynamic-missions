"""Static tests for the DMS Arma 3 mission "Ambush" (Livonia). Run: uv run pytest arma -q

Same checks as test_mission_files.py (The Hill), adapted to this mission's layout, plus: every
mod class in fn_config is recorded in CLASSES.md, the test params the harness sets exist, and the
mission has no RHS dependency in mission.sqm (so the in-mission mod check can end it cleanly).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sqf_check

MISSION = Path(__file__).resolve().parents[1] / "missions" / "dms_ambush.Enoch"
SQF_FILES = sorted(MISSION.rglob("*.sqf"))
ENOCH_SIZE = 12800


def _desc() -> dict:
    return sqf_check.parse_config(
        (MISSION / "description.ext").read_text(encoding="utf-8"), "description.ext"
    )


def _sqm() -> dict:
    return sqf_check.parse_config(
        (MISSION / "mission.sqm").read_text(encoding="utf-8"), "mission.sqm"
    )


def _config_src() -> str:
    return (MISSION / "functions" / "fn_config.sqf").read_text(encoding="utf-8")


def _config_value(key: str) -> str:
    m = re.search(rf'\["{key}",\s*"([^"]+)"\]', _config_src())
    assert m, key
    return m.group(1)


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


def test_mission_folder_name_gives_world() -> None:
    # tools/arma_harness/run_mission.py takes the world from <name>.<world>
    name, _, world = MISSION.name.rpartition(".")
    assert name == "dms_ambush" and world == "Enoch"


# ---------------------------------------------------------------- description.ext


def test_params_include_harness_test_params() -> None:
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
    sites = re.findall(r'^\t\t\["([^"]+)", \[\d+, \d+\]\]', _config_src(), flags=re.MULTILINE)
    assert params["DMS_site"]["texts"][1:] == sites


def test_functions_declared_and_present() -> None:
    declared = sqf_check.cfg_functions(_desc())
    files = {p.stem[3:] for p in (MISSION / "functions").glob("fn_*.sqf")}
    assert declared == files
    assert _desc()["CfgFunctions"]["DMS"]["tag"] == "DMS"


def test_comm_menu_items() -> None:
    menu = _desc()["CfgCommunicationMenu"]
    assert set(menu) == {"DMS_ArtyFire", "DMS_ArtySpot"}
    for cls in menu.values():
        assert cls["removeAfterExpressionCall"] == 1
        assert "remoteExecCall" in cls["expression"]


def test_debriefing_classes() -> None:
    deb = _desc()["CfgDebriefing"]
    assert {"DMS_Win", "DMS_FailDead", "DMS_FailEscape", "DMS_FailMods", "DMS_TestEnd"} <= set(deb)
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
    # vanilla only: the mission must load without RHS so the mod check can report what is missing
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
    pos = players[0]["PositionInfo"]["position"]
    assert len(pos) == 3 and 0 < pos[0] < ENOCH_SIZE and 0 < pos[2] < ENOCH_SIZE
    ids = [group["id"], *(u["id"] for u in units)]
    assert len(set(ids)) == len(ids)
    assert sqm["EditorData"]["ItemIDProvider"]["nextID"] > max(ids)


# ---------------------------------------------------------------- fn_config data


def test_config_sites_on_enoch() -> None:
    sites = re.findall(r'^\t\t\["([^"]+)", \[(\d+), (\d+)\]\]', _config_src(), flags=re.MULTILINE)
    assert 2 <= len(sites) <= 3
    for _name, x, y in sites:
        assert 1000 < int(x) < ENOCH_SIZE - 500 and 1000 < int(y) < ENOCH_SIZE - 500


def test_config_distances_consistent() -> None:
    src = _config_src()

    def num(key: str) -> int:
        m = re.search(rf'\["{key}", (\d+)\]', src)
        assert m, key
        return int(m.group(1))

    assert num("killLineDistance") < num("exitDistance")
    assert num("rpMinRouteDistance") < num("rpDistance")
    assert num("escapeFailCount") >= 1
    m = re.search(r'\["artyDangerClose", (\d+)\]', src)
    lo = re.search(r'\["ambushDistance", \[(\d+), (\d+)\]\]', src)
    # mortars on the kill zone are not danger close for the squad at the ambush position
    assert m and lo and int(lo.group(1)) > int(m.group(1))


def test_config_keys_unique() -> None:
    keys = re.findall(r'^\t\["(\w+)",', _config_src(), flags=re.MULTILINE)
    assert len(keys) == len(set(keys))


def test_test_mode_expected_checks_are_emitted() -> None:
    block = re.search(r'\["testExpected", \[(.*?)\]\]', _config_src(), flags=re.DOTALL)
    assert block
    expected = re.findall(r'"(\w+)"', block.group(1))
    sqf = "\n".join(p.read_text(encoding="utf-8") for p in SQF_FILES if p.name != "fn_config.sqf")
    for name in expected:
        assert f'"{name}"' in sqf, name


def test_required_mods_listed() -> None:
    block = re.search(r'\["mods", \[(.*?)\n\t\]\]', _config_src(), flags=re.DOTALL)
    assert block
    mods = re.findall(r'\["([^"]+)", "(\w+)", (true|false)\]', block.group(1))
    required = {patch for _label, patch, req in mods if req == "true"}
    want = {"cba_main", "ace_main", "lambs_danger", "lambs_wp", "rhs_main", "rhsusf_main"}
    assert want <= required


def test_mod_classes_recorded_in_classes_md() -> None:
    """Every RHS class string and LAMBS function the mission uses is listed in CLASSES.md."""
    classes_md = (MISSION / "CLASSES.md").read_text(encoding="utf-8").lower()
    sqf = "\n".join(p.read_text(encoding="utf-8") for p in SQF_FILES)
    used = set(re.findall(r'"((?:rhs|RHS)\w+)"', sqf))
    used |= set(re.findall(r"\blambs_\w+_fnc_\w+", sqf))
    patches = re.findall(r'"(\w+_main|lambs_\w+)", (?:true|false)', sqf)
    assert used
    for name in sorted(used | set(patches)):
        assert f"`{name.lower()}`" in classes_md, name
