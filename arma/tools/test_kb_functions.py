"""Every BIS/BIN function used by Arma missions must exist in the knowledge-base list."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
KB = ROOT / "docs" / "arma" / "kb" / "functions.txt"
MISSIONS = ROOT / "arma" / "missions"
PATTERN = re.compile(r"\b(BI[SN]_fnc_[A-Za-z0-9_]+)")


def known_functions() -> set[str]:
    lines = KB.read_text(encoding="utf-8").splitlines()
    return {ln.strip().lower() for ln in lines if ln.strip() and not ln.startswith("#")}


def test_kb_list_loaded() -> None:
    assert len(known_functions()) > 2000


def test_mission_functions_exist_in_kb() -> None:
    known = known_functions()
    unknown: dict[str, list[str]] = {}
    for path in MISSIONS.rglob("*"):
        if path.suffix.lower() not in {".sqf", ".ext", ".hpp", ".sqm"}:
            continue
        for name in PATTERN.findall(path.read_text(encoding="utf-8", errors="replace")):
            if name.lower() not in known:
                unknown.setdefault(name, []).append(str(path.relative_to(ROOT)))
    assert not unknown, f"functions not in docs/arma/kb/functions.txt: {unknown}"
