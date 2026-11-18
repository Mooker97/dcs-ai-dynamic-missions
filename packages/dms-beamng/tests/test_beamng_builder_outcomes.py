from __future__ import annotations

from types import SimpleNamespace
from typing import Any

from dms_beamng import (
    BeamNGpySink,
    DrivingMissionSpec,
    OutcomeTracker,
    Telemetry,
    format_outcome_line,
    plan,
    to_mission_outcome,
)
from dms_core.schemas import parse_dcs_log

Fake = tuple[SimpleNamespace, list[tuple[str, Any]]]
FAR = (0.0, 0.0, 0.0)


def test_builder_against_fake(spec: DrivingMissionSpec, fake_bp: Fake) -> None:
    module, log = fake_bp
    data = spec.model_dump(exclude_none=True)
    data["ai_driver"] = True
    p = plan(DrivingMissionSpec.model_validate(data), variant=1)
    res = BeamNGpySink(home="E:/fake", module=module).build(p)

    assert [n for n, _ in log] == [
        "BeamNGpy",
        "bng.open",
        "Scenario",
        "Vehicle",
        "scenario.add_vehicle",
        "scenario.make",
        "bng.scenario.load",
        "bng.scenario.start",
        "bng.env.set_tod",
        "bng.traffic.spawn",
        "player.ai.set_mode",
        "player.ai.set_aggression",
    ]
    calls = dict(log)
    assert calls["Scenario"] == (("west_coast_usa", "dms_b01_getaway_v1"), {"description": p.title})
    assert calls["scenario.add_vehicle"][1] == {"pos": p.player.pos, "rot_quat": p.player.rot_quat}
    assert calls["Vehicle"] == (("player",), {"model": "etk800", "license": "DMS-01"})
    assert calls["bng.traffic.spawn"][1]["max_amount"] == p.traffic.amount
    assert calls["player.ai.set_mode"][0] == ("span",)
    assert res.scenario_name == "dms_b01_getaway_v1"
    assert res.plan_hash == p.plan_hash
    assert set(res.handles) == {"bng", "scenario", "vehicles"}


def test_builder_no_traffic_no_ai(spec: DrivingMissionSpec, fake_bp: Fake) -> None:
    module, log = fake_bp
    data = spec.model_dump(exclude_none=True)
    data["traffic"] = {"amount": 0}
    BeamNGpySink(module=module).build(plan(DrivingMissionSpec.model_validate(data)))
    names = [n for n, _ in log]
    assert "bng.traffic.spawn" not in names
    assert not any(".ai." in n for n in names)


def _run(spec: DrivingMissionSpec, arrested: bool = False) -> list[dict[str, Any]]:
    p = plan(spec, variant=0)
    assert p.pursuit is not None
    safe = p.objectives[1].pos
    assert safe is not None
    tr = OutcomeTracker(p)
    t0 = p.pursuit.start_after_sec
    out = tr.update(Telemetry(0, FAR))
    out += tr.update(Telemetry(t0 + 160, FAR, damage=500))  # escalation level 3
    if arrested:
        return out + tr.update(Telemetry(t0 + 170, FAR, arrested=True))
    out += tr.update(Telemetry(t0 + 200, FAR, evaded=True))
    out += tr.update(Telemetry(t0 + 300, safe))
    out += tr.update(Telemetry(t0 + 306, safe))
    return out


def test_tracker_success_path(spec: DrivingMissionSpec) -> None:
    out = _run(spec)
    end = out[-1]
    assert end["kind"] == "end"
    assert end["result"] == "success"
    assert sum(1 for o in out if o["kind"] == "end") == 1
    assert end["outcome"]["lose_police"] is True
    assert end["outcome"]["reach_safehouse"] is True
    assert end["outcome"]["clean_car"] is True
    assert end["outcome"]["roadblocks_seen"] is True
    assert end["beats"] == ["alarm", "roadblocks_up", "lost_them", "home_free"]
    assert end["qualityDeltas"] == {"heat": -1, "cash": 1}


def test_tracker_requires_order(spec: DrivingMissionSpec) -> None:
    p = plan(spec)
    safe = p.objectives[1].pos
    assert safe is not None
    tr = OutcomeTracker(p)
    tr.update(Telemetry(30, safe))
    tr.update(Telemetry(40, safe))
    assert tr.done["reach_safehouse"] is False  # must lose police first
    assert tr.result is None


def test_tracker_arrest(spec: DrivingMissionSpec) -> None:
    end = _run(spec, arrested=True)[-1]
    assert end["result"] == "failure"
    assert end["outcome"]["arrested"] is True
    assert end["qualityDeltas"] == {"heat": 2}


def test_time_limit_and_abort(spec: DrivingMissionSpec) -> None:
    tr = OutcomeTracker(plan(spec))
    end = tr.update(Telemetry(601, FAR))[-1]
    assert end["result"] == "failure"
    assert end["outcome"]["time_limit"] is True
    assert tr.update(Telemetry(700, FAR)) == []
    assert OutcomeTracker(plan(spec)).abort(12.0)[-1]["result"] == "aborted"


def test_lines_parse_as_dms_outcomes(spec: DrivingMissionSpec) -> None:
    out = _run(spec)
    log = "\n".join(
        f"2026-10-29 12:00:0{i}.000 INFO    SCRIPTING (Main): {format_outcome_line(p)}"
        for i, p in enumerate(out)
    )
    parsed = parse_dcs_log(log)
    assert len(parsed) == len(out)
    last = parsed[-1]
    assert last.mission_id == "b01_getaway"
    assert last.kind == "end"
    assert last.result == "success"
    assert last.quality_deltas == {"heat": -1, "cash": 1}
    assert last.extra["backend"] == "beamng"
    assert to_mission_outcome(out[-1]).outcomes["reach_safehouse"] is True
