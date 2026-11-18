from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

from arma_paths import HILL_CONFIG


@pytest.fixture
def hill_text() -> str:
    """The live, hand-tuned The Hill config (read-only)."""
    if not HILL_CONFIG.is_file():
        pytest.skip("The Hill mission not present")
    return HILL_CONFIG.read_text(encoding="utf-8")
