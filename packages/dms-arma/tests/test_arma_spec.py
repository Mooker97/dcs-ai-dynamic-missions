from __future__ import annotations

import copy
from typing import Any

import pytest
from arma_paths import EXAMPLE
from dms_arma import ArmaMissionSpec, load_spec
from pydantic import ValidationError


def _raw() -> dict[str, Any]:
    return load_spec(EXAMPLE).model_dump(mode="json")


def _invalid(mutate: Any) -> None:
    raw = copy.deepcopy(_raw())
    mutate(raw)
    with pytest.raises(ValidationError):
        ArmaMissionSpec.model_validate(raw)


def test_extra_fields_forbidden() -> None:
    _invalid(lambda r: r.update(bogus=1))
    _invalid(lambda r: r["exfil"].update(heli=1))


def test_every_field_has_a_description() -> None:
    def walk(model: type[Any], seen: set[type[Any]]) -> None:
        if model in seen:
            return
        seen.add(model)
        for name, info in model.model_fields.items():
            assert info.description, f"{model.__name__}.{name} has no description"
            ann = info.annotation
            for sub in (*getattr(ann, "__args__", ()), ann):
                if isinstance(sub, type) and hasattr(sub, "model_fields"):
                    walk(sub, seen)

    walk(ArmaMissionSpec, set())


def test_ranges_and_bounds() -> None:
    _invalid(lambda r: r["qrf"].update(wave1_delay=[480, 300]))
    _invalid(lambda r: r["squad"].update(skill=1.5))
    _invalid(lambda r: r["sites"]["sites"][0].update(start_bearing=360))
    _invalid(lambda r: r["sites"]["sites"][0].update(mode="CAMP"))
    _invalid(lambda r: r["sites"].update(sites=[]))
    _invalid(lambda r: r["enemy"]["skill"].update(luck=0.5))


def test_class_names_are_identifiers() -> None:
    _invalid(lambda r: r["exfil"].update(heli_class='B_Heli"; hint "x'))
    _invalid(lambda r: r["squad"]["classes"].append("bad name"))


def test_sentry_items_have_no_class() -> None:
    _invalid(lambda r: r["compound"]["composition"][-1].update(class_name="O_Soldier_F"))
    _invalid(lambda r: r["compound"]["composition"][0].update(class_name=""))


def test_class_names_lists_every_reference() -> None:
    spec = load_spec(EXAMPLE)
    names = {n for _, n in spec.class_names()}
    assert {"Sh_82mm_AMOS", "B_Heli_Transport_01_F", "O_APC_Wheeled_02_rcws_v2_F"} <= names
    assert "" not in names
