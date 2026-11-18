"""Static tests for the DMS Arma 3 mission "Village Sweep" (Malden, modded).

Run: uv run pytest arma -q
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sqf_check

MISSION = Path(__file__).resolve().parents[1] / "missions" / "dms_village.Malden"
SQF_FILES = sorted(MISSION.rglob("*.sqf"))
CONFIG = MISSION / "functions" / "fn_config.sqf"
MALDEN_SIZE = 12800


def _desc() -> dict:
    return sqf_check.parse_config(
        (MISSION / "description.ext").read_text(encoding="utf-8"), "description.ext"
    )


def _sqm() -> dict:
    return sqf_check.parse_config(
        (MISSION / "mission.sqm").read_text(encoding="utf-8"), "mission.sqm"
    )


def _cfg_src() -> str:
    return CONFIG.read_text(encoding="utf-8")


def _all_sqf() -> str:
    return "\n".join(p.read_text(encoding="utf-8") for p in SQF_FILES)


def _config_value(key: str) -> str:
    m = re.search(rf'\["{key}",\s*"([^"]+)"\]', _cfg_src())
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


def test_no_raw_wait_without_exit() -> None:
    """Every waitUntil must be able to end: it mentions DMS_over or a time bound."""
    for p in SQF_FILES:
        src = p.read_text(encoding="utf-8")
        for m in re.finditer(r"waitUntil\s*\{", src):
            depth, i = 1, m.end()
            while depth and i < len(src):
                depth += {"{": 1, "}": -1}.get(src[i], 0)
                i += 1
            body = src[m.end() : i]
            assert "DMS_over" in body or "time" in body, (
                f"{p.name}: unbounded waitUntil {body[:80]!r}"
            )


# ---------------------------------------------------------------- description.ext


def test_params() -> None:
    params = _desc()["Params"]
    for name in [
        "DMS_seed",
        "DMS_village",
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
    # harness defaults (tools/arma_harness/run_mission.py): --time-scale 15, --start-dist 300
    assert 15 in params["DMS_testTimeScale"]["values"]
    assert 300 in params["DMS_testStartDist"]["values"]
    for used in re.findall(r'\["(DMS_\w+)",\s*-?\d+\]\s*call\s+BIS_fnc_getParamValue', _all_sqf()):
        assert used in params, used


def test_village_param_matches_config() -> None:
    labels = re.findall(r'^\t\t\["(\w+)", \[\d+, \d+\]\],?$', _cfg_src(), flags=re.MULTILINE)
    texts = _desc()["Params"]["DMS_village"]["texts"]
    assert texts[1:] == labels


def test_functions_declared_and_present() -> None:
    declared = sqf_check.cfg_functions(_desc())
    files = {p.stem[3:] for p in (MISSION / "functions").glob("fn_*.sqf")}
    assert declared == files
    assert _desc()["CfgFunctions"]["DMS"]["tag"] == "DMS"


def test_comm_menu_items() -> None:
    menu = _desc()["CfgCommunicationMenu"]
    assert set(menu) == {"DMS_IfvMove", "DMS_IfvHold", "DMS_IfvSuppress"}
    for cls in menu.values():
        assert "remoteExecCall ['DMS_fnc_ifv', 2]" in cls["expression"]
        assert cls["text"].startswith("Bradley:")
    # every menu item is handed to the player, and every mode it sends is handled
    local = (MISSION / "initPlayerLocal.sqf").read_text(encoding="utf-8")
    ifv = (MISSION / "functions" / "fn_ifv.sqf").read_text(encoding="utf-8")
    for name, cls in menu.items():
        assert f'"{name}"' in local, name
        mode = re.match(r"\['(\w+)'", cls["expression"])
        assert mode and f'case "{mode.group(1)}"' in ifv, name


def test_debriefing_classes() -> None:
    deb = _desc()["CfgDebriefing"]
    for cls in deb.values():
        assert {"title", "subtitle", "description"} <= set(cls)
    for end in set(re.findall(r'"(DMS_(?:Win\w*|Fail\w*|TestEnd))"', _all_sqf())):
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


def test_mission_folder_world() -> None:
    assert MISSION.name.rpartition(".")[2] == "Malden"


def test_mission_sqm_structure() -> None:
    sqm = _sqm()
    assert sqm["version"] >= 52
    assert sqm["binarizationWanted"] == 0
    # the slot is vanilla, so a missing mod is reported by the script instead of failing the load
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
    assert len(pos) == 3 and 0 < pos[0] < MALDEN_SIZE and 0 < pos[2] < MALDEN_SIZE
    ids = [group["id"], *(u["id"] for u in units)]
    assert len(set(ids)) == len(ids)
    assert sqm["EditorData"]["ItemIDProvider"]["nextID"] > max(ids)


# ---------------------------------------------------------------- fn_config data


def test_config_villages() -> None:
    villages = re.findall(r'^\t\t\["(\w+)", \[(\d+), (\d+)\]\],?$', _cfg_src(), flags=re.MULTILINE)
    assert 2 <= len(villages) <= 3
    for _name, x, y in villages:
        assert 0 < int(x) < MALDEN_SIZE and 0 < int(y) < MALDEN_SIZE


def test_config_keys_unique() -> None:
    keys = re.findall(r'^\t\["(\w+)",', _cfg_src(), flags=re.MULTILINE)
    assert len(keys) == len(set(keys))


def test_required_mods_listed() -> None:
    block = re.search(r'\["requiredMods", \[(.*?)\n\t\]\]', _cfg_src(), flags=re.DOTALL)
    assert block
    patches = set(re.findall(r'\["[^"]+", "(\w+)"\]', block.group(1)))
    assert {
        "cba_main",
        "ace_main",
        "lambs_danger",
        "lambs_wp",
        "rhs_main",
        "rhsusf_main",
        "rhsgref_main",
    } <= patches


def test_mod_classes_documented() -> None:
    """Every mod class and LAMBS function the mission uses is recorded in CLASSES.md."""
    classes_md = (MISSION / "CLASSES.md").read_text(encoding="utf-8")
    used = set(re.findall(r'"((?:rhs|RHS_)\w+)"', _cfg_src()))
    used |= set(re.findall(r"\b(lambs_\w+)", _all_sqf()))
    assert used
    missing = sorted(u for u in used if f"`{u}`" not in classes_md)
    assert not missing, missing


def test_test_mode_expected_checks_are_emitted() -> None:
    block = re.search(r'\["testExpected", \[(.*?)\]\]', _cfg_src(), flags=re.DOTALL)
    assert block
    expected = re.findall(r'"(\w+)"', block.group(1))
    sqf = "\n".join(p.read_text(encoding="utf-8") for p in SQF_FILES if p.name != "fn_config.sqf")
    for name in [*expected, "outcome_forced", "ifv_lost"]:
        assert f'"{name}"' in sqf, name
