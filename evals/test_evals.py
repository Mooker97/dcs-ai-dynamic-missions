"""Keep the eval suite green: golden specs pass every stage, premises lint against the catalog."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

import pytest

HERE = Path(__file__).resolve().parent
REPO = HERE.parent


def _load_runner() -> ModuleType:
    name = "dms_evals_run"
    if name in sys.modules:
        return sys.modules[name]
    spec = importlib.util.spec_from_file_location(name, HERE / "run.py")
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


run = _load_runner()
GOLDENS = run.golden_ids()
PREMISES = run.premise_ids()


def test_suite_sizes() -> None:
    assert len(GOLDENS) >= 8
    assert len(PREMISES) >= 30


@pytest.mark.parametrize("golden_id", GOLDENS)
def test_golden(golden_id: str) -> None:
    rep = run.run_golden(golden_id)
    fails = [f"[{c.category}] {c.name}: {c.detail}" for c in rep.checks if not c.ok]
    assert rep.ok, f"{golden_id} failed:\n" + "\n".join(fails)


def test_premises_lint_clean() -> None:
    problems: dict[str, list[str]] = {}
    for stem in PREMISES:
        p = run.Premise.model_validate(run._load_yaml(run.PREMISES_DIR / f"{stem}.yaml"))
        probs = run.lint_premise(p, stem)
        if probs:
            problems[stem] = probs
    assert not problems, problems


def test_premises_cover_genres_and_theaters() -> None:
    premises = [run.load_premise(i) for i in PREMISES]
    assert {p.genre for p in premises} == {"historical", "adapted", "fictional", "fantasy"}
    assert len({p.expect.theater for p in premises}) >= 8
    assert len({a for p in premises for a in p.expect.airframes}) >= 15


def test_score_mode_runs_on_example_campaign() -> None:
    camp = REPO / "campaigns" / "dustoff-valley"
    rep = run.score_campaign(camp, run.load_premise(PREMISES[0]), build=False)
    cats = rep.by_category()
    assert {"files", "schema", "premise", "coverage", "story"} <= set(cats)
    assert cats["schema"]["passed"] == cats["schema"]["total"]
    assert 0.0 < rep.score < 1.0  # dustoff-valley is not this premise: some checks must fail
    data = rep.to_dict()
    assert data["total"] == len(rep.checks)
