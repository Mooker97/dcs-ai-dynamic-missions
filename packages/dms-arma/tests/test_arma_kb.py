from __future__ import annotations

from arma_paths import EXAMPLE
from dms_arma import check_classes, check_functions, emit_config, load_spec
from dms_arma.kb import find_kb, known_functions, verified_classes


def test_kb_loads() -> None:
    kb = find_kb()
    assert len(known_functions(kb)) > 2000
    classes = verified_classes(kb)
    assert "b_heli_transport_01_f" in classes and "sh_82mm_amos" in classes
    assert "extra_classes" not in classes


def test_the_hill_classes_are_all_verified() -> None:
    assert check_classes(load_spec(EXAMPLE)) == []


def test_unverified_class_is_reported_not_rejected() -> None:
    spec = load_spec(EXAMPLE)
    spec.exfil.heli_class = "rhs_uh60m"  # a mod class: legal in the spec, but unverified
    issues = check_classes(spec)
    assert [(i.level, i.where) for i in issues] == [("unverified", "exfil.heli_class[0]")]


def test_function_check() -> None:
    text = "[] call BIS_fnc_taskCreate; [] call BIS_fnc_doesNotExist; [] call BIS_fnc_doesNotExist;"
    issues = check_functions(text, "x.sqf")
    assert [i.message.split()[0] for i in issues] == ["BIS_fnc_doesNotExist"]
    assert check_functions(emit_config(load_spec(EXAMPLE)), "fn_config.sqf") == []
