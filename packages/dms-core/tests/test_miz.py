"""Tests for dms_core.miz.MizFile against real missions (always on tmp copies)."""

from __future__ import annotations

import io
import zipfile
from pathlib import Path

import pytest
from dms_core.luaio import loads
from dms_core.miz import TABLES, MizError, MizFile


def _entries(path: Path) -> dict[str, tuple[int, bytes]]:
    with zipfile.ZipFile(path) as zf:
        return {i.filename: (i.compress_type, zf.read(i)) for i in zf.infolist()}


def test_open_save_unchanged_is_identical(miz_path: Path, tmp_path: Path) -> None:
    out = tmp_path / "out.miz"
    MizFile.open(miz_path).save(out)
    assert _entries(out) == _entries(miz_path)  # same names, order, compression, bytes
    with zipfile.ZipFile(out) as a, zipfile.ZipFile(miz_path) as b:
        assert a.namelist() == b.namelist()


def test_parse_all_tables_then_save(miz_path: Path, tmp_path: Path) -> None:
    miz = MizFile.open(miz_path)
    originals = {p: miz.table(p) for p in TABLES if p in miz.files()}
    assert "mission" in originals
    for path, data in originals.items():
        miz.set_table(path, data)  # force re-serialization of every table
    out = miz.save(tmp_path / "out.miz")
    src, dst = _entries(miz_path), _entries(out)
    assert list(src) == list(dst)
    for name, (ctype, data) in src.items():
        assert dst[name][0] == ctype
        if name in TABLES:
            assert loads(dst[name][1], TABLES[name]) == loads(data, TABLES[name])
        else:
            assert dst[name][1] == data, f"untouched entry {name} changed"


def test_resource_and_trigger(miz_path: Path, tmp_path: Path) -> None:
    miz = MizFile.open(miz_path)
    before_trig = len(miz.table("mission").get("trigrules") or {})
    key = miz.add_resource(b"env.info('hello from DMS')\n", "dms_test.lua")
    assert key.startswith("ResKey_Action_")
    key2 = miz.add_resource(b"-- second\n", "l10n/DEFAULT/dms_two.lua")
    assert key2 != key
    assert miz.add_resource(b"-- replaced\n", "dms_test.lua") == key  # same file -> same key
    idx = miz.add_do_script_file_trigger(key, "DMS init", seconds=3)
    idx2 = miz.add_do_script_file_trigger(key2, "DMS start", condition="mission_start")
    assert idx == before_trig + 1 and idx2 == idx + 1
    out = miz.save(tmp_path / "out.miz")

    with zipfile.ZipFile(out) as zf:
        assert zf.read("l10n/DEFAULT/dms_test.lua") == b"-- replaced\n"
        map_res = loads(zf.read("l10n/DEFAULT/mapResource"), "mapResource")
        mission = loads(zf.read("mission"), "mission")
    assert map_res[key] == "dms_test.lua" and map_res[key2] == "dms_two.lua"
    assert mission["maxDictId"] >= int(key2.rsplit("_", 1)[1])

    rule = mission["trigrules"][idx]
    assert rule["predicate"] == "triggerOnce" and rule["comment"] == "DMS init"
    assert rule["rules"][1] == {"predicate": "c_time_after", "seconds": 3}
    assert rule["actions"][1] == {"predicate": "a_do_script_file", "file": key}
    trig = mission["trig"]
    assert trig["conditions"][idx] == "return(c_time_after(3) )"
    assert trig["actions"][idx] == (
        f'a_do_script_file(getValueResourceByKey("{key}")); mission.trig.func[{idx}]=nil;'
    )
    assert trig["func"][idx] == (
        f"if mission.trig.conditions[{idx}]() then mission.trig.actions[{idx}]() end"
    )
    assert trig["flag"][idx] is True

    start = mission["trigrules"][idx2]
    assert start["predicate"] == "triggerStart" and start["rules"] == {}
    assert trig["conditions"][idx2] == "return(true)"
    assert idx2 in trig["funcStartup"] and idx2 not in trig["func"]

    # Existing triggers are untouched.
    orig = loads(_entries(miz_path)["mission"][1], "mission")
    for i, r in (orig.get("trigrules") or {}).items():
        assert mission["trigrules"][i] == r
        assert mission["trig"]["actions"][i] == orig["trig"]["actions"][i]


def test_trigger_requires_registered_key(miz_path: Path) -> None:
    miz = MizFile.open(miz_path)
    with pytest.raises(MizError):
        miz.add_do_script_file_trigger("ResKey_Action_999999", "x")
    key = miz.add_resource(b"x", "x.lua")
    with pytest.raises(MizError):
        miz.add_do_script_file_trigger(key, "x", condition="bogus")
    with pytest.raises(MizError):
        miz.add_resource(b"x")


def test_ids_and_groups(miz_path: Path) -> None:
    miz = MizFile.open(miz_path)
    ids = miz.next_ids()
    assert ids.group_id >= 1 and ids.unit_id >= 1
    refs = miz._iter_groups()
    if not refs:
        assert miz.find_group("nope") is None
        return
    ref = refs[0]
    found = miz.find_group(ref.group["name"])
    assert found is not None and found.group is ref.group
    assert ids.group_id > max(r.group.get("groupId", 0) for r in refs)
    assert miz.find_group("\0definitely-not-a-group") is None


def test_raw_bytes_and_files(miz_path: Path, tmp_path: Path) -> None:
    miz = MizFile.open(miz_path)
    miz.write_bytes("l10n/DEFAULT/extra.txt", b"abc")
    assert "l10n/DEFAULT/extra.txt" in miz.files()
    assert miz.read_bytes("l10n/DEFAULT/extra.txt") == b"abc"
    mission = miz.table("mission")
    mission["dms_marker"] = "x"
    miz.mark_dirty("mission")
    assert b'["dms_marker"] = "x"' in miz.read_bytes("mission")
    with pytest.raises(KeyError):
        miz.read_bytes("nope")
    with pytest.raises(KeyError):
        miz.table("theatre")
    data = miz.to_bytes()
    reopened = MizFile(data)
    assert reopened.table("mission")["dms_marker"] == "x"
    assert zipfile.ZipFile(io.BytesIO(data)).testzip() is None


def test_save_in_place(miz_path: Path) -> None:
    miz = MizFile.open(miz_path)
    miz.add_resource(b"--", "inplace.lua")
    miz.save()
    assert "l10n/DEFAULT/inplace.lua" in MizFile.open(miz_path).files()
