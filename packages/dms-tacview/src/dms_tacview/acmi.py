"""ACMI 2.x text parser (Tacview telemetry), plain ``.txt.acmi`` or zipped ``.zip.acmi``.

Format facts used here are from the Tacview "ACMI flight recordings 2.2" documentation; see
docs/ideas/tacview.md for what is verified and what is assumed. Parsing is pure: only
:func:`read_acmi_text` / :func:`parse_acmi_file` touch the filesystem.

The parser is streaming and forgiving: malformed lines are counted and skipped, never fatal.
"""

from __future__ import annotations

import bisect
import dataclasses
import io
import math
import zipfile
from collections.abc import Iterable, Iterator
from datetime import datetime
from pathlib import Path

__all__ = [
    "GLOBAL_ID",
    "TRANSFORM_FIELDS",
    "AcmiError",
    "AcmiEvent",
    "AcmiHeader",
    "AcmiObject",
    "Recording",
    "TrackPoint",
    "Transform",
    "iter_logical_lines",
    "parse_acmi",
    "parse_acmi_file",
    "read_acmi_text",
    "split_fields",
]

#: Object id that carries global properties and events.
GLOBAL_ID = "0"

#: Transform component names by component count (spec: 3, 5, 6 and 9 component notations).
TRANSFORM_FIELDS: dict[int, tuple[str, ...]] = {
    3: ("lon", "lat", "alt"),
    5: ("lon", "lat", "alt", "u", "v"),
    6: ("lon", "lat", "alt", "roll", "pitch", "yaw"),
    9: ("lon", "lat", "alt", "roll", "pitch", "yaw", "u", "v", "heading"),
}

#: Events whose pipe-separated parameters are ``ObjectId|...|Text``.
_OBJECT_EVENTS = frozenset({"Message", "LeftArea", "Destroyed", "TakenOff", "Landed"})
#: Events whose only parameter is free text.
_TEXT_EVENTS = frozenset({"Bookmark", "Debug"})


class AcmiError(ValueError):
    """The input is not an ACMI 2.x text recording."""


@dataclasses.dataclass
class Transform:
    """Last known transform of an object. ``None`` = never set. Angles in degrees."""

    lon: float | None = None
    lat: float | None = None
    alt: float | None = None
    roll: float | None = None
    pitch: float | None = None
    yaw: float | None = None
    u: float | None = None
    v: float | None = None
    heading: float | None = None


@dataclasses.dataclass(frozen=True)
class TrackPoint:
    """One position sample (absolute lon/lat in degrees, altitude in metres MSL)."""

    t: float
    lon: float
    lat: float
    alt: float
    u: float | None = None
    v: float | None = None


@dataclasses.dataclass
class AcmiObject:
    """One object (id is lower-case hex, as in the file without leading zeros)."""

    id: str
    first_seen: float
    last_seen: float
    props: dict[str, str] = dataclasses.field(default_factory=dict)
    transform: Transform = dataclasses.field(default_factory=Transform)
    track: list[TrackPoint] = dataclasses.field(default_factory=list)
    removed_at: float | None = None
    transform_notation: int | None = None

    @property
    def name(self) -> str | None:
        return self.props.get("Name")

    @property
    def tags(self) -> frozenset[str]:
        """``Type`` tags, e.g. ``Medium+Air+FixedWing`` -> {Medium, Air, FixedWing}."""
        t = self.props.get("Type", "")
        return frozenset(p.strip() for p in t.split("+") if p.strip())

    @property
    def parent(self) -> str | None:
        p = self.props.get("Parent")
        return _norm_id(p) if p else None

    def has_tag(self, *tags: str) -> bool:
        return any(t in self.tags for t in tags)

    def position_at(self, t: float) -> TrackPoint | None:
        """Linearly interpolated position at ``t``; clamped to the first/last sample."""
        if not self.track:
            return None
        times = [p.t for p in self.track]
        i = bisect.bisect_left(times, t)
        if i <= 0:
            return self.track[0]
        if i >= len(self.track):
            return self.track[-1]
        a, b = self.track[i - 1], self.track[i]
        if b.t == a.t:
            return b
        f = (t - a.t) / (b.t - a.t)
        return TrackPoint(
            t=t,
            lon=a.lon + (b.lon - a.lon) * f,
            lat=a.lat + (b.lat - a.lat) * f,
            alt=a.alt + (b.alt - a.alt) * f,
        )


@dataclasses.dataclass(frozen=True)
class AcmiEvent:
    """``0,Event=Type|...`` at time ``t``.

    ``object_ids``: leading id parameters (object events); ``text``: the trailing text parameter;
    ``params``: ``Key:Value`` parameters (``Timeout`` weapon events).
    """

    t: float
    kind: str
    object_ids: tuple[str, ...] = ()
    text: str = ""
    params: dict[str, str] = dataclasses.field(default_factory=dict)


@dataclasses.dataclass
class AcmiHeader:
    file_type: str | None = None
    file_version: str | None = None
    globals: dict[str, str] = dataclasses.field(default_factory=dict)

    @property
    def reference_time(self) -> datetime | None:
        raw = self.globals.get("ReferenceTime")
        if not raw:
            return None
        try:
            return datetime.fromisoformat(raw.replace("Z", "+00:00"))
        except ValueError:
            return None

    @property
    def reference_longitude(self) -> float:
        return _float_or(self.globals.get("ReferenceLongitude"), 0.0)

    @property
    def reference_latitude(self) -> float:
        return _float_or(self.globals.get("ReferenceLatitude"), 0.0)


@dataclasses.dataclass
class Recording:
    header: AcmiHeader
    objects: dict[str, AcmiObject]
    events: list[AcmiEvent]
    start_time: float
    end_time: float
    malformed_lines: list[tuple[int, str]] = dataclasses.field(default_factory=list)
    comment_lines: int = 0

    def events_of(self, kind: str) -> list[AcmiEvent]:
        return [e for e in self.events if e.kind == kind]


# --------------------------------------------------------------------------- reading


def read_acmi_text(path: Path) -> str:
    """Return the ACMI text of ``path``; zip containers (any extension) are unpacked."""
    data = path.read_bytes()
    if data[:4] == b"PK\x03\x04":
        try:
            with zipfile.ZipFile(io.BytesIO(data)) as zf:
                names = [n for n in zf.namelist() if not n.endswith("/")]
                if not names:
                    raise AcmiError(f"{path}: empty zip archive")
                pick = next((n for n in names if n.lower().endswith(".acmi")), names[0])
                data = zf.read(pick)
        except zipfile.BadZipFile as exc:
            raise AcmiError(f"{path}: corrupt zip archive ({exc})") from None
    if data[:2] in (b"7z", b"7z\xbc\xaf"):
        raise AcmiError(f"{path}: 7z-compressed ACMI is not supported; unpack it first")
    return data.decode("utf-8-sig", errors="replace")


def iter_logical_lines(text: str) -> Iterator[tuple[int, str]]:
    """Yield ``(first_line_no, line)``; a trailing backslash continues the line (joined by \\n)."""
    buf: list[str] = []
    start = 0
    for no, raw in enumerate(text.splitlines(), start=1):
        line = raw.rstrip("\r")
        if not buf:
            start = no
        if line.endswith("\\") and not line.endswith("\\\\"):
            buf.append(line[:-1])
            continue
        buf.append(line)
        yield start, "\n".join(buf)
        buf = []
    if buf:
        yield start, "\n".join(buf)


def split_fields(line: str) -> list[str]:
    """Split on commas not escaped with a backslash; ``\\,`` becomes ``,``."""
    out: list[str] = []
    cur: list[str] = []
    i = 0
    n = len(line)
    while i < n:
        c = line[i]
        if c == "\\" and i + 1 < n and line[i + 1] in ",\\":
            cur.append(line[i + 1])
            i += 2
            continue
        if c == ",":
            out.append("".join(cur))
            cur = []
        else:
            cur.append(c)
        i += 1
    out.append("".join(cur))
    return out


# --------------------------------------------------------------------------- parsing


def parse_acmi_file(path: Path, *, min_sample_dt: float = 0.0) -> Recording:
    return parse_acmi(read_acmi_text(path), min_sample_dt=min_sample_dt)


def parse_acmi(
    source: str | Iterable[str], *, min_sample_dt: float = 0.0, strict_header: bool = True
) -> Recording:
    """Parse ACMI text (a string, or an iterable of physical lines).

    ``min_sample_dt`` thins tracks: a new sample is kept only if at least that many seconds after
    the previous one (the latest transform is always tracked; removal keeps a final sample).
    ``strict_header`` raises :class:`AcmiError` when ``FileType`` is not ``text/acmi/tacview``.
    """
    text = source if isinstance(source, str) else "\n".join(source)
    text = text.removeprefix("﻿")
    header = AcmiHeader()
    objects: dict[str, AcmiObject] = {}
    events: list[AcmiEvent] = []
    malformed: list[tuple[int, str]] = []
    comments = 0
    t = 0.0
    t_min: float | None = None
    t_max = 0.0
    dirty: set[str] = set()

    def flush_samples() -> None:
        for oid in dirty:
            obj = objects[oid]
            tr = obj.transform
            if tr.lon is None or tr.lat is None:
                continue
            pt = TrackPoint(
                t=obj.last_seen,
                lon=tr.lon + header.reference_longitude,
                lat=tr.lat + header.reference_latitude,
                alt=tr.alt if tr.alt is not None else 0.0,
                u=tr.u,
                v=tr.v,
            )
            if obj.track and obj.track[-1].t >= pt.t:
                obj.track[-1] = pt
            elif obj.track and pt.t - obj.track[-1].t < min_sample_dt:
                continue
            else:
                obj.track.append(pt)
        dirty.clear()

    for no, line in iter_logical_lines(text):
        s = line.strip()
        if not s:
            continue
        if s.startswith("//"):
            comments += 1
            continue
        if s.startswith("FileType="):
            header.file_type = s.split("=", 1)[1].strip()
            continue
        if s.startswith("FileVersion="):
            header.file_version = s.split("=", 1)[1].strip()
            continue
        if s.startswith("#"):
            try:
                new_t = float(s[1:])
            except ValueError:
                malformed.append((no, line))
                continue
            flush_samples()
            t = new_t
            t_min = t if t_min is None else min(t_min, t)
            t_max = max(t_max, t)
            continue
        if s.startswith("-"):
            oid = _norm_id(s[1:])
            obj = objects.get(oid)
            if obj is None or not _is_hex(oid):
                malformed.append((no, line))
                continue
            dirty.add(oid)
            flush_samples()
            obj.removed_at = t
            obj.last_seen = max(obj.last_seen, t)
            continue
        fields = split_fields(line)
        oid = _norm_id(fields[0])
        if not _is_hex(oid):
            malformed.append((no, line))
            continue
        if oid == GLOBAL_ID:
            for f in fields[1:]:
                key, sep, value = f.partition("=")
                if not sep:
                    continue
                if key == "Event":
                    ev = _parse_event(t, value)
                    if ev is None:
                        malformed.append((no, line))
                    else:
                        events.append(ev)
                else:
                    header.globals[key] = value
            continue
        obj = objects.get(oid)
        if obj is None or obj.removed_at is not None:
            # A re-used id after removal starts a fresh object (keeps the latest lifespan).
            obj = AcmiObject(id=oid, first_seen=t, last_seen=t)
            objects[oid] = obj
        obj.last_seen = max(obj.last_seen, t)
        bad = False
        for f in fields[1:]:
            key, sep, value = f.partition("=")
            if not sep:
                bad = True
                continue
            if key == "T":
                if _apply_transform(obj, value):
                    dirty.add(oid)
                else:
                    bad = True
            else:
                obj.props[key] = value
        if bad:
            malformed.append((no, line))
    flush_samples()

    if strict_header and header.file_type != "text/acmi/tacview":
        raise AcmiError(f"not an ACMI text recording (FileType={header.file_type!r})")
    return Recording(
        header=header,
        objects=objects,
        events=events,
        start_time=t_min if t_min is not None else 0.0,
        end_time=t_max,
        malformed_lines=malformed,
        comment_lines=comments,
    )


def _apply_transform(obj: AcmiObject, value: str) -> bool:
    parts = value.split("|")
    names = TRANSFORM_FIELDS.get(len(parts))
    if names is None:
        return False
    obj.transform_notation = len(parts)
    for name, raw in zip(names, parts, strict=True):
        raw = raw.strip()
        if not raw:
            continue  # omitted component keeps its previous value
        try:
            num = float(raw)
        except ValueError:
            return False
        if not math.isfinite(num):
            return False
        setattr(obj.transform, name, num)
    return True


def _parse_event(t: float, value: str) -> AcmiEvent | None:
    parts = value.split("|")
    kind = parts[0].strip()
    if not kind:
        return None
    rest = parts[1:]
    if kind in _TEXT_EVENTS:
        return AcmiEvent(t=t, kind=kind, text="|".join(rest))
    if kind == "Timeout" or (rest and all(":" in p for p in rest if p)):
        params: dict[str, str] = {}
        for p in rest:
            k, sep, v = p.partition(":")
            if sep:
                params[k.strip()] = v.strip()
        ids = tuple(_norm_id(params[k]) for k in ("SourceId", "TargetId") if k in params)
        return AcmiEvent(t=t, kind=kind, object_ids=ids, params=params)
    if not rest:
        return AcmiEvent(t=t, kind=kind)
    if len(rest) == 1:
        only = rest[0].strip()
        if kind in _OBJECT_EVENTS and _is_hex(_norm_id(only)):
            return AcmiEvent(t=t, kind=kind, object_ids=(_norm_id(only),))
        return AcmiEvent(t=t, kind=kind, text=rest[0])
    ids = tuple(_norm_id(p) for p in rest[:-1] if p.strip())
    return AcmiEvent(t=t, kind=kind, object_ids=ids, text=rest[-1])


def _norm_id(raw: str) -> str:
    s = raw.strip().lower()
    stripped = s.lstrip("0")
    return stripped if stripped else ("0" if s else "")


def _is_hex(s: str) -> bool:
    return bool(s) and len(s) <= 16 and all(c in "0123456789abcdef" for c in s)


def _float_or(raw: str | None, default: float) -> float:
    if raw is None:
        return default
    try:
        return float(raw)
    except ValueError:
        return default
