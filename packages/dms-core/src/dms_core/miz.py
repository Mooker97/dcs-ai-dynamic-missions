"""In-memory .miz (DCS mission zip) reader/writer.

Lua tables are parsed lazily with :mod:`dms_core.luaio` and only re-serialized when changed;
every other entry is written back with identical content and compression type.
Never round-trip user missions through pydcs: it is lossy.
"""

from __future__ import annotations

import io
import os
import re
import tempfile
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, NamedTuple

from dms_core import luaio

__all__ = ["TABLES", "GroupRef", "MizError", "MizFile", "NextIds"]

L10N = "l10n/DEFAULT/"

#: Lua-table entries of a .miz: archive path -> global variable name.
TABLES: dict[str, str] = {
    "mission": "mission",
    "options": "options",
    "warehouses": "warehouses",
    L10N + "dictionary": "dictionary",
    L10N + "mapResource": "mapResource",
}
_ALIASES = {"dictionary": L10N + "dictionary", "mapResource": L10N + "mapResource"}
_CATEGORIES = ("plane", "helicopter", "vehicle", "ship", "static")
_KEY_NUM = re.compile(r"^(?:DictKey|ResKey)_.*_(\d+)$")
_TRIGGER_CONDITIONS = ("time_more", "mission_start")


class MizError(ValueError):
    """Raised for malformed missions or invalid operations."""


class NextIds(NamedTuple):
    group_id: int
    unit_id: int


@dataclass
class GroupRef:
    """A group found in ``mission["coalition"]``. ``group`` is the live dict (edits stick)."""

    coalition: str
    country: str
    category: str
    group: dict[Any, Any]


@dataclass
class _Entry:
    info: zipfile.ZipInfo
    data: bytes


def _table_path(name: str) -> str:
    path = _ALIASES.get(name, name)
    if path not in TABLES:
        raise KeyError(f"{name!r} is not a Lua table entry; expected one of {sorted(TABLES)}")
    return path


def _index_dict(parent: dict[Any, Any], key: str) -> dict[Any, Any]:
    """Return ``parent[key]`` as an int-keyed dict, creating or converting it as needed."""
    value = parent.get(key)
    if value is None:
        value = {}
    elif isinstance(value, list):
        value = {i + 1: v for i, v in enumerate(value)}
    elif not isinstance(value, dict):
        raise MizError(f"expected a table at {key!r}, got {type(value).__name__}")
    parent[key] = value
    return value


def _next_index(*tables: dict[Any, Any]) -> int:
    ints = [k for t in tables for k in t if isinstance(k, int) and not isinstance(k, bool)]
    return max(ints, default=0) + 1


class MizFile:
    """A .miz archive held in memory."""

    def __init__(self, data: bytes | None = None, path: str | os.PathLike[str] | None = None):
        self.path = Path(path) if path is not None else None
        self._entries: dict[str, _Entry] = {}
        self._tables: dict[str, Any] = {}
        self._dirty: set[str] = set()
        if data is not None:
            with zipfile.ZipFile(io.BytesIO(data)) as zf:
                for info in zf.infolist():
                    if info.is_dir():
                        continue
                    self._entries[info.filename] = _Entry(info, zf.read(info))

    @classmethod
    def open(cls, path: str | os.PathLike[str]) -> MizFile:
        return cls(Path(path).read_bytes(), path)

    # ------------------------------------------------------------ raw entries

    def files(self) -> list[str]:
        return list(self._entries)

    def read_bytes(self, path: str) -> bytes:
        if path in self._dirty:
            return self._serialize(path)
        try:
            return self._entries[path].data
        except KeyError:
            raise KeyError(f"{path!r} not in archive") from None

    def write_bytes(self, path: str, data: bytes) -> None:
        entry = self._entries.get(path)
        if entry is None:
            info = zipfile.ZipInfo(path, date_time=_now())
            info.compress_type = zipfile.ZIP_DEFLATED
            self._entries[path] = _Entry(info, bytes(data))
        else:
            entry.data = bytes(data)
        self._tables.pop(path, None)
        self._dirty.discard(path)

    # ------------------------------------------------------------ Lua tables

    def table(self, name: str) -> Any:
        """Parsed table for ``mission``, ``options``, ``warehouses``, ``dictionary`` or
        ``mapResource`` (full archive paths also accepted). Mutations count as edits only
        after :meth:`set_table` or :meth:`mark_dirty`; the helper methods do this themselves."""
        path = _table_path(name)
        if path not in self._tables:
            if path not in self._entries:
                raise KeyError(f"{path!r} not in archive")
            self._tables[path] = luaio.loads(self._entries[path].data, TABLES[path])
        return self._tables[path]

    def set_table(self, name: str, data: Any) -> None:
        path = _table_path(name)
        self._tables[path] = data
        self._dirty.add(path)
        if path not in self._entries:
            info = zipfile.ZipInfo(path, date_time=_now())
            info.compress_type = zipfile.ZIP_DEFLATED
            self._entries[path] = _Entry(info, b"")

    def mark_dirty(self, name: str) -> None:
        """Flag a table mutated in place so :meth:`save` re-serializes it."""
        self.set_table(name, self.table(name))

    def _serialize(self, path: str) -> bytes:
        text = luaio.dumps(self._tables[path], TABLES[path])
        return text.encode("utf-8", "surrogateescape")

    # ------------------------------------------------------------ resources & triggers

    def _alloc_key_number(self) -> int:
        mission = self.table("mission")
        used = [int(mission.get("maxDictId", 0) or 0)]
        for key in self.table("mapResource"):
            m = _KEY_NUM.match(str(key))
            if m:
                used.append(int(m.group(1)))
        if L10N + "dictionary" in self._entries:
            for key in self.table("dictionary"):
                m = _KEY_NUM.match(str(key))
                if m:
                    used.append(int(m.group(1)))
        n = max(used) + 1
        mission["maxDictId"] = n
        self.mark_dirty("mission")
        return n

    def add_resource(
        self, source: str | os.PathLike[str] | bytes, arcname: str | None = None
    ) -> str:
        """Store a file under ``l10n/DEFAULT/`` and register it in mapResource.

        Returns its ``ResKey_Action_N`` key. If a key already maps to the same file name, the
        file is replaced and that key reused.
        """
        if isinstance(source, bytes):
            if not arcname:
                raise MizError("arcname is required when adding raw bytes")
            data = source
        else:
            data = Path(source).read_bytes()
            arcname = arcname or Path(source).name
        assert arcname is not None
        filename = arcname[len(L10N) :] if arcname.startswith(L10N) else arcname
        if not filename or "/" in filename or "\\" in filename:
            raise MizError(f"invalid resource name {arcname!r}")
        if L10N + "mapResource" not in self._entries:
            self.set_table("mapResource", {})
        map_res = self.table("mapResource")
        self.write_bytes(L10N + filename, data)
        for key, value in map_res.items():
            if value == filename:
                return str(key)
        key = f"ResKey_Action_{self._alloc_key_number()}"
        map_res[key] = filename
        self.mark_dirty("mapResource")
        return key

    def add_do_script_file_trigger(
        self,
        res_key: str,
        comment: str,
        condition: str = "time_more",
        seconds: int = 1,
    ) -> int:
        """Add a run-once DO SCRIPT FILE trigger; returns its 1-based trigger index.

        ``condition="time_more"`` -> ONCE + TIME MORE(seconds) (``c_time_after``);
        ``condition="mission_start"`` -> MISSION START with no conditions.
        Updates ``trigrules`` (Mission Editor data) and the compiled ``trig`` strings that
        DCS actually executes.
        """
        if condition not in _TRIGGER_CONDITIONS:
            raise MizError(f"condition must be one of {_TRIGGER_CONDITIONS}, got {condition!r}")
        if res_key not in self.table("mapResource"):
            raise MizError(f"{res_key!r} is not registered in mapResource")
        mission = self.table("mission")
        rules_tbl = _index_dict(mission, "trigrules")
        trig = mission.get("trig")
        if not isinstance(trig, dict):
            trig = {}
            mission["trig"] = trig
        actions = _index_dict(trig, "actions")
        conditions = _index_dict(trig, "conditions")
        func = _index_dict(trig, "func")
        func_startup = _index_dict(trig, "funcStartup")
        flag = _index_dict(trig, "flag")
        for extra in ("events", "custom", "customStartup"):
            _index_dict(trig, extra)
        idx = _next_index(rules_tbl, actions, conditions, func, func_startup, flag)

        action_rule = {"predicate": "a_do_script_file", "file": res_key}
        call = f'a_do_script_file(getValueResourceByKey("{res_key}"));'
        run = f"if mission.trig.conditions[{idx}]() then mission.trig.actions[{idx}]() end"
        if condition == "time_more":
            rules_tbl[idx] = {
                "predicate": "triggerOnce",
                "comment": comment,
                "eventlist": "",
                "rules": {1: {"predicate": "c_time_after", "seconds": seconds}},
                "actions": {1: action_rule},
            }
            conditions[idx] = f"return(c_time_after({seconds}) )"
            actions[idx] = f"{call} mission.trig.func[{idx}]=nil;"
            func[idx] = run
        else:
            rules_tbl[idx] = {
                "predicate": "triggerStart",
                "comment": comment,
                "eventlist": "",
                "rules": {},
                "actions": {1: action_rule},
            }
            conditions[idx] = "return(true)"
            actions[idx] = call
            func_startup[idx] = run
        flag[idx] = True
        self.mark_dirty("mission")
        return idx

    # ------------------------------------------------------------ groups

    def _iter_groups(self) -> list[GroupRef]:
        refs: list[GroupRef] = []
        coalitions = self.table("mission").get("coalition") or {}
        for side, side_tbl in coalitions.items():
            countries = side_tbl.get("country") if isinstance(side_tbl, dict) else None
            if not isinstance(countries, (dict, list)):
                continue
            for country in countries.values() if isinstance(countries, dict) else countries:
                if not isinstance(country, dict):
                    continue
                for cat in _CATEGORIES:
                    groups = (country.get(cat) or {}).get("group")
                    if isinstance(groups, list):
                        groups = dict(enumerate(groups, 1))
                    if not isinstance(groups, dict):
                        continue
                    for grp in groups.values():
                        if isinstance(grp, dict):
                            refs.append(GroupRef(str(side), str(country.get("name", "")), cat, grp))
        return refs

    def next_ids(self) -> NextIds:
        """Next free groupId and unitId (max existing + 1)."""
        max_g = max_u = 0
        for ref in self._iter_groups():
            gid = ref.group.get("groupId")
            if isinstance(gid, int):
                max_g = max(max_g, gid)
            units = ref.group.get("units") or {}
            for unit in units.values() if isinstance(units, dict) else units:
                uid = unit.get("unitId") if isinstance(unit, dict) else None
                if isinstance(uid, int):
                    max_u = max(max_u, uid)
        return NextIds(max_g + 1, max_u + 1)

    def find_group(self, name: str) -> GroupRef | None:
        for ref in self._iter_groups():
            if ref.group.get("name") == name:
                return ref
        return None

    # ------------------------------------------------------------ save

    def to_bytes(self) -> bytes:
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w") as zf:
            for path, entry in self._entries.items():
                data = self._serialize(path) if path in self._dirty else entry.data
                src = entry.info
                info = zipfile.ZipInfo(path, date_time=src.date_time)
                info.compress_type = src.compress_type
                info.external_attr = src.external_attr
                info.create_system = src.create_system
                info.comment = src.comment
                zf.writestr(info, data)
        return buf.getvalue()

    def save(self, path: str | os.PathLike[str] | None = None) -> Path:
        """Write the archive (atomically) to *path*, defaulting to the opened path."""
        target = Path(path) if path is not None else self.path
        if target is None:
            raise MizError("no path given and MizFile was not opened from a file")
        payload = self.to_bytes()
        target.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix=".miz-", dir=target.parent)
        try:
            with os.fdopen(fd, "wb") as fh:
                fh.write(payload)
            os.replace(tmp, target)
        except BaseException:
            if os.path.exists(tmp):
                os.unlink(tmp)
            raise
        return target


def _now() -> tuple[int, int, int, int, int, int]:
    import time

    t = time.localtime()
    return (t.tm_year, t.tm_mon, t.tm_mday, t.tm_hour, t.tm_min, t.tm_sec)
