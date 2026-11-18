"""briefing.md -> DCS mission-editor briefing texts.

DCS has four briefing fields: sortie (the title line), description (situation), and one task
text per coalition. The mapping from the mission-designer's five-paragraph order:

* the first ``#`` heading is the sortie;
* everything before paragraph 2 (header line, intelligence narrative, 1. Situation) is the
  description;
* from the first heading that is ``2.`` or ``Mission`` onward is the blue task;
* a heading containing the word ``Red`` (e.g. ``## Red task``) starts the red task, which runs
  until the next heading of the same or a higher level.

Markdown is stripped to plain text. Paragraphs are unwrapped to one line each (the DCS briefing
window word-wraps itself, so hard breaks give ragged text) unless ``width`` asks for hard wraps.
"""

from __future__ import annotations

import re
import textwrap
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

from ._markdown import Block, Bullet, Heading, Paragraph, Rule, Table, parse, strip_inline

BRIEFING_FILE = "briefing.md"

_MISSION_HEADING = re.compile(r"^\s*(?:2\s*[.)]|mission\b)", re.IGNORECASE)
_RED_HEADING = re.compile(r"\bred\b", re.IGNORECASE)

Target = Literal["description", "blue", "red"]


@dataclass(frozen=True)
class BriefingText:
    """The four DCS briefing strings."""

    sortie: str
    description: str
    blue_task: str = ""
    red_task: str = ""


def _wrap(text: str, width: int | None, indent: str = "", hang: str = "") -> list[str]:
    if width is None:
        return [f"{indent}{text}"]
    return textwrap.wrap(
        text,
        width=width,
        initial_indent=indent,
        subsequent_indent=hang or indent,
        break_long_words=False,
        break_on_hyphens=False,
    ) or [indent]


def _render(blocks: list[Block], width: int | None) -> str:
    out: list[str] = []
    prev: Block | None = None
    for b in blocks:
        tight = isinstance(b, Bullet) and isinstance(prev, Bullet)
        if out and not tight:
            out.append("")
        if isinstance(b, Heading):
            out.append(strip_inline(b.text).upper())
        elif isinstance(b, Paragraph):
            out.extend(_wrap(strip_inline(" ".join(b.lines)), width))
        elif isinstance(b, Bullet):
            pad = "  " * b.depth
            out.extend(_wrap(strip_inline(b.text), width, f"{pad}- ", f"{pad}  "))
        elif isinstance(b, Table):
            out.append(" | ".join(strip_inline(c) for c in b.header))
            for row in b.rows:
                out.extend(_wrap(" | ".join(strip_inline(c) for c in row), width, "", "  "))
        elif isinstance(b, Rule):
            out.append("-" * 20)
        prev = b
    return "\n".join(out).strip("\n")


def briefing_from_markdown(
    md: str,
    fallback_title: str = "",
    fallback_blue_task: str = "",
    fallback_red_task: str = "",
    width: int | None = None,
) -> BriefingText:
    """Convert briefing Markdown to DCS briefing texts (see the module docstring)."""
    sortie = ""
    sections: dict[Target, list[Block]] = {"description": [], "blue": [], "red": []}
    target: Target = "description"
    main: Target = "description"
    red_level = 0
    for b in parse(md):
        if isinstance(b, Heading):
            text = strip_inline(b.text)
            if b.level == 1 and not sortie:
                sortie = text
                continue
            if target == "red" and b.level <= red_level:
                target = main
            if _RED_HEADING.search(text):
                target, red_level = "red", b.level
            elif target != "red" and _MISSION_HEADING.match(text):
                target = main = "blue"
        sections[target].append(b)
    return BriefingText(
        sortie=sortie or fallback_title,
        description=_render(sections["description"], width),
        blue_task=_render(sections["blue"], width) or fallback_blue_task,
        red_task=_render(sections["red"], width) or fallback_red_task,
    )


def load_briefing(
    path: str | Path,
    fallback_title: str = "",
    fallback_blue_task: str = "",
    fallback_red_task: str = "",
    width: int | None = None,
) -> BriefingText | None:
    """Read ``briefing.md`` at ``path``; ``None`` when the file is missing or blank."""
    p = Path(path)
    if not p.is_file():
        return None
    md = p.read_text(encoding="utf-8")
    if not md.strip():
        return None
    return briefing_from_markdown(
        md, fallback_title, fallback_blue_task, fallback_red_task, width=width
    )
