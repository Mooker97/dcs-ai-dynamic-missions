"""DMS eval harness: golden mission regression suite and structural premise scoring.

Two modes, neither of which calls an LLM or the network:

``--golden``
    Runs every hand-written mission in ``evals/specs/<id>/`` through the same library code as
    ``dms validate -> plan -> build -> check`` (into a temp dir), plans twice to prove the fixed
    seed is deterministic, compares the result with ``expect.yaml`` and scores beat/line coverage.

``--score <campaign_dir> --premise <id>``
    Structurally scores a campaign folder that the skills (story-writer -> campaign-planner ->
    mission-designer) produced for ``evals/premises/<id>.yaml``: file presence, schema validity,
    adherence to the premise's expected properties, beat/line coverage and build + check.

``--lint-premises`` checks every premise against the catalog (theater, airframes, eras).

Usage::

    uv run python evals/run.py --golden
    uv run python evals/run.py --score campaigns/<slug> --premise p01-... --json out.json
    uv run python evals/run.py --lint-premises
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import sys
import tempfile
import time
from collections.abc import Iterable
from pathlib import Path
from typing import Any, Literal

import yaml
from dms_core.catalog import load_catalog
from dms_core.schemas import (
    BeatSheet,
    CampaignArc,
    ContentMode,
    DMSModel,
    MissionSpec,
    MissionType,
    StoryBible,
    Theater,
    VoiceLineSet,
)
from pydantic import Field, ValidationError

REPO = Path(__file__).resolve().parents[1]
EVALS = REPO / "evals"
SPECS_DIR = EVALS / "specs"
PREMISES_DIR = EVALS / "premises"

# ---------------------------------------------------------------------------
# Models: premise and golden expectations
# ---------------------------------------------------------------------------


class StoryElement(DMSModel):
    """A story element the premise demands; found by keyword in the generated text."""

    id: str = Field(description="Short id, e.g. 'defector'.")
    description: str = Field(description="What must be present in the story.")
    any_of: list[str] = Field(
        min_length=1,
        description="Case-insensitive keywords; the element counts as present if any appears.",
    )


class PremiseExpect(DMSModel):
    """Properties an adherent campaign must have; checked structurally by ``--score``."""

    theater: Theater = Field(description="DCS map the bible and every mission must use.")
    era: tuple[int, int] = Field(description="[min, max] year the bible/missions must fall in.")
    mode: ContentMode = Field(description="Expected bible content mode.")
    player_coalition: Literal["blue", "red"] = Field(
        default="blue", description="Side the player flies for."
    )
    airframes: list[str] = Field(
        min_length=1, description="Acceptable player aircraft (DCS type ids from the catalog)."
    )
    airframe_role: str = Field(
        description="Catalog role of the player airframe, e.g. attack_helo, multirole."
    )
    missions: tuple[int, int] = Field(description="[min, max] number of missions in arc.yaml.")
    mission_types: list[MissionType] = Field(
        default_factory=list, description="Mission types that must appear somewhere in the arc."
    )
    story_elements: list[StoryElement] = Field(
        default_factory=list, description="Must-have story elements."
    )


class Premise(DMSModel):
    """One eval premise (evals/premises/<id>.yaml)."""

    id: str = Field(description="Premise id = file stem, e.g. 'p01-orchard-watch'.")
    title: str = Field(description="Working title.")
    genre: Literal["historical", "adapted", "fictional", "fantasy"] = Field(
        description="Story genre; 'fantasy' maps to bible mode 'fictional' with a tech veneer."
    )
    prompt: str = Field(description="The premise exactly as given to the story-writer skill.")
    expect: PremiseExpect = Field(description="Expected properties of the generated campaign.")
    notes: str | None = Field(default=None, description="Why this premise is in the suite.")


class GoldenRuntime(DMSModel):
    """Exact runtime counts in the plan."""

    beats: int = Field(ge=0, description="len(plan.runtime.beats).")
    pools: int = Field(ge=0, description="len(plan.runtime.pools).")
    encounters: int = Field(ge=0, description="len(plan.runtime.encounters).")
    voice: int = Field(ge=0, description="len(plan.runtime.voice).")


class GoldenExpect(DMSModel):
    """expect.yaml of a golden spec."""

    theater: Theater = Field(description="Expected plan theater.")
    mission_type: MissionType = Field(description="Expected spec mission type.")
    player_aircraft: list[str] = Field(min_length=1, description="Player aircraft in the plan.")
    max_warnings: int = Field(ge=0, description="Upper bound on validate warnings.")
    min_groups: int = Field(ge=0, description="Lower bound on plan groups.")
    runtime: GoldenRuntime = Field(description="Exact runtime counts.")


# ---------------------------------------------------------------------------
# Results
# ---------------------------------------------------------------------------


@dataclasses.dataclass
class Check:
    """One scored check."""

    category: str
    name: str
    ok: bool
    detail: str = ""
    subject: str = ""

    def to_dict(self) -> dict[str, Any]:
        return dataclasses.asdict(self)


@dataclasses.dataclass
class Report:
    """A list of checks with a score."""

    kind: str
    subject: str
    checks: list[Check] = dataclasses.field(default_factory=list)
    seconds: float = 0.0

    def add(self, category: str, name: str, ok: bool, detail: str = "", subject: str = "") -> bool:
        self.checks.append(Check(category, name, bool(ok), detail, subject))
        return bool(ok)

    @property
    def passed(self) -> int:
        return sum(c.ok for c in self.checks)

    @property
    def ok(self) -> bool:
        return all(c.ok for c in self.checks)

    @property
    def score(self) -> float:
        return self.passed / len(self.checks) if self.checks else 0.0

    def by_category(self) -> dict[str, dict[str, int]]:
        out: dict[str, dict[str, int]] = {}
        for c in self.checks:
            row = out.setdefault(c.category, {"passed": 0, "total": 0})
            row["total"] += 1
            row["passed"] += int(c.ok)
        return out

    def to_dict(self) -> dict[str, Any]:
        return {
            "kind": self.kind,
            "subject": self.subject,
            "ok": self.ok,
            "score": round(self.score, 4),
            "passed": self.passed,
            "total": len(self.checks),
            "seconds": round(self.seconds, 2),
            "categories": self.by_category(),
            "checks": [c.to_dict() for c in self.checks],
        }


# ---------------------------------------------------------------------------
# Pipeline (same library calls as the dms CLI)
# ---------------------------------------------------------------------------


def _cli() -> Any:
    """The dms CLI module; its helpers are the reference validate/plan/build/check path."""
    from dms_cli import main as cli

    cli._STATE["root"] = REPO
    return cli


@dataclasses.dataclass
class PipelineResult:
    """What each stage produced."""

    errors: list[str] = dataclasses.field(default_factory=list)
    warnings: list[str] = dataclasses.field(default_factory=list)
    bundle: Any = None
    plan: Any = None
    plan_error: str | None = None
    deterministic: bool | None = None
    built: bool = False
    build_error: str | None = None
    check_ok: bool | None = None
    check_problems: list[str] = dataclasses.field(default_factory=list)


def run_pipeline(mission_dir: Path, *, build: bool = True, twice: bool = False) -> PipelineResult:
    """validate -> plan (optionally twice) -> build -> check, stopping at the first failure."""
    cli = _cli()
    from dms_cli.util import CliError, resolve_mission, to_jsonable

    res = PipelineResult()
    mp = resolve_mission(mission_dir, root=REPO)
    findings, bundle, _note = cli._validate(mp)
    res.errors = [f.render() for f in findings if f.severity == "error"]
    res.warnings = [f.render() for f in findings if f.severity != "error"]
    res.bundle = bundle
    if res.errors or bundle is None:
        return res
    try:
        res.plan = cli._plan(bundle, None, None)
        if twice:
            again = cli._plan(bundle, None, None)
            res.deterministic = res.plan.model_dump_json() == again.model_dump_json()
    except (CliError, ValueError, KeyError, RuntimeError) as exc:
        res.plan_error = f"{type(exc).__name__}: {exc}"
        return res
    if not build:
        return res
    with tempfile.TemporaryDirectory(prefix="dms-eval-") as tmp:
        out = Path(tmp) / f"{res.plan.mission_id}.miz"
        plan = res.plan.model_copy(deep=True)
        try:
            built, _notes = cli._build_obj(plan, mp.dir, out, None, Path(tmp), Path(tmp))
        except (CliError, ValueError, KeyError, RuntimeError, OSError) as exc:
            res.build_error = f"{type(exc).__name__}: {exc}"
            return res
        res.built = Path(built).is_file()
        report = cli._check(Path(built))
        data = to_jsonable(report)
        res.check_ok = bool(getattr(report, "ok", False))
        issues = data.get("issues", []) if isinstance(data, dict) else []
        res.check_problems = [
            cli._one_line(i)
            for i in issues
            if isinstance(i, dict) and str(i.get("severity", "")).lower() == "error"
        ]
    return res


# ---------------------------------------------------------------------------
# Beat / line coverage (shared by golden and score modes)
# ---------------------------------------------------------------------------


def _as_list(v: str | list[str] | None) -> list[str]:
    if v is None:
        return []
    return [v] if isinstance(v, str) else list(v)


def coverage_checks(
    report: Report,
    spec: MissionSpec,
    beats: BeatSheet | None,
    lines: VoiceLineSet | None,
    subject: str,
) -> None:
    """Structural narrative coverage of one mission's beats.yaml / lines.yaml."""

    def add(name: str, ok: bool, detail: str = "") -> bool:
        return report.add("coverage", name, ok, detail, subject)

    beat_list = beats.beats if beats else []
    line_list = lines.lines if lines else []
    if not add("has beats", bool(beat_list), f"{len(beat_list)} beats"):
        return
    beat_ids = {b.id for b in beat_list}
    line_ids = {ln.id for ln in line_list}

    missing = sorted({lid for b in beat_list for lid in b.lines if lid not in line_ids})
    add("beat lines exist", not missing, ", ".join(missing[:5]))

    orphan = sorted(ln.id for ln in line_list if ln.beat and ln.beat not in beat_ids)
    add("lines point at real beats", not orphan, ", ".join(orphan[:5]))

    used = {lid for b in beat_list for lid in b.lines}
    unused = sorted(line_ids - used)
    add("every line is used by a beat", not unused, ", ".join(unused[:5]))

    voiced = [b for b in beat_list if b.lines]
    thin = sorted(b.id for b in voiced if len(b.lines) < 2)
    add("voiced beats have >=2 variants", not thin, ", ".join(thin[:5]))

    cast = set(spec.cast)
    speakers = {b.speaker for b in beat_list if b.speaker} | {ln.speaker for ln in line_list}
    off_cast = sorted(s for s in speakers if s not in cast)
    add("speakers are in the cast", not off_cast, ", ".join(off_cast))

    set_flags = {f for b in beat_list for f in _as_list(b.effects.set_flag)}
    unset = sorted(
        o.success_flag
        for o in spec.objectives
        if o.success_flag and o.success_flag not in set_flags
    )
    add("objective success flags are set by beats", not unset, ", ".join(unset))

    ends = [b.id for b in beat_list if b.effects.end_mission == "success"]
    add("a beat ends the mission in success", bool(ends), ", ".join(ends))

    add("has a guaranteed beat", any(b.guaranteed for b in beat_list))

    no_tel = sorted(
        e.id
        for e in spec.dynamic.encounters
        if e.telegraph_beat and e.telegraph_beat not in beat_ids
    )
    add("encounter telegraph beats exist", not no_tel, ", ".join(no_tel))


# ---------------------------------------------------------------------------
# Golden mode
# ---------------------------------------------------------------------------


def golden_ids() -> list[str]:
    """Ids of every golden spec folder."""
    return sorted(p.name for p in SPECS_DIR.iterdir() if (p / "mission-spec.yaml").is_file())


def _load_yaml(path: Path) -> Any:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def run_golden(golden_id: str) -> Report:
    """Score one golden spec; every check must pass."""
    t0 = time.perf_counter()
    gdir = SPECS_DIR / golden_id
    rep = Report("golden", golden_id)
    try:
        expect = GoldenExpect.model_validate(_load_yaml(gdir / "expect.yaml"))
    except (OSError, ValidationError) as exc:
        rep.add("expect", "expect.yaml valid", False, str(exc).splitlines()[0])
        return rep
    res = run_pipeline(gdir, build=True, twice=True)
    rep.add("validate", "no errors", not res.errors, "; ".join(res.errors[:3]))
    rep.add(
        "validate",
        "warnings within cap",
        len(res.warnings) <= expect.max_warnings,
        f"{len(res.warnings)} <= {expect.max_warnings}",
    )
    if res.bundle is not None:
        spec = res.bundle.spec
        rep.add("expect", "id matches folder", spec.id == golden_id, spec.id)
        rep.add("expect", "seed is fixed", spec.seed is not None, str(spec.seed))
        rep.add("expect", "mission type", spec.mission_type == expect.mission_type)
        coverage_checks(rep, spec, res.bundle.beats, res.bundle.lines, golden_id)
    if not rep.add("plan", "plans", res.plan is not None, res.plan_error or ""):
        rep.seconds = time.perf_counter() - t0
        return rep
    rep.add("plan", "deterministic (same seed, same plan)", bool(res.deterministic))
    plan = res.plan
    rep.add("expect", "theater", plan.theater == expect.theater, str(plan.theater))
    players = sorted({u.type for g in plan.groups if g.client for u in g.units})
    rep.add(
        "expect",
        "player aircraft",
        players == sorted(set(expect.player_aircraft)),
        ", ".join(players),
    )
    rep.add(
        "expect",
        "min groups",
        len(plan.groups) >= expect.min_groups,
        f"{len(plan.groups)} >= {expect.min_groups}",
    )
    rt = plan.runtime
    for key in ("beats", "pools", "encounters", "voice"):
        got = len(getattr(rt, key) or {}) if rt is not None else 0
        want = getattr(expect.runtime, key)
        rep.add("expect", f"runtime {key}", got == want, f"{got} (want {want})")
    rep.add("build", "builds .miz", res.built, res.build_error or "")
    if res.built:
        rep.add("check", "dms check OK", bool(res.check_ok), "; ".join(res.check_problems[:3]))
    rep.seconds = time.perf_counter() - t0
    return rep


# ---------------------------------------------------------------------------
# Premises
# ---------------------------------------------------------------------------


def load_premise(premise_id: str) -> Premise:
    """Load and validate evals/premises/<id>.yaml."""
    path = PREMISES_DIR / f"{premise_id}.yaml"
    if not path.is_file():
        known = ", ".join(premise_ids()[:5])
        raise SystemExit(f"error: no premise {premise_id!r} in {PREMISES_DIR} (e.g. {known})")
    return Premise.model_validate(_load_yaml(path))


def premise_ids() -> list[str]:
    """Ids (file stems) of every premise."""
    return sorted(p.stem for p in PREMISES_DIR.glob("*.yaml"))


def lint_premise(p: Premise, stem: str) -> list[str]:
    """Catalog problems with a premise (empty = fine)."""
    c = load_catalog()
    probs: list[str] = []
    e = p.expect
    if p.id != stem:
        probs.append(f"id {p.id!r} != file stem {stem!r}")
    if e.era[0] > e.era[1] or e.missions[0] > e.missions[1] or e.missions[0] < 1:
        probs.append("era/missions ranges must be [min<=max], missions >= 1")
    want_mode = "fictional" if p.genre == "fantasy" else p.genre
    if e.mode != want_mode:
        probs.append(f"genre {p.genre!r} should expect mode {want_mode!r}")
    for ac in e.airframes:
        u = c.units.get(ac)
        if u is None:
            probs.append(f"airframe {ac!r} not in the catalog")
            continue
        if "player" not in u.tags:
            probs.append(f"airframe {ac!r} is not player-flyable")
        if e.player_coalition not in u.coalitions:
            probs.append(f"airframe {ac!r} is not flown by {e.player_coalition}")
        if not u.has_role(e.airframe_role):
            probs.append(f"airframe {ac!r} has role {u.role!r}, not {e.airframe_role!r}")
        spans = [c.eras[x].years for x in u.eras if x in c.eras]
        if not any(lo <= e.era[1] and e.era[0] <= hi for lo, hi in spans):
            probs.append(f"airframe {ac!r} eras {u.eras} do not overlap {list(e.era)}")
    if not e.story_elements:
        probs.append("no story_elements")
    return probs


# ---------------------------------------------------------------------------
# Score mode
# ---------------------------------------------------------------------------


def _read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return ""


def _validated(
    rep: Report, path: Path, model: type[DMSModel], subject: str
) -> tuple[Any | None, str]:
    text = _read_text(path)
    if not rep.add("files", f"{path.name} exists", bool(text), subject=subject):
        return None, ""
    try:
        obj = model.model_validate(yaml.safe_load(text))
    except (yaml.YAMLError, ValidationError) as exc:
        first = str(exc).splitlines()
        rep.add("schema", f"{path.name} valid", False, " ".join(first[:3]), subject)
        return None, text
    rep.add("schema", f"{path.name} valid", True, subject=subject)
    return obj, text


def _in_range(v: int, rng: tuple[int, int]) -> bool:
    return rng[0] <= v <= rng[1]


def score_campaign(campaign_dir: Path, premise: Premise, *, build: bool = True) -> Report:
    """Structurally score skill-produced outputs for ``premise`` (no LLM, no network)."""
    t0 = time.perf_counter()
    cdir = campaign_dir.resolve()
    rep = Report("score", f"{premise.id} @ {cdir.name}")
    e = premise.expect
    texts: list[str] = []

    premise_md = _read_text(cdir / "premise.md")
    rep.add("files", "premise.md exists", bool(premise_md))
    texts.append(premise_md)
    continuity = _read_text(cdir / "continuity.md")
    rep.add("files", "continuity.md exists", bool(continuity))
    texts.append(continuity)
    rep.add("files", "state/qualities.yaml exists", (cdir / "state" / "qualities.yaml").is_file())

    bible, btxt = _validated(rep, cdir / "bible.yaml", StoryBible, "bible")
    arc, atxt = _validated(rep, cdir / "arc.yaml", CampaignArc, "arc")
    texts += [btxt, atxt]

    if bible is not None:
        rep.add("premise", "theater", bible.setting.theater == e.theater, bible.setting.theater)
        rep.add("premise", "era", _in_range(bible.setting.era, e.era), str(bible.setting.era))
        rep.add("premise", "content mode", bible.mode == e.mode, bible.mode)
        sides = {f.dcs.coalition for f in bible.factions}
        rep.add(
            "premise",
            "player and enemy sides exist",
            e.player_coalition in sides and len(sides - {"neutral"}) >= 2,
            ", ".join(sorted(sides)),
        )
        speaking = [ch for ch in bible.characters if ch.voice is not None]
        rep.add("premise", "has voiced characters", bool(speaking), f"{len(speaking)} voiced")
        if e.mode == "historical":
            rep.add("premise", "historical bible cites sources", bool(bible.sources))

    arc_missions = [m for act in arc.acts for m in act.missions] if arc is not None else []
    if arc is not None:
        n = len(arc_missions)
        rep.add("premise", "mission count", _in_range(n, e.missions), f"{n} in {list(e.missions)}")
        types = {m.mission_type for m in arc_missions}
        missing = sorted(set(e.mission_types) - types)
        rep.add("premise", "required mission types", not missing, ", ".join(missing))
        frames = sorted({m.player_aircraft for m in arc_missions if m.player_aircraft})
        rep.add(
            "premise",
            "arc player aircraft",
            bool(frames) and all(_airframe_ok(f, e) for f in frames),
            ", ".join(frames) or "none set",
        )
        rep.add("arc", "defines qualities", bool(arc.qualities), f"{len(arc.qualities)}")
        branches = sum(len(m.branches) for m in arc_missions)
        rep.add("arc", "has branches", branches > 0, f"{branches}")
        keyless = [m.id for m in arc_missions if not m.key_beats]
        rep.add("arc", "missions list key beats", not keyless, ", ".join(keyless[:5]))
        ids = {m.id for m in arc_missions}
        bad = sorted({b.goto for m in arc_missions for b in m.branches if b.goto not in ids})
        rep.add("arc", "branch targets exist", not bad, ", ".join(bad))

    mdirs = sorted(p for p in (cdir / "missions").glob("m*") if (p / "mission-spec.yaml").is_file())
    rep.add("files", "at least one designed mission", bool(mdirs), f"{len(mdirs)}")
    for mdir in mdirs:
        _score_mission(rep, mdir, e, bible, {m.id for m in arc_missions}, build, texts)

    blob = "\n".join(texts).lower()
    for el in e.story_elements:
        hit = next((k for k in el.any_of if k.lower() in blob), None)
        rep.add("story", el.id, hit is not None, f"found '{hit}'" if hit else el.description)
    rep.seconds = time.perf_counter() - t0
    return rep


def _airframe_ok(aircraft: str, e: PremiseExpect) -> bool:
    if aircraft in e.airframes:
        return True
    u = load_catalog().units.get(aircraft)
    return u is not None and u.has_role(e.airframe_role) and e.player_coalition in u.coalitions


def _score_mission(
    rep: Report,
    mdir: Path,
    e: PremiseExpect,
    bible: StoryBible | None,
    arc_ids: set[str],
    build: bool,
    texts: list[str],
) -> None:
    sub = mdir.name
    texts += [_read_text(mdir / n) for n in ("briefing.md", "kneeboard.md", "lines.yaml")]
    res = run_pipeline(mdir, build=build)
    rep.add("schema", "dms validate: no errors", not res.errors, "; ".join(res.errors[:3]), sub)
    if res.bundle is None:
        return
    spec = res.bundle.spec
    rep.add("premise", "mission in arc", spec.id in arc_ids or not arc_ids, spec.id, sub)
    rep.add("premise", "mission theater", spec.theater == e.theater, spec.theater, sub)
    rep.add("premise", "mission era", _in_range(spec.era, e.era), str(spec.era), sub)
    flights = spec.player_flights
    rep.add(
        "premise",
        "player aircraft",
        all(_airframe_ok(f.aircraft, e) for f in flights),
        ", ".join(f.aircraft for f in flights),
        sub,
    )
    rep.add(
        "premise",
        "player coalition",
        all(f.coalition == e.player_coalition for f in flights),
        ", ".join(f.coalition for f in flights),
        sub,
    )
    if bible is not None:
        rep.add("premise", "mission mode matches bible", spec.content_mode == bible.mode, "", sub)
    coverage_checks(rep, spec, res.bundle.beats, res.bundle.lines, sub)
    if not rep.add("build", "plans", res.plan is not None, res.plan_error or "", sub):
        return
    if build:
        rep.add("build", "builds .miz", res.built, res.build_error or "", sub)
        if res.built:
            rep.add("build", "dms check OK", bool(res.check_ok), "; ".join(res.check_problems), sub)


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------


def _table(rows: Iterable[list[str]], head: list[str]) -> str:
    rows = [head, *rows]
    widths = [max(len(r[i]) for r in rows) for i in range(len(head))]
    fmt = "  ".join(f"{{:<{w}}}" for w in widths)
    lines = [fmt.format(*r) for r in rows]
    lines.insert(1, "  ".join("-" * w for w in widths))
    return "\n".join(lines)


def golden_table(reports: list[Report]) -> str:
    """One row per golden: pass/fail per stage category."""
    cats = ["validate", "plan", "build", "check", "expect", "coverage"]
    rows = []
    for r in reports:
        bc = r.by_category()
        cells = []
        for c in cats:
            row = bc.get(c)
            cells.append(
                "-" if row is None else ("PASS" if row["passed"] == row["total"] else "FAIL")
            )
        rows.append([r.subject, *cells, f"{r.passed}/{len(r.checks)}", f"{r.seconds:.1f}s"])
    return _table(rows, ["golden", *cats, "checks", "time"])


def score_table(rep: Report) -> str:
    """Per-category totals followed by every failed check."""
    rows = [[k, f"{v['passed']}/{v['total']}"] for k, v in rep.by_category().items()]
    out = [_table(rows, ["category", "passed"])]
    fails = [c for c in rep.checks if not c.ok]
    if fails:
        out.append("\nfailed:")
        out += [
            f"  [{c.category}] {c.subject + ': ' if c.subject else ''}{c.name}"
            + (f" ({c.detail})" if c.detail else "")
            for c in fails
        ]
    out.append(f"\nscore {rep.passed}/{len(rep.checks)} = {rep.score:.0%}")
    return "\n".join(out)


def _write_json(data: Any, path: Path | None) -> None:
    text = json.dumps(data, indent=2, ensure_ascii=False)
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text + "\n", encoding="utf-8")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="evals/run.py", description=__doc__.split("\n\n")[0])
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--golden", action="store_true", help="Run the golden spec suite.")
    mode.add_argument("--score", type=Path, metavar="CAMPAIGN_DIR", help="Score a campaign.")
    mode.add_argument("--lint-premises", action="store_true", help="Check premises vs catalog.")
    ap.add_argument("--premise", help="Premise id for --score (evals/premises/<id>.yaml).")
    ap.add_argument("--only", action="append", help="--golden: run only these ids.")
    ap.add_argument("--no-build", action="store_true", help="--score: skip plan/build/check.")
    ap.add_argument("--json", type=Path, dest="json_out", help="Also write the JSON report here.")
    ap.add_argument("--json-stdout", action="store_true", help="Print JSON instead of a table.")
    ap.add_argument("--min-score", type=float, default=None, help="--score: fail below this.")
    args = ap.parse_args(argv)

    if args.lint_premises:
        bad = 0
        for stem in premise_ids():
            try:
                probs = lint_premise(
                    Premise.model_validate(_load_yaml(PREMISES_DIR / f"{stem}.yaml")), stem
                )
            except ValidationError as exc:
                probs = [str(exc).splitlines()[0]]
            bad += bool(probs)
            print(f"{'FAIL' if probs else 'ok  '} {stem}" + "".join(f"\n     - {p}" for p in probs))
        print(f"{len(premise_ids()) - bad}/{len(premise_ids())} premises ok")
        return 1 if bad else 0

    if args.golden:
        ids = args.only or golden_ids()
        reports = [run_golden(i) for i in ids]
        data = {
            "kind": "golden",
            "ok": all(r.ok for r in reports),
            "results": [r.to_dict() for r in reports],
        }
        _write_json(data, args.json_out)
        if args.json_stdout:
            print(json.dumps(data, indent=2))
        else:
            print(golden_table(reports))
            for r in reports:
                for c in r.checks:
                    if not c.ok:
                        print(f"FAIL {r.subject} [{c.category}] {c.name}: {c.detail}")
            print(f"\n{sum(r.ok for r in reports)}/{len(reports)} goldens green")
        return 0 if data["ok"] else 1

    if not args.premise:
        ap.error("--score needs --premise <id>")
    if not args.score.is_dir():
        ap.error(f"not a directory: {args.score}")
    rep = score_campaign(args.score, load_premise(args.premise), build=not args.no_build)
    data = rep.to_dict()
    _write_json(data, args.json_out)
    print(json.dumps(data, indent=2) if args.json_stdout else score_table(rep))
    if args.min_score is not None and rep.score < args.min_score:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
