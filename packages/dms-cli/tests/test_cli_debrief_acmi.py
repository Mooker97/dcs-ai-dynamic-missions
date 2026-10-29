"""``dms debrief --acmi``: Tacview facts merged into the debriefed outcome (G1)."""

from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Any

import pytest
import yaml
from dms_cli.main import app
from dms_cli.util import find_root
from typer.testing import CliRunner

ROOT = find_root(Path(__file__).parent)
CAMPAIGN = ROOT / "campaigns" / "dustoff-valley"
DCS_LOG = ROOT / "tests" / "fixtures" / "dcs-logs" / "multi-session-dcs.log.txt"
TV_FIX = ROOT / "packages" / "dms-tacview" / "tests" / "fixtures"

runner = CliRunner()


def invoke(*args: str) -> Any:
    return runner.invoke(app, ["--root", str(ROOT), *args], catch_exceptions=False)


@pytest.fixture
def campaign(tmp_path: Path) -> Path:
    camp = tmp_path / "dustoff-valley"
    (camp / "state").mkdir(parents=True)
    shutil.copy(CAMPAIGN / "arc.yaml", camp / "arc.yaml")
    shutil.copy(CAMPAIGN / "state" / "qualities.yaml", camp / "state" / "qualities.yaml")
    mdir = camp / "missions" / "m01-first-light"
    mdir.mkdir(parents=True)
    shutil.copy(TV_FIX / "hog_points.yaml", mdir / "tacview-points.yaml")
    return camp


def _args(camp: Path, *extra: str) -> list[str]:
    return ["debrief", str(camp), "--mission", "m01", "--log", str(DCS_LOG), *extra]


def test_debrief_acmi_dry_run_json(campaign: Path) -> None:
    acmi = str(TV_FIX / "hog_cas.txt.acmi")
    res = invoke(*_args(campaign, "--acmi", acmi, "--acmi-player", "Mooker", "--dry-run", "--json"))
    assert res.exit_code == 0, res.output
    out = json.loads(res.output)["outcome"]
    tv = out["extra"]["tacview"]
    assert tv["player"]["object_id"] == "101" and tv["player"]["landed"] is True
    assert tv["weapons_released"] == [{"weapon": "Mk-82", "count": 2, "hits": 1}]
    assert tv["time_over_target"][0]["name"] == "Column"  # from missions/m01-*/tacview-points
    assert tv["facts"]["tv_player_kills"] == 1
    assert not any(k.startswith("tv_") for k in out["outcomes"])  # not merged by default
    assert not (campaign / "state" / "outcomes").exists()


def test_debrief_acmi_facts_written_and_flagged(campaign: Path) -> None:
    acmi = str(TV_FIX / "hog_cas.txt.acmi")
    res = invoke(*_args(campaign, "--acmi", acmi, "--acmi-player", "101", "--acmi-facts"))
    assert res.exit_code == 0, res.output
    assert "tacview weapon: Mk-82 x2 (1 hit)" in res.output
    assert "tacview kill: Ural-375 (id 301) with Mk-82" in res.output
    out = yaml.safe_load((campaign / "state" / "outcomes" / "m01.yaml").read_text("utf-8"))
    assert out["outcomes"]["tv_player_landed"] is True
    assert out["extra"]["tacview"]["merged_into_outcomes"] is True
    q = yaml.safe_load((campaign / "state" / "qualities.yaml").read_text("utf-8"))
    assert q["flags"]["m01_tv_player_landed"] is True
    # the ACMI does not change the re-debrief guard (session_hash is from dcs.log only)
    again = invoke(*_args(campaign))
    assert again.exit_code == 1 and "already" in again.output


def test_debrief_acmi_auto_and_missing(
    campaign: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    empty = tmp_path / "tv-empty"
    empty.mkdir()
    monkeypatch.setenv("DMS_TACVIEW_DIR", str(empty))
    monkeypatch.setenv("USERPROFILE", str(tmp_path / "nohome"))
    monkeypatch.setenv("HOME", str(tmp_path / "nohome"))
    res = invoke(*_args(campaign, "--acmi", "auto", "--dry-run"))
    assert res.exit_code == 0, res.output
    assert "tacview error: no *.acmi found" in res.output

    tv_dir = tmp_path / "Tacview"
    tv_dir.mkdir()
    shutil.copy(TV_FIX / "hog_cas.txt.acmi", tv_dir / "Tacview-20261029-DCS-m01.txt.acmi")
    monkeypatch.setenv("DMS_TACVIEW_DIR", str(tv_dir))
    res = invoke(*_args(campaign, "--acmi", "auto", "--dry-run", "--json"))
    assert res.exit_code == 0, res.output
    tv = json.loads(res.output)["outcome"]["extra"]["tacview"]
    assert tv["source"].endswith("Tacview-20261029-DCS-m01.txt.acmi") and tv["player"]

    res = invoke(*_args(campaign, "--acmi", str(tmp_path / "nope.acmi"), "--dry-run"))
    assert res.exit_code == 2 and "ACMI not found" in res.output
