"""plan.json -> one deterministic kneeboard map page (768x1024 PNG), CONTRACTS "Map page" (U3).

The page is drawn from the BuildPlan alone, with no map tiles (licensing and determinism):
lat/lon graticule, north arrow, NM scale bar, bullseye, the client routes with named
steerpoints (IP / TGT highlighted), friendly airbases, known threat rings, no-strike areas and a
steerpoint list with lat/lon.

Fog of war: only enemy groups the player is meant to know about are drawn. A group must be
``hidden: false`` and not ``late_activation``, and when ``runtime.intel.fog_of_war`` is on it must
also be in ``intel.known_groups``. Hidden groups never touch the page, not even its extent, so
adding a hidden threat to a plan leaves the PNG bytes unchanged.

Text uses Pillow's bundled default font (as :mod:`.kneeboard` does), and shapes are drawn
without antialiasing, so the bytes are deterministic for a given Pillow build.
"""

# mypy: disallow-untyped-calls=False

from __future__ import annotations

import io
import math
import re
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

from dms_core.catalog import CatalogLookupError, find_airbases, load_catalog
from dms_core.schemas import BuildPlan
from dms_core.schemas.plan import PlanGroup, PlanWaypoint
from PIL import Image, ImageDraw

from .geo import latlon_to_xy, xy_to_latlon
from .kneeboard import BG, FG, LINE, MUTED, PAGE_H, PAGE_W, Font, _font, printable
from .mission import terrain_by_name

MAP_STEM = "kneeboard-map"
NM = 1852.0

# Map frame on the page (pixels).
MAP_L, MAP_T, MAP_R, MAP_B = 24, 64, PAGE_W - 24, 744
MAP_W, MAP_H = MAP_R - MAP_L, MAP_B - MAP_T
MIN_SPAN_NM = 10.0
PAD = 0.12

ROUTE = (25, 55, 150)
ROUTE_ALT = (120, 140, 200)
FRIEND = (20, 90, 200)
THREAT = (200, 20, 20)
NOSTRIKE = (170, 0, 170)
GRID = (205, 200, 185)
BULLS = (0, 120, 60)
WHITE = (255, 255, 255)

#: Ring radius (NM) when no catalog template gives one, by catalog unit role.
ROLE_RANGE_NM: dict[str, float] = {
    "sam_long": 25.0,
    "sam_medium": 15.0,
    "sam_radar": 10.0,
    "sam_short": 5.0,
    "manpads": 2.5,
    "aaa": 1.5,
    "cruiser": 40.0,
    "destroyer": 25.0,
    "frigate": 20.0,
    "corvette": 8.0,
    "carrier": 8.0,
}
_GROUND = ("vehicle", "ship", "static")
_NO_STRIKE = re.compile(r"no[_-]?strike|(?:^|[^a-z])(?:nsa|nfa)(?:$|[^a-z])|no[_-]?fire|restricted")

XY = tuple[float, float]


@dataclass(frozen=True)
class Steerpoint:
    """One route point: DCS mission editor number (0 = start), label, map x/y."""

    num: int
    name: str
    x: float
    y: float


@dataclass(frozen=True)
class Threat:
    """One known threat: group name, label, centre and ring radius (0 = marker only)."""

    group: str
    label: str
    x: float
    y: float
    radius_m: float


@dataclass(frozen=True)
class NoStrike:
    """A no-strike area: polygon points (x, y), or a circle (one centre point + radius)."""

    name: str
    points: tuple[XY, ...]
    radius_m: float | None = None


@dataclass(frozen=True)
class MapFeatures:
    """Everything the map page draws, in DCS map metres (x north, y east)."""

    routes: tuple[tuple[str, tuple[Steerpoint, ...]], ...]
    airbases: tuple[tuple[str, float, float], ...]
    threats: tuple[Threat, ...]
    no_strike: tuple[NoStrike, ...]
    bullseye: XY


# ---------------------------------------------------------------------------- features
def _player_side(plan: BuildPlan) -> str:
    if plan.runtime is not None:
        return "red" if plan.runtime.players.coalition == 1 else "blue"
    first = next((g for g in plan.groups if g.client), None)
    return first.coalition if first is not None and first.coalition != "neutral" else "blue"


def _wp_name(i: int, wp: PlanWaypoint) -> str:
    if wp.name:
        return wp.name
    if i == 0:
        return wp.airbase or "START"
    if wp.action == "Landing":
        return wp.airbase or "LAND"
    return ""


def _routes(plan: BuildPlan) -> tuple[tuple[str, tuple[Steerpoint, ...]], ...]:
    out: list[tuple[str, tuple[Steerpoint, ...]]] = []
    seen: set[tuple[tuple[float, float, str], ...]] = set()
    for g in plan.groups:
        if not g.client:
            continue
        pts = g.route or [PlanWaypoint(x=g.units[0].x, y=g.units[0].y)]
        sps = tuple(Steerpoint(i, _wp_name(i, wp), wp.x, wp.y) for i, wp in enumerate(pts))
        key = tuple((round(s.x), round(s.y), s.name) for s in sps)
        if key not in seen:
            seen.add(key)
            out.append((g.name, sps))
    return tuple(out)


def _airbases(plan: BuildPlan, side: str) -> tuple[tuple[str, float, float], ...]:
    names = sorted(
        {wp.airbase for g in plan.groups if g.coalition == side for wp in g.route if wp.airbase}
    )
    if not names:
        return ()
    try:
        known = {a.name: a for a in find_airbases(plan.theater)}
    except (CatalogLookupError, RuntimeError):
        return ()
    return tuple((n, known[n].x, known[n].y) for n in names if n in known)


@lru_cache(maxsize=1)
def _template_ranges() -> dict[str, float]:
    """Unit type -> the largest ``max_range_nm`` of any catalog template it appears in."""
    out: dict[str, float] = {}
    for t in load_catalog().templates.values():
        if t.max_range_nm:
            for u in t.units:
                out[u.type] = max(out.get(u.type, 0.0), float(t.max_range_nm))
    return out


def _type_range_nm(type_id: str) -> tuple[float, str]:
    """(ring radius NM, display name) for a unit type; radius 0 = not an air threat."""
    units = load_catalog().units
    ut = units.get(type_id)
    if ut is None:
        return 0.0, type_id
    if ut.role not in ROLE_RANGE_NM:
        return 0.0, ut.name
    return _template_ranges().get(type_id) or ROLE_RANGE_NM[ut.role], ut.name


def _known(plan: BuildPlan, g: PlanGroup, enemy: str) -> bool:
    """Fog of war: True only for enemy ground groups the player is meant to see."""
    if g.coalition != enemy or g.category not in _GROUND or g.hidden or g.late_activation:
        return False
    intel = plan.runtime.intel if plan.runtime is not None else None
    if intel is not None and intel.fog_of_war:
        return g.name in (intel.known_groups or [])
    return True


def _threats(plan: BuildPlan, side: str) -> tuple[Threat, ...]:
    enemy = "red" if side == "blue" else "blue"
    out = []
    for g in plan.groups:
        if not _known(plan, g, enemy):
            continue
        best_nm, best_name = 0.0, ""
        for u in g.units:
            nm, name = _type_range_nm(u.type)
            if nm > best_nm or not best_name:
                best_nm, best_name = nm, name
        cx = sum(u.x for u in g.units) / len(g.units)
        cy = sum(u.y for u in g.units) / len(g.units)
        label = best_name.split(" (")[0][:20] + (f" {best_nm:g}NM" if best_nm else "")
        out.append(Threat(g.name, label, cx, cy, best_nm * NM))
    return tuple(out)


def _no_strike(plan: BuildPlan) -> tuple[NoStrike, ...]:
    rt_zones = plan.runtime.zones if plan.runtime is not None else {}
    out = []
    for z in plan.zones:
        if not _NO_STRIKE.search(z.name.lower()):
            continue
        rz = rt_zones.get(z.name)
        if rz is not None and rz.kind == "polygon":
            out.append(NoStrike(z.name, tuple((p.x, p.y) for p in rz.points)))
        elif z.kind == "polygon":
            out.append(NoStrike(z.name, tuple(z.points)))
        elif z.x is not None and z.y is not None and z.radius_m is not None:
            out.append(NoStrike(z.name, ((z.x, z.y),), z.radius_m))
    return tuple(out)


def _bullseye(plan: BuildPlan, side: str) -> XY:
    terrain = terrain_by_name(plan.theater)
    be = terrain.bullseye_red if side == "red" else terrain.bullseye_blue
    return (float(be["x"]), float(be["y"]))


def map_features(plan: BuildPlan) -> MapFeatures:
    """What the map page shows (fog of war applied)."""
    side = _player_side(plan)
    return MapFeatures(
        routes=_routes(plan),
        airbases=_airbases(plan, side),
        threats=_threats(plan, side),
        no_strike=_no_strike(plan),
        bullseye=_bullseye(plan, side),
    )


# ---------------------------------------------------------------------------- projection
@dataclass(frozen=True)
class _View:
    """DCS x/y metres <-> map-image pixels (north up, equal scale)."""

    x_top: float  # DCS x at the top edge
    y_left: float  # DCS y at the left edge
    px_per_m: float

    def px(self, x: float, y: float) -> XY:
        return ((y - self.y_left) * self.px_per_m, (self.x_top - x) * self.px_per_m)

    def xy(self, px: float, py: float) -> XY:
        return (self.x_top - py / self.px_per_m, self.y_left + px / self.px_per_m)


def _view(f: MapFeatures) -> _View:
    pts: list[XY] = [(s.x, s.y) for _n, r in f.routes for s in r]
    pts += [(x, y) for _n, x, y in f.airbases]
    pts += [(t.x, t.y) for t in f.threats]
    for ns in f.no_strike:
        pts += list(ns.points)
    xs = [p[0] for p in pts] or [f.bullseye[0]]
    ys = [p[1] for p in pts] or [f.bullseye[1]]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    # The bullseye joins the extent only when that grows it by at most a quarter.
    bx, by = f.bullseye
    span = max(x1 - x0, y1 - y0, MIN_SPAN_NM * NM)
    if max(x1, bx) - min(x0, bx) <= 1.25 * span and max(y1, by) - min(y0, by) <= 1.25 * span:
        x0, x1, y0, y1 = min(x0, bx), max(x1, bx), min(y0, by), max(y1, by)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    h_m = max(x1 - x0, MIN_SPAN_NM * NM) * (1 + 2 * PAD)
    w_m = max(y1 - y0, MIN_SPAN_NM * NM) * (1 + 2 * PAD)
    scale = min(MAP_W / w_m, MAP_H / h_m)
    return _View(x_top=cx + MAP_H / 2 / scale, y_left=cy - MAP_W / 2 / scale, px_per_m=scale)


# ---------------------------------------------------------------------------- drawing
def _nice(target: float, steps: Sequence[float]) -> float:
    return min(steps, key=lambda s: (abs(math.log(s / target)), s))


def _text(d: ImageDraw.ImageDraw, xy: XY, text: str, size: int, fill: tuple[int, int, int]) -> None:
    """Text with a 1-px background halo so it reads over lines."""
    font = _font(size)
    x, y = round(xy[0]), round(xy[1])
    t = printable(text)
    for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        d.text((x + dx, y + dy), t, font=font, fill=BG)
    d.text((x, y), t, font=font, fill=fill)


def _len(font: Font, text: str) -> float:
    return float(font.getlength(printable(text)))


Box = tuple[float, float, float, float]


class _Labels:
    """Deterministic label placement: the first candidate spot that overlaps no earlier label."""

    def __init__(self, d: ImageDraw.ImageDraw) -> None:
        self.d = d
        self.boxes: list[Box] = []

    def place(self, anchor: XY, text: str, size: int, fill: tuple[int, int, int]) -> None:
        w = _len(_font(size), text)
        h = size + 4
        ax, ay = anchor
        cands = [
            (ax + 11, ay - h - 4),
            (ax + 11, ay + 4),
            (ax - w - 11, ay - h - 4),
            (ax - w - 11, ay + 4),
            (ax - w / 2, ay + 12),
            (ax - w / 2, ay - h - 14),
            (ax + 11, ay - 2 * h - 6),
            (ax + 11, ay + h + 6),
            (ax - w - 11, ay - 2 * h - 6),
            (ax - w - 11, ay + h + 6),
        ]
        inside = [c for c in cands if 2 <= c[0] <= MAP_W - w - 2 and 2 <= c[1] <= MAP_H - h - 2]
        free = [
            c
            for c in inside
            if not any(self._hit((c[0], c[1], c[0] + w, c[1] + h), b) for b in self.boxes)
        ]
        x, y = (free or inside or cands)[0]
        self.boxes.append((x, y, x + w, y + h))
        _text(self.d, (x, y), text, size, fill)

    @staticmethod
    def _hit(a: Box, b: Box) -> bool:
        return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def _dm(v: float, pos: str, neg: str, deg_w: int, decimals: int) -> str:
    h = pos if v >= 0 else neg
    a = abs(v)
    deg = int(a)
    mins = round((a - deg) * 60, decimals)
    if mins >= 60:
        deg, mins = deg + 1, 0.0
    width = 3 + decimals if decimals else 2
    return f"{h}{deg:0{deg_w}d}°{mins:0{width}.{decimals}f}'"


def ddm(lat: float, lon: float) -> str:
    """``N36°12.345' E036°01.234'`` (degrees, decimal minutes)."""
    return f"{_dm(lat, 'N', 'S', 2, 3)} {_dm(lon, 'E', 'W', 3, 3)}"


def _graticule(d: ImageDraw.ImageDraw, v: _View, plan: BuildPlan) -> None:
    terrain = terrain_by_name(plan.theater)
    corners = [v.xy(px, py) for px in (0, MAP_W / 2, MAP_W) for py in (0, MAP_H / 2, MAP_H)]
    lls = [xy_to_latlon(terrain, x, y) for x, y in corners]
    lat0, lat1 = min(a for a, _ in lls), max(a for a, _ in lls)
    lon0, lon1 = min(b for _, b in lls), max(b for _, b in lls)
    steps = (1, 2, 5, 10, 15, 20, 30, 60, 120, 300)
    step = _nice(max(lat1 - lat0, 1e-6) * 60 / 4, steps) / 60
    samples = 32

    def lines(fixed_lat: bool) -> Iterable[tuple[float, list[XY]]]:
        lo, hi = (lat0, lat1) if fixed_lat else (lon0, lon1)
        o_lo, o_hi = (lon0, lon1) if fixed_lat else (lat0, lat1)
        k = math.ceil(lo / step - 1e-9)
        while k * step <= hi + 1e-9:
            val = k * step
            pts = []
            for i in range(samples + 1):
                other = o_lo + (o_hi - o_lo) * i / samples
                lat, lon = (val, other) if fixed_lat else (other, val)
                pts.append(v.px(*latlon_to_xy(terrain, lat, lon)))
            yield val, pts
            k += 1

    for val, pts in lines(True):
        d.line(pts, fill=GRID, width=1)
        left = min(pts, key=lambda p: (abs(p[0] - 4), p[1]))
        _text(d, (4, left[1] - 16), _dm(val, "N", "S", 2, 0), 14, MUTED)
    for val, pts in lines(False):
        d.line(pts, fill=GRID, width=1)
        bottom = min(pts, key=lambda p: (abs(p[1] - (MAP_H - 18)), p[0]))
        _text(d, (bottom[0] + 3, MAP_H - 18), _dm(val, "E", "W", 3, 0), 14, MUTED)


def _hatched(map_img: Image.Image, v: _View, ns: NoStrike) -> None:
    mask = Image.new("L", map_img.size, 0)
    md = ImageDraw.Draw(mask)
    if ns.radius_m is not None:
        cx, cy = v.px(*ns.points[0])
        r = ns.radius_m * v.px_per_m
        box = [cx - r, cy - r, cx + r, cy + r]
        md.ellipse(box, fill=255)
    else:
        poly = [v.px(x, y) for x, y in ns.points]
        md.polygon(poly, fill=255)
    hatch = Image.new("RGB", map_img.size, NOSTRIKE)
    lines = Image.new("L", map_img.size, 0)
    ld = ImageDraw.Draw(lines)
    for k in range(-MAP_H, MAP_W, 12):
        ld.line([(k, MAP_H), (k + MAP_H, 0)], fill=255, width=1)
    keep = Image.new("L", map_img.size, 0)
    keep.paste(lines, mask=mask)
    map_img.paste(hatch, mask=keep)
    d = ImageDraw.Draw(map_img)
    if ns.radius_m is not None:
        d.ellipse(box, outline=NOSTRIKE, width=2)
        anchor = (box[0] + 4, box[1] + r - 8)
    else:
        d.polygon(poly, outline=NOSTRIKE, width=2)
        anchor = (min(p[0] for p in poly) + 4, min(p[1] for p in poly) + 4)
    _text(d, anchor, "NO STRIKE", 14, NOSTRIKE)


def _route(
    d: ImageDraw.ImageDraw, v: _View, sps: Sequence[Steerpoint], primary: bool, lab: _Labels
) -> None:
    pts = [v.px(s.x, s.y) for s in sps]
    if not primary:  # other client routes (start variants, other flights): thin, unlabelled
        if len(pts) > 1:
            d.line(pts, fill=ROUTE_ALT, width=1)
        return
    if len(pts) > 1:
        d.line(pts, fill=ROUTE, width=3)
    for s, (px, py) in zip(sps, pts, strict=True):
        name = s.name.upper()
        if name == "IP":
            d.polygon(
                [(px, py - 10), (px - 9, py + 7), (px + 9, py + 7)], fill=WHITE, outline=ROUTE
            )
            d.polygon([(px, py - 9), (px - 8, py + 6), (px + 8, py + 6)], outline=ROUTE)
        elif name.startswith("TGT"):
            d.ellipse([px - 9, py - 9, px + 9, py + 9], outline=THREAT, width=2)
            d.line([(px - 13, py), (px + 13, py)], fill=THREAT, width=2)
            d.line([(px, py - 13), (px, py + 13)], fill=THREAT, width=2)
        else:
            d.ellipse([px - 6, py - 6, px + 6, py + 6], fill=WHITE, outline=ROUTE, width=2)
        lab.place((px, py), f"{s.num} {s.name}".strip(), 16, ROUTE)


def _bulls(d: ImageDraw.ImageDraw, v: _View, be: XY, lab: _Labels) -> None:
    px, py = v.px(*be)
    if 0 <= px <= MAP_W and 0 <= py <= MAP_H:
        for r in (5, 11, 17):
            d.ellipse([px - r, py - r, px + r, py + r], outline=BULLS, width=1)
        d.line([(px - 22, py), (px + 22, py)], fill=BULLS, width=1)
        d.line([(px, py - 22), (px, py + 22)], fill=BULLS, width=1)
        lab.place((px + 8, py + 8), "BULLS", 15, BULLS)
        return
    cx, cy = v.xy(MAP_W / 2, MAP_H / 2)
    brg = math.degrees(math.atan2(be[1] - cy, be[0] - cx)) % 360
    rng = math.dist((cx, cy), be) / NM
    # Clip the centre->bullseye ray to the frame (inset 30 px).
    ox, oy = MAP_W / 2, MAP_H / 2
    dx, dy = px - ox, py - oy
    t = min((ox - 30) / abs(dx) if dx else math.inf, (oy - 30) / abs(dy) if dy else math.inf)
    ex, ey = ox + dx * t, oy + dy * t
    a = math.atan2(dy, dx)
    tip = (ex + 14 * math.cos(a), ey + 14 * math.sin(a))
    left = (ex + 10 * math.cos(a + 2.5), ey + 10 * math.sin(a + 2.5))
    right = (ex + 10 * math.cos(a - 2.5), ey + 10 * math.sin(a - 2.5))
    d.polygon([tip, left, right], fill=BULLS)
    lab.place((ex, ey), f"BULLS {round(brg) % 360:03d}/{round(rng)}", 15, BULLS)


def _north_arrow(d: ImageDraw.ImageDraw) -> None:
    x, y = MAP_W - 34, 14
    d.polygon([(x, y), (x - 10, y + 30), (x, y + 23)], fill=FG)
    d.polygon([(x, y), (x + 10, y + 30), (x, y + 23)], outline=FG)
    _text(d, (x - 5, y + 32), "N", 16, FG)


def _scale_bar(d: ImageDraw.ImageDraw, v: _View) -> Box:
    """Draw the NM scale bar (bottom left); returns its backing box."""
    nm = _nice(MAP_W / 4 / (v.px_per_m * NM), (0.5, 1, 2, 5, 10, 20, 25, 50, 100, 200))
    seg = nm * NM * v.px_per_m / 4
    x0, y0 = 14.0, MAP_H - 46.0
    box = (x0 - 6, y0 - 22, x0 + 4 * seg + 40, y0 + 12)
    d.rectangle(box, fill=BG)
    for i in range(4):
        d.rectangle(
            [x0 + i * seg, y0, x0 + (i + 1) * seg, y0 + 6],
            fill=FG if i % 2 == 0 else WHITE,
            outline=FG,
        )
    _text(d, (x0 - 2, y0 - 19), "0", 14, FG)
    _text(d, (x0 + 4 * seg - 4, y0 - 19), f"{nm:g} NM", 14, FG)
    return box


def _draw_map(plan: BuildPlan, f: MapFeatures) -> Image.Image:
    v = _view(f)
    img = Image.new("RGB", (MAP_W, MAP_H), BG)
    d = ImageDraw.Draw(img)
    lab = _Labels(d)
    _graticule(d, v, plan)
    lab.boxes.append(_scale_bar(d, v))  # under the features; labels keep clear of it
    for ns in f.no_strike:
        _hatched(img, v, ns)
    labels: list[tuple[XY, str, int, tuple[int, int, int]]] = []
    for t in f.threats:
        px, py = v.px(t.x, t.y)
        r = t.radius_m * v.px_per_m
        if r > 0:
            d.ellipse([px - r, py - r, px + r, py + r], outline=THREAT, width=2)
        d.polygon([(px, py - 7), (px + 7, py), (px, py + 7), (px - 7, py)], fill=THREAT)
        labels.append(((px, py), t.label, 14, THREAT))
    for name, x, y in f.airbases:
        px, py = v.px(x, y)
        d.ellipse([px - 9, py - 9, px + 9, py + 9], outline=FRIEND, width=2)
        d.line([(px - 6, py + 6), (px + 6, py - 6)], fill=FRIEND, width=3)
        labels.append(((px, py), name, 15, FRIEND))
    for i, (_g, sps) in reversed(list(enumerate(f.routes))):
        _route(d, v, sps, i == 0, lab)
    _bulls(d, v, f.bullseye, lab)
    for anchor, text, size, fill in labels:
        lab.place(anchor, text, size, fill)
    _north_arrow(d)
    return img


def render_map_page(plan: BuildPlan) -> bytes | None:
    """The map page PNG, or ``None`` when the plan has no client group."""
    f = map_features(plan)
    if not f.routes:
        return None
    page = Image.new("RGB", (PAGE_W, PAGE_H), BG)
    page.paste(_draw_map(plan, f), (MAP_L, MAP_T))
    d = ImageDraw.Draw(page)
    d.rectangle([MAP_L - 1, MAP_T - 1, MAP_R, MAP_B], outline=FG, width=2)
    title = f"MAP  {plan.mission_id}"
    _text(d, (MAP_L, 18), title, 28, FG)
    _text(d, (MAP_L + 1, 18), title, 28, FG)  # faux bold
    sub = f"{plan.theater}  {plan.date.isoformat()}"
    _text(d, (MAP_R - _len(_font(16), sub), 28), sub, 16, MUTED)

    terrain = terrain_by_name(plan.theater)
    group, sps = f.routes[0]
    y = MAP_B + 12.0
    head = f"STEERPOINTS ({group})" if len(f.routes) > 1 else "STEERPOINTS"
    _text(d, (MAP_L, y), head, 17, FG)
    y += 24
    col_w = (MAP_R - MAP_L) / 2
    rows = 8
    for i, s in enumerate(sps[: 2 * rows]):
        cx = MAP_L + col_w * (i // rows)
        cy = y + 21 * (i % rows)
        lat, lon = xy_to_latlon(terrain, s.x, s.y)
        _text(d, (cx, cy), f"{s.num:>2} {s.name[:8]}", 15, ROUTE)
        _text(d, (cx + 110, cy), ddm(lat, lon), 15, FG)
    y += 21 * rows + 6
    blat, blon = xy_to_latlon(terrain, *f.bullseye)
    _text(d, (MAP_L, y), f"BULLS  {ddm(blat, blon)}", 15, BULLS)
    fy = PAGE_H - 40 + 4
    d.line([MAP_L, fy - 8, MAP_R, fy - 8], fill=LINE, width=1)
    note = "Known threats only. No map tiles."
    _text(d, (MAP_L, fy), note, 14, MUTED)
    buf = io.BytesIO()
    page.save(buf, format="PNG", optimize=False, compress_level=9)
    return buf.getvalue()


def write_map_page(plan: BuildPlan, out_dir: str | Path) -> list[Path]:
    """Write ``<out_dir>/<mission_id>-kneeboard-map-01.png``; ``[]`` when there is no page."""
    png = render_map_page(plan)
    if png is None:
        return []
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    safe = re.sub(r"[^A-Za-z0-9_-]+", "_", f"{plan.mission_id}-{MAP_STEM}")
    p = out / f"{safe}-01.png"
    p.write_bytes(png)
    return [p]
