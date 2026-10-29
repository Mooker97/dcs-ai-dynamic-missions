"""Merge a Tacview ACMI recording into a debriefed ``MissionOutcome`` (``dms debrief --acmi``).

Never fatal: a missing or unparseable recording becomes ``extra.tacview.error`` plus a warning,
and the dcs.log debrief goes on. ``extra.session_hash`` is not touched, so adding or removing the
ACMI does not change the re-debrief guard. Contract: docs/CONTRACTS.md "Debrief: Tacview ACMI".
"""

from __future__ import annotations

import os
from collections.abc import Iterable, Sequence
from pathlib import Path

from dms_core.schemas import MissionOutcome

from .acmi import AcmiError, parse_acmi_file
from .facts import TacviewFacts, attach_tacview, tacview_facts
from .summary import Heuristics, NamedPoint, select_player, summarize

__all__ = [
    "ACMI_GLOBS",
    "TACVIEW_DIR_ENV",
    "default_tacview_dirs",
    "find_newest_acmi",
    "merge_acmi",
]

#: Overrides the Tacview folder search (one path; checked first).
TACVIEW_DIR_ENV = "DMS_TACVIEW_DIR"
#: Recording names: ``*.txt.acmi`` / ``*.zip.acmi`` (and a bare ``*.acmi``).
ACMI_GLOBS = ("*.acmi",)


def default_tacview_dirs(home: Path | None = None) -> list[Path]:
    """Candidate Tacview recording folders, most specific first (existing or not).

    ``$DMS_TACVIEW_DIR``, then ``Documents\\Tacview`` under ``%USERPROFILE%`` / home, then the
    OneDrive-redirected ``OneDrive\\Documents\\Tacview`` [? exact default not confirmed].
    """
    out: list[Path] = []
    env = os.environ.get(TACVIEW_DIR_ENV)
    if env:
        out.append(Path(env))
    bases: list[Path] = []
    if home is not None:
        bases.append(home)
    else:
        prof = os.environ.get("USERPROFILE")
        if prof:
            bases.append(Path(prof))
        bases.append(Path.home())
    for b in bases:
        out.append(b / "Documents" / "Tacview")
        out.append(b / "OneDrive" / "Documents" / "Tacview")
    seen: set[str] = set()
    uniq: list[Path] = []
    for p in out:
        key = str(p).lower()
        if key not in seen:
            seen.add(key)
            uniq.append(p)
    return uniq


def find_newest_acmi(dirs: Iterable[Path]) -> Path | None:
    """The newest (mtime) ``*.acmi`` directly inside any of ``dirs``; ``None`` if there is none."""
    best: tuple[float, Path] | None = None
    for d in dirs:
        if not d.is_dir():
            continue
        for pattern in ACMI_GLOBS:
            for f in d.glob(pattern):
                if not f.is_file():
                    continue
                m = f.stat().st_mtime
                if best is None or m > best[0]:
                    best = (m, f)
    return best[1] if best else None


def _with_warning(outcome: MissionOutcome, block: TacviewFacts, msg: str) -> MissionOutcome:
    block = block.model_copy(update={"warnings": [*block.warnings, msg]})
    return attach_tacview(outcome, block)


def merge_acmi(
    outcome: MissionOutcome,
    acmi: Path,
    *,
    player: str | None = None,
    points: Sequence[NamedPoint] | None = None,
    merge_into_outcomes: bool = False,
    heuristics: Heuristics | None = None,
) -> MissionOutcome:
    """Return a copy of ``outcome`` with ``extra["tacview"]`` from the ACMI file ``acmi``.

    Player choice: ``player`` if given; else the first of ``outcome.players`` that matches an
    ACMI object (id / Pilot / Name / CallSign / Group); else the first piloted aircraft
    (heuristic, labelled). ``merge_into_outcomes`` also adds the ``tv_*`` facts to
    ``outcomes`` without overwriting Lua-reported keys.
    """
    src = str(acmi)
    try:
        rec = parse_acmi_file(acmi)
    except (OSError, AcmiError, UnicodeDecodeError) as exc:
        msg = f"cannot read ACMI {src}: {exc}"
        return _with_warning(outcome, TacviewFacts(source=src, error=msg), msg)
    chosen = player
    if chosen is None:
        for po in outcome.players:
            if select_player(rec, po.name)[0] is not None:
                chosen = po.name
                break
    summary = summarize(
        rec, player=chosen, points=list(points or []), heuristics=heuristics, source=src
    )
    block = tacview_facts(summary, recording_time=rec.header.globals.get("RecordingTime"))
    if summary.player is None:
        return _with_warning(
            outcome, block, f"no player aircraft in {src}; only global facts recorded"
        )
    return attach_tacview(outcome, block, merge_into_outcomes=merge_into_outcomes)
