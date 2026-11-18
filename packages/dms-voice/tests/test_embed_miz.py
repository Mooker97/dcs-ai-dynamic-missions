"""Voice -> .miz: rendered clips land in l10n/DEFAULT, mapResource and the sound keeper trigger.

Runs the real pipeline offline: PlaceholderSynth (no API key) -> radio FX -> cache -> manifest ->
plan_mission -> build_from_plan -> check_miz, on the viper-detachment m01 mission files.
"""

from __future__ import annotations

import zipfile
from pathlib import Path
from typing import Any

import pytest
import yaml  # type: ignore[import-untyped,unused-ignore]
from dms_core.miz import MizFile
from dms_core.schemas import BeatSheet, MissionSpec, StoryBible, VoiceLineSet
from dms_gen.builder import build_from_plan  # type: ignore[import-untyped,unused-ignore]
from dms_gen.check import check_miz  # type: ignore[import-untyped,unused-ignore]
from dms_gen.planner import (  # type: ignore[import-untyped,unused-ignore]
    plan_mission,
    write_runtime_config,
)
from dms_voice.cache import TTSCache
from dms_voice.render import PLACEHOLDER_MODEL, PlaceholderSynth, render_lines

REPO = Path(__file__).resolve().parents[3]
CAMPAIGN = REPO / "campaigns" / "viper-detachment"
M01 = CAMPAIGN / "missions" / "m01-broken-umbrella"
VOICED_BEATS = {"mission_start", "magic_checkin"}  # a subset keeps ffmpeg time low


def _yaml(p: Path) -> Any:
    return yaml.safe_load(p.read_text(encoding="utf-8"))


def _arr(t: Any) -> list[Any]:
    if not t:
        return []
    return [t[k] for k in sorted(k for k in t if isinstance(k, int))]


@pytest.fixture(scope="module")
def built(tmp_path_factory: pytest.TempPathFactory) -> dict[str, Any]:
    if not (M01 / "mission-spec.yaml").is_file():
        pytest.skip("viper-detachment m01 not present")
    tmp = tmp_path_factory.mktemp("voice-embed")
    spec = MissionSpec.model_validate(_yaml(M01 / "mission-spec.yaml"))
    beats = BeatSheet.model_validate(_yaml(M01 / "beats.yaml"))
    lines = VoiceLineSet.model_validate(_yaml(M01 / "lines.yaml"))
    bible = StoryBible.model_validate(_yaml(CAMPAIGN / "bible.yaml"))
    voiced = [ln for ln in lines.lines if ln.beat in VOICED_BEATS]
    assert len(voiced) >= 6
    manifest = render_lines(
        voiced,
        {},
        tmp / "voice",
        model=PLACEHOLDER_MODEL,
        client=PlaceholderSynth(),
        cache=TTSCache(tmp / "cache"),
    )
    dms = tmp / "dms.lua"
    dms.write_text('DMS = DMS or {}\nenv.info("[DMS] dummy runtime")\n', encoding="utf-8")
    plan = plan_mission(
        spec,
        beats,
        lines,
        voice_manifest=tmp / "voice" / "manifest.json",
        seed=7,
        bible=bible,
        dms_lua=str(dms),
    )
    write_runtime_config(plan, tmp)
    out = build_from_plan(plan, tmp / "m01-voiced.miz", base_dir=tmp)
    return {"out": out, "plan": plan, "manifest": manifest, "lines": lines}


def test_placeholder_manifest(built: dict[str, Any]) -> None:
    for lid, m in built["manifest"].items():
        assert m["file"] == f"{lid}.ogg"
        assert 0.8 <= m["dur_sec"] <= 13.0


def test_ogg_files_embedded_in_l10n_default(built: dict[str, Any]) -> None:
    with zipfile.ZipFile(built["out"]) as z:
        names = set(z.namelist())
        for m in built["manifest"].values():
            arc = f"l10n/DEFAULT/{m['file']}"
            assert arc in names
            assert z.read(arc)[:4] == b"OggS"


def test_map_resource_and_keeper_reference_every_clip(built: dict[str, Any]) -> None:
    miz = MizFile.open(built["out"])
    res = miz.table("mapResource")
    files = {m["file"] for m in built["manifest"].values()}
    by_file = {v: k for k, v in res.items()}
    assert files <= set(by_file), files - set(by_file)
    mission = miz.table("mission")
    rules = _arr(mission["trigrules"])
    keeper = [r for r in rules if "keep sound" in str(r.get("comment", ""))]
    assert len(keeper) == 1
    acts = _arr(keeper[0]["actions"])
    assert {a["predicate"] for a in acts} == {"a_out_sound"}
    assert {res[a["file"]] for a in acts} == files
    cond = _arr(keeper[0]["rules"])
    assert [c["predicate"] for c in cond] == ["c_flag_equals"]  # never true: flag is never set
    # the compiled trig strings carry the keeper too (DCS runs `trig`, not `trigrules`)
    idx = rules.index(keeper[0]) + 1
    assert all(a["file"] in mission["trig"]["actions"][idx] for a in acts)


def test_runtime_voice_map_files_and_durations(built: dict[str, Any]) -> None:
    voice = built["plan"].runtime.voice
    manifest = built["manifest"]
    for ln in built["lines"].lines:
        entry = voice[ln.id]
        if ln.id in manifest:
            assert entry.file == manifest[ln.id]["file"]
            assert entry.dur_sec == pytest.approx(manifest[ln.id]["dur_sec"])
        else:
            assert not entry.file  # subtitle only


def test_check_miz_ok(built: dict[str, Any]) -> None:
    rep = check_miz(built["out"])
    assert rep.ok, [i for i in rep.issues if i.severity == "error"]
    assert not [i for i in rep.issues if i.code == "voice_file_missing"]
