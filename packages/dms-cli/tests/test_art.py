"""``dms art``: briefing pictures copied in display order."""

from __future__ import annotations

from pathlib import Path

import pytest
from dms_cli.art import art_name, current_art, set_art
from dms_cli.main import app
from dms_cli.util import CliError, find_root
from PIL import Image
from typer.testing import CliRunner

ROOT = find_root()
runner = CliRunner()


def _img(path: Path, colour: tuple[int, int, int] = (10, 20, 30)) -> Path:
    Image.new("RGB", (8, 6), colour).save(path)
    return path


@pytest.fixture
def mission(tmp_path: Path) -> Path:
    mdir = tmp_path / "m01-test"
    mdir.mkdir()
    (mdir / "mission-spec.yaml").write_text("id: m01-test\n", encoding="utf-8")
    return mdir


def test_art_name() -> None:
    assert art_name(1, ".png") == "briefing.png"
    assert art_name(3, ".jpg") == "briefing-3.jpg"


def test_set_replaces_in_order_and_keeps_old(mission: Path, tmp_path: Path) -> None:
    _img(mission / "briefing.png")
    _img(mission / "briefing-2.png")
    a = _img(tmp_path / "a.jpeg", (255, 0, 0))
    b = _img(tmp_path / "b.png", (0, 255, 0))
    change = set_art(mission, [a, b])
    assert [p.name for p in current_art(mission)] == ["briefing.jpg", "briefing-2.png"]
    assert (mission / "briefing.jpg").read_bytes() == a.read_bytes()
    assert not (mission / "briefing.png").exists()
    kept = sorted(dst.name for _, dst in change.moved)
    assert kept == ["briefing-2.png", "briefing.png"]
    assert all(dst.is_file() and "replaced-art" in dst.parts for _, dst in change.moved)


def test_reorder_existing_pictures(mission: Path) -> None:
    first = _img(mission / "briefing.png", (1, 1, 1)).read_bytes()
    second = _img(mission / "briefing-2.png", (2, 2, 2)).read_bytes()
    set_art(mission, [mission / "briefing-2.png", mission / "briefing.png"])
    assert (mission / "briefing.png").read_bytes() == second
    assert (mission / "briefing-2.png").read_bytes() == first


def test_append_numbers_after_highest(mission: Path, tmp_path: Path) -> None:
    _img(mission / "briefing.png")
    _img(mission / "briefing-3.png")
    set_art(mission, [_img(tmp_path / "c.png")], append=True)
    assert (mission / "briefing-4.png").is_file()
    assert (mission / "briefing.png").is_file()


def test_dry_run_changes_nothing(mission: Path, tmp_path: Path) -> None:
    _img(mission / "briefing.png")
    change = set_art(mission, [_img(tmp_path / "d.png")], dry_run=True)
    assert [dst.name for _, dst in change.copied] == ["briefing.png"]
    assert not (mission / "out").exists()


@pytest.mark.parametrize("name", ["x.gif", "missing.png"])
def test_bad_inputs(mission: Path, tmp_path: Path, name: str) -> None:
    if name.endswith(".gif"):
        (tmp_path / name).write_bytes(b"GIF89a")
    with pytest.raises(CliError):
        set_art(mission, [tmp_path / name])


def test_cli_sets_and_lists(mission: Path, tmp_path: Path) -> None:
    a = _img(tmp_path / "a.png")
    res = runner.invoke(app, ["--root", str(ROOT), "art", str(mission), str(a)])
    assert res.exit_code == 0, res.output
    assert "briefing pictures (1): briefing.png" in res.output
    res = runner.invoke(app, ["--root", str(ROOT), "art", str(mission)])
    assert res.exit_code == 0, res.output
    assert "briefing pictures (1): briefing.png" in res.output
