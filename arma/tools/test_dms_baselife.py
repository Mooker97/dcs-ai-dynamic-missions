"""Static tests for the ambient "base life" module and its test mission.

Run: uv run pytest arma -q
Module: arma/modules/ambient (DMSA_fnc_*), vendored byte-identical into dms_baselife.Altis.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sqf_check

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "arma" / "modules" / "ambient"
MISSION = ROOT / "arma" / "missions" / "dms_baselife.Altis"
VENDORED = MISSION / "modules" / "ambient"
KB = ROOT / "docs" / "arma" / "kb" / "functions.txt"
MODULE_SQF = sorted((MODULE / "functions").glob("*.sqf"))
MISSION_SQF = sorted(MISSION.rglob("*.sqf"))
BIS_RE = re.compile(r"\b(BI[SN]_fnc_[A-Za-z0-9_]+)")
DMSA_RE = re.compile(r"\bDMSA_fnc_(\w+)")


def _kb() -> set[str]:
    return {
        ln.strip().lower()
        for ln in KB.read_text(encoding="utf-8").splitlines()
        if ln.strip() and not ln.startswith("#")
    }


def _real_warnings(rep: sqf_check.Report) -> list[str]:
    """Drop 'unverified BIS function' warnings for functions that are in the kb list."""
    kb = _kb()
    out = []
    for w in rep.warnings:
        m = re.search(r"unverified BIS function (\S+)", w)
        if m and m.group(1).lower() in kb:
            continue
        out.append(w)
    return out


def _wait_bodies(src: str) -> list[str]:
    """Bodies of every waitUntil { ... } (brace-balanced)."""
    out = []
    for m in re.finditer(r"waitUntil\s*\{", src):
        depth, i = 1, m.end()
        while depth and i < len(src):
            depth += {"{": 1, "}": -1}.get(src[i], 0)
            i += 1
        out.append(src[m.end() : i - 1])
    return out


def _desc() -> dict:
    return sqf_check.parse_config(
        (MISSION / "description.ext").read_text(encoding="utf-8"), "description.ext"
    )


def _hpp() -> dict:
    return sqf_check.parse_config(
        (MODULE / "cfgFunctions.hpp").read_text(encoding="utf-8"), "cfgFunctions.hpp"
    )


# ---------------------------------------------------------------- module


@pytest.mark.parametrize("path", MODULE_SQF, ids=lambda p: p.name)
def test_module_sqf_clean(path: Path) -> None:
    rep = sqf_check.check_sqf(path.read_text(encoding="utf-8"), path.name)
    assert rep.errors == []
    assert _real_warnings(rep) == []


def test_module_files_exist() -> None:
    for rel in ["README.md", "CLASSES.md", "cfgFunctions.hpp"]:
        assert (MODULE / rel).is_file(), rel


def test_module_cfgfunctions_match_files() -> None:
    hpp = _hpp()
    assert set(hpp) == {"DMSA"}
    assert hpp["DMSA"]["tag"] == "DMSA"
    cat = hpp["DMSA"]["ambient"]
    assert cat["file"] == "modules\\ambient\\functions"
    declared = {k for k, v in cat.items() if isinstance(v, dict)}
    files = {p.stem[3:] for p in MODULE_SQF}
    assert declared == files
    used: set[str] = set()
    for p in MODULE_SQF:
        used.update(DMSA_RE.findall(p.read_text(encoding="utf-8")))
    assert used <= declared, used - declared
    assert "ambientAdd" in declared


def test_module_does_not_use_mission_functions() -> None:
    for p in MODULE_SQF:
        tokens, _ = sqf_check.tokenize(p.read_text(encoding="utf-8"), p.name)
        ids = {t.text for t in tokens if t.kind == "ID"}
        assert not {i for i in ids if i.startswith("DMS_fnc_") or i == "DMS_cfg"}, p.name


def test_module_bis_functions_in_kb() -> None:
    kb = _kb()
    for p in [*MODULE_SQF, MODULE / "cfgFunctions.hpp"]:
        for name in BIS_RE.findall(p.read_text(encoding="utf-8")):
            assert name.lower() in kb, f"{p.name}: {name}"


def test_module_lambs_variables() -> None:
    src = "\n".join(p.read_text(encoding="utf-8") for p in MODULE_SQF)
    # Exact names verified in the LAMBS Danger 2.6.2 PBOs (see CLASSES.md).
    assert '"lambs_danger_disableGroupAI", true, true' in src
    assert '"lambs_danger_disableAI", true, true' in src


def test_module_tags_and_never_fires() -> None:
    spawn = (MODULE / "functions" / "fn_ambientSpawn.sqf").read_text(encoding="utf-8")
    heli = (MODULE / "functions" / "fn_ambientHeli.sqf").read_text(encoding="utf-8")
    for src in (spawn, heli):
        assert 'setVariable ["DMSA_ambient", _id]' in src
        assert 'setCombatMode "BLUE"' in src
        assert "setCaptive false" in src
    assert (
        '"CYCLE"' in spawn
        and '"LIMITED"' in spawn
        and "nearRoads" in (MODULE / "functions" / "fn_ambientAdd.sqf").read_text(encoding="utf-8")
    )


def test_module_waits_are_bounded() -> None:
    """Every waitUntil in the module has a time-based escape."""
    for p in MODULE_SQF:
        src = p.read_text(encoding="utf-8")
        for body in _wait_bodies(src):
            assert "time" in body, f"{p.name}: unbounded waitUntil: {body.strip()[:80]}"


def test_module_defaults_documented() -> None:
    add = (MODULE / "functions" / "fn_ambientAdd.sqf").read_text(encoding="utf-8")
    readme = (MODULE / "README.md").read_text(encoding="utf-8")
    block = re.search(r"private _defaults = \[(.*?)\n\];", add, flags=re.DOTALL)
    assert block
    keys = re.findall(r'\["(\w+)",', block.group(1))
    assert {"activeRadius", "despawnRadius", "maxUnits", "maxVehicles", "faction"} <= set(keys)
    assert re.search(r'\["activeRadius", 600\]', add)
    assert re.search(r'\["despawnRadius", 900\]', add)
    assert re.search(r'\["despawnDelay", 30\]', add)
    for k in keys:
        assert f"`{k}`" in readme, k


def test_preset_classes_recorded() -> None:
    src = (MODULE / "functions" / "fn_ambientPresets.sqf").read_text(encoding="utf-8")
    classes_md = (MODULE / "CLASSES.md").read_text(encoding="utf-8")
    presets = re.findall(r'case "(\w+)":', src)
    assert {"rhs_usarmy", "rhs_usmc", "vanilla_nato"} <= set(presets)
    names = set(re.findall(r'"((?:B|rhsusf|RHS)_[A-Za-z0-9_]+)"', src))
    assert len(names) > 30
    for n in names:
        short = n.split("rhsusf_usmc_marpat_wd")[-1]
        assert f"`{n}`" in classes_md or f"`{short}`" in classes_md, n


# ---------------------------------------------------------------- vendored copy


def test_vendored_copy_identical() -> None:
    src_files = {
        p.relative_to(MODULE).as_posix(): p.read_bytes()
        for p in [MODULE / "cfgFunctions.hpp", *MODULE_SQF]
    }
    dst_files = {
        p.relative_to(VENDORED).as_posix(): p.read_bytes()
        for p in VENDORED.rglob("*")
        if p.is_file() and p.suffix in {".sqf", ".hpp"}
    }
    assert set(src_files) == set(dst_files)
    for rel, data in src_files.items():
        assert dst_files[rel].replace(b"\r\n", b"\n") == data.replace(b"\r\n", b"\n"), rel


# ---------------------------------------------------------------- mission


@pytest.mark.parametrize("path", MISSION_SQF, ids=lambda p: p.relative_to(MISSION).as_posix())
def test_mission_sqf_clean(path: Path) -> None:
    rep = sqf_check.check_sqf(
        path.read_text(encoding="utf-8"), path.name, allow_random=path.name == "fn_rng.sqf"
    )
    assert rep.errors == []
    assert _real_warnings(rep) == []


def test_whole_mission_check_passes() -> None:
    rep = sqf_check.check_mission(MISSION)
    assert rep.errors == []
    assert _real_warnings(rep) == []


def test_mission_files_exist() -> None:
    for rel in [
        "mission.sqm",
        "description.ext",
        "initServer.sqf",
        "initPlayerLocal.sqf",
        "functions/fn_config.sqf",
        "functions/fn_testMode.sqf",
        "modules/ambient/cfgFunctions.hpp",
    ]:
        assert (MISSION / rel).is_file(), rel


def test_description_includes_module() -> None:
    text = (MISSION / "description.ext").read_text(encoding="utf-8")
    cfgf = re.search(r"class CfgFunctions\s*\{(.*)\n\};", text, flags=re.DOTALL)
    assert cfgf
    assert '#include "modules\\ambient\\cfgFunctions.hpp"' in cfgf.group(1)
    desc = _desc()
    assert desc["CfgFunctions"]["DMS"]["tag"] == "DMS"
    assert desc["respawn"] == 0
    assert desc["Header"]["maxPlayers"] == 1


def test_mission_dmsa_calls_declared() -> None:
    declared = {k for k, v in _hpp()["DMSA"]["ambient"].items() if isinstance(v, dict)}
    for p in MISSION_SQF:
        for fn in DMSA_RE.findall(p.read_text(encoding="utf-8")):
            assert fn in declared, f"{p.name}: DMSA_fnc_{fn}"


def test_params() -> None:
    params = _desc()["Params"]
    for name in [
        "DMS_seed",
        "DMS_site",
        "DMS_faction",
        "DMS_debug",
        "DMS_testMode",
        "DMS_testMinutes",
    ]:
        p = params[name]
        assert len(p["values"]) == len(p["texts"]), name
        assert p["default"] in p["values"], name
    # The harness always sets these; the mission declares them so the server accepts the class.
    for name in ["DMS_testTimeScale", "DMS_testStartDist", "DMS_testAssist"]:
        assert name in params
    sqf = "\n".join(p.read_text(encoding="utf-8") for p in MISSION_SQF)
    for used in re.findall(r'\["(DMS_\w+)",\s*-?\d+\]\s*call\s+BIS_fnc_getParamValue', sqf):
        assert used in params, used


def test_faction_param_matches_config() -> None:
    cfg = (MISSION / "functions" / "fn_config.sqf").read_text(encoding="utf-8")
    m = re.search(r'\["factions", \[(.*?)\]\]', cfg)
    assert m
    factions = re.findall(r'"(\w+)"', m.group(1))
    assert factions == ["auto", "vanilla_nato", "rhs_usarmy", "rhs_usmc"]
    p = _desc()["Params"]["DMS_faction"]
    assert p["values"] == list(range(len(factions)))
    block = re.search(r'\["sites", \[(.*?)\n\t\]\]', cfg, flags=re.DOTALL)
    assert block
    sites = re.findall(r'\["([^"]+)", \[(\d+), (\d+)\]\]', block.group(1))
    assert len(sites) == len(_desc()["Params"]["DMS_site"]["values"])
    for _n, x, y in sites:
        assert 0 < int(x) < 30720 and 0 < int(y) < 30720


def test_test_mode_expected_checks_are_emitted() -> None:
    cfg = (MISSION / "functions" / "fn_config.sqf").read_text(encoding="utf-8")
    block = re.search(r'\["testExpected", \[(.*?)\]\]', cfg, flags=re.DOTALL)
    assert block
    expected = re.findall(r'"(\w+)"', block.group(1))
    assert len(expected) == len(set(expected))
    sqf = "\n".join(p.read_text(encoding="utf-8") for p in MISSION_SQF if p.name != "fn_config.sqf")
    for name in expected:
        assert f'"{name}"' in sqf, name
    test_mode = (MISSION / "functions" / "fn_testMode.sqf").read_text(encoding="utf-8")
    for marker in ['"DONE", "TEST"', "SUMMARY pass=", "DMSA_watchers"]:
        assert marker in test_mode


def test_test_mode_waits_are_bounded() -> None:
    src = (MISSION / "functions" / "fn_testMode.sqf").read_text(encoding="utf-8")
    bodies = _wait_bodies(src)
    assert len(bodies) >= 8
    for body in bodies:
        assert "time" in body, body.strip()[:80]


def test_mission_sqm_player() -> None:
    sqm = sqf_check.parse_config(
        (MISSION / "mission.sqm").read_text(encoding="utf-8"), "mission.sqm"
    )
    assert sqm["binarizationWanted"] == 0
    group = sqm["Mission"]["Entities"]["Item0"]
    unit = group["Entities"]["Item0"]
    assert unit["Attributes"]["isPlayer"] == 1
    x, _z, y = unit["PositionInfo"]["position"]
    cfg = (MISSION / "functions" / "fn_config.sqf").read_text(encoding="utf-8")
    first = re.search(r'\["[^"]+", \[(\d+), (\d+)\]\]', cfg)
    assert first
    assert abs(x - int(first.group(1))) < 200 and abs(y - int(first.group(2))) < 200
