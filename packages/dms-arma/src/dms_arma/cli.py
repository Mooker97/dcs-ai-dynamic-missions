"""`dms-arma` command: import | emit | validate | build."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .config import emit_config, spec_from_sqf
from .kb import check_spec
from .mission import build_mission, dump_spec, load_spec


def main(argv: list[str] | None = None) -> int:
    """Entry point. Exit 1 when there are errors (unverified classes only warn)."""
    ap = argparse.ArgumentParser(prog="dms-arma", description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("import", help="fn_config.sqf -> spec YAML (stdout or -o)")
    p.add_argument("config", type=Path)
    p.add_argument("--world", default="Altis")
    p.add_argument("--name", default="The Hill")
    p.add_argument("-o", "--out", type=Path)
    p = sub.add_parser("emit", help="spec YAML -> fn_config.sqf (stdout or -o)")
    p.add_argument("spec", type=Path)
    p.add_argument("-o", "--out", type=Path)
    p = sub.add_parser("validate", help="schema + KB checks for a spec")
    p.add_argument("spec", type=Path)
    p.add_argument("--strict", action="store_true", help="unverified classes are errors")
    p = sub.add_parser("build", help="copy template mission + write generated fn_config.sqf")
    p.add_argument("spec", type=Path)
    p.add_argument("--template", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--overwrite", action="store_true")
    p.add_argument("--strict", action="store_true", help="unverified classes are errors")
    args = ap.parse_args(argv)

    if args.cmd == "import":
        spec = spec_from_sqf(
            args.config.read_text(encoding="utf-8"), world=args.world, name=args.name
        )
        return _write(dump_spec(spec), args.out)
    if args.cmd == "emit":
        return _write(emit_config(load_spec(args.spec), source=args.spec.as_posix()), args.out)
    spec = load_spec(args.spec)
    if args.cmd == "validate":
        issues = check_spec(spec)
    else:
        issues = build_mission(
            spec, args.template, args.out, source=args.spec.as_posix(), overwrite=args.overwrite
        )
        print(f"wrote {args.out}")
    for issue in issues:
        print(issue, file=sys.stderr)
    bad = [i for i in issues if i.level == "error" or args.strict]
    return 1 if bad else 0


def _write(text: str, out: Path | None) -> int:
    if out is None:
        sys.stdout.write(text)
    else:
        out.write_bytes(text.encode("utf-8"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
