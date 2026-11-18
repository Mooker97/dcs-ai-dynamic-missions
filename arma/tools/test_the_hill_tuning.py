"""Guards for The Hill's tuning: README radii match fn_config, and the QRF fight-time floors exist.

The floors (PLAN C1a) stop test-time compression from stacking every QRF wave on the squad at once.
Normal play is unchanged because DMS_fnc_t caps the floor at the unscaled value.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MISSION = ROOT / "arma" / "missions" / "dms_the_hill.Altis"
FUNCS = MISSION / "functions"
README = ROOT / "arma" / "README.md"


def _cfg_num(key: str) -> float:
    src = (FUNCS / "fn_config.sqf").read_text(encoding="utf-8")
    m = re.search(rf'\["{key}",\s*(-?\d+(?:\.\d+)?)\]', src)
    assert m, key
    return float(m.group(1))


def _fmt_m(v: float) -> str:
    return f"{int(v)} m"


def _fmt_km(v: float) -> str:
    return f"{v / 1000:g} km"


def _exfil_bullets() -> str:
    text = README.read_text(encoding="utf-8")
    m = re.search(r"\*\*Extraction.*?\n(.*?)\n- \*\*Win", text, flags=re.DOTALL)
    assert m, "README extraction section not found"
    return re.sub(r"\s+", " ", m.group(1))


def test_readme_hot_lz_radii_match_config() -> None:
    sec = _exfil_bullets()
    hot = _cfg_num("exfilHotRadius")
    veh = _cfg_num("exfilHotVehicleRadius")
    count = int(_cfg_num("exfilHotCount"))
    assert f"{count} or more known enemies within {_fmt_m(hot)} of the LZ" in sec
    assert f"armed enemy vehicle within {_fmt_m(veh)}" in sec
    assert f"holds {_fmt_km(_cfg_num('exfilHoldDistance'))} out" in sec
    # Every metre figure in the hot-LZ bullet is one of the configured radii.
    bullet = sec[sec.index("holds") : sec.index("It lands")]
    figures = {int(x) for x in re.findall(r"(\d+) m\b", bullet)}
    assert figures == {int(hot), int(veh)}, figures


def test_readme_boarding_and_win_distances_match_config() -> None:
    sec = _exfil_bullets()
    assert f"waits {int(_cfg_num('exfilWaitOnGround'))} s" in sec
    assert f"within {_fmt_m(_cfg_num('exfilBoardRadius'))}" in sec
    win = README.read_text(encoding="utf-8")
    assert f"gets {_fmt_km(_cfg_num('exfilDepartDistance'))} out" in win


def test_hot_vehicle_radius_covers_rcws_range() -> None:
    # Seed 2 (2026-10-28): an RCWS APC within 600 m shot the heli down.
    assert _cfg_num("exfilHotVehicleRadius") >= 1200
    assert _cfg_num("exfilHotRadius") < _cfg_num("exfilHotVehicleRadius")


def test_qrf_fight_time_floors_present() -> None:
    src = (FUNCS / "fn_qrf.sqf").read_text(encoding="utf-8")
    floors = {
        "wave1Delay": r'\[DMS_rolls get "wave1Delay",\s*(\d+)\]\s*call DMS_fnc_t',
        "wave2DragTime": r'\[_cfg get "wave2DragTime",\s*(\d+)\]\s*call DMS_fnc_t',
        "wave2Delay": r'\[DMS_rolls get "wave2Delay",\s*(\d+)\]\s*call DMS_fnc_t',
    }
    got = {}
    for key, pat in floors.items():
        m = re.search(pat, src)
        assert m, f"{key}: no DMS_fnc_t floor"
        got[key] = int(m.group(1))
    assert got == {"wave1Delay": 240, "wave2DragTime": 600, "wave2Delay": 90}


def test_floors_never_raise_normal_play_values() -> None:
    """DMS_fnc_t returns max(s * scale, min(floor, s)); at scale 1 that is s for every floor."""
    src = (FUNCS / "fn_t.sqf").read_text(encoding="utf-8")
    assert "(_min min _s)" in src

    def t(s: float, floor: float, scale: float) -> float:
        return max(s * scale, min(floor, s))

    lo1, hi1 = _cfg_range("wave1Delay")
    lo2, hi2 = _cfg_range("wave2Delay")
    drag = _cfg_num("wave2DragTime")
    for s, floor in [(lo1, 240), (hi1, 240), (lo2, 90), (hi2, 90), (drag, 600)]:
        assert t(s, floor, 1.0) == s
        assert t(s, floor, 0.15) >= min(floor, s)


def _cfg_range(key: str) -> tuple[float, float]:
    src = (FUNCS / "fn_config.sqf").read_text(encoding="utf-8")
    m = re.search(rf'\["{key}",\s*\[(\d+),\s*(\d+)\]\]', src)
    assert m, key
    return float(m.group(1)), float(m.group(2))


def test_test_squad_extraction_opts_out_of_lambs() -> None:
    src = (FUNCS / "fn_testMode.sqf").read_text(encoding="utf-8")
    # Exact names from the LAMBS Danger 2.6.2 PBOs (arma/modules/ambient/CLASSES.md).
    classes_md = (ROOT / "arma" / "modules" / "ambient" / "CLASSES.md").read_text(encoding="utf-8")
    for var in ("lambs_danger_disableGroupAI", "lambs_danger_disableAI"):
        assert f"`{var}`" in classes_md
        assert f'setVariable ["{var}", true, true]' in src
    assert "doFollow" in src and "_grp move DMS_lz" in src
    for field in ("wp=", "beh=", "dest=", "currentWaypoint", "expectedDestination", "behaviour"):
        assert field in src, field
