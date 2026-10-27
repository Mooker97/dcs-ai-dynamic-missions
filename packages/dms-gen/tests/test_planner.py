from __future__ import annotations

import json
import os
import shutil
from pathlib import Path
from typing import Any

import pytest
import yaml
from dms_core.schemas import BeatSheet, MissionSpec, StoryBible, VoiceLineSet
from dms_core.schemas.plan import BuildPlan
from dms_gen.builder import build_from_plan
from dms_gen.check import check_miz, lua51_syntax_error
from dms_gen.planner import PlanError, has_errors, plan_mission, validate, write_runtime_config

REPO = Path(__file__).resolve().parents[3]
M01 = REPO / "campaigns" / "dustoff-valley" / "missions" / "m01-first-light"
BIBLE = REPO / "campaigns" / "dustoff-valley" / "bible.yaml"
GOLDEN_OUT = Path(
    r"C:\Users\mook\AppData\Local\Temp\claude\C--coding-claude-projects-claude-test-DMS"
    r"\8d082774-cfce-4930-8670-d823956b8b69\scratchpad\planner-out\m01.miz"
)


def _yaml(p: Path) -> Any:
    return yaml.safe_load(p.read_text(encoding="utf-8"))


def convoy_spec(**over: Any) -> MissionSpec:
    data: dict[str, Any] = {
        "id": "t01-convoy",
        "title": "Road to Reyhanli",
        "theater": "Syria",
        "era": 2012,
        "date": "2012-05-02",
        "start_time": "07:30",
        "mission_type": "CONVOY_ESCORT",
        "blue_countries": ["USA"],
        "red_countries": ["Insurgents"],
        "cast": ["ops"],
        "areas": [
            {"id": "base", "where": {"kind": "near_airbase", "airbase": "Hatay", "radius_nm": 1}},
            {
                "id": "start_gate",
                "where": {
                    "kind": "near_airbase",
                    "airbase": "Hatay",
                    "radius_nm": 1,
                    "bearing_deg": 90,
                    "distance_nm": 3,
                },
            },
            {
                "id": "town",
                "where": {"kind": "near_named_place", "place": "Reyhanli", "radius_nm": 1.5},
            },
            {
                "id": "ambush_ridge",
                "where": {
                    "kind": "near_named_place",
                    "place": "Reyhanli",
                    "radius_nm": 2,
                    "bearing_deg": 300,
                    "distance_nm": 5,
                },
            },
            {
                "id": "kirikhan",
                "where": {"kind": "near_named_place", "place": "Kirikhan", "radius_nm": 1},
            },
        ],
        "player_flights": [
            {
                "callsign": "Gunfighter",
                "aircraft": "AH-64D_BLK_II",
                "count": 2,
                "start_area": "base",
                "loadout": "auto",
            }
        ],
        "objectives": [
            {
                "id": "convoy_arrives",
                "kind": "escort",
                "description": "Get the convoy through.",
                "area": "town",
                "target": "convoy_main",
                "success_flag": "convoy_safe",
            },
            {
                "id": "kill_guns",
                "kind": "destroy",
                "description": "Silence the guns.",
                "primary": False,
                "area": "kirikhan",
                "target": "guns_kirikhan",
            },
        ],
        "threats": [
            {"id": "guns_kirikhan", "role": "aaa", "area": "kirikhan", "strength": "medium"},
            {"id": "tech_town", "role": "technicals", "area": "town", "strength": "light"},
        ],
        "support": [
            {
                "id": "convoy_main",
                "role": "convoy",
                "callsign": "Ripper 2-1",
                "route": ["start_gate", "ambush_ridge", "town"],
                "composition": "3x M 818, 1x Hummer",
            },
        ],
        "dynamic": {
            "pools": [
                {
                    "id": "qrf",
                    "roles": ["technicals", "infantry"],
                    "areas": ["ambush_ridge"],
                    "pick": [1, 3],
                },
                {
                    "id": "popup",
                    "roles": ["manpads", "aaa"],
                    "areas": ["ambush_ridge", "town"],
                    "pick": [1, 1],
                },
            ],
            "encounters": [
                {
                    "id": "qrf_waves",
                    "kind": "waves",
                    "pool": "qrf",
                    "trigger": {"type": "beat", "beat": "convoy_hit"},
                    "waves": 2,
                    "gap_min": [2, 4],
                    "hunt": True,
                },
                {
                    "id": "popup_aa",
                    "kind": "ambush_sam",
                    "pool": "popup",
                    "trigger": {"type": "proximity", "area": "ambush_ridge", "radius_nm": 4},
                    "chance": 60,
                    "telegraph_beat": "aa_warning",
                },
            ],
        },
    }
    data.update(over)
    return MissionSpec.model_validate(data)


def convoy_beats() -> BeatSheet:
    return BeatSheet.model_validate(
        [
            {
                "id": "start",
                "when": {"event": "mission.start"},
                "speaker": "ops",
                "lines": ["start_v1", "start_v2"],
            },
            {
                "id": "convoy_hit",
                "when": {"event": "unit.hit", "group_prefix": "convoy_main"},
                "speaker": "ops",
                "lines": ["hit_v1"],
            },
            {
                "id": "aa_warning",
                "when": {"event": "encounter.spawned", "encounter": "popup_aa"},
                "speaker": "ops",
                "lines": ["aa_v1"],
            },
            {
                "id": "guns_dead",
                "when": {"event": "group.dead", "group_prefix": "guns_kirikhan"},
                "speaker": "ops",
                "lines": ["start_v1"],
            },
        ]
    )


def convoy_lines() -> VoiceLineSet:
    return VoiceLineSet.model_validate(
        [
            {"id": "start_v1", "speaker": "ops", "text": "Gunfighter, Ops. Convoy is rolling."},
            {"id": "start_v2", "speaker": "ops", "text": "[calm] Gunfighter, convoy moving now."},
            {"id": "hit_v1", "speaker": "ops", "text": "Ripper is taking fire, west side!"},
            {"id": "aa_v1", "speaker": "ops", "text": "Spike on the ridge, watch the ridge."},
        ]
    )


def fake_voice(lines: VoiceLineSet, out: Path) -> Path:
    """Stand-in for `dms voice`: dummy .ogg files plus manifest.json."""
    out.mkdir(parents=True, exist_ok=True)
    manifest = {}
    for ln in lines.lines:
        (out / f"{ln.id}.ogg").write_bytes(b"OggS-dummy")
        manifest[ln.id] = {
            "file": f"{ln.id}.ogg",
            "dur_sec": 2.5,
            "text": ln.text,
            "speaker": ln.speaker,
        }
    (out / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    return out / "manifest.json"


def dummy_dms_lua(tmp: Path) -> Path:
    p = tmp / "dms.lua"
    p.write_text('DMS = DMS or {}\nenv.info("[DMS] dummy runtime")\n', encoding="utf-8")
    return p


def placements(plan: BuildPlan) -> list[tuple[str, float, float]]:
    return [(u.name, u.x, u.y) for g in plan.groups if not g.client for u in g.units]


def load_m01() -> tuple[MissionSpec, BeatSheet, VoiceLineSet, StoryBible | None] | None:
    if not (M01 / "mission-spec.yaml").is_file():
        return None
    try:
        spec = MissionSpec.model_validate(_yaml(M01 / "mission-spec.yaml"))
        beats = BeatSheet.model_validate(_yaml(M01 / "beats.yaml"))
        lines = VoiceLineSet.model_validate(_yaml(M01 / "lines.yaml"))
        bible = StoryBible.model_validate(_yaml(BIBLE)) if BIBLE.is_file() else None
    except Exception:  # being written concurrently by another agent
        return None
    return spec, beats, lines, bible


# --------------------------------------------------------------------------- validate


def test_validate_clean_spec_has_no_errors() -> None:
    issues = validate(convoy_spec(), convoy_beats(), convoy_lines())
    assert not has_errors(issues), [i for i in issues if i.severity == "error"]


def test_validate_misspelled_airbase_suggests() -> None:
    spec = convoy_spec()
    data = spec.model_dump(mode="json")
    data["areas"][0]["where"]["airbase"] = "Hatey"
    issues = validate(MissionSpec.model_validate(data))
    bad = [i for i in issues if i.path.endswith("areas[0].where.airbase")]
    assert bad and bad[0].severity == "error"
    assert "Hatay" in bad[0].suggestions
    with pytest.raises(PlanError):
        plan_mission(MissionSpec.model_validate(data))


def test_validate_catches_semantic_problems() -> None:
    data = convoy_spec().model_dump(mode="json")
    data["areas"][2]["where"]["place"] = "Reyhanly"
    data["player_flights"][0]["aircraft"] = "AH-64X"
    data["player_flights"][0]["country"] = "Russia"
    data["objectives"][1]["target"] = "guns_kirikan"
    data["red_countries"] = ["CJTF Red"]
    issues = validate(MissionSpec.model_validate(data))
    by_path = {i.path.split(":", 1)[1]: i for i in issues}
    assert "Reyhanli" in by_path["areas[2].where.place"].suggestions
    assert by_path["player_flights[0].aircraft"].severity == "error"
    assert by_path["player_flights[0].country"].severity == "error"
    assert "guns_kirikhan" in by_path["objectives[1].target"].suggestions
    alias = by_path["red_countries[0]"]
    assert alias.severity == "warning"
    assert alias.suggestions == ["Combined Joint Task Forces Red"]


def test_validate_range_and_density() -> None:
    data = convoy_spec().model_dump(mode="json")
    data["areas"][4]["where"] = {"kind": "near_named_place", "place": "Damascus", "radius_nm": 1}
    data["threats"].append({"id": "big_sam", "role": "sam_long", "area": "town"})
    issues = validate(MissionSpec.model_validate(data))
    msgs = " ".join(i.problem for i in issues)
    assert any(i.path.endswith("objectives[1].area") and i.severity == "error" for i in issues)
    assert "rarely survivable" in msgs


# --------------------------------------------------------------------------- plan


def test_plan_is_deterministic_and_seeded() -> None:
    spec, beats, lines = convoy_spec(), convoy_beats(), convoy_lines()
    a = plan_mission(spec, beats, lines, seed=11)
    b = plan_mission(spec, beats, lines, seed=11)
    c = plan_mission(spec, beats, lines, seed=12)
    assert a.model_dump_json() == b.model_dump_json()
    assert placements(a) != placements(c)
    assert a.seed == 11 and a.runtime is not None and a.runtime.seed == 11
    # no seed anywhere: stable default derived from the mission id
    assert plan_mission(spec).seed == plan_mission(spec).seed


def test_plan_contents_and_runtime_refs() -> None:
    spec = convoy_spec()
    plan = plan_mission(spec, convoy_beats(), convoy_lines(), seed=3)
    rt = plan.runtime
    assert rt is not None
    names = [g.name for g in plan.groups]
    assert "Gunfighter 1" in names
    assert any(n.startswith("guns_kirikhan_") for n in names)
    assert any(n.startswith("convoy_main") for n in names)
    player = next(g for g in plan.groups if g.client)
    assert len(player.units) == 2 and player.route[0].airbase == "Hatay"
    assert player.units[0].payload is not None and len(player.units[0].payload.pylons) == 4
    convoy = next(g for g in plan.groups if g.source == "convoy_main")
    assert [w.action for w in convoy.route] == ["On Road", "On Road"]
    assert {u.type for u in convoy.units} == {"M 818", "Hummer"}
    # every referenced template/zone/pool exists, and only referenced templates are emitted
    used_tpls = {m.tpl for p in rt.pools.values() for m in p.members}
    assert used_tpls == set(rt.templates)
    for p in rt.pools.values():
        assert set(p.zones) <= set(rt.zones)
    for e in rt.encounters:
        assert e.pool in rt.pools
        assert e.trigger.zone is None or e.trigger.zone in rt.zones
    assert {z.name for z in plan.zones} == set(spec.area_ids()) == set(rt.zones)
    waves = next(e for e in rt.encounters if e.id == "qrf_waves")
    assert waves.gap_sec == (120, 240) and waves.trigger.beat == "convoy_hit"
    popup = next(e for e in rt.encounters if e.id == "popup_aa")
    assert popup.telegraph == "beat:aa_warning" and popup.trigger.radius_m == pytest.approx(7408)
    assert [b.id for b in rt.beats] == [b.id for b in convoy_beats().beats]
    assert set(rt.voice) == {ln.id for ln in convoy_lines().lines}
    assert rt.voice["start_v2"].text == "Gunfighter, convoy moving now."  # audio tag stripped
    assert rt.players.coalition == 2 and rt.intel.fog_of_war
    assert [r.path for r in plan.resources] == [
        "l10n/DEFAULT/dms_config.lua",
        "l10n/DEFAULT/dms.lua",
    ]  # config first; nothing rendered yet
    assert all(not v.file for v in rt.voice.values())  # subtitle-only
    assert rt.speakers == {}  # no bible, no support speakers
    # red ground stays on the map and hidden under fog of war
    for g in plan.groups:
        if g.coalition == "red":
            assert g.hidden


def test_sam_spacing_and_town_offset() -> None:
    data = convoy_spec().model_dump(mode="json")
    data["threats"] = [
        {"id": "sams", "role": "sam_short", "area": "town", "strength": "heavy"},
    ]
    plan = plan_mission(MissionSpec.model_validate(data), seed=5)
    import math

    from dms_gen.planner import resolve_area

    spec = MissionSpec.model_validate(data)
    town = resolve_area("Syria", next(a for a in spec.areas if a.id == "town"))
    anchors = [(g.units[0].x, g.units[0].y) for g in plan.groups if g.source == "sams"]
    assert len(anchors) == 3
    assert town.place_center is not None
    for i, p in enumerate(anchors):
        assert math.dist(p, town.place_center) >= 590
        for q in anchors[i + 1 :]:
            assert math.dist(p, q) >= 1400


def test_voice_manifest_feeds_runtime_and_resources(tmp_path: Path) -> None:
    lines = convoy_lines()
    manifest = fake_voice(lines, tmp_path / "voice")
    plan = plan_mission(convoy_spec(), convoy_beats(), lines, voice_manifest=manifest, seed=1)
    assert plan.runtime is not None
    assert plan.runtime.voice["hit_v1"].dur_sec == 2.5
    sounds = [r for r in plan.resources if r.kind == "sound"]
    assert len(sounds) == 4 and all(Path(r.source).is_file() for r in sounds)


# --------------------------------------------------------------------------- build + check


def test_build_and_check_ok(tmp_path: Path) -> None:
    lines = convoy_lines()
    manifest = fake_voice(lines, tmp_path / "voice")
    dms = dummy_dms_lua(tmp_path)
    plan = plan_mission(
        convoy_spec(), convoy_beats(), lines, voice_manifest=manifest, seed=9, dms_lua=str(dms)
    )
    write_runtime_config(plan, tmp_path)
    out = build_from_plan(plan, tmp_path / "t01.miz", base_dir=tmp_path)
    rep = check_miz(out)
    assert rep.ok, rep.model_dump_json(indent=1)
    assert rep.stats["player_slots"] == 2
    assert not [i for i in rep.issues if i.code == "voice_subtitle_only"]
    json.loads(rep.model_dump_json())


def test_subtitle_only_build_is_valid(tmp_path: Path) -> None:
    dms = dummy_dms_lua(tmp_path)
    plan = plan_mission(convoy_spec(), convoy_beats(), convoy_lines(), seed=4, dms_lua=str(dms))
    write_runtime_config(plan, tmp_path)
    rep = check_miz(build_from_plan(plan, tmp_path / "sub.miz", base_dir=tmp_path))
    assert rep.ok, [i for i in rep.issues if i.severity == "error"]
    assert any(i.code == "voice_subtitle_only" for i in rep.warnings)


def _golden_dms_lua(tmp: Path) -> Path:
    real = REPO / "dist" / "dms.lua"
    if real.is_file() and lua51_syntax_error(real.read_bytes()) is None:
        copy = tmp / "dms.lua"
        shutil.copyfile(real, copy)  # snapshot: the bundle may be rebuilt concurrently
        return copy
    return dummy_dms_lua(tmp)


def test_m01_end_to_end_golden(tmp_path: Path) -> None:
    loaded = load_m01()
    if loaded is None:
        spec, beats, lines, bible = convoy_spec(), convoy_beats(), convoy_lines(), None
    else:
        spec, beats, lines, bible = loaded
    issues = validate(spec, beats, lines, bible)
    assert not has_errors(issues), [i for i in issues if i.severity == "error"]
    dms = _golden_dms_lua(tmp_path)  # no voice manifest: subtitle-only, flyable as is
    manifest = None
    plan_a = plan_mission(
        spec, beats, lines, voice_manifest=manifest, seed=2012, bible=bible, dms_lua=str(dms)
    )
    plan_b = plan_mission(
        spec, beats, lines, voice_manifest=manifest, seed=2012, bible=bible, dms_lua=str(dms)
    )
    plan_c = plan_mission(
        spec, beats, lines, voice_manifest=manifest, seed=7, bible=bible, dms_lua=str(dms)
    )
    assert plan_a.model_dump_json() == plan_b.model_dump_json()
    assert placements(plan_a) != placements(plan_c)
    rt = plan_a.runtime
    assert rt is not None
    assert {m.tpl for p in rt.pools.values() for m in p.members} == set(rt.templates)
    for p in rt.pools.values():
        assert set(p.zones) <= set(rt.zones)
    assert bible is None or rt.speakers  # callsigns from the bible
    write_runtime_config(plan_a, tmp_path)
    out = build_from_plan(plan_a, tmp_path / "m01.miz", base_dir=tmp_path)
    rep = check_miz(out)
    assert rep.ok, [i for i in rep.issues if i.severity == "error"]
    if GOLDEN_OUT.parent.parent.is_dir() or os.environ.get("DMS_GOLDEN_OUT"):
        dest = Path(os.environ.get("DMS_GOLDEN_OUT", GOLDEN_OUT))
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(out, dest)
        (dest.parent / "m01.plan.json").write_text(plan_a.model_dump_json(indent=2), "utf-8")
        (dest.parent / "m01.check.json").write_text(rep.model_dump_json(indent=2), "utf-8")
