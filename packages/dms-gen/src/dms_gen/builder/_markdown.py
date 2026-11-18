"""Tiny block-level Markdown reader for briefing.md / kneeboard.md.

Supports what the mission-designer writes: ATX headings, paragraphs (line breaks kept),
bullet and numbered lists with continuation lines, pipe tables, horizontal rules and inline
``**bold**`` / ``*italic*`` / ```code``` / ``[links](url)``. Anything else is plain text.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

_HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
_BULLET = re.compile(r"^(\s*)(?:[-*+]|\d+[.)])\s+(.*)$")
_RULE = re.compile(r"^\s*(?:-\s*){3,}$|^\s*(?:\*\s*){3,}$|^\s*(?:_\s*){3,}$")
_TABLE_SEP = re.compile(r"^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$")

_IMAGE_OR_LINK = re.compile(r"!?\[([^\]]*)\]\([^)]*\)")
_CODE = re.compile(r"`([^`]*)`")
_STRONG = re.compile(r"(\*\*|__)(.+?)\1")
_EMPH = re.compile(r"(?<![\w*])([*_])(?!\s)(.+?)(?<!\s)\1(?![\w*])")
_ESCAPE = re.compile(r"\\([\\`*_{}\[\]()#+\-.!|])")
_HTML_TAG = re.compile(r"</?[A-Za-z][^>]*>")


@dataclass(frozen=True)
class Heading:
    level: int
    text: str


@dataclass(frozen=True)
class Paragraph:
    lines: tuple[str, ...]


@dataclass
class Bullet:
    depth: int
    text: str


@dataclass(frozen=True)
class Table:
    header: tuple[str, ...]
    rows: tuple[tuple[str, ...], ...]


@dataclass(frozen=True)
class Rule:
    pass


Block = Heading | Paragraph | Bullet | Table | Rule


@dataclass
class _State:
    blocks: list[Block] = field(default_factory=list)
    para: list[str] = field(default_factory=list)
    table: list[str] = field(default_factory=list)

    def flush(self) -> None:
        if self.para:
            self.blocks.append(Paragraph(tuple(self.para)))
            self.para = []
        if self.table:
            self.blocks.append(_table(self.table))
            self.table = []


def _cells(line: str) -> tuple[str, ...]:
    s = line.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|") and not s.endswith("\\|"):
        s = s[:-1]
    return tuple(c.strip().replace("\\|", "|") for c in re.split(r"(?<!\\)\|", s))


def _table(lines: list[str]) -> Table | Paragraph:
    if len(lines) < 2 or not _TABLE_SEP.match(lines[1]):
        return Paragraph(tuple(line.strip() for line in lines))
    header = _cells(lines[0])
    n = len(header)
    rows = []
    for line in lines[2:]:
        cells = _cells(line)
        rows.append((cells + ("",) * n)[:n])
    return Table(header, tuple(rows))


def parse(md: str) -> list[Block]:
    """Split Markdown into blocks. Paragraph line breaks are preserved (callers decide)."""
    st = _State()
    for raw in md.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        line = raw.rstrip()
        if not line.strip():
            st.flush()
            continue
        if line.lstrip().startswith("|"):
            if st.para:
                st.flush()
            st.table.append(line)
            continue
        if st.table:
            st.flush()
        h = _HEADING.match(line)
        if h:
            st.flush()
            st.blocks.append(Heading(len(h.group(1)), h.group(2)))
            continue
        if _RULE.match(line):
            st.flush()
            st.blocks.append(Rule())
            continue
        b = _BULLET.match(line)
        if b:
            st.flush()
            indent = len(b.group(1).expandtabs(4))
            st.blocks.append(Bullet(indent // 2, b.group(2).strip()))
            continue
        last = st.blocks[-1] if st.blocks else None
        if not st.para and isinstance(last, Bullet):
            last.text = f"{last.text} {line.strip()}"  # continuation (indented or lazy)
            continue
        st.para.append(line.strip())
    st.flush()
    return st.blocks


def strip_inline(text: str) -> str:
    """Remove inline Markdown (emphasis, code, links, html tags, escapes)."""
    text = _IMAGE_OR_LINK.sub(r"\1", text)
    text = _CODE.sub(r"\1", text)
    text = _STRONG.sub(r"\2", text)
    text = _EMPH.sub(r"\2", text)
    text = _HTML_TAG.sub("", text)
    text = _ESCAPE.sub(r"\1", text)
    return re.sub(r"[ \t]+", " ", text).strip()


def bold_spans(text: str) -> list[tuple[str, bool]]:
    """Split ``text`` into (plain text, is_bold) spans; other inline markup is stripped."""
    spans: list[tuple[str, bool]] = []
    pos = 0
    for m in _STRONG.finditer(text):
        if m.start() > pos:
            spans.append((_strip_keep_space(text[pos : m.start()]), False))
        spans.append((_strip_keep_space(m.group(2)), True))
        pos = m.end()
    if pos < len(text):
        spans.append((_strip_keep_space(text[pos:]), False))
    return [s for s in spans if s[0]]


def _strip_keep_space(text: str) -> str:
    lead = " " if text[:1].isspace() else ""
    trail = " " if text[-1:].isspace() else ""
    inner = strip_inline(text)
    return f"{lead}{inner}{trail}" if inner else lead or trail
