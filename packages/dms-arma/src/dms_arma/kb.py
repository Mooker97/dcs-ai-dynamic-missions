"""Checks against the verified Arma knowledge base in `docs/arma/kb/`.

- Class names: `classes-verified.md` lists every class confirmed with `isClass` on a dedicated
  server (vanilla). A spec class not in it is reported as UNVERIFIED, not as wrong: modded or
  simply not-yet-checked classes are legitimate, they just need a diag run.
- BIS functions: `functions.txt` is the full `BIS_fnc_*`/`BIN_fnc_*` list. An unknown name in SQF
  is an ERROR (same rule as `arma/tools/test_kb_functions.py`).
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from functools import cache
from pathlib import Path
from typing import Literal

from .spec import ArmaMissionSpec

BIS_PATTERN = re.compile(r"\b(BI[SN]_fnc_[A-Za-z0-9_]+)")
_CLASS_TOKEN = re.compile(r"`([A-Za-z][A-Za-z0-9]*_[A-Za-z0-9_]+)`")


@dataclass(frozen=True)
class Issue:
    """A validation finding."""

    level: Literal["error", "unverified"]
    where: str
    message: str

    def __str__(self) -> str:
        return f"{self.level.upper()} {self.where}: {self.message}"


def find_kb(start: Path | None = None) -> Path:
    """Locate `docs/arma/kb` by walking up from `start` (default: this file, then the cwd)."""
    starts = [start] if start else [Path(__file__).resolve(), Path.cwd()]
    for base in starts:
        for parent in [base, *base.parents]:
            cand = parent / "docs" / "arma" / "kb"
            if (cand / "functions.txt").is_file():
                return cand
    raise FileNotFoundError("docs/arma/kb not found (run inside the DMS repo)")


@cache
def known_functions(kb: Path) -> frozenset[str]:
    """Lower-cased BIS/BIN function names from functions.txt."""
    lines = (kb / "functions.txt").read_text(encoding="utf-8").splitlines()
    return frozenset(ln.strip().lower() for ln in lines if ln.strip() and not ln.startswith("#"))


@cache
def verified_classes(kb: Path) -> frozenset[str]:
    """Class names (lower-cased; Arma config lookups are case-insensitive) from the KB markdown.

    Takes every back-ticked `Prefix_Name` token, skipping ALL_CAPS identifiers (script
    constants such as EXTRA_CLASSES).
    """
    text = (kb / "classes-verified.md").read_text(encoding="utf-8")
    return frozenset(
        tok.lower() for tok in _CLASS_TOKEN.findall(text) if not re.fullmatch(r"[A-Z0-9_]+", tok)
    )


def check_classes(spec: ArmaMissionSpec, kb: Path | None = None) -> list[Issue]:
    """UNVERIFIED for every spec class that is not in classes-verified.md."""
    known = verified_classes(kb or find_kb())
    return [
        Issue("unverified", path, f"{name} is not in docs/arma/kb/classes-verified.md")
        for path, name in spec.class_names()
        if name.lower() not in known
    ]


def check_functions(text: str, where: str, kb: Path | None = None) -> list[Issue]:
    """ERROR for every BIS/BIN function in `text` that is not in functions.txt."""
    known = known_functions(kb or find_kb())
    seen: set[str] = set()
    out: list[Issue] = []
    for name in BIS_PATTERN.findall(text):
        if name.lower() not in known and name not in seen:
            seen.add(name)
            out.append(Issue("error", where, f"{name} is not in docs/arma/kb/functions.txt"))
    return out


def check_spec(spec: ArmaMissionSpec, kb: Path | None = None) -> list[Issue]:
    """All KB checks for a spec (classes; the spec itself holds no function names)."""
    return check_classes(spec, kb)
