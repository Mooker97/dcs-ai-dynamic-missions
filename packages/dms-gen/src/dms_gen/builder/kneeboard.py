"""kneeboard.md -> portrait PNG kneeboard pages (768x1024) for ``KNEEBOARD/IMAGES``.

Rendering uses only Pillow's bundled default font (``ImageFont.load_default(size=...)``), so no
font files ship with DMS. Output is deterministic: the same Markdown gives the same PNG bytes on
the same Pillow/FreeType build. Line breaks inside paragraphs are kept (kneeboard lines are
deliberate); long lines word-wrap. Tables get measured columns with wrapped cells. Content that
overflows a page continues on the next one, and every page carries a "title  n/N" footer.
"""

from __future__ import annotations

import io
import re
import unicodedata
from collections.abc import Sequence
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from ._markdown import Bullet, Heading, Paragraph, Rule, Table, bold_spans, parse, strip_inline

KNEEBOARD_FILE = "kneeboard.md"

PAGE_W = 768
PAGE_H = 1024
MARGIN = 40
FOOTER_H = 30
BODY = 22
TABLE = 20
HEADINGS = {1: 34, 2: 27, 3: 24}
CELL_PAD = 6

BG = (250, 248, 240)
FG = (20, 20, 20)
MUTED = (90, 90, 90)
LINE = (140, 140, 140)
HEAD_BG = (222, 222, 210)

Font = ImageFont.FreeTypeFont | ImageFont.ImageFont | ImageFont.TransposedFont


@lru_cache(maxsize=16)
def _font(size: int) -> Font:
    return ImageFont.load_default(size=size)


# Pillow's default font lacks these glyphs; substitute ASCII so nothing renders as a box.
_FALLBACK = {
    "—": "-",  # em dash
    "–": "-",  # noqa: RUF001 (en dash)
    "−": "-",  # noqa: RUF001 (minus)
    "→": "->",
    "←": "<-",
    "↔": "<->",
    "⇒": "=>",
    "↑": "^",
    "↓": "v",
    "×": "x",  # noqa: RUF001
    "•": "·",
    "≤": "<=",
    "≥": ">=",
    "≈": "~",
    "✓": "OK",
    "✗": "X",
}


@lru_cache(maxsize=1)
def _notdef() -> bytes:
    return bytes(_font(BODY).getmask("\U000f0000"))


@lru_cache(maxsize=1024)
def _glyph(ch: str) -> str:
    if ch.isascii():
        return " " if ch == "\t" else ch
    if ch.isspace():
        return " "
    if bytes(_font(BODY).getmask(ch)) != _notdef():
        return ch
    if ch in _FALLBACK:
        return _FALLBACK[ch]
    base = "".join(c for c in unicodedata.normalize("NFKD", ch) if not unicodedata.combining(c))
    return base if base and base.isascii() else "?"


def printable(text: str) -> str:
    """``text`` with characters the default font cannot draw replaced by ASCII stand-ins."""
    return "".join(_glyph(ch) for ch in text)


def _len(font: Font, text: str) -> float:
    return float(font.getlength(text))


# A laid-out line is a list of (x offset, text, bold) runs.
Run = tuple[float, str, bool]


def _words(spans: Sequence[tuple[str, bool]]) -> list[tuple[str, bool, bool]]:
    """(word, bold, space_before) tokens across spans."""
    out: list[tuple[str, bool, bool]] = []
    pending = False
    for text, bold in spans:
        for m in re.finditer(r"(\s*)(\S+)", text):
            out.append((m.group(2), bold, bool(m.group(1)) or pending))
            pending = False
        if text[-1:].isspace():
            pending = True
    return out


def _break_word(word: str, font: Font, max_w: float) -> list[str]:
    parts, cur = [], ""
    for ch in word:
        if cur and _len(font, cur + ch) > max_w:
            parts.append(cur)
            cur = ""
        cur += ch
    return [*parts, cur] if cur else parts


def _layout(spans: Sequence[tuple[str, bool]], font: Font, max_w: float) -> list[list[Run]]:
    """Greedy word wrap of styled spans into lines no wider than ``max_w``."""
    space = _len(font, " ")
    lines: list[list[Run]] = [[]]
    x = 0.0
    for word, bold, sp in _words(spans):
        pieces = _break_word(word, font, max_w) if _len(font, word) > max_w else [word]
        for i, piece in enumerate(pieces):
            w = _len(font, piece) + (1 if bold else 0)
            gap = space if (sp and i == 0 and lines[-1]) else 0.0
            if lines[-1] and x + gap + w > max_w:
                lines.append([])
                x, gap = 0.0, 0.0
            lines[-1].append((x + gap, piece, bold))
            x += gap + w
    return lines


@dataclass
class _Canvas:
    title: str
    pages: list[Image.Image]
    y: float = MARGIN

    @property
    def draw(self) -> ImageDraw.ImageDraw:
        return ImageDraw.Draw(self.pages[-1])

    @property
    def bottom(self) -> float:
        return PAGE_H - MARGIN - FOOTER_H

    def new_page(self) -> None:
        self.pages.append(Image.new("RGB", (PAGE_W, PAGE_H), BG))
        self.y = MARGIN

    def ensure(self, h: float) -> None:
        """Start a new page unless ``h`` pixels still fit (a fresh page always accepts)."""
        if self.y + h > self.bottom and self.y > MARGIN:
            self.new_page()

    def text_line(self, runs: list[Run], x0: float, font: Font, fill: tuple[int, int, int]) -> None:
        d = self.draw
        for x, text, bold in runs:
            d.text((x0 + x, self.y), text, font=font, fill=fill)
            if bold:  # faux bold: no bold face in Pillow's default font
                d.text((x0 + x + 1, self.y), text, font=font, fill=fill)


def _line_h(size: int) -> float:
    return round(size * 1.35)


def _paragraph(c: _Canvas, spans: list[tuple[str, bool]], size: int, x0: float, w: float) -> None:
    font = _font(size)
    for runs in _layout(spans, font, w):
        c.ensure(_line_h(size))
        c.text_line(runs, x0, font, FG)
        c.y += _line_h(size)


def _col_widths(table: Table, font: Font, avail: float) -> list[float]:
    rows = [table.header, *table.rows]
    n = len(table.header)
    natural = [
        max(_len(font, strip_inline(r[i])) + 1 for r in rows) + 2 * CELL_PAD for i in range(n)
    ]
    if sum(natural) <= avail:
        widths = list(natural)
        widths[-1] += avail - sum(natural)
        return widths
    # Fair share: columns narrower than their share keep their width; the rest split the remainder.
    widths = [0.0] * n
    todo = set(range(n))
    left = avail
    while todo:
        share = left / len(todo)
        fits = {i for i in todo if natural[i] <= share}
        if not fits:
            for i in sorted(todo):
                widths[i] = share
            break
        for i in fits:
            widths[i] = natural[i]
            left -= natural[i]
        todo -= fits
    return widths


def _table(c: _Canvas, table: Table) -> None:
    font = _font(TABLE)
    lh = _line_h(TABLE)
    x0 = float(MARGIN)
    widths = _col_widths(table, font, PAGE_W - 2 * MARGIN)
    right = x0 + sum(widths)
    for r, row in enumerate([table.header, *table.rows]):
        header = r == 0
        cells = [
            _layout(
                [(strip_inline(cell), True)] if header else bold_spans(cell), font, w - 2 * CELL_PAD
            )
            for cell, w in zip(row, widths, strict=True)
        ]
        h = max(len(lines) for lines in cells) * lh + 2 * CELL_PAD - 4
        c.ensure(h)
        d = c.draw
        top = c.y
        if header:
            d.rectangle([x0, top, right, top + h], fill=HEAD_BG)
        x = x0
        for lines, w in zip(cells, widths, strict=True):
            c.y = top + CELL_PAD - 2
            for runs in lines:
                c.text_line(runs, x + CELL_PAD, font, FG)
                c.y += lh
            x += w
        d.rectangle([x0, top, right, top + h], outline=LINE, width=1)
        x = x0
        for w in widths[:-1]:
            x += w
            d.line([x, top, x, top + h], fill=LINE, width=1)
        c.y = top + h
    c.y += 10


def render_kneeboard(md: str, title: str = "") -> list[bytes]:
    """Render kneeboard Markdown to PNG pages (bytes). ``title`` defaults to the first ``#``."""
    blocks = parse(printable(md))
    title = printable(title)
    if not title:
        title = next((strip_inline(b.text) for b in blocks if isinstance(b, Heading)), "")
    c = _Canvas(title=title, pages=[])
    c.new_page()
    width = PAGE_W - 2 * MARGIN
    prev = None
    for b in blocks:
        if isinstance(b, Heading):
            size = HEADINGS.get(b.level, BODY)
            if c.y > MARGIN:
                c.y += 8 if b.level > 1 else 14
            c.ensure(_line_h(size) * 2)
            _paragraph(c, [(strip_inline(b.text), True)], size, MARGIN, width)
            if b.level == 1:
                c.draw.line([MARGIN, c.y, PAGE_W - MARGIN, c.y], fill=FG, width=2)
                c.y += 10
        elif isinstance(b, Paragraph):
            if isinstance(prev, Paragraph):
                c.y += 10
            for line in b.lines:
                _paragraph(c, bold_spans(line), BODY, MARGIN, width)
        elif isinstance(b, Bullet):
            indent = MARGIN + 22 * b.depth
            c.ensure(_line_h(BODY))
            c.draw.text((indent, c.y), "-", font=_font(BODY), fill=FG)
            _paragraph(c, bold_spans(b.text), BODY, indent + 18, PAGE_W - MARGIN - indent - 18)
        elif isinstance(b, Table):
            c.y += 4
            _table(c, b)
        elif isinstance(b, Rule):
            c.ensure(12)
            c.draw.line([MARGIN, c.y + 5, PAGE_W - MARGIN, c.y + 5], fill=LINE, width=1)
            c.y += 12
        prev = b
    out: list[bytes] = []
    n = len(c.pages)
    small = _font(16)
    for i, page in enumerate(c.pages, start=1):
        d = ImageDraw.Draw(page)
        fy = PAGE_H - MARGIN + 4
        d.line([MARGIN, fy - 8, PAGE_W - MARGIN, fy - 8], fill=LINE, width=1)
        if title:
            d.text((MARGIN, fy), title, font=small, fill=MUTED)
        label = f"{i}/{n}"
        d.text((PAGE_W - MARGIN - _len(small, label), fy), label, font=small, fill=MUTED)
        buf = io.BytesIO()
        page.save(buf, format="PNG", optimize=False, compress_level=9)
        out.append(buf.getvalue())
    return out


def write_kneeboard_pages(
    md_path: str | Path, out_dir: str | Path, stem: str = "kneeboard", title: str = ""
) -> list[Path]:
    """Render ``md_path`` into ``out_dir/<stem>-01.png`` ... ; returns the written paths.

    Page numbers are zero-padded so DCS (which orders kneeboard images by file name) shows them
    in order. Returns ``[]`` when the Markdown file is missing or blank.
    """
    src = Path(md_path)
    if not src.is_file():
        return []
    md = src.read_text(encoding="utf-8")
    if not md.strip():
        return []
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    safe = re.sub(r"[^A-Za-z0-9_-]+", "_", stem) or "kneeboard"
    paths = []
    for i, png in enumerate(render_kneeboard(md, title), start=1):
        p = out / f"{safe}-{i:02d}.png"
        p.write_bytes(png)
        paths.append(p)
    return paths
