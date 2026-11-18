"""``dms-tacview summarize <file.acmi>``: print a FlightSummary (YAML or JSON)."""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Sequence
from pathlib import Path
from typing import Any

import yaml

from .acmi import AcmiError, parse_acmi_file
from .facts import outcome_facts
from .summary import Heuristics, NamedPoint, summarize

__all__ = ["load_points", "main"]


def load_points(path: Path) -> list[NamedPoint]:
    """Named points: YAML/JSON list of ``{name, lon, lat, radius_m?}`` or ``{points: [...]}``."""
    data: Any = yaml.safe_load(path.read_text(encoding="utf-8"))
    if isinstance(data, dict):
        data = data.get("points", [])
    if not isinstance(data, list):
        raise ValueError(f"{path}: expected a list of points")
    return [NamedPoint.model_validate(p) for p in data]


def _parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="dms-tacview", description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("summarize", help="Summarize a Tacview ACMI recording.")
    s.add_argument("file", type=Path, help=".txt.acmi or .zip.acmi file")
    s.add_argument("--player", help="Player object id, Pilot, Name, CallSign or Group")
    s.add_argument("--points", type=Path, help="YAML/JSON list of {name, lon, lat, radius_m}")
    s.add_argument("--json", action="store_true", help="Print JSON instead of YAML")
    s.add_argument("--facts", action="store_true", help="Print only the tv_* outcome facts")
    s.add_argument("--full", action="store_true", help="Include every object and track sample")
    s.add_argument("--sample-dt", type=float, default=0.0, help="Thin tracks while parsing (s)")
    s.add_argument("--track-sample", type=float, default=10.0, help="Player track spacing (s)")
    return ap


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        rec = parse_acmi_file(args.file, min_sample_dt=args.sample_dt)
        points = load_points(args.points) if args.points else None
    except (OSError, AcmiError, ValueError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    summary = summarize(
        rec,
        player=args.player,
        points=points,
        heuristics=Heuristics(track_sample_s=args.track_sample),
        source=str(args.file),
    )
    data: Any
    if args.facts:
        data = outcome_facts(summary)
    else:
        exclude: set[str] | None = None if args.full else {"objects"}
        data = summary.model_dump(mode="json", exclude=exclude)
        if not args.full and data.get("player"):
            data["player"].pop("samples", None)
    if args.json:
        print(json.dumps(data, indent=2))
    else:
        print(yaml.safe_dump(data, sort_keys=False, allow_unicode=True), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
