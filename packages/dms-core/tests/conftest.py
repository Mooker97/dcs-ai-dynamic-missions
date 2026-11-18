"""Shared fixtures for dms-core tests: locate real .miz missions (read-only sources)."""

from __future__ import annotations

import shutil
from pathlib import Path

import pytest

TESTS_DIR = Path(__file__).resolve().parent
REPO_ROOT = TESTS_DIR.parents[2]

_SEARCH_GLOBS: list[tuple[Path, str]] = [
    (TESTS_DIR / "fixtures" / "miz", "*.miz"),
    (REPO_ROOT / "miz-files" / "input", "*.miz"),
    (REPO_ROOT / "legacy" / "miz-modification" / "tests", "**/*.miz"),
]
_EXTRA_FILES = [
    Path.home() / "Saved Games" / "DCS" / "Missions" / "Syria AH64" / "Dustoff Corridor.miz",
]


def find_miz_fixtures() -> list[Path]:
    """All available fixture missions, de-duplicated by file name (first location wins)."""
    found: dict[str, Path] = {}
    for base, pattern in _SEARCH_GLOBS:
        if base.is_dir():
            for p in sorted(base.glob(pattern)):
                found.setdefault(p.name.lower(), p)
    for p in _EXTRA_FILES:
        if p.is_file():
            found.setdefault(p.name.lower(), p)
    return list(found.values())


def pytest_generate_tests(metafunc: pytest.Metafunc) -> None:
    if "miz_source" in metafunc.fixturenames:
        paths = find_miz_fixtures()
        if paths:
            metafunc.parametrize("miz_source", paths, ids=[p.stem for p in paths])
        else:
            metafunc.parametrize(
                "miz_source",
                [pytest.param(None, marks=pytest.mark.skip(reason="no .miz fixtures found"))],
            )


@pytest.fixture
def miz_path(miz_source: Path, tmp_path: Path) -> Path:
    """A private copy of a fixture mission (sources are never written)."""
    dest = tmp_path / miz_source.name
    shutil.copyfile(miz_source, dest)
    return dest
