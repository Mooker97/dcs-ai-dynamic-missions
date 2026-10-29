"""v0.7 campaign loop, end to end (no DCS): dcs.log -> `dms debrief` -> state -> `dms plan` next.

Uses a copy of campaigns/viper-detachment (the live campaign's state is never touched).
Fixtures: tests/fixtures/dcs-logs/headless-m03-dms-test.log.txt (real headless DCS lines) and
synthetic-m01-*.log.txt (m01 flights in the same line format; m01 has not been flown yet).
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Any

import pytest
import yaml
from dms_cli.main import app
from dms_cli.util import find_root
from dms_core import outcomes as oc
from dms_core.schemas import BeatSheet, Qualities
from typer.testing import CliRunner

ROOT = find_root(Path(__file__).parent)
VIPER = ROOT / "campaigns" / "viper-detachment"
LOGS = ROOT / "tests" / "fixtures" / "dcs-logs"
M02 = "m02-the-quarry"

runner = CliRunner()


def invoke(*args: str) -> Any:
    return runner.invoke(app, ["--root", str(ROOT), *args], catch_exceptions=False)


@pytest.fixture
def camp(tmp_path: Path) -> Path:
    """A fresh copy of the viper campaign (arc, bible, initial state, mission folders, no out/)."""
    dst = tmp_path / "campaigns" / "viper-detachment"
    shutil.copytree(VIPER, dst, ignore=shutil.ignore_patterns("out", "voice", "outcomes", "*.miz"))
    # Start from the arc's initial state, whatever the live campaign has reached.
    arc, _ = oc.load_debrief_inputs(dst)
    assert arc is not None
    init = Qualities(values={q.id: q.initial for q in arc.qualities})
    (dst / "state" / "qualities.yaml").write_text(
        yaml.safe_dump(init.model_dump(mode="json"), sort_keys=False), encoding="utf-8"
    )
    return dst


def debrief(camp: Path, mission: str, log: str) -> dict[str, Any]:
    args = ["debrief", str(camp), "--mission", mission, "--log", str(LOGS / log)]
    dry = invoke(*args, "--dry-run")
    assert dry.exit_code == 0, dry.output
    assert not (camp / "state" / "outcomes").exists()
    res = invoke(*args, "--json")
    assert res.exit_code == 0, res.output
    data: dict[str, Any] = json.loads(res.output)
    return data


def plan(camp: Path, mission: str) -> dict[str, Any]:
    mdir = camp / "missions" / mission
    res = invoke("plan", str(mdir), "--seed", "7")
    assert res.exit_code == 0, res.output
    data: dict[str, Any] = json.loads((mdir / "out" / "plan.json").read_text(encoding="utf-8"))
    return data


def armed_beats(camp: Path, mission: str, qualities: dict[str, float]) -> set[str]:
    """Beats with a `requires.qualities` gate that holds for the planned DMS_CONFIG.qualities."""
    raw = yaml.safe_load((camp / "missions" / mission / "beats.yaml").read_text("utf-8"))
    sheet = BeatSheet.model_validate(raw)
    values = {k: int(v) for k, v in qualities.items()}
    out: set[str] = set()
    for b in sheet.beats:
        if b.requires is None or not b.requires.qualities:
            continue
        gate = b.requires.model_copy(update={"flags": [], "flags_not": [], "beats_fired": []})
        if oc.requires_hold(gate, {}, values)[0]:
            out.add(b.id)
    return out


def test_m01_outcome_shapes_m02(camp: Path, tmp_path: Path) -> None:
    lost_camp = tmp_path / "lost" / "viper-detachment"
    shutil.copytree(camp, lost_camp)

    win = debrief(camp, "m01", "synthetic-m01-win.log.txt")
    assert win["next_mission"] == M02
    assert win["qualities"]["values"]["sam_threat"] == 0  # radar + SA-8 + 2 launchers
    assert win["qualities"]["values"]["intel"] == 2  # window held
    assert win["qualities"]["flags"]["m01_window_held"] is True
    reasons = [c["reason"] for c in win["outcome"]["extra"]["quality_changes"]]
    assert all(r.startswith("arc quality_effects") for r in reasons) and len(reasons) == 3
    # collateral is machine form (no "not machine-readable"); civilians_hit was never reported,
    # so the debriefer is told the key is missing rather than it silently counting as false
    assert not any("collateral" in w and "machine-readable" in w for w in win["warnings"])
    assert any("civilians_hit not in this flight's outcome facts" in w for w in win["warnings"])

    lost = debrief(lost_camp, "m01", "synthetic-m01-window-lost.log.txt")
    assert lost["next_mission"] == M02
    assert lost["qualities"]["values"]["sam_threat"] == 2
    assert lost["qualities"]["values"]["intel"] == 1

    # state written + continuity appended (append-only: the old text is still a prefix)
    old = (VIPER / "continuity.md").read_text(encoding="utf-8")
    cont = (camp / "continuity.md").read_text(encoding="utf-8")
    assert cont.startswith(old.rstrip("\n"))
    assert "— dms debrief — m01-broken-umbrella flown (success)" in cont
    assert "intel 1→2" in cont and f"Next: {M02}" in cont
    state = Qualities.model_validate(
        yaml.safe_load((camp / "state" / "qualities.yaml").read_text("utf-8"))
    )
    assert state.next_mission == M02 and state.updated_after == "m01-broken-umbrella"
    assert (camp / "state" / "outcomes" / "m01.yaml").is_file()

    # the next mission's plan reflects the outcome
    p_win, p_lost = plan(camp, M02), plan(lost_camp, M02)
    q_win, q_lost = p_win["runtime"]["qualities"], p_lost["runtime"]["qualities"]
    assert q_win["sam_threat"] == 0 and q_win["intel"] == 2
    assert q_lost["sam_threat"] == 2 and q_lost["intel"] == 1
    a_win, a_lost = armed_beats(camp, M02, q_win), armed_beats(lost_camp, M02, q_lost)
    assert "intel_mark" in a_win and "intel_mark" not in a_lost  # MQ-9 marks the active site
    assert "sam_cue" in a_lost and "sam_cue" not in a_win  # pop-up SAM only if the umbrella lived
    f_win, f_lost = p_win["runtime"]["flags"], p_lost["runtime"]["flags"]
    assert f_win["m01_window_held"] is True and f_win["m01_success"] is True
    assert f_lost.get("m01_window_held") is not True  # campaign flags -> DMS_CONFIG.flags
    assert p_win["groups"] == p_lost["groups"]  # same seed: only the campaign state differs


def test_m01_player_lost_replays(camp: Path) -> None:
    dead = debrief(camp, "m01", "synthetic-m01-player-lost.log.txt")
    assert dead["outcome"]["result"] == "failure"
    assert dead["next_mission"] == "m01-broken-umbrella"
    assert "branch 1" in dead["next_reason"]
    assert dead["qualities"]["values"]["sam_threat"] == 2


def test_real_headless_m03_log(camp: Path) -> None:
    """Real [DMS.OUTCOME] line from a headless DCS run (update only, no end line)."""
    data = debrief(camp, "m03", "headless-m03-dms-test.log.txt")
    ex = data["outcome"]["extra"]
    assert data["mission_id"] == "m03-troops-in-contact"
    assert ex["ended"] is False and ex["dms_version"] == "0.3.0.dev0+635bb9c"
    assert {w["module"] for w in ex["log_warnings"]} == {"Ground", "Intel"}
    # no end line: arc effects ("-1 if not position_held") are NOT applied to an unended flight
    assert data["qualities"]["values"]["partner_morale"] == 0
    assert any("flight did not end" in w for w in data["warnings"])
    assert not data["outcome"]["extra"]["quality_changes"]
    assert data["qualities"]["flags"]["m03_position_held"] is False
    assert any("no result" in w for w in data["warnings"])
    assert data["next_mission"] == "m04-last-launcher"
    again = invoke(
        "debrief", str(camp), "-m", "m03", "--log", str(LOGS / "headless-m03-dms-test.log.txt")
    )
    assert again.exit_code == 1 and "already" in again.output


def test_force_redebrief_rolls_back_and_replaces(camp: Path, tmp_path: Path) -> None:
    """--force on the same flight (even from a rotated dcs.log.old) does not double anything."""
    first = debrief(camp, "m01", "synthetic-m01-win.log.txt")
    rotated = tmp_path / "Logs" / "dcs.log.old"
    rotated.parent.mkdir()
    shutil.copy(LOGS / "synthetic-m01-win.log.txt", rotated)
    args = ["debrief", str(camp), "-m", "m01", "--log", str(rotated)]
    blocked = invoke(*args)
    assert blocked.exit_code == 1 and "already" in blocked.output
    res = invoke(*args, "--force", "--json")
    assert res.exit_code == 0, res.output
    again = json.loads(res.output)
    assert again["qualities"]["values"] == first["qualities"]["values"]
    assert any("rolled back previous debrief" in w for w in again["warnings"])
    cont = (camp / "continuity.md").read_text(encoding="utf-8")
    assert cont.count("— dms debrief — m01-broken-umbrella flown") == 1
