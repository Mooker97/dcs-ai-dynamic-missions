"""``dms voice <lines.yaml> [--out DIR] [--dry-run]`` entry point (wired into dms-cli later)."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import yaml  # type: ignore[import-untyped,unused-ignore]

from .client import DEFAULT_MODEL, MissingApiKeyError, VoiceApiError
from .fx import PRESETS
from .models import VoiceLineSet
from .render import DEFAULT_FX, load_voices, render_lines


def load_lines(path: Path) -> list[Any]:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if isinstance(data, list):
        data = {"lines": data}
    if not isinstance(data, dict):
        raise ValueError(f"{path}: expected a mapping with 'lines' or a list of lines")
    return list(VoiceLineSet.model_validate(data).lines)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="dms voice", description="Render lines.yaml to radio .ogg")
    p.add_argument("lines", type=Path, help="lines.yaml")
    p.add_argument("--out", type=Path, default=None, help="output dir (default: <lines>/../voice)")
    p.add_argument("--voices", type=Path, default=None, help="speaker->voice json")
    p.add_argument("--model", default=DEFAULT_MODEL)
    p.add_argument("--fx", default=DEFAULT_FX, choices=sorted(PRESETS))
    p.add_argument("--dry-run", action="store_true", help="estimate characters; no API calls")
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        lines = load_lines(args.lines)
        voices = load_voices(args.voices)
        out = args.out or args.lines.parent / "voice"
        manifest = render_lines(
            lines, voices, out, dry_run=args.dry_run, model=args.model, fx_preset=args.fx
        )
    except (MissingApiKeyError, VoiceApiError, KeyError, ValueError, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    if args.dry_run:
        print(json.dumps(manifest, indent=2, ensure_ascii=False))
    else:
        print(f"wrote {len(manifest)} lines + manifest.json to {out}")
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
