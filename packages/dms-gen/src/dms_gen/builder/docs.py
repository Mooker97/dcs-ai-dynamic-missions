"""Fold a mission folder's ``briefing.md`` and ``kneeboard.md`` into a BuildPlan, then build.

``build_from_plan`` here is what ``dms_gen.builder.build_from_plan`` exports (and what the CLI
and MCP server call with ``base_dir=<mission dir>``). When ``base_dir`` holds the
mission-designer's files:

* ``briefing.md`` replaces ``plan.briefing`` (sortie, description, blue/red task). Fields the
  Markdown does not provide fall back to the planner's minimal ``PlanBriefing``.
* ``kneeboard.md`` is rendered to PNG pages and appended as
  ``KNEEBOARD/IMAGES/<id>-kneeboard-NN.png``
  kneeboard resources (all aircraft).

The plan file on disk is never changed; the PNGs live in a temp dir for the build only.
"""

from __future__ import annotations

import os
import tempfile
from pathlib import Path

from dms_core.schemas import BuildPlan
from dms_core.schemas.plan import PlanBriefing, PlanResource

from .briefing import BRIEFING_FILE, load_briefing
from .kneeboard import KNEEBOARD_FILE, write_kneeboard_pages
from .plan_adapter import build_from_plan as _build_plan


def apply_mission_docs(
    plan: BuildPlan, mission_dir: str | os.PathLike[str], work_dir: str | os.PathLike[str]
) -> BuildPlan:
    """Return ``plan`` with briefing.md / kneeboard.md (if present in ``mission_dir``) applied.

    Kneeboard PNGs are written to ``work_dir``, which must outlive the build.
    """
    mdir = Path(mission_dir)
    update: dict[str, object] = {}
    fb = plan.briefing
    br = load_briefing(
        mdir / BRIEFING_FILE,
        fallback_title=fb.title if fb else plan.mission_id,
        fallback_blue_task=fb.blue_task if fb else "",
        fallback_red_task=fb.red_task if fb else "",
    )
    if br is not None:
        update["briefing"] = PlanBriefing(
            title=br.sortie,
            description=br.description or (fb.description if fb else ""),
            blue_task=br.blue_task,
            red_task=br.red_task,
        )
    pages = write_kneeboard_pages(
        mdir / KNEEBOARD_FILE, Path(work_dir), stem=f"{plan.mission_id}-kneeboard"
    )
    if pages:
        taken = {r.path for r in plan.resources}
        extra = [
            PlanResource(
                path=f"KNEEBOARD/IMAGES/{p.name}", source=str(p.resolve()), kind="kneeboard"
            )
            for p in pages
            if f"KNEEBOARD/IMAGES/{p.name}" not in taken
        ]
        update["resources"] = [*plan.resources, *extra]
    return plan.model_copy(update=update) if update else plan


def build_from_plan(
    plan: BuildPlan,
    out: str | os.PathLike[str],
    base_dir: str | os.PathLike[str] | None = None,
) -> Path:
    """Build ``plan`` into ``out``, folding in ``base_dir``'s briefing.md and kneeboard.md.

    Resource ``source`` paths resolve against ``base_dir`` (default: cwd). Mission docs are only
    looked up when ``base_dir`` is given.
    """
    if base_dir is None:
        return _build_plan(plan, out)
    with tempfile.TemporaryDirectory(prefix="dms-docs-") as tmp:
        return _build_plan(apply_mission_docs(plan, base_dir, tmp), out, base_dir=base_dir)
