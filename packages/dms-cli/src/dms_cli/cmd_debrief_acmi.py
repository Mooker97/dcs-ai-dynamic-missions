"""``dms debrief --acmi <path|auto>``: merge Tacview ACMI facts into the debriefed outcome.

Kept out of ``main.py`` so the debrief command only gains three options and two calls.
Contract: docs/CONTRACTS.md "Debrief: Tacview ACMI (`dms debrief --acmi`)".
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from dms_core.schemas import MissionOutcome

from .util import CliError

__all__ = ["POINTS_FILE", "apply_acmi", "mission_points", "report_lines", "resolve_acmi"]

#: Optional named points / zones for time-over-target, in the mission folder.
POINTS_FILE = "tacview-points.yaml"


def resolve_acmi(arg: str) -> Path | None:
    """``auto`` -> newest ACMI in the Tacview folder (``None`` if none); else an existing file."""
    from dms_tacview import default_tacview_dirs, find_newest_acmi

    if arg.strip().lower() == "auto":
        return find_newest_acmi(default_tacview_dirs())
    p = Path(arg).expanduser()
    if not p.is_file():
        raise CliError(f"ACMI not found: {arg}")
    return p.resolve()


def mission_points(campaign_dir: Path, mission_id: str) -> Path | None:
    """``missions/<dir>/tacview-points.yaml`` for ``mission_id`` (exact dir, else mNN prefix)."""
    mroot = campaign_dir / "missions"
    if not mroot.is_dir():
        return None
    key = mission_id.split("-", 1)[0]
    dirs = sorted(d for d in mroot.iterdir() if d.is_dir())
    exact = [d for d in dirs if d.name == mission_id]
    pref = [d for d in dirs if d.name == key or d.name.startswith(f"{key}-")]
    for d in exact or pref:
        f = d / POINTS_FILE
        if f.is_file():
            return f
    return None


def apply_acmi(
    outcome: MissionOutcome,
    campaign_dir: Path,
    mission_id: str,
    acmi: str,
    *,
    player: str | None = None,
    merge_facts: bool = False,
) -> MissionOutcome:
    """Return ``outcome`` with ``extra.tacview`` filled from the ACMI named by ``acmi``.

    A missing ``auto`` recording or an unreadable file is recorded in ``extra.tacview.error``
    (never fatal); an explicit path that does not exist is a usage error.
    """
    from dms_tacview import TacviewFacts, attach_tacview, merge_acmi
    from dms_tacview.cli import load_points

    path = resolve_acmi(acmi)
    if path is None:
        msg = "no *.acmi found in the Tacview folder (set DMS_TACVIEW_DIR or pass a path)"
        return attach_tacview(outcome, TacviewFacts(error=msg, warnings=[msg]))
    points = None
    pts_file = mission_points(campaign_dir, mission_id)
    if pts_file is not None:
        try:
            points = load_points(pts_file)
        except (OSError, ValueError) as exc:
            raise CliError(f"bad {pts_file}: {exc}") from None
    return merge_acmi(outcome, path, player=player, points=points, merge_into_outcomes=merge_facts)


def report_lines(outcome: MissionOutcome) -> list[str]:
    """Plain-text lines describing ``extra.tacview`` (empty when no ACMI was asked for)."""
    tv: dict[str, Any] | None = outcome.extra.get("tacview")
    if not tv:
        return []
    lines = [f"tacview: {tv.get('source') or '(no file)'}"]
    if tv.get("error"):
        lines.append(f"tacview error: {tv['error']}")
        return lines
    p = tv.get("player")
    if p:
        alt = p.get("min_alt_m")
        lines.append(
            f"tacview player: {p.get('pilot') or p.get('name') or p['object_id']} "
            f"(id {p['object_id']}, {p['selected_by']}) flight {p['flight_time_s']:.0f}s "
            f"{p['distance_km']:.1f} km min alt {'?' if alt is None else f'{alt:.0f}'} m "
            f"landed={'yes' if p['landed'] else 'no'} "
            f"destroyed={'yes' if p['destroyed'] else 'no'}"
        )
    for w in tv.get("weapons_released", []):
        lines.append(f"tacview weapon: {w['weapon']} x{w['count']} ({w['hits']} hit)")
    for k in tv.get("kills", []):
        if k.get("by_player"):
            lines.append(
                f"tacview kill: {k['victim']} (id {k['victim_id']}) with "
                f"{k.get('weapon') or '?'} at t={k['t']:.0f}s [{k['method']}, {k['confidence']}]"
            )
    for z in tv.get("time_over_target", []):
        inside = z.get("time_inside_s")
        lines.append(
            f"tacview point {z['name']}: closest {z['min_distance_m']:.0f} m"
            + ("" if inside is None else f", inside {inside:.0f}s")
        )
    if tv.get("merged_into_outcomes"):
        lines.append("tacview facts merged into outcomes (--acmi-facts)")
    for w in tv.get("warnings", []):
        lines.append(f"tacview warning: {w}")
    return lines
