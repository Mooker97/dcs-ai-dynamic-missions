from __future__ import annotations

import zipfile
from pathlib import Path

import pytest
from dms_tacview.acmi import (
    AcmiError,
    iter_logical_lines,
    parse_acmi,
    parse_acmi_file,
    split_fields,
)

FIX = Path(__file__).parent / "fixtures"
VIPER = FIX / "viper_strike.txt.acmi"


def test_header_and_globals() -> None:
    rec = parse_acmi_file(VIPER)
    h = rec.header
    assert h.file_type == "text/acmi/tacview"
    assert h.file_version == "2.2"
    assert h.reference_longitude == 41.0
    assert h.reference_latitude == 42.0
    assert h.reference_time is not None and h.reference_time.hour == 8
    assert h.globals["Briefing"] == "Find the convoy, kill the trucks"
    assert h.globals["Comments"] == "Line one of the comments\nline two of the comments"
    assert rec.start_time == 0.0 and rec.end_time == 150.0
    assert rec.comment_lines == 3


def test_malformed_lines_are_skipped_not_fatal() -> None:
    rec = parse_acmi_file(VIPER)
    assert [line for _, line in rec.malformed_lines] == ["xyz,Name=Broken line"]


def test_reference_offsets_and_delta_transform() -> None:
    rec = parse_acmi_file(VIPER)
    p = rec.objects["101"]
    # 9-component notation, then only lon + alt updated at #5
    assert p.transform_notation == 9
    t5 = next(pt for pt in p.track if pt.t == 5)
    assert t5.lon == pytest.approx(41.505)
    assert t5.lat == pytest.approx(42.2)  # kept from #0
    assert t5.alt == 60
    assert p.transform.yaw == 90 and p.transform.heading == 90
    # 5-component U/V
    farp = rec.objects["501"]
    assert farp.transform_notation == 5
    assert (farp.transform.u, farp.transform.v) == (12000, -3000)
    # 6-component wingman: lat unchanged across deltas
    wing = rec.objects["102"]
    assert wing.transform_notation == 6
    assert wing.track[-1].lat == pytest.approx(42.2)


def test_props_and_lifespans() -> None:
    rec = parse_acmi_file(VIPER)
    mig = rec.objects["301"]
    assert mig.props["Pilot"] == "Fulcrum 1"
    assert mig.tags == frozenset({"Air", "FixedWing"})
    assert (mig.first_seen, mig.removed_at) == (30, 71)
    assert rec.objects["401"].parent == "101"
    assert rec.objects["102"].removed_at == 130
    assert rec.objects["101"].removed_at is None


def test_events() -> None:
    rec = parse_acmi_file(VIPER)
    kinds = [e.kind for e in rec.events]
    assert kinds == [
        "TakenOff",
        "Message",
        "Destroyed",
        "Bookmark",
        "Landed",
        "Timeout",
        "Destroyed",
    ]
    taken = rec.events[0]
    assert taken.object_ids == ("101",) and taken.text.startswith("Mooker has taken off")
    destroyed = rec.events_of("Destroyed")
    assert [(e.t, e.object_ids) for e in destroyed] == [(70, ("301",)), (141, ("203",))]
    assert rec.events_of("Bookmark")[0].text == "SA-8 launch"
    to = rec.events_of("Timeout")[0]
    assert to.params["Outcome"] == "Kill" and to.object_ids == ("101", "203")


def test_zip_container(tmp_path: Path) -> None:
    z = tmp_path / "flight.zip.acmi"
    with zipfile.ZipFile(z, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("flight.txt.acmi", VIPER.read_bytes())
    a = parse_acmi_file(z)
    b = parse_acmi_file(VIPER)
    assert a.objects.keys() == b.objects.keys()
    assert a.objects["101"].track == b.objects["101"].track


def test_bom_crlf_and_leading_zero_ids() -> None:
    text = (
        "﻿FileType=text/acmi/tacview\r\nFileVersion=2.2\r\n#0\r\n"
        "00A1,T=1|2|3,Name=X\r\n#1.5\r\n-a1\r\n"
    )
    rec = parse_acmi(text)
    assert rec.objects["a1"].removed_at == 1.5
    assert rec.objects["a1"].track[0].lon == 1.0


def test_min_sample_dt_thins_tracks() -> None:
    lines = ["FileType=text/acmi/tacview", "FileVersion=2.2"]
    for i in range(100):
        lines += [f"#{i * 0.1:.1f}", f"1,T={i * 0.001}|0|1000"]
    full = parse_acmi(lines)
    thin = parse_acmi(lines, min_sample_dt=1.0)
    assert len(full.objects["1"].track) == 100
    assert 9 <= len(thin.objects["1"].track) <= 11


def test_strict_header() -> None:
    with pytest.raises(AcmiError):
        parse_acmi("#0\n1,T=1|2|3\n")
    assert parse_acmi("#0\n1,T=1|2|3\n", strict_header=False).objects["1"].track


def test_split_and_continuation() -> None:
    assert split_fields(r"1,Name=a\,b,Pilot=c") == ["1", "Name=a,b", "Pilot=c"]
    assert list(iter_logical_lines("a\\\nb\nc")) == [(1, "a\nb"), (3, "c")]


def test_bad_transform_is_malformed() -> None:
    rec = parse_acmi("FileType=text/acmi/tacview\nFileVersion=2.2\n#0\n1,T=1|2\n2,T=1|x|3\n")
    assert len(rec.malformed_lines) == 2
