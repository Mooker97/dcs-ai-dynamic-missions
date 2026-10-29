"""Every class-like string in every Arma mission's fn_config.sqf is backed by a verified source.

A class counts as verified when it is back-ticked in `docs/arma/kb/classes-verified.md` (vanilla,
checked with `isClass` on a dedicated server) or in a `CLASSES.md` that belongs to the mission
(its own, or the shared ambient module's when the mission ships that module). Those files record
classes read from the mod PBOs. Test-check names, faction keys and mod display names are not
classes and are skipped.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest
from arma_paths import ROOT
from dms_arma.kb import find_kb, verified_classes

MISSIONS_DIR = ROOT / "arma" / "missions"
AMBIENT_CLASSES = ROOT / "arma" / "modules" / "ambient" / "CLASSES.md"
MISSIONS = sorted(p for p in MISSIONS_DIR.glob("*.*") if (p / "mission.sqm").is_file())

CLASS_LIKE = re.compile(r'"([A-Za-z][A-Za-z0-9]*_[A-Za-z0-9_]+)"')
TICKED = re.compile(r"`([^`\s]+)`")
# Config keys whose string values are names, not classes.
NON_CLASS_KEYS = ("testExpected", "factions")
# Mod display names (first element of a [displayName, cfgPatches] pair).
NON_CLASS_NAMES = frozenset({"cba_a3"})


def _key_block(src: str, key: str) -> str:
    m = re.search(rf'\["{key}",\s*\[(.*?)\]\]', src, flags=re.DOTALL)
    return m.group(1) if m else ""


def config_class_names(mission: Path) -> set[str]:
    """Class-like string literals from the mission's fn_config.sqf file(s)."""
    out: set[str] = set()
    for cfg in mission.rglob("fn_config.sqf"):
        src = cfg.read_text(encoding="utf-8")
        skip = {n for key in NON_CLASS_KEYS for n in CLASS_LIKE.findall(_key_block(src, key))}
        out |= {n for n in CLASS_LIKE.findall(src) if n not in skip}
    return {n for n in out if n.lower() not in NON_CLASS_NAMES}


def verified_for(mission: Path) -> set[str]:
    known = set(verified_classes(find_kb()))
    docs = list(mission.rglob("CLASSES.md"))
    if (mission / "modules" / "ambient").is_dir() and AMBIENT_CLASSES.is_file():
        docs.append(AMBIENT_CLASSES)
    for doc in docs:
        known |= {t.lower() for t in TICKED.findall(doc.read_text(encoding="utf-8"))}
    return known


def test_all_six_missions_found() -> None:
    names = {p.name for p in MISSIONS}
    assert len(MISSIONS) >= 6, names
    assert "dms_the_hill.Altis" in names


@pytest.mark.parametrize("mission", MISSIONS, ids=lambda p: p.name)
def test_mission_classes_are_verified(mission: Path) -> None:
    names = config_class_names(mission)
    assert names, f"no class names found in {mission.name}"
    known = verified_for(mission)
    missing = sorted(n for n in names if n.lower() not in known)
    assert missing == [], f"{mission.name}: not in the kb or the mission's CLASSES.md: {missing}"


def test_the_hill_is_vanilla_kb_only() -> None:
    """The Hill has no CLASSES.md, so every class must be in the dedicated-server kb list."""
    hill = MISSIONS_DIR / "dms_the_hill.Altis"
    assert not list(hill.rglob("CLASSES.md"))
    known = verified_classes(find_kb())
    assert sorted(n for n in config_class_names(hill) if n.lower() not in known) == []


def test_check_catches_an_unverified_class(tmp_path: Path) -> None:
    mission = tmp_path / "dms_fake.Altis"
    (mission / "functions").mkdir(parents=True)
    (mission / "functions" / "fn_config.sqf").write_text(
        'createHashMapFromArray [["heli", "B_Heli_Transport_01_F"], ["x", "rhs_made_up_F"],'
        ' ["testExpected", ["spawn_squad"]]]',
        encoding="utf-8",
    )
    names = config_class_names(mission)
    assert names == {"B_Heli_Transport_01_F", "rhs_made_up_F"}
    assert sorted(n for n in names if n.lower() not in verified_for(mission)) == ["rhs_made_up_F"]


def test_kb_root_is_the_repo_kb() -> None:
    assert find_kb() == ROOT / "docs" / "arma" / "kb"
