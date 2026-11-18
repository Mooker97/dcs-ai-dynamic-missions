"""Static tests for the DMS Arma 3 mission "Recon and Strike". Run: uv run pytest arma -q"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sqf_check

MISSION = Path(__file__).resolve().parents[1] / "missions" / "dms_recon.Enoch"
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


def _all_sqf(exclude_config: bool = False) -> str:
    return "\n".join(
        p.read_text(encoding="utf-8")
        for p in SQF_FILES
        if not (exclude_config and p.name == "fn_config.sqf")
    )


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
        "CLASSES.md",
        "README.md",
    ]:
        assert (MISSION / rel).is_file(), rel


def test_shared_framework_matches_the_hill() -> None:
    """fn_rng, fn_t and fn_log are the proven Hill framework, copied unchanged."""
    hill = MISSION.parent / "dms_the_hill.Altis" / "functions"
    for name in ["fn_rng.sqf", "fn_t.sqf", "fn_log.sqf"]:
        assert (MISSION / "functions" / name).read_text(encoding="utf-8") == (
            hill / name
        ).read_text(encoding="utf-8"), name


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
    for used in re.findall(r'\["(DMS_\w+)",\s*-?\d+\]\s*call\s+BIS_fnc_getParamValue', _all_sqf()):
        assert used in params, used


def test_harness_default_params_are_listed() -> None:
    """tools/arma_harness/run_mission.py defaults: --minutes 15, --time-scale 15, --start-dist 300,
    --assist 180."""
    params = _desc()["Params"]
    assert 15 in params["DMS_testMinutes"]["values"]
    assert 15 in params["DMS_testTimeScale"]["values"]
    assert 300 in params["DMS_testStartDist"]["values"]
    assert 180 in params["DMS_testAssist"]["values"]


def test_site_param_matches_config() -> None:
    texts = _desc()["Params"]["DMS_site"]["texts"][1:]
    names = re.findall(r'^\t\t\["([^"]+)", \[\d+, \d+\], \d+\]', _config_src(), re.MULTILINE)
    assert texts == names


def test_functions_declared_and_present() -> None:
    declared = sqf_check.cfg_functions(_desc())
    files = {p.stem[3:] for p in (MISSION / "functions").glob("fn_*.sqf")}
    assert declared == files
    assert _desc()["CfgFunctions"]["DMS"]["tag"] == "DMS"


def test_comm_menu_items() -> None:
    menu = _desc()["CfgCommunicationMenu"]
    assert set(menu) == {"DMS_ReportLaser", "DMS_ReportCursor"}
    for cls in menu.values():
        assert cls["removeAfterExpressionCall"] == 1
        assert "remoteExecCall ['DMS_fnc_strike', 2]" in cls["expression"]
    assert "laserTarget" in menu["DMS_ReportLaser"]["expression"]
    assert menu["DMS_ReportCursor"]["cursor"]
    sqf = _all_sqf()
    for item in re.findall(r'"(DMS_Report\w+)"', sqf):
        assert item in menu, item


def test_debriefing_classes() -> None:
    deb = _desc()["CfgDebriefing"]
    for cls in deb.values():
        assert {"title", "subtitle", "description"} <= set(cls)
    for end in set(re.findall(r'"(DMS_(?:Win|Fail\w*|TestEnd))"', _all_sqf())):
        assert end in deb, end


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
    # Vanilla only, so the mission loads without mods and initServer can name the missing ones.
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
    assert players[0]["type"] == "B_Soldier_TL_F"
    pos = players[0]["PositionInfo"]["position"]
    assert len(pos) == 3 and 0 < pos[0] < 12800 and 0 < pos[2] < 12800
    ids = [group["id"], *(u["id"] for u in units)]
    assert len(set(ids)) == len(ids)
    assert sqm["EditorData"]["ItemIDProvider"]["nextID"] > max(ids)


def test_mission_folder_is_enoch() -> None:
    assert MISSION.name.endswith(".Enoch")


# ---------------------------------------------------------------- fn_config data


def test_config_sites() -> None:
    sites = re.findall(
        r'^\t\t\["([^"]+)", \[(\d+), (\d+)\], (\d+)\],?$', _config_src(), flags=re.MULTILINE
    )
    assert len(sites) == 3
    for _name, x, y, brg in sites:
        # Livonia is 12800 m square; keep anchors well inside it.
        assert 1000 < int(x) < 11800 and 1000 < int(y) < 11800
        assert 0 <= int(brg) < 360


def test_config_keys_unique() -> None:
    keys = re.findall(r'^\t\["(\w+)",', _config_src(), flags=re.MULTILINE)
    assert len(keys) == len(set(keys))


def test_test_mode_expected_checks_are_emitted() -> None:
    block = re.search(r'\["testExpected", \[(.*?)\]\]', _config_src(), flags=re.DOTALL)
    assert block
    expected = re.findall(r'"(\w+)"', block.group(1))
    sqf = _all_sqf(exclude_config=True)
    for name in expected:
        assert f'"{name}"' in sqf, name


def test_classes_documented() -> None:
    """Every mod/vanilla class string in fn_config is recorded in CLASSES.md."""
    classes_md = (MISSION / "CLASSES.md").read_text(encoding="utf-8")
    strings = set(re.findall(r'"([A-Za-z0-9_]+)"', _config_src()))
    class_like = {
        s for s in strings if s.startswith(("rhs", "RHS", "Laser", "CamoNet", "Box_", "Sh_"))
    }
    assert class_like, "no classes found"
    for cls in sorted(class_like):
        assert f"`{cls}`" in classes_md, cls


def test_lambs_functions_documented() -> None:
    classes_md = (MISSION / "CLASSES.md").read_text(encoding="utf-8")
    used = set(re.findall(r"\blambs_wp_fnc_\w+", _all_sqf()))
    assert used == {"lambs_wp_fnc_taskCamp", "lambs_wp_fnc_taskPatrol", "lambs_wp_fnc_taskHunt"}
    for fn in used:
        assert f"`{fn}`" in classes_md, fn


def test_required_mods_checked_at_init() -> None:
    src = (MISSION / "initServer.sqf").read_text(encoding="utf-8")
    for patch in ["cba_main", "ace_main", "lambs_danger", "lambs_wp", "rhs_main", "rhsusf_main"]:
        assert f'"{patch}"' in src, patch
    assert "Mods: %1" in src
    assert '"DMS_FailMods"' in src


def test_qrf_is_infantry_only() -> None:
    """Lesson from The Hill: never send armed vehicles hunting the squad; the QRF is infantry."""
    sqf = _all_sqf()
    assert "createVehicleCrew" not in (MISSION / "functions" / "fn_alarm.sqf").read_text(
        encoding="utf-8"
    )
    assert "canMove" not in sqf
