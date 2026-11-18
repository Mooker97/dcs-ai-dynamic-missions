"""Paths shared by the dms-arma tests."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HILL = ROOT / "arma" / "missions" / "dms_the_hill.Altis"
HILL_CONFIG = HILL / "functions" / "fn_config.sqf"
EXAMPLE = Path(__file__).resolve().parents[1] / "examples" / "the_hill.yaml"
