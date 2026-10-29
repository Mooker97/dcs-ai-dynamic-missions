from __future__ import annotations

import pytest
from dms_beamng import DrivingMissionSpec, plan
from dms_beamng.spec import Objective
from pydantic import ValidationError


def test_example_validates(spec: DrivingMissionSpec) -> None:
    assert spec.kind == "getaway"
    assert spec.pursuit is not None
    assert [o.id for o in spec.objectives] == ["lose_police", "reach_safehouse", "clean_car"]


def test_extra_keys_rejected(spec: DrivingMissionSpec) -> None:
    data = spec.model_dump()
    data["bogus"] = 1
    with pytest.raises(ValidationError):
        DrivingMissionSpec.model_validate(data)


def test_bad_refs_rejected(spec: DrivingMissionSpec) -> None:
    data = spec.model_dump(exclude_none=True)
    data["objectives"][1]["after"] = "nope"
    with pytest.raises(ValidationError):
        DrivingMissionSpec.model_validate(data)
    data = spec.model_dump(exclude_none=True)
    data.pop("pursuit")
    with pytest.raises(ValidationError, match="pursuit"):
        DrivingMissionSpec.model_validate(data)
    with pytest.raises(ValidationError):
        Objective(id="x", type="reach")


def test_every_field_described() -> None:
    from dms_beamng import planner
    from dms_beamng import spec as spec_mod

    for mod in (spec_mod, planner):
        for obj in vars(mod).values():
            fields = getattr(obj, "model_fields", None)
            if isinstance(obj, type) and fields and obj.__module__ == mod.__name__:
                for name, f in fields.items():
                    assert f.description, f"{obj.__name__}.{name} lacks a description"


def test_plan_is_deterministic(spec: DrivingMissionSpec) -> None:
    a = plan(spec, variant=3)
    b = plan(spec, variant=3)
    assert a == b
    assert a.plan_hash == b.plan_hash
    assert len(a.plan_hash) == 64
    assert a.model_dump_json() == b.model_dump_json()


def test_variants_differ_and_stay_in_bounds(spec: DrivingMissionSpec) -> None:
    plans = [plan(spec, variant=v) for v in range(20)]
    assert len({p.plan_hash for p in plans}) == 20
    assert len({p.picks["reach_safehouse"] for p in plans}) > 1
    for p in plans:
        assert 0.75 <= p.time_of_day <= 0.95
        assert 6 <= p.traffic.amount <= 12
        assert p.pursuit is not None
        assert 5 <= p.pursuit.start_after_sec <= 20
        assert p.picks["reach_safehouse"] != p.picks["start"]
        assert [s.after_sec for s in p.pursuit.escalation] == [60, 150, 270]


def test_unknown_location_fails(spec: DrivingMissionSpec) -> None:
    data = spec.model_dump(exclude_none=True)
    data["start"] = {"at": "atlantis"}
    with pytest.raises(KeyError, match="atlantis"):
        plan(DrivingMissionSpec.model_validate(data))
