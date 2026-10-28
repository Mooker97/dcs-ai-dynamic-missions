"""``dms voice <lines.yaml> [--out DIR] [--dry-run]`` entry point (called by ``dms_cli``).

Model: ``--model`` if given, else ``VoiceLineSet.model`` from lines.yaml.
Voices: the campaign bible (two levels above the mission folder) first, then ``--voices`` or the
discovered ``data/voice/voices.json`` as fallback.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import yaml  # type: ignore[import-untyped,unused-ignore]

from .client import MissingApiKeyError, VoiceApiError
from .fx import PRESETS
from .models import VoiceLineSet
from .render import (
    DEFAULT_FX,
    find_bible,
    load_bible_voices,
    load_voices,
    merge_voices,
    render_lines,
)


def load_line_set(path: Path) -> VoiceLineSet:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict | list):
        raise ValueError(f"{path}: expected a mapping with 'lines' or a list of lines")
    return VoiceLineSet.model_validate(data)


def load_lines(path: Path) -> list[Any]:
    return list(load_line_set(path).lines)


def resolve_voices(lines_path: Path, voices_path: Path | None = None) -> dict[str, Any]:
    """Bible VoiceProfiles first, voices.json (explicit or discovered) as fallback."""
    fallback = load_voices(voices_path)
    bible = find_bible(lines_path)
    if bible is None:
        return fallback
    return merge_voices(load_bible_voices(bible), fallback)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="dms voice", description="Render lines.yaml to radio .ogg")
    p.add_argument("lines", type=Path, help="lines.yaml")
    p.add_argument("--out", type=Path, default=None, help="output dir (default: <lines>/../voice)")
    p.add_argument("--voices", type=Path, default=None, help="fallback speaker->voice json")
    p.add_argument("--model", default=None, help="TTS model (default: lines.yaml `model`)")
    p.add_argument("--fx", default=DEFAULT_FX, choices=sorted(PRESETS))
    p.add_argument("--dry-run", action="store_true", help="estimate characters; no API calls")
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        line_set = load_line_set(args.lines)
        voices = resolve_voices(args.lines, args.voices)
        model = args.model or line_set.model
        out = args.out or args.lines.parent / "voice"
        manifest = render_lines(
            line_set.lines, voices, out, dry_run=args.dry_run, model=model, fx_preset=args.fx
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
