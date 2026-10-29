"""Fold a mission folder's ``briefing.md`` and ``kneeboard.md`` into a BuildPlan, then build.

``build_from_plan`` here is what ``dms_gen.builder.build_from_plan`` exports (and what the CLI
and MCP server call with ``base_dir=<mission dir>``). When ``base_dir`` holds the
mission-designer's files:

* ``briefing.md`` replaces ``plan.briefing`` (sortie, description, blue/red task). Fields the
  Markdown does not provide fall back to the planner's minimal ``PlanBriefing``.
* ``kneeboard.md`` is rendered to PNG pages and appended as
  ``KNEEBOARD/IMAGES/<id>-kneeboard-NN.png``
  kneeboard resources (all aircraft).

Both files may hold plan-time conditional blocks (``<!-- if intel >= 2 -->`` ...
``<!-- endif -->``, :mod:`.conditional`), resolved against ``plan.runtime`` qualities and flags.

Every ``TBD (plan)`` in either file becomes the frequency of the agency named on that line
(:func:`fill_plan_frequencies`), and a generated ``COMMS`` kneeboard page lists ``plan.comms``.

The plan file on disk is never changed; the PNGs live in a temp dir for the build only.
"""

from __future__ import annotations

import os
import re
import tempfile
from collections.abc import Sequence
from pathlib import Path

from dms_core.schemas import BuildPlan
from dms_core.schemas.plan import PlanBriefing, PlanComm, PlanResource

from .briefing import BRIEFING_FILE, load_briefing
from .conditional import plan_facts, render_conditionals
from .kneeboard import KNEEBOARD_FILE, write_kneeboard_pages
from .plan_adapter import build_from_plan as _build_plan

TBD_PLAN = re.compile(r"TBD\s*\(plan\)", re.IGNORECASE)
COMMS_FILE = "comms.md"


def _freq(c: PlanComm) -> str:
    return f"{c.frequency_mhz:.3f} {c.modulation}"


def fill_plan_frequencies(md: str, comms: Sequence[PlanComm]) -> str:
    """Replace each ``TBD (plan)`` with the frequency of the agency named on its line.

    An agency is named by its callsign, id or speaker id (case-insensitive; the longest match
    wins); a line naming none gets ``see kneeboard COMMS``.
    """
    keys: list[tuple[str, PlanComm]] = []
    for c in comms:
        for k in {c.callsign, c.id, c.speaker or "", c.callsign.split(" ")[0]}:
            if k and len(k) >= 3:
                keys.append((k.lower(), c))
    keys.sort(key=lambda kc: (-len(kc[0]), kc[0]))
    out = []
    for line in md.split("\n"):
        if TBD_PLAN.search(line):
            low = line.lower()
            hit = next((c for k, c in keys if k in low), None)
            line = TBD_PLAN.sub(_freq(hit) if hit else "see kneeboard COMMS", line)
        out.append(line)
    return "\n".join(out)


def comms_markdown(comms: Sequence[PlanComm], title: str = "COMMS") -> str:
    """The generated comms kneeboard page (one row per agency)."""
    rows = [f"| {c.kind} | {c.callsign} | {_freq(c)} | {c.preset or '-'} |" for c in comms]
    return "\n".join(
        [f"# {title}", "", "| Agency | Callsign | MHz | Preset |", "|---|---|---|---|", *rows, ""]
    )


# A picture next to briefing.md becomes the briefing image (all sides).
BRIEFING_IMAGES = ("briefing.jpg", "briefing.png")


def apply_mission_docs(
    plan: BuildPlan, mission_dir: str | os.PathLike[str], work_dir: str | os.PathLike[str]
) -> BuildPlan:
    """Return ``plan`` with briefing.md / kneeboard.md (if present in ``mission_dir``) applied.

    Kneeboard PNGs are written to ``work_dir``, which must outlive the build. Conditional
    blocks are resolved first (raises ``ValueError`` on a bad condition or unbalanced block).
    """
    mdir = _resolved_docs(plan, Path(mission_dir), Path(work_dir))
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
    if plan.comms:
        cm = mdir / COMMS_FILE
        cm.write_text(comms_markdown(plan.comms), encoding="utf-8")
        pages += write_kneeboard_pages(
            cm, Path(work_dir), stem=f"{plan.mission_id}-kneeboard-comms", title="COMMS"
        )
    picture = next(
        (mdir_src for name in BRIEFING_IMAGES if (mdir_src := Path(mission_dir) / name).is_file()),
        None,
    )
    if picture is not None and not any(r.kind == "briefing_image" for r in plan.resources):
        update["resources"] = [
            *plan.resources,
            PlanResource(path=picture.name, source=str(picture.resolve()), kind="briefing_image"),
        ]
    if pages:
        taken = {r.path for r in plan.resources}
        extra = [
            PlanResource(
                path=f"KNEEBOARD/IMAGES/{p.name}", source=str(p.resolve()), kind="kneeboard"
            )
            for p in pages
            if f"KNEEBOARD/IMAGES/{p.name}" not in taken
        ]
        base = update.get("resources", plan.resources)
        assert isinstance(base, list)
        update["resources"] = [*base, *extra]
    return plan.model_copy(update=update) if update else plan


def _resolved_docs(plan: BuildPlan, mission_dir: Path, work_dir: Path) -> Path:
    """Copy briefing.md / kneeboard.md into ``work_dir/docs`` with conditionals resolved."""
    out = work_dir / "docs"
    out.mkdir(parents=True, exist_ok=True)
    facts = plan_facts(plan)
    for name in (BRIEFING_FILE, KNEEBOARD_FILE):
        src = mission_dir / name
        dst = out / name
        if src.is_file():
            md = src.read_text(encoding="utf-8")
            md = render_conditionals(md, facts, source=str(src))
            dst.write_text(fill_plan_frequencies(md, plan.comms), encoding="utf-8")
        elif dst.exists():
            dst.unlink()
    return out


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
