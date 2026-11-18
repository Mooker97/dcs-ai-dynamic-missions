"""Static tests for the DMS Arma 3 mission. Run: uv run pytest arma -q"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sqf_check

MISSION = Path(__file__).resolve().parents[1] / "missions" / "dms_the_hill.Altis"
SQF_FILES = sorted(MISSION.rglob("*.sqf"))


def _desc() -> dict:
    return sqf_check.parse_config(
        (MISSION / "description.ext").read_text(encoding="utf-8"), "description.ext"
    )


def _sqm() -> dict:
    return sqf_check.parse_config(
        (MISSION / "mission.sqm").read_text(encoding="utf-8"), "mission.sqm"
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
    ]:
        assert (MISSION / rel).is_file(), rel


# ---------------------------------------------------------------- description.ext


def test_params() -> None:
    params = _desc()["Params"]
    for name in ["DMS_seed", "DMS_site", "DMS_debug", "DMS_testMode", "DMS_testMinutes"]:
        p = params[name]
        assert len(p["values"]) == len(p["texts"]), name
        assert p["default"] in p["values"], name
    sqf = "\n".join(p.read_text(encoding="utf-8") for p in SQF_FILES)
    for used in re.findall(r'\["(DMS_\w+)",\s*-?\d+\]\s*call\s+BIS_fnc_getParamValue', sqf):
        assert used in params, used


def test_functions_declared_and_present() -> None:
    declared = sqf_check.cfg_functions(_desc())
    files = {p.stem[3:] for p in (MISSION / "functions").glob("fn_*.sqf")}
    assert declared == files
    assert _desc()["CfgFunctions"]["DMS"]["tag"] == "DMS"


def test_comm_menu_items() -> None:
    menu = _desc()["CfgCommunicationMenu"]
    assert set(menu) == {"DMS_ArtyFire", "DMS_ArtySpot", "DMS_Extract"}
    for cls in menu.values():
        assert cls["removeAfterExpressionCall"] == 1
        assert "remoteExecCall" in cls["expression"]


def test_debriefing_classes() -> None:
    deb = _desc()["CfgDebriefing"]
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
    assert "A3_Characters_F" in sqm["addons"]
    assert sqm["AddonsMetaData"]["List"]["items"] == len(sqm["addons"])
    ents = sqm["Mission"]["Entities"]
    _count_items(ents)
    group = ents["Item0"]
    assert group["dataType"] == "Group" and group["side"] == "West"
    units = [v for k, v in group["Entities"].items() if k.startswith("Item")]
    players = [u for u in units if u["Attributes"].get("isPlayer") == 1]
    assert len(players) == 1
    assert players[0]["Attributes"]["isPlayable"] == 1
    assert players[0]["type"] == _config_value("squadLeaderClass")
    assert len(players[0]["PositionInfo"]["position"]) == 3
    ids = [group["id"], *(u["id"] for u in units)]
    assert len(set(ids)) == len(ids)
    assert sqm["EditorData"]["ItemIDProvider"]["nextID"] > max(ids)


def _config_value(key: str) -> str:
    src = (MISSION / "functions" / "fn_config.sqf").read_text(encoding="utf-8")
    m = re.search(rf'\["{key}",\s*"([^"]+)"\]', src)
    assert m, key
    return m.group(1)


# ---------------------------------------------------------------- fn_config data


def test_config_sites_and_composition() -> None:
    src = (MISSION / "functions" / "fn_config.sqf").read_text(encoding="utf-8")
    sites = re.findall(
        r'^\t\t\["([^"]+)", \[(\d+), (\d+)\], (\d+), (\d+), \[\[', src, flags=re.MULTILINE
    )
    assert 2 <= len(sites) <= 3
    for _name, x, y, cdir, brg in sites:
        assert 0 < int(x) < 30720 and 0 < int(y) < 30720
        assert 0 <= int(cdir) < 360 and 0 <= int(brg) < 360
    modes = re.findall(r'^\t\t\["[^"]+", \[\d+, \d+\].*"(OUTPOST|BUILD)"\],?$', src, re.MULTILINE)
    assert len(modes) == len(sites)

    def kinds_of(key: str) -> list[str]:
        block = re.search(rf'\["{key}", \[(.*?)\n\t\]\]', src, flags=re.DOTALL)
        assert block, key
        return re.findall(
            r'^\t\t\["(BLD|OBJ|STATIC|SENTRY|INTEL|OVER)",', block.group(1), flags=re.MULTILINE
        )

    kinds = kinds_of("composition")
    assert kinds.count("INTEL") == 1
    assert kinds.count("BLD") >= 2 and 1 <= kinds.count("STATIC") <= 2
    okinds = kinds_of("outpostComposition")
    assert okinds.count("INTEL") == 1 and "BLD" not in okinds
    assert 1 <= okinds.count("STATIC") <= 2


def test_config_keys_unique() -> None:
    src = (MISSION / "functions" / "fn_config.sqf").read_text(encoding="utf-8")
    keys = re.findall(r'^\t\["(\w+)",', src, flags=re.MULTILINE)
    assert len(keys) == len(set(keys))


def test_test_mode_expected_checks_are_emitted() -> None:
    src = (MISSION / "functions" / "fn_config.sqf").read_text(encoding="utf-8")
    block = re.search(r'\["testExpected", \[(.*?)\]\]', src, flags=re.DOTALL)
    assert block
    expected = re.findall(r'"(\w+)"', block.group(1))
    sqf = "\n".join(p.read_text(encoding="utf-8") for p in SQF_FILES if p.name != "fn_config.sqf")
    for name in expected:
        if name.startswith("qrf_wave"):
            assert 'format ["qrf_wave%1"' in sqf
        else:
            assert f'"{name}"' in sqf, name


# ---------------------------------------------------------------- checker self-tests


@pytest.mark.parametrize(
    ("snippet", "fragment"),
    [
        ("private _a = [1, 2;", "unclosed"),
        ("private _a = (1 + 2];", "closes"),
        ('private _a = "abc;', "unterminated string"),
        ("/* never closed", "unterminated block comment"),
        ("private _a = [1, 2,];", "trailing comma"),
        ("private _a = 1\nprivate _b = 2;", "missing ';'"),
        ("private _a = {1}\n_a = 2;", "missing ';'"),
        ('private _a = ["X"] call DMS_fnc_rng + 1;', "parentheses"),
        ("sleep (1) + 2;", "sleep"),
        ("private _a = random 5;", "seeded RNG"),
    ],
)
def test_checker_catches(snippet: str, fragment: str) -> None:
    rep = sqf_check.check_sqf(snippet)
    assert any(fragment in e for e in rep.errors), rep.errors


def test_checker_hygiene_warnings() -> None:
    rep = sqf_check.check_sqf("_leak = 1;\nprivate _ok = _undefined;")
    assert any("_leak" in w for w in rep.warnings)
    assert any("_undefined" in w for w in rep.warnings)


def test_checker_accepts_valid_sqf() -> None:
    src = (
        'params ["_a", ["_b", 2]];\nprivate _s = "say ""hi""";\n'
        "if (_a > _b) then {\n\t_s = 'x';\n} else {\n\t_s = 'y';\n};\n"
        "private _r = (5 call { _this * 2 }) + 1;\n"
        "{ diag_log _x; } forEach [1, 2];\n"
        "private _n = 1 + floor (random 3); // dms-allow-random\n"
    )
    rep = sqf_check.check_sqf(src)
    assert rep.errors == [] and rep.warnings == []


def test_config_parser_rejects_bad_cfg() -> None:
    with pytest.raises(sqf_check.ConfigError):
        sqf_check.parse_config("class A { x = 1; }")  # missing ';' after class
    with pytest.raises(sqf_check.ConfigError):
        sqf_check.parse_config("a[] = {1, 2,};")
