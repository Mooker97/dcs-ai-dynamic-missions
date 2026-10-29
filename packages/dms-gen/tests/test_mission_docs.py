"""briefing.md / kneeboard.md -> DCS briefing texts and kneeboard PNGs inside the built .miz."""

from __future__ import annotations

import datetime as dt
import io
import shutil
import zipfile
from pathlib import Path
from typing import Any

import pytest
from dms_core.miz import MizFile
from dms_core.schemas.plan import (
    BuildPlan,
    PlanBriefing,
    PlanGroup,
    PlanUnit,
    PlanWaypoint,
)
from dms_gen.builder import (
    apply_mission_docs,
    briefing_from_markdown,
    build_from_plan,
    render_kneeboard,
)
from dms_gen.builder.kneeboard import PAGE_H, PAGE_W, printable
from PIL import Image

REPO = Path(__file__).resolve().parents[3]
M01 = REPO / "campaigns" / "dustoff-valley" / "missions" / "m01-first-light"


def _plan() -> BuildPlan:
    return BuildPlan(
        mission_id="m01-first-light",
        seed=7,
        theater="Syria",
        date=dt.date(2004, 6, 1),
        start_time_sec=6 * 3600,
        blue_countries=["USA"],
        red_countries=["Insurgents"],
        groups=[
            PlanGroup(
                name="Dusty 1",
                category="helicopter",
                coalition="blue",
                country="USA",
                client=True,
                units=[PlanUnit(name="Dusty 1-1", type="AH-64D_BLK_II", x=0, y=0, skill="Client")],
                route=[PlanWaypoint(x=0, y=0, action="From Parking Area", airbase="Hatay")],
            ),
        ],
        briefing=PlanBriefing(
            title="Plan title", description="plan desc", blue_task="plan blue", red_task="plan red"
        ),
    )


@pytest.fixture
def mission_dir(tmp_path: Path) -> Path:
    """A tmp copy of m01's briefing.md + kneeboard.md (never build into campaigns/**/out)."""
    d = tmp_path / "m01"
    d.mkdir()
    for name in ("briefing.md", "kneeboard.md"):
        shutil.copy(M01 / name, d / name)
    return d


def _dict_text(miz: MizFile, mission: dict[str, Any], key: str) -> str:
    ref = mission[key]
    dictionary = miz.table("dictionary")
    return str(dictionary.get(ref, ref))


def _briefing(path: Path) -> dict[str, str]:
    miz = MizFile.open(path)
    mission = miz.table("mission")
    keys = {
        "sortie": "sortie",
        "description": "descriptionText",
        "blue": "descriptionBlueTask",
        "red": "descriptionRedTask",
    }
    return {k: _dict_text(miz, mission, v) for k, v in keys.items()}


def _kneeboards(path: Path) -> dict[str, bytes]:
    with zipfile.ZipFile(path) as z:
        return {n: z.read(n) for n in z.namelist() if n.startswith("KNEEBOARD/")}


# ---------------------------------------------------------------------------- briefing text
def test_briefing_sections_split_and_markdown_stripped() -> None:
    b = briefing_from_markdown((M01 / "briefing.md").read_text(encoding="utf-8"))
    assert b.sortie == "FIRST LIGHT"
    assert "INTELLIGENCE NARRATIVE" in b.description
    assert "1. SITUATION" in b.description
    assert "2. MISSION" not in b.description
    assert b.blue_task.startswith("2. MISSION")
    assert "5. COMMAND & SIGNAL" in b.blue_task
    assert "Hatay Ops" in b.blue_task
    for text in (b.description, b.blue_task):
        assert "**" not in text and "##" not in text and "|---" not in text
    # Soft-wrapped Markdown paragraphs become one line each (DCS wraps the window itself).
    assert "Two days ashore and we still know very little about the valley. What we have" in (
        b.description
    )
    assert b.red_task == ""


def test_briefing_red_section_fallbacks_and_hard_wrap() -> None:
    md = (
        "# OP TEST\n\nIntro *text* with a [link](http://x).\n\n## 2. Mission\n\n"
        "Blue does a thing.\n\n## Red task\n\n- Defend the **bridge**.\n\n"
        "## 3. Execution\n\nGo.\n"
    )
    b = briefing_from_markdown(md, fallback_red_task="unused")
    assert b.sortie == "OP TEST"
    assert b.description == "Intro text with a link."
    assert b.red_task == "RED TASK\n\n- Defend the bridge."
    assert "Blue does a thing." in b.blue_task and "3. EXECUTION" in b.blue_task
    assert "RED" not in b.blue_task
    nob = briefing_from_markdown("Just words.", "Fallback", "fb blue", "fb red")
    assert (nob.sortie, nob.description, nob.blue_task, nob.red_task) == (
        "Fallback",
        "Just words.",
        "fb blue",
        "fb red",
    )
    wrapped = briefing_from_markdown("# T\n\n" + "word " * 40, width=30)
    assert all(len(line) <= 30 for line in wrapped.description.splitlines())


# ---------------------------------------------------------------------------- kneeboard pages
def test_kneeboard_png_valid_and_deterministic() -> None:
    md = (M01 / "kneeboard.md").read_text(encoding="utf-8")
    pages = render_kneeboard(md)
    assert pages == render_kneeboard(md)  # same Markdown -> same bytes
    assert len(pages) == 1
    img = Image.open(io.BytesIO(pages[0]))
    assert img.format == "PNG" and img.size == (PAGE_W, PAGE_H)
    assert len(img.getcolors(maxcolors=1 << 16) or []) > 2  # something was drawn


def test_kneeboard_paginates_long_content() -> None:
    md = "# LONG\n\n" + "\n".join(f"- line {i} with some words" for i in range(120))
    pages = render_kneeboard(md)
    assert len(pages) >= 3
    for png in pages:
        assert Image.open(io.BytesIO(png)).size == (PAGE_W, PAGE_H)


def test_printable_replaces_missing_glyphs() -> None:
    assert printable("A — B → C") == "A - B -> C"
    assert printable("café · ok") in ("café · ok", "cafe · ok")


# ---------------------------------------------------------------------------- in the .miz
def test_build_embeds_briefing_and_kneeboard(mission_dir: Path, tmp_path: Path) -> None:
    out = build_from_plan(_plan(), tmp_path / "a.miz", base_dir=mission_dir)
    br = _briefing(out)
    assert br["sortie"] == "FIRST LIGHT"
    assert "INTELLIGENCE NARRATIVE" in br["description"]
    assert br["blue"].startswith("2. MISSION")
    assert br["red"] == "plan red"  # no red section in briefing.md -> planner fallback
    kb = _kneeboards(out)
    assert list(kb) == [
        "KNEEBOARD/IMAGES/m01-first-light-kneeboard-01.png",
        "KNEEBOARD/IMAGES/m01-first-light-kneeboard-map-01.png",  # generated map page (U3)
    ]
    for png in kb.values():
        img = Image.open(io.BytesIO(png))
        img.verify()
        assert img.size == (PAGE_W, PAGE_H)
    # Rebuild: identical kneeboard bytes (reproducible builds).
    out2 = build_from_plan(_plan(), tmp_path / "b.miz", base_dir=mission_dir)
    assert _kneeboards(out2) == kb
    assert _briefing(out2) == br


def test_build_without_docs_uses_plan_briefing(tmp_path: Path) -> None:
    empty = tmp_path / "empty"
    empty.mkdir()
    out = build_from_plan(_plan(), tmp_path / "c.miz", base_dir=empty)
    br = _briefing(out)
    assert (br["sortie"], br["description"], br["blue"]) == ("Plan title", "plan desc", "plan blue")
    assert list(_kneeboards(out)) == ["KNEEBOARD/IMAGES/m01-first-light-kneeboard-map-01.png"]


def test_apply_mission_docs_leaves_input_plan_alone(mission_dir: Path, tmp_path: Path) -> None:
    plan = _plan()
    new = apply_mission_docs(plan, mission_dir, tmp_path / "work")
    assert plan.briefing is not None and plan.briefing.title == "Plan title"
    assert plan.resources == []
    assert new.briefing is not None and new.briefing.title == "FIRST LIGHT"
    assert [(r.kind, r.path) for r in new.resources] == [
        ("kneeboard", "KNEEBOARD/IMAGES/m01-first-light-kneeboard-01.png"),
        ("kneeboard", "KNEEBOARD/IMAGES/m01-first-light-kneeboard-map-01.png"),
    ]
    BuildPlan.model_validate(new.model_dump())


def test_briefing_picture_embedded_for_every_side(mission_dir: Path, tmp_path: Path) -> None:
    Image.new("RGB", (64, 36), (200, 120, 40)).save(mission_dir / "briefing.jpg")
    out = build_from_plan(_plan(), tmp_path / "pic.miz", base_dir=mission_dir)
    miz = MizFile.open(out)
    mission = miz.table("mission")
    for key in ("pictureFileNameB", "pictureFileNameR", "pictureFileNameN"):
        assert mission[key], key
    assert "l10n/DEFAULT/briefing.jpg" in miz.files()
