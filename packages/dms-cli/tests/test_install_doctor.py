"""``dms install`` and ``dms doctor``: tmp Saved Games via DMS_DCS_SAVED_GAMES, fake .miz bytes."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

import pytest
from dms_cli import install as inst
from dms_cli.main import app
from dms_cli.util import find_root
from typer.testing import CliRunner

ROOT = find_root(Path(__file__).parent)
runner = CliRunner()
MID = "m01-test-flight"


def invoke(*args: str) -> Any:
    return runner.invoke(app, ["--root", str(ROOT), *args], catch_exceptions=False)


@pytest.fixture
def saved(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    sg = tmp_path / "Saved Games"
    sg.mkdir()
    monkeypatch.setenv(inst.SAVED_GAMES_ENV, str(sg))
    return sg


@pytest.fixture
def mission(tmp_path: Path) -> Path:
    mdir = tmp_path / "campaigns" / "viper-test" / "missions" / MID
    out = mdir / "out"
    out.mkdir(parents=True)
    (mdir / "mission-spec.yaml").write_text(f"id: {MID}\n", encoding="utf-8")
    for name in (f"{MID}.miz", f"{MID}-ramp.miz", f"{MID}-air.miz", f"{MID}-test.miz"):
        (out / name).write_bytes(b"PK fake " + name.encode())
    (out / "other.miz").write_bytes(b"not ours")
    return mdir


def _dest(saved: Path, variant_dir: str) -> Path:
    return saved / variant_dir / "Missions" / "DMS" / "viper-test"


def test_dry_run_writes_nothing(saved: Path, mission: Path) -> None:
    r = invoke("install", str(mission), "--dcs", "stable", "--dry-run")
    assert r.exit_code == 0, r.output
    assert "dry run: nothing written" in r.output
    assert f"{MID}-ramp.miz" in r.output
    assert list(saved.iterdir()) == []


def test_install_copies_variants(saved: Path, mission: Path) -> None:
    r = invoke("install", str(mission / "mission-spec.yaml"), "--dcs", "stable")
    assert r.exit_code == 0, r.output
    dest = _dest(saved, "DCS")
    names = sorted(p.name for p in dest.iterdir())
    assert names == sorted([f"{MID}.miz", f"{MID}-air.miz", f"{MID}-ramp.miz"])
    assert (dest / f"{MID}-air.miz").read_bytes() == (
        mission / "out" / f"{MID}-air.miz"
    ).read_bytes()
    assert "Missions\\DMS\\viper-test\\" in r.output
    # overwrite + --test includes the test build
    r = invoke("install", str(mission), "--dcs", "stable", "--test")
    assert r.exit_code == 0, r.output
    assert (dest / f"{MID}-test.miz").is_file()


def test_install_single_miz(saved: Path, mission: Path) -> None:
    r = invoke("install", str(mission / "out" / f"{MID}-ramp.miz"), "--dcs", "openbeta")
    assert r.exit_code == 0, r.output
    assert [p.name for p in _dest(saved, "DCS.openbeta").iterdir()] == [f"{MID}-ramp.miz"]


def test_openbeta_selection(saved: Path, mission: Path) -> None:
    r = invoke("install", str(mission), "--dcs", "openbeta", "--json")
    assert r.exit_code == 0, r.output
    data = json.loads(r.output)
    assert data["dcs"] == "openbeta"
    assert Path(data["dest"]) == _dest(saved, "DCS.openbeta")
    assert len(data["files"]) == 3
    assert (_dest(saved, "DCS.openbeta") / f"{MID}.miz").is_file()


def test_auto_selection(saved: Path, mission: Path) -> None:
    # neither exists -> DCS with a warning
    d, v, warns = inst.pick_dcs_dir(saved, "auto")
    assert (d, v) == (saved / "DCS", "stable") and warns
    # only openbeta exists -> openbeta
    (saved / "DCS.openbeta" / "Logs").mkdir(parents=True)
    assert inst.pick_dcs_dir(saved, "auto")[1] == "openbeta"
    # both: newest dcs.log wins
    (saved / "DCS" / "Logs").mkdir(parents=True)
    stable_log = saved / "DCS" / "Logs" / "dcs.log"
    beta_log = saved / "DCS.openbeta" / "Logs" / "dcs.log"
    stable_log.write_text("x")
    beta_log.write_text("x")
    os.utime(stable_log, (1000, 1000))
    os.utime(beta_log, (2000, 2000))
    assert inst.pick_dcs_dir(saved, "auto")[1] == "openbeta"
    os.utime(stable_log, (3000, 3000))
    assert inst.pick_dcs_dir(saved, "auto")[1] == "stable"
    r = invoke("install", str(mission))
    assert r.exit_code == 0, r.output
    assert (_dest(saved, "DCS") / f"{MID}.miz").is_file()


def test_bad_dcs_choice(saved: Path, mission: Path) -> None:
    r = invoke("install", str(mission), "--dcs", "beta")
    assert r.exit_code == 2


def test_no_built_miz(saved: Path, tmp_path: Path) -> None:
    mdir = tmp_path / "solo"
    mdir.mkdir()
    (mdir / "mission-spec.yaml").write_text("id: solo\ncampaign: loose\n", encoding="utf-8")
    r = invoke("install", str(mdir))
    assert r.exit_code == 1
    assert "run `dms run" in r.output
    assert inst.campaign_name(mdir) == "loose"
    assert inst.campaign_name(tmp_path) == "misc"


# ---- doctor ------------------------------------------------------------------------------------

FAKE_KEY = "sk_fake_doctor_secret_1234567890"


def test_doctor_never_prints_key(saved: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ELEVENLABS_API_KEY", FAKE_KEY)
    r = invoke("doctor")
    assert r.exit_code in (0, 1), r.output
    assert FAKE_KEY not in r.output
    assert "CHECK" in r.output and "STATUS" in r.output
    line = next(ln for ln in r.output.splitlines() if ln.startswith("elevenlabs key"))
    assert "OK" in line and "set (environment)" in line
    r = invoke("doctor", "--json")
    assert FAKE_KEY not in r.output


def test_doctor_json_shape(saved: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    (saved / "DCS.openbeta").mkdir()
    monkeypatch.setattr(inst, "find_dcs_installs", lambda candidates=None: [])
    r = invoke("doctor", "--json")
    data = json.loads(r.output)
    assert set(data) == {"ok", "checks"}
    assert r.exit_code == (0 if data["ok"] else 1)
    names = {c["name"] for c in data["checks"]}
    for n in (
        "python",
        "dms_core",
        "pydcs",
        "lupa/lua51",
        "ffmpeg",
        "elevenlabs key",
        "dcs install",
        "dcs saved games",
        "dist/dms.lua",
        "git-lfs",
        "uv",
    ):
        assert n in names
    for c in data["checks"]:
        assert set(c) == {"name", "status", "detail", "fix"}
        assert c["status"] in ("OK", "WARN", "FAIL")
    by = {c["name"]: c for c in data["checks"]}
    assert by["dcs install"]["status"] == "WARN"
    assert by["dcs saved games"]["status"] == "OK"
    assert by["lupa/lua51"]["detail"] == "Lua 5.1"


def test_doctor_exit_codes(monkeypatch: pytest.MonkeyPatch) -> None:
    warn = [lambda _r: [inst.Check("a", "WARN", "meh", "do x")]]
    monkeypatch.setattr(inst, "DOCTOR_CHECKS", warn)
    r = invoke("doctor")
    assert r.exit_code == 0 and "fix:" in r.output and "a: do x" in r.output

    def boom(_r: Path) -> list[inst.Check]:
        raise RuntimeError("nope")

    monkeypatch.setattr(inst, "DOCTOR_CHECKS", [*warn, boom])
    r = invoke("doctor")
    assert r.exit_code == 1 and "FAIL" in r.output


def test_missing_key_warns(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("ELEVENLABS_API_KEY", raising=False)
    monkeypatch.chdir(tmp_path)
    rows = inst.check_elevenlabs(tmp_path)
    assert rows[0].status == "WARN"
    (tmp_path / ".env").write_text(f"ELEVENLABS_API_KEY={FAKE_KEY}\n", encoding="utf-8")
    rows = inst.check_elevenlabs(tmp_path)
    assert rows[0].status == "OK" and FAKE_KEY not in rows[0].detail
