"""Plan-time conditional blocks in briefing.md / kneeboard.md (dms_gen.builder.conditional)."""

from __future__ import annotations

import datetime as dt
from pathlib import Path

import pytest
from dms_core.schemas.plan import BuildPlan
from dms_core.schemas.runtime import RuntimeConfig
from dms_gen.builder import apply_mission_docs, render_conditionals
from dms_gen.builder.conditional import plan_facts

MD = """# Brief
always
<!-- if intel >= 2 and not m01_player_lost -->
imagery
<!-- if m01_window_held -->
window held
<!-- endif -->
<!-- elif sam_threat >= 2 -->
sam belt
<!-- else -->
nothing
<!-- endif -->
tail
"""


def _lines(md: str) -> list[str]:
    return [ln for ln in md.splitlines() if ln]


def test_if_branch_and_nested() -> None:
    out = render_conditionals(MD, {"intel": 2, "m01_window_held": True})
    assert _lines(out) == ["# Brief", "always", "imagery", "window held", "tail"]
    out = render_conditionals(MD, {"intel": 3, "m01_window_held": False})
    assert _lines(out) == ["# Brief", "always", "imagery", "tail"]


def test_elif_else_and_unknown_keys() -> None:
    assert _lines(render_conditionals(MD, {"intel": 1, "sam_threat": 2})) == [
        "# Brief",
        "always",
        "sam belt",
        "tail",
    ]
    assert "nothing" in render_conditionals(MD, {})  # unknown keys are false / 0
    out = render_conditionals(MD, {"intel": 2, "m01_player_lost": True, "sam_threat": 0})
    assert "nothing" in out and "imagery" not in out


def test_no_directives_is_identity_and_other_comments_kept() -> None:
    md = "a\n<!-- just a note -->\nb\n"
    assert render_conditionals(md, {}) == md


@pytest.mark.parametrize(
    "md",
    [
        "<!-- if intel >>= 2 -->\nx\n<!-- endif -->\n",
        "<!-- if -->\nx\n<!-- endif -->\n",
        "<!-- if intel -->\nx\n",
        "x\n<!-- endif -->\n",
        "<!-- else -->\n",
        "<!-- if a -->\n<!-- else -->\n<!-- elif b -->\n<!-- endif -->\n",
        "<!-- if a -->\n<!-- else -->\n<!-- else -->\n<!-- endif -->\n",
        "<!-- if a -->\n<!-- else b -->\n<!-- endif -->\n",
    ],
)
def test_invalid_blocks_raise(md: str) -> None:
    with pytest.raises(ValueError):
        render_conditionals(md, {})


def _plan(qualities: dict[str, float], flags: dict[str, bool]) -> BuildPlan:
    return BuildPlan(
        mission_id="m02-x",
        seed=1,
        theater="Syria",
        date=dt.date(2016, 6, 1),
        start_time_sec=0,
        runtime=RuntimeConfig(mission_id="m02-x", qualities=qualities, flags=flags),
    )


def test_plan_facts_quality_wins() -> None:
    facts = plan_facts(_plan({"intel": 2.0}, {"intel": False, "m01_success": True}))
    assert facts == {"intel": 2.0, "m01_success": True}


def test_apply_mission_docs_resolves_briefing_and_kneeboard(tmp_path: Path) -> None:
    mdir = tmp_path / "m"
    mdir.mkdir()
    (mdir / "briefing.md").write_text(
        "# Sortie\n\n## Situation\n<!-- if m01_success -->\nThe SA-6 is dead.\n"
        "<!-- else -->\nThe SA-6 still covers the valley.\n<!-- endif -->\n",
        encoding="utf-8",
    )
    (mdir / "kneeboard.md").write_text(
        "# Card\n<!-- if intel >= 2 -->\nIMAGERY\n<!-- endif -->\n", encoding="utf-8"
    )
    work = tmp_path / "work"
    plan = apply_mission_docs(_plan({"intel": 2.0}, {"m01_success": True}), mdir, work)
    assert plan.briefing is not None
    text = plan.briefing.description + plan.briefing.blue_task
    assert "SA-6 is dead" in text and "still covers" not in text and "<!--" not in text
    assert "IMAGERY" in (work / "docs" / "kneeboard.md").read_text(encoding="utf-8")
    assert any(r.kind == "kneeboard" for r in plan.resources)

    plan = apply_mission_docs(_plan({"intel": 0.0}, {}), mdir, tmp_path / "work2")
    assert plan.briefing is not None
    assert "still covers" in plan.briefing.description + plan.briefing.blue_task
    assert "IMAGERY" not in (tmp_path / "work2" / "docs" / "kneeboard.md").read_text("utf-8")

    (mdir / "kneeboard.md").write_text("<!-- if intel -->\nunclosed\n", encoding="utf-8")
    with pytest.raises(ValueError, match="never closed"):
        apply_mission_docs(_plan({}, {}), mdir, tmp_path / "work3")
