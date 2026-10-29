"""The ``dms`` command line (typer). Plain-text output, no colours or emoji (Windows-safe).

Exit codes: 0 ok, 1 validation/check problems found, 2 usage or I/O error.
"""

from __future__ import annotations

import dataclasses
import importlib.util
import json
import os
import re
import shutil
import tempfile
from pathlib import Path
from types import ModuleType
from typing import Annotated, Any

import typer
from pydantic import BaseModel, ValidationError

from .util import (
    PLAN_FILE,
    CliError,
    Finding,
    MissionPaths,
    dumps,
    eras_for,
    find_root,
    finding_from,
    latest_mtime,
    load_yaml,
    mission_dir_for_plan,
    pydantic_findings,
    record_check,
    resolve_mission,
    to_jsonable,
)

app = typer.Typer(
    name="dms",
    help="DCS Dynamic Mission System: validate, plan, voice, build and check missions.",
    rich_markup_mode=None,
    pretty_exceptions_enable=False,
    add_completion=False,
    no_args_is_help=True,
)
catalog_app = typer.Typer(
    help="Grounding lookups: units, templates, airbases, mission types.",
    rich_markup_mode=None,
    no_args_is_help=True,
)
app.add_typer(catalog_app, name="catalog")

_STATE: dict[str, Path | None] = {"root": None}


@app.callback()
def _main(
    root: Annotated[
        Path | None,
        typer.Option("--root", help="Repo root (default: walk up to the uv workspace)."),
    ] = None,
) -> None:
    _STATE["root"] = root.resolve() if root else None


# ---- shared helpers ----------------------------------------------------------------------------


def _root() -> Path:
    r = _STATE["root"]
    if r is not None:
        return r
    found = find_root()
    _STATE["root"] = found
    return found


def _echo(msg: str = "") -> None:
    typer.echo(msg)


def _fail(msg: str, code: int = 2) -> typer.Exit:
    typer.echo(f"error: {msg}", err=True)
    return typer.Exit(code)


def _guard(fn: Any) -> Any:
    """Turn CliError into a clean message + exit code."""
    import functools

    @functools.wraps(fn)
    def wrapper(*args: Any, **kwargs: Any) -> Any:
        try:
            return fn(*args, **kwargs)
        except CliError as exc:
            raise _fail(str(exc), exc.code) from None

    return wrapper


@dataclasses.dataclass
class Bundle:
    spec: Any
    beats: Any | None
    lines: Any | None
    bible: Any | None
    mission_dir: Path | None = None


def _load_bundle(mp: MissionPaths) -> tuple[list[Finding], Bundle | None]:
    from dms_core.schemas import BeatSheet, MissionSpec, StoryBible, VoiceLineSet

    findings: list[Finding] = []
    loaded: dict[str, Any] = {}
    items: list[tuple[str, Path | None, type[BaseModel]]] = [
        ("spec", mp.spec, MissionSpec),
        ("beats", mp.beats, BeatSheet),
        ("lines", mp.lines, VoiceLineSet),
        ("bible", mp.bible, StoryBible),
    ]
    for key, path, model in items:
        if path is None:
            loaded[key] = None
            continue
        data = load_yaml(path)
        if data is None and key != "spec":
            data = []
        try:
            loaded[key] = model.model_validate(data)
        except ValidationError as exc:
            findings.extend(pydantic_findings(exc, path.name, model))
    if findings:
        return findings, None
    return findings, Bundle(**loaded, mission_dir=mp.dir)


def _semantic_findings(b: Bundle) -> tuple[list[Finding], str | None]:
    """planner.validate when available, else dms_core's cross-file check (with a note)."""
    try:
        from dms_gen import planner  # type: ignore[import-untyped,unused-ignore]
    except ImportError:
        planner = None  # type: ignore[assignment,unused-ignore]
    if planner is not None and hasattr(planner, "validate"):
        issues = planner.validate(b.spec, beats=b.beats, lines=b.lines, bible=b.bible)
        return [finding_from(i) for i in issues], None
    from dms_core.schemas import BeatSheet, VoiceLineSet, validate_mission_bundle

    issues = validate_mission_bundle(
        b.spec, b.beats or BeatSheet(), b.lines or VoiceLineSet(), bible=b.bible
    )
    note = "dms_gen.planner not available; ran cross-file checks only"
    return [finding_from(i) for i in issues], note


def _validate(mp: MissionPaths) -> tuple[list[Finding], Bundle | None, str | None]:
    findings, bundle = _load_bundle(mp)
    if bundle is None:
        return findings, None, None
    sem, note = _semantic_findings(bundle)
    return findings + sem, bundle, note


def _errors(findings: list[Finding]) -> list[Finding]:
    return [f for f in findings if f.severity == "error"]


def _print_findings(findings: list[Finding]) -> None:
    for f in findings:
        _echo(f.render())


def _plan(bundle: Bundle, seed: int | None, manifest: Path | None) -> Any:
    """planner.plan_mission; the manifest is passed as a path so sound files resolve next to it."""
    import inspect

    from dms_gen import planner  # type: ignore[import-untyped,unused-ignore]

    if manifest is not None and not manifest.is_file():
        raise CliError(f"voice manifest not found: {manifest}")
    kwargs: dict[str, Any] = {
        "beats": bundle.beats,
        "lines": bundle.lines,
        "voice_manifest": manifest,
        "seed": seed,
    }
    params = inspect.signature(planner.plan_mission).parameters
    if "bible" in params:
        kwargs["bible"] = bundle.bible
    loader = getattr(planner, "load_campaign_qualities", None)
    if bundle.mission_dir is not None and loader is not None and "qualities" in params:
        try:  # campaign values at plan time -> DMS_CONFIG.qualities
            kwargs["qualities"] = loader(bundle.mission_dir)
        except ValueError as exc:
            raise CliError(f"campaign qualities: {exc}", 1) from exc
    flag_loader = getattr(planner, "load_campaign_flags", None)
    if bundle.mission_dir is not None and flag_loader is not None and "flags" in params:
        try:  # campaign flags at plan time -> DMS_CONFIG.flags
            kwargs["flags"] = flag_loader(bundle.mission_dir)
        except ValueError as exc:
            raise CliError(f"campaign flags: {exc}", 1) from exc
    try:
        return planner.plan_mission(bundle.spec, **kwargs)
    except Exception as exc:
        if type(exc).__name__ == "PlanError" or isinstance(exc, ValueError | KeyError):
            raise CliError(f"planning failed: {exc}", 1) from exc
        raise


def _plan_summary(plan: Any) -> list[str]:
    groups = list(getattr(plan, "groups", []) or [])
    clients = [g for g in groups if getattr(g, "client", False)]
    rt = getattr(plan, "runtime", None)
    out = [
        f"mission {plan.mission_id}  seed {plan.seed}  theater {plan.theater}",
        f"groups {len(groups)} (player {len(clients)})  zones {len(plan.zones)}  "
        f"triggers {len(plan.triggers)}  resources {len(plan.resources)}",
    ]
    for g in clients:
        u0 = g.units[0] if g.units else None
        freq = getattr(g, "frequency_mhz", None) or getattr(g, "frequency", None)
        extra = f"  {freq} MHz" if freq else ""
        out.append(f"  player: {g.name} ({u0.type if u0 else '?'} x{len(g.units)}){extra}")
    if rt is not None:
        out.append(
            f"runtime: templates {len(rt.templates)}  pools {len(rt.pools)}  "
            f"encounters {len(rt.encounters)}  beats {len(rt.beats)}  voice {len(rt.voice)}"
        )
    return out


def _load_tool(root: Path, name: str) -> ModuleType:
    path = root / "tools" / f"{name}.py"
    if not path.is_file():
        raise CliError(f"{path} not found")
    spec = importlib.util.spec_from_file_location(f"_dms_tool_{name}", path)
    if spec is None or spec.loader is None:
        raise CliError(f"cannot load {path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _bundle_lua(root: Path, out: Path) -> Path:
    mod = _load_tool(root, "bundle_lua")
    try:
        result = mod.bundle(out, quiet=True)
    except SystemExit as exc:  # bundler may exit on compile errors
        raise CliError(f"bundle_lua failed: {exc.code}", 1) from None
    return Path(result) if result else out


def _lua_sources(root: Path) -> list[Path]:
    src = sorted((root / "lua" / "src").rglob("*.lua"))
    return [*src, root / "lua" / "manifest.txt"]


def _ensure_lua(root: Path, lua: Path | None) -> tuple[Path, str]:
    """Return the bundle path, rebuilding the default dist/dms.lua when missing or stale."""
    if lua is not None:
        lua = lua.resolve()
        if not lua.is_file():
            raise CliError(f"--lua {lua} not found")
        return lua, "given"
    out = root / "dist" / "dms.lua"
    if out.is_file() and out.stat().st_mtime >= latest_mtime(_lua_sources(root)):
        return out, "up to date"
    reason = "missing" if not out.is_file() else "stale"
    _bundle_lua(root, out)
    return out, f"rebuilt ({reason})"


def _resolve_resources(plan: Any, mission_dir: Path, root: Path, plan_dir: Path) -> None:
    """Make every relative resource source absolute (mission dir, then repo root, then plan dir)."""
    for r in plan.resources:
        src = Path(r.source)
        if src.is_absolute():
            continue
        for base in (mission_dir, root, plan_dir):
            if (base / src).exists():
                r.source = str((base / src).resolve())
                break


def _attach_lua(plan: Any, lua: Path, tmp: Path) -> str:
    """Point the plan's dms.lua script resource at ``lua``; add it if the plan has none."""
    from dms_core.schemas import PlanResource
    from dms_gen.plugins import (  # type: ignore[import-untyped,unused-ignore]
        dms_lua_insert_index,
    )

    for r in plan.resources:
        if r.kind == "script" and (
            Path(r.path).name == "dms.lua" or Path(r.source).name == "dms.lua"
        ):
            r.source = str(lua)
            return "linked"
    new: list[Any] = []
    if plan.runtime is not None and not any(
        Path(r.path).name == "dms_config.lua" for r in plan.resources
    ):
        cfg = tmp / "dms_config.lua"
        cfg.write_text(plan.runtime.to_lua_source(), encoding="utf-8")
        new.append(PlanResource(path="l10n/DEFAULT/dms_config.lua", source=str(cfg), kind="script"))
    new.append(PlanResource(path="l10n/DEFAULT/dms.lua", source=str(lua), kind="script"))
    # after the plugins (mist/moose/skynet) and any existing config, before the DMS adapters
    res = list(plan.resources)
    at = dms_lua_insert_index(x.path for x in res)
    plan.resources = [*res[:at], *new, *res[at:]]
    return "added"


def _check(path: Path) -> Any:
    from dms_gen.check import check_miz  # type: ignore[import-untyped,unused-ignore]

    report = check_miz(path)
    record_check(path, report)  # out/check.json, same as the MCP build/check
    return report


def _print_check(report: Any) -> bool:
    data = to_jsonable(report)
    ok = bool(getattr(report, "ok", data.get("ok") if isinstance(data, dict) else False))
    _echo(f"check: {'OK' if ok else 'FAILED'}")
    if isinstance(data, dict):
        for key, val in data.items():
            if key == "ok":
                continue
            if isinstance(val, list):
                if not val:
                    continue
                _echo(f"  {key}: {len(val)}")
                for item in val:
                    _echo(f"    - {_one_line(item)}")
            elif isinstance(val, dict):
                if val:
                    _echo(f"  {key}: " + ", ".join(f"{k}={_one_line(v)}" for k, v in val.items()))
            elif val is not None:
                _echo(f"  {key}: {val}")
    return ok


def _one_line(item: Any) -> str:
    if isinstance(item, dict):
        if "problem" in item or "message" in item:
            sev = item.get("severity") or item.get("level")
            where = item.get("path") or item.get("where") or item.get("code")
            msg = item.get("problem") or item.get("message")
            return " ".join(str(x) for x in (sev and str(sev).upper(), where, msg) if x)
        return json.dumps(item, ensure_ascii=False, default=str)
    return str(item)


def _write_runtime_config(plan: Any, out_dir: Path) -> Path | None:
    """Write plan.runtime to the plan's dms_config.lua resource (in <mission>/out/) and make
    that resource point at the written file. No-op for plans without that resource."""
    res = next((r for r in plan.resources if Path(r.path).name == "dms_config.lua"), None)
    if res is None or plan.runtime is None:
        return None
    try:
        from dms_gen.planner import (  # type: ignore[import-untyped,unused-ignore]
            write_runtime_config,
        )
    except ImportError:
        write_runtime_config = None  # type: ignore[assignment]
    src = Path(res.source)
    if not src.is_absolute():
        res.source = str((out_dir / src.name).resolve())
    out_dir.mkdir(parents=True, exist_ok=True)
    if write_runtime_config is not None:
        path = Path(write_runtime_config(plan, base_dir=out_dir))
    else:
        path = Path(res.source)
        path.write_text(plan.runtime.to_lua_source() + "\n", encoding="utf-8")
    res.source = str(path.resolve())
    return path


def _build_variants(
    plan_path: Path, out: Path | None, lua: Path | None, variant: str | None
) -> list[tuple[str | None, Path, list[str]]]:
    """Build plan.json into one .miz per player-flight variant: ``(variant, miz, notes)``.

    No variants: one ``<id>.miz`` (``out`` overrides). With variants: ``<id>-<variant>.miz``
    each, then ``<id>.miz`` (or ``out``) as a byte copy of the first variant, returned last as
    ``(None, path, notes)``. ``variant`` builds only that one (``out`` names it).
    """
    from dms_core.schemas import BuildPlan
    from dms_core.variants import plan_variants, variant_miz_name, variant_plan

    try:
        plan = BuildPlan.model_validate_json(plan_path.read_text(encoding="utf-8"))
    except ValidationError as exc:
        _print_findings(pydantic_findings(exc, plan_path.name, BuildPlan))
        raise CliError(f"{plan_path.name} is not a valid BuildPlan", 1) from None
    mdir = mission_dir_for_plan(plan_path)
    odir = mdir / "out"
    variants = plan_variants(plan)
    if variant is not None and variant not in variants:
        raise CliError(f"unknown variant {variant!r}; plan has {variants or 'no variants'}", 1)
    if not variants:
        miz = out or odir / variant_miz_name(plan.mission_id, None)
        built, notes = _build_obj(plan, mdir, miz, lua, odir, plan_path.parent)
        return [(None, built, notes)]
    todo = [variant] if variant is not None else variants
    builds: list[tuple[str | None, Path, list[str]]] = []
    for v in todo:
        miz = (out if variant is not None and out else None) or odir / variant_miz_name(
            plan.mission_id, v
        )
        built, notes = _build_obj(variant_plan(plan, v), mdir, miz, lua, odir, plan_path.parent)
        builds.append((v, built, [f"variant {v}: {built.name}", *notes]))
    if variant is None:
        alias = (out or odir / variant_miz_name(plan.mission_id, None)).resolve()
        alias.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(builds[0][1], alias)
        builds.append((None, alias, [f"{alias.name} = copy of variant {variants[0]}"]))
    return builds


def _build_obj(
    plan: Any, mdir: Path, out: Path, lua: Path | None, cfg_dir: Path, plan_dir: Path
) -> tuple[Path, list[str]]:
    from dms_gen.builder import build_from_plan  # type: ignore[import-untyped,unused-ignore]

    root = _root()
    out = out.resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    lua_path, lua_state = _ensure_lua(root, lua)
    notes = [f"lua: {lua_path} ({lua_state})"]
    with tempfile.TemporaryDirectory(prefix="dms-cli-") as tmp:
        cfg = _write_runtime_config(plan, cfg_dir)
        if cfg is not None:
            notes.append(f"runtime config: {cfg}")
        _resolve_resources(plan, mdir, root, plan_dir)
        notes.append(f"lua resource {_attach_lua(plan, lua_path, Path(tmp))}")
        missing = [r.source for r in plan.resources if not Path(r.source).exists()]
        if missing:
            raise CliError("missing resource files: " + ", ".join(missing), 1)
        built = build_from_plan(plan, out, base_dir=mdir)
    return Path(built), notes


TEST_DIR = "test"
TEST_PLAN_FILE = "plan.test.json"


def _make_test(
    mp: MissionPaths,
    bundle: Bundle,
    plan_obj: Any,
    minutes: float | None,
    variant: str | None = None,
) -> Any:
    """make_test_plan + write out/test/{dms_test.lua, plan.test.json}; returns the TestBuild."""
    from dms_gen.planner import (  # type: ignore[import-untyped,unused-ignore]
        make_test_plan,
        write_test_lua,
    )

    try:
        tb = make_test_plan(plan_obj, bundle.spec, bundle.beats, minutes=minutes, variant=variant)
    except ValueError as exc:
        raise CliError(f"test build failed: {exc}", 1) from exc
    tdir = mp.out_dir / TEST_DIR
    lua = write_test_lua(tb, tdir)
    (tdir / TEST_PLAN_FILE).write_text(tb.plan.model_dump_json(indent=2), encoding="utf-8")
    _echo(f"test: proxy '{tb.proxy}'  route {tb.route_km} km  minutes {tb.minutes:g}")
    _echo(f"test: wrote {lua} and {tdir / TEST_PLAN_FILE}")
    return tb


def _build_test(
    mp: MissionPaths, tb: Any, output: Path | None, lua: Path | None
) -> tuple[Path, list[str]]:
    out = output or mp.out_dir / f"{tb.plan.mission_id}-test.miz"
    tdir = mp.out_dir / TEST_DIR
    return _build_obj(tb.plan, mp.dir, out, lua, tdir, tdir)


def _harness_hint(miz: Path, minutes: float) -> str:
    return f"uv run python tools/dcs_harness/run_mission.py {miz} --minutes {minutes:g} --accel 16"


def _saved_seed(mp: MissionPaths) -> int | None:
    p = mp.out_dir / PLAN_FILE
    if not p.is_file():
        return None
    try:
        seed = json.loads(p.read_text(encoding="utf-8")).get("seed")
    except (OSError, ValueError):
        return None
    return int(seed) if isinstance(seed, int) else None


# ---- commands ----------------------------------------------------------------------------------

Target = Annotated[Path, typer.Argument(help="Mission folder or mission-spec.yaml.")]
JsonOpt = Annotated[bool, typer.Option("--json", help="Machine-readable JSON output.")]
TestOpt = Annotated[
    bool,
    typer.Option(
        "--test",
        help="Headless-DCS test variant: AI player proxy + in-mission checks (out/test/, "
        "<id>-test.miz). Normal outputs are left untouched.",
    ),
]
VariantOpt = Annotated[
    str | None,
    typer.Option(
        "--variant",
        help="Player-flight start variant (e.g. ramp / air): build only <id>-<variant>.miz; "
        "with --test, take the proxy from this variant.",
    ),
]
TestMinutesOpt = Annotated[
    float | None,
    typer.Option("--test-minutes", help="Override the test's model minutes (default: derived)."),
]


@app.command()
@_guard
def validate(
    target: Target,
    beats: Annotated[Path | None, typer.Option(help="beats.yaml (default: next to spec).")] = None,
    lines: Annotated[Path | None, typer.Option(help="lines.yaml (default: next to spec).")] = None,
    bible: Annotated[
        Path | None, typer.Option(help="bible.yaml (default: nearest one walking up).")
    ] = None,
    as_json: JsonOpt = False,
    lint: Annotated[
        bool,
        typer.Option(
            "--lint/--no-lint",
            help="Run the mission-quality lint (dms_core.lint; arc rules for this mission).",
        ),
    ] = True,
    strict: Annotated[
        bool, typer.Option("--strict", help="Treat warnings as errors (exit 1 on any).")
    ] = False,
) -> None:
    """Validate mission-spec/beats/lines (schema + cross-file + planner checks + quality lint).

    TARGET may also be a campaign's arc.yaml: schema check plus the campaign-wide arc lint.
    """
    mp: MissionPaths | None
    findings: list[Finding]
    note: str | None
    if target.is_file() and target.name == "arc.yaml":
        from dms_core.lint import lint_arc
        from dms_core.schemas import CampaignArc

        try:
            arc_obj = CampaignArc.model_validate(load_yaml(target))
        except ValidationError as exc:
            findings = pydantic_findings(exc, target.name, CampaignArc)
        else:
            findings = [finding_from(i) for i in lint_arc(arc_obj, target.parent)] if lint else []
        mp = None
        note = None
    else:
        mp = resolve_mission(target, beats=beats, lines=lines, bible=bible, root=_root())
        findings, bundle, note = _validate(mp)
        if lint and bundle is not None:
            from dms_core.lint import lint_mission_dir

            findings += [
                finding_from(i)
                for i in lint_mission_dir(
                    bundle.mission_dir, bundle.spec, bundle.beats, bundle.lines, bundle.bible
                )
            ]
    errs = [f for f in findings if f.severity == "error" or (strict and f.severity == "warning")]
    if as_json:
        _echo(
            dumps(
                {
                    "ok": not errs,
                    "errors": len(errs),
                    "warnings": len(findings) - len(errs),
                    "files": (
                        {k: v for k, v in dataclasses.asdict(mp).items() if k != "dir"}
                        if mp is not None
                        else {"arc": target}
                    ),
                    "note": note,
                    "issues": [f.to_dict() for f in findings],
                }
            )
        )
    else:
        _print_findings(findings)
        if note:
            _echo(f"note: {note}")
        used = (
            ", ".join(p.name for p in (mp.spec, mp.beats, mp.lines, mp.bible) if p)
            if mp is not None
            else target.name
        )
        status = "OK" if not errs else "FAILED"
        _echo(f"{status}: {len(errs)} error(s), {len(findings) - len(errs)} warning(s) [{used}]")
    if errs:
        raise typer.Exit(1)


@app.command()
@_guard
def plan(
    target: Target,
    output: Annotated[
        Path | None, typer.Option("-o", "--output", help="Default <mission>/out/plan.json.")
    ] = None,
    seed: Annotated[int | None, typer.Option(help="Override the planner seed.")] = None,
    voice_manifest: Annotated[
        Path | None, typer.Option(help="Default <mission>/voice/manifest.json if present.")
    ] = None,
    test: TestOpt = False,
    test_minutes: TestMinutesOpt = None,
) -> None:
    """Compile a mission spec into an exact, seeded plan.json."""
    mp = resolve_mission(target, root=_root())
    findings, bundle = _load_bundle(mp)
    if bundle is None:
        _print_findings(findings)
        raise CliError("schema errors; run `dms validate` and fix them first", 1)
    manifest_path = voice_manifest or (mp.voice_manifest if mp.voice_manifest.is_file() else None)
    plan_obj = _plan(bundle, seed, manifest_path)
    if test:
        for line in _plan_summary(plan_obj):
            _echo(line)
        _make_test(mp, bundle, plan_obj, test_minutes)
        return
    out = (output or mp.out_dir / PLAN_FILE).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(plan_obj.model_dump_json(indent=2), encoding="utf-8")
    for line in _plan_summary(plan_obj):
        _echo(line)
    _echo(f"voice manifest: {manifest_path if manifest_path else 'none (subtitles only)'}")
    _echo(f"wrote {out}")


@app.command()
@_guard
def voice(
    target: Annotated[Path, typer.Argument(help="lines.yaml or mission folder.")],
    out: Annotated[Path | None, typer.Option(help="Output dir (default <mission>/voice).")] = None,
    dry_run: Annotated[bool, typer.Option("--dry-run", help="Estimate cost only.")] = False,
    fx: Annotated[str | None, typer.Option(help="Radio FX preset.")] = None,
    voices: Annotated[Path | None, typer.Option(help="speaker->voice JSON.")] = None,
    model: Annotated[str | None, typer.Option(help="TTS model id.")] = None,
    offline: Annotated[
        bool,
        typer.Option("--offline", help="Placeholder tone clips: no API key, no cost."),
    ] = False,
    rerender: Annotated[
        list[str] | None,
        typer.Option(
            "--rerender", metavar="LINE_ID", help="Force a fresh take of this line (repeatable)."
        ),
    ] = None,
    no_raw_cache: Annotated[
        bool,
        typer.Option("--no-raw-cache", help="Force a fresh take of every line (bills all)."),
    ] = False,
) -> None:
    """Render lines.yaml to radio-FX .ogg files (delegates to dms_voice)."""
    from dms_voice.cli import main as voice_main

    lines = target.resolve()
    if lines.is_dir():
        lines = lines / "lines.yaml"
    if not lines.is_file():
        raise CliError(f"not found: {lines}")
    argv = [str(lines)]
    for flag, val in (("--out", out), ("--fx", fx), ("--voices", voices), ("--model", model)):
        if val is not None:
            argv += [flag, str(val)]
    for line_id in rerender or []:
        argv += ["--rerender", line_id]
    for flag, on in (
        ("--dry-run", dry_run),
        ("--offline", offline),
        ("--no-raw-cache", no_raw_cache),
    ):
        if on:
            argv.append(flag)
    try:
        rc = voice_main(argv)
    except SystemExit as exc:  # argparse errors
        rc = exc.code if isinstance(exc.code, int) else 2
    if rc:
        raise typer.Exit(rc)


@app.command()
@_guard
def build(
    target: Annotated[Path, typer.Argument(help="plan.json or mission folder.")],
    output: Annotated[
        Path | None, typer.Option("-o", "--output", help="Default <mission>/out/<id>.miz.")
    ] = None,
    lua: Annotated[
        Path | None, typer.Option(help="Lua bundle (default dist/dms.lua, auto-rebuilt).")
    ] = None,
    test: TestOpt = False,
    test_minutes: TestMinutesOpt = None,
    seed: Annotated[
        int | None, typer.Option(help="--test: planner seed (default: seed of out/plan.json).")
    ] = None,
    variant: VariantOpt = None,
) -> None:
    """Build a .miz from plan.json (one per player-flight variant), then check each."""
    if test:
        _build_test_cmd(target, output, lua, test_minutes, seed, variant)
        return
    t = target.resolve()
    plan_path = t / "out" / PLAN_FILE if t.is_dir() else t
    if not plan_path.is_file():
        raise CliError(f"no plan at {plan_path}; run `dms plan` first")
    if not _build_and_check(plan_path, output, lua, variant, ""):
        _echo("the .miz was written but check found problems")
        raise typer.Exit(1)


def _build_and_check(
    plan_path: Path, output: Path | None, lua: Path | None, variant: str | None, indent: str
) -> bool:
    """Build all variants of plan.json and check each .miz; True when every check passed."""
    ok = True
    _warn_placeholder_voice(mission_dir_for_plan(plan_path), indent)
    builds = _build_variants(plan_path, output, lua, variant)
    for v, built, notes in builds:
        for n in notes:
            _echo(f"{indent}{n}")
        if v is None and len(builds) > 1:
            continue  # <id>.miz alias: a byte copy of the first variant, already checked
        _echo(f"{indent}built {built}" + (f" (variant {v})" if v else ""))
        if not _print_check(_check(built)):
            ok = False
    return ok


def _warn_placeholder_voice(mission_dir: Path, indent: str) -> None:
    """Warn when voice/manifest.json holds offline placeholder clips (tone bursts, not speech).

    Lives on the build path: ``dms check`` only sees the .miz, which has no manifest."""
    path = mission_dir / "voice" / "manifest.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return
    if not isinstance(data, dict):
        return
    ids = sorted(
        str(k)
        for k, v in data.items()
        if isinstance(v, dict) and (v.get("placeholder") or v.get("model") == "placeholder")
    )
    if ids:
        _echo(
            f"{indent}WARNING: {len(ids)}/{len(data)} voice clips are offline placeholders "
            f"(tone bursts, not speech): {', '.join(ids[:5])}{' ...' if len(ids) > 5 else ''}; "
            "re-render with `dms voice <mission>` (no --offline) before flying"
        )


def _build_test_cmd(
    target: Path,
    output: Path | None,
    lua: Path | None,
    minutes: float | None,
    seed: int | None,
    variant: str | None = None,
) -> None:
    t = target.resolve()
    if t.is_file() and t.suffix == ".json":
        t = mission_dir_for_plan(t)
    mp = resolve_mission(t, root=_root())
    findings, bundle = _load_bundle(mp)
    if bundle is None:
        _print_findings(findings)
        raise CliError("schema errors; run `dms validate` and fix them first", 1)
    seed = seed if seed is not None else _saved_seed(mp)
    manifest_path = mp.voice_manifest if mp.voice_manifest.is_file() else None
    plan_obj = _plan(bundle, seed, manifest_path)
    _echo(f"test: planned seed {plan_obj.seed}")
    tb = _make_test(mp, bundle, plan_obj, minutes, variant)
    _warn_placeholder_voice(mp.dir, "")
    built, notes = _build_test(mp, tb, output, lua)
    for n in notes:
        _echo(n)
    _echo(f"built {built}")
    ok = _print_check(_check(built))
    _echo("harness: " + _harness_hint(built, tb.minutes))
    if not ok:
        _echo("the .miz was written but check found problems")
        raise typer.Exit(1)


@app.command()
@_guard
def check(
    miz: Annotated[
        Path, typer.Argument(help=".miz file, or a mission folder (checks every built variant).")
    ],
    as_json: JsonOpt = False,
) -> None:
    """Structural check of a .miz (IDs, slots, resources, config, Lua syntax)."""
    targets = _check_targets(miz)
    reports = [_check(m) for m in targets]
    if as_json:
        if len(reports) == 1:
            _echo(dumps(reports[0]))
        else:
            _echo(dumps({str(m): r for m, r in zip(targets, reports, strict=True)}))
        ok = all(bool(getattr(r, "ok", False)) for r in reports)
    else:
        ok = True
        for m, r in zip(targets, reports, strict=True):
            if len(targets) > 1:
                _echo(f"{m.name}:")
            ok = _print_check(r) and ok
    if not ok:
        raise typer.Exit(1)


def _check_targets(target: Path) -> list[Path]:
    """The .miz files ``dms check`` should check for ``target``.

    A .miz is itself. A mission folder (or its ``out/``) resolves like ``dms build`` writes:
    ``out/<id>-<variant>.miz`` for each player-flight variant in ``out/plan.json``, else
    ``out/<id>.miz``. Without a plan, every non-test ``out/*.miz``."""
    if target.is_file():
        return [target.resolve()]
    if not target.is_dir():
        raise CliError(f"not found: {target}")
    t = target.resolve()
    out = t if t.name == "out" and not (t / "out").is_dir() else t / "out"
    plan_path = out / PLAN_FILE
    names: list[str] = []
    if plan_path.is_file():
        from dms_core.schemas import BuildPlan
        from dms_core.variants import plan_variants, variant_miz_name

        try:
            plan = BuildPlan.model_validate_json(plan_path.read_text(encoding="utf-8"))
        except ValidationError:
            plan = None
        if plan is not None:
            variants = plan_variants(plan)
            names = [variant_miz_name(plan.mission_id, v) for v in variants] or [
                variant_miz_name(plan.mission_id, None)
            ]
    found = [out / n for n in names if (out / n).is_file()]
    if not found:
        found = sorted(p for p in out.glob("*.miz") if not p.name.endswith("-test.miz"))
    if not found:
        raise CliError(f"no built .miz in {out}; run `dms build {target}` first")
    return found


@app.command()
@_guard
def run(
    target: Target,
    seed: Annotated[int | None, typer.Option(help="Override the planner seed.")] = None,
    skip_voice: Annotated[bool, typer.Option("--skip-voice", help="Never render voice.")] = False,
    output: Annotated[Path | None, typer.Option("-o", "--output", help=".miz path.")] = None,
    test: TestOpt = False,
    test_minutes: TestMinutesOpt = None,
    install: Annotated[
        bool,
        typer.Option("--install", help="After a clean build, copy the .miz files into DCS."),
    ] = False,
    dcs: Annotated[
        str, typer.Option("--dcs", help="--install target: stable | openbeta | auto.")
    ] = "auto",
) -> None:
    """validate -> voice -> plan -> build -> check, stopping at the first failure."""
    root = _root()
    mp = resolve_mission(target, root=root)

    _echo("[1/5] validate")
    findings, bundle, note = _validate(mp)
    errs = _errors(findings)
    _print_findings(findings)
    if note:
        _echo(f"  note: {note}")
    if errs or bundle is None:
        _echo(f"  FAILED: {len(errs)} error(s)")
        raise typer.Exit(1)
    _echo(f"  OK ({len(findings)} warning(s))")

    _echo("[2/5] voice")
    _run_voice_step(mp, skip_voice)

    _echo("[3/5] plan")
    manifest_path = mp.voice_manifest if mp.voice_manifest.is_file() else None
    plan_obj = _plan(bundle, seed, manifest_path)
    for line in _plan_summary(plan_obj):
        _echo(f"  {line}")
    tb: Any = None
    plan_path = mp.out_dir / PLAN_FILE
    if test:
        tb = _make_test(mp, bundle, plan_obj, test_minutes)
    else:
        plan_path.parent.mkdir(parents=True, exist_ok=True)
        plan_path.write_text(plan_obj.model_dump_json(indent=2), encoding="utf-8")
        _echo(f"  wrote {plan_path}")

    _echo("[4/5] build")
    if tb is None:
        _echo("[5/5] check")
        if not _build_and_check(plan_path, output, None, None, "  "):
            _echo("FAILED: the .miz was written but check found problems")
            raise typer.Exit(1)
        _echo(f"DONE: {mp.out_dir}")
        if install:
            _install(mp.dir, dcs, dry_run=False, include_test=False)
        return
    if install:
        _echo("note: --install is ignored with --test (use `dms install --test`)")
    built, notes = _build_test(mp, tb, output, None)
    for n in notes:
        _echo(f"  {n}")
    _echo(f"  built {built}")

    _echo("[5/5] check")
    if not _print_check(_check(built)):
        _echo(f"FAILED: {built} was written but check found problems")
        raise typer.Exit(1)
    if tb is not None:
        _echo("harness: " + _harness_hint(built, tb.minutes))
    _echo(f"DONE: {built}")


def _voice_estimate(lines: Path) -> str:
    try:
        from dms_voice.cli import load_line_set, resolve_voices
        from dms_voice.render import plan_lines

        line_set = load_line_set(lines)
        est = plan_lines(line_set.lines, resolve_voices(lines), model=line_set.model)
        return str(est.summary())
    except Exception as exc:  # estimate is advisory only
        return f"estimate unavailable ({exc})"


def _run_voice_step(mp: MissionPaths, skip: bool) -> None:
    if mp.lines is None:
        _echo("  skipped: no lines.yaml")
        return
    if mp.voice_manifest.is_file() or skip:
        why = "manifest present" if mp.voice_manifest.is_file() else "--skip-voice"
        _echo(f"  skipped ({why}); cost to (re)render: {_voice_estimate(mp.lines)}")
        return
    _echo(f"  estimate: {_voice_estimate(mp.lines)}")
    from dms_voice.cli import main as voice_main

    try:
        rc = voice_main([str(mp.lines)])
    except SystemExit as exc:
        rc = exc.code if isinstance(exc.code, int) else 2
    if rc:
        _echo("  WARNING: voice render failed; continuing with subtitles only")
    else:
        _echo(f"  wrote {mp.voice_manifest}")


@app.command()
@_guard
def schema(
    out: Annotated[Path | None, typer.Option(help="Output dir (default <root>/schemas).")] = None,
) -> None:
    """Export JSON Schemas for every DMS file format."""
    from dms_core.schemas import export_json_schemas

    paths = export_json_schemas(out or _root() / "schemas")
    for p in paths:
        _echo(f"wrote {p}")


@app.command("bundle-lua")
@_guard
def bundle_lua(
    out: Annotated[Path | None, typer.Option(help="Default <root>/dist/dms.lua.")] = None,
) -> None:
    """Concatenate lua/src/dms (manifest order) into dist/dms.lua."""
    root = _root()
    path = _bundle_lua(root, (out or root / "dist" / "dms.lua").resolve())
    _echo(f"wrote {path}")


# ---- install / doctor --------------------------------------------------------------------------


def _install(target: Path, dcs: str, *, dry_run: bool, include_test: bool) -> Any:
    from . import install as inst

    plan_obj = inst.plan_install(target, dcs, include_test)
    inst.execute_install(plan_obj, dry_run, _echo)
    return plan_obj


DcsOpt = Annotated[str, typer.Option("--dcs", help="stable | openbeta | auto (newest dcs.log).")]


@app.command("install")
@_guard
def install_cmd(
    target: Annotated[
        Path, typer.Argument(help="Mission folder, mission-spec.yaml, its out/ dir or a .miz.")
    ],
    dcs: DcsOpt = "auto",
    dry_run: Annotated[bool, typer.Option("--dry-run", help="Print, copy nothing.")] = False,
    test: Annotated[bool, typer.Option("--test", help="Also install <id>-test.miz.")] = False,
    as_json: JsonOpt = False,
) -> None:
    """Copy built .miz files to <Saved Games>/DCS[.openbeta]/Missions/DMS/<campaign>/."""
    from . import install as inst

    if not as_json:
        _install(target, dcs, dry_run=dry_run, include_test=test)
        return
    plan_obj = inst.plan_install(target, dcs, test)
    inst.execute_install(plan_obj, dry_run, None)
    _echo(dumps(plan_obj.to_dict(dry_run)))


@app.command()
@_guard
def doctor(as_json: JsonOpt = False) -> None:
    """Check the toolchain: packages, Lua 5.1, ffmpeg, voice key, DCS folders, bundle, LFS, uv."""
    from . import install as inst

    rows = inst.run_doctor(_root())
    failed = any(r.status == "FAIL" for r in rows)
    if as_json:
        _echo(dumps({"ok": not failed, "checks": [r.to_dict() for r in rows]}))
    else:
        for line in inst.render_doctor(rows):
            _echo(line)
    if failed:
        raise typer.Exit(1)


# ---- catalog -----------------------------------------------------------------------------------


def _table(rows: list[dict[str, Any]], cols: list[str]) -> None:
    if not rows:
        _echo("(no matches)")
        return
    cells = [[_cell(r.get(c)) for c in cols] for r in rows]
    widths = [max(len(c), *(len(row[i]) for row in cells)) for i, c in enumerate(cols)]
    _echo("  ".join(c.ljust(w) for c, w in zip(cols, widths, strict=True)).rstrip())
    for row in cells:
        _echo("  ".join(v.ljust(w) for v, w in zip(row, widths, strict=True)).rstrip())


def _cell(v: Any) -> str:
    if isinstance(v, list | tuple):
        return ",".join(str(x) for x in v)
    if isinstance(v, float):
        return f"{v:.0f}" if abs(v) >= 100 else f"{v:.3f}"
    return "" if v is None else str(v)


_eras_for = eras_for  # shared with dms-mcp (dms_cli.util)


def _catalog() -> Any:
    from dms_core import catalog

    cat_dir = _root() / "data" / "catalog"
    return catalog.load_catalog(cat_dir if cat_dir.is_dir() else None)


def _emit(rows: list[dict[str, Any]], cols: list[str], as_json: bool) -> None:
    if as_json:
        _echo(dumps(rows))
    else:
        _table(rows, cols)
        _echo(f"{len(rows)} result(s)")


EraOpt = Annotated[str | None, typer.Option(help="Era id or a year, e.g. modern or 1985.")]
CoalOpt = Annotated[str | None, typer.Option(help="blue | red | neutral.")]
RoleOpt = Annotated[str | None, typer.Option(help="Role or tag, e.g. sam_short, mbt.")]
CatOpt = Annotated[str | None, typer.Option(help="Domain, e.g. ground, air, ship.")]


@catalog_app.command("units")
@_guard
def catalog_units(
    era: EraOpt = None,
    coalition: CoalOpt = None,
    role: RoleOpt = None,
    category: CatOpt = None,
    as_json: JsonOpt = False,
) -> None:
    """DCS unit types matching the filters."""
    cat = _catalog()
    eras = _eras_for(cat, era)
    units = cat.find_units(coalition=coalition, role=role, category=category)
    if eras is not None:
        units = [u for u in units if set(u.eras) & set(eras)]
    rows = [u.model_dump(mode="json") for u in units]
    _emit(rows, ["id", "name", "category", "role", "threat", "eras", "coalitions"], as_json)


@catalog_app.command("templates")
@_guard
def catalog_templates(
    era: EraOpt = None,
    coalition: CoalOpt = None,
    role: RoleOpt = None,
    category: CatOpt = None,
    as_json: JsonOpt = False,
) -> None:
    """Group templates (usable as threat/pool members)."""
    cat = _catalog()
    eras = _eras_for(cat, era)
    tpls = cat.find_templates(role=role, coalition=coalition, category=category)
    if eras is not None:
        tpls = [t for t in tpls if not t.eras or set(t.eras) & set(eras)]
    rows = [t.model_dump(mode="json") for t in tpls]
    for r, t in zip(rows, tpls, strict=True):
        r["n_units"] = len(t.units)
    if not rows and role is not None and not as_json:
        if role == "civilian":
            _echo(
                "no catalog templates for 'civilian': the planner builds civilian groups from "
                "a neutral bible faction's dcs.units (see `dms catalog units --coalition neutral`)"
            )
        elif role not in cat.template_roles():
            _echo(f"unknown role '{role}'. Valid roles: {', '.join(cat.template_roles())}")
    _emit(rows, ["id", "name", "role", "coalition", "category", "n_units", "eras"], as_json)


@catalog_app.command("airbases")
@_guard
def catalog_airbases(
    theater: Annotated[str, typer.Option(help="DCS map, e.g. Syria, Caucasus.")],
    near: Annotated[
        str | None, typer.Option(help="Airbase name or 'x,y' map metres; sorts by distance.")
    ] = None,
    limit: Annotated[int | None, typer.Option(help="Max results.")] = None,
    as_json: JsonOpt = False,
) -> None:
    """Airbases on a theater (pydcs terrain data)."""
    from dms_core import catalog
    from dms_core.catalog import CatalogLookupError

    ref: str | tuple[float, float] | None = near
    if near and re.fullmatch(r"\s*-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?\s*", near):
        x, y = (float(v) for v in near.split(","))
        ref = (x, y)
    try:
        bases = catalog.find_airbases(theater, near=ref, limit=limit)
    except CatalogLookupError as exc:
        raise CliError(str(exc)) from None
    rows = [b.model_dump(mode="json") for b in bases]
    cols = ["name", "id", "x", "y", "lat", "lon", "uhf_mhz", "vhf_mhz"]
    if near:
        cols.append("distance_m")
    _emit(rows, cols, as_json)


@catalog_app.command("mission-types")
@_guard
def catalog_mission_types(
    as_json: JsonOpt = False,
) -> None:
    """Mission types with typical aircraft, roles and duration."""
    cat = _catalog()
    if as_json:
        _echo(dumps([m.model_dump(mode="json") for m in cat.mission_types.values()]))
        return
    rows = [
        {
            "id": m.id,
            "name": m.name,
            "player_roles": m.player_roles,
            "duration_min": f"{m.duration_min[0]}-{m.duration_min[1]}",
            "intensities": list(m.threats),
        }
        for m in cat.mission_types.values()
    ]
    _emit(rows, ["id", "name", "player_roles", "duration_min", "intensities"], False)


# ---- outcome / campaign ------------------------------------------------------------------------


@app.command()
@_guard
def outcome(
    log: Annotated[Path, typer.Argument(help="Path to dcs.log.")],
    mission_id: Annotated[str | None, typer.Option(help="Only this mission id.")] = None,
    as_json: JsonOpt = False,
) -> None:
    """Parse [DMS.OUTCOME] lines from dcs.log."""
    from dms_core.schemas import parse_dcs_log, summarize_outcomes

    if not log.is_file():
        raise CliError(f"not found: {log}")
    recs = parse_dcs_log(log.read_text(encoding="utf-8", errors="replace"))
    if mission_id:
        recs = [r for r in recs if r.mission_id == mission_id]
    summary = summarize_outcomes(recs)
    if as_json:
        _echo(dumps({"records": recs, "summary": summary}))
        return
    if not recs:
        _echo("no [DMS.OUTCOME] lines found")
        return
    for r in recs:
        t = f"t={r.time:.0f}s" if r.time is not None else "t=?"
        what = " ".join(x for x in (r.kind, r.beat, r.result) if x)
        facts = json.dumps(r.outcomes, ensure_ascii=False) if r.outcomes else ""
        _echo(f"{t} {r.mission_id or '-'} {what} {facts}".rstrip())
    for key, s in summary.items():
        _echo(
            f"summary {key or '(no mission id)'}: result={s.result} outcomes={s.outcomes} "
            f"kills={s.kills} losses={s.losses} flags={s.flags}"
        )
    _echo(f"{len(recs)} record(s)")


@app.command()
@_guard
def debrief(
    campaign_dir: Annotated[Path, typer.Argument(help="campaigns/<slug> folder.")],
    mission: Annotated[
        str, typer.Option("--mission", "-m", help="Mission id or prefix, e.g. m01.")
    ],
    log: Annotated[
        Path | None,
        typer.Option(help="dcs.log (or its Logs dir). Default: newest stable/openbeta log."),
    ] = None,
    dry_run: Annotated[bool, typer.Option("--dry-run", help="Print, write nothing.")] = False,
    force: Annotated[
        bool, typer.Option("--force", help="Re-apply even if this flight was already debriefed.")
    ] = False,
    seed: Annotated[int | None, typer.Option(help="Seed for branch `chance` rolls.")] = None,
    no_arc_effects: Annotated[
        bool,
        typer.Option("--no-arc-effects", help="Apply beat qualityDeltas only, not arc effects."),
    ] = False,
    force_arc_effects: Annotated[
        bool,
        typer.Option(
            "--force-arc-effects",
            help="Apply arc quality_effects even though the flight did not end (no end line).",
        ),
    ] = False,
    no_continuity: Annotated[
        bool, typer.Option("--no-continuity", help="Do not append to continuity.md.")
    ] = False,
    acmi: Annotated[
        str | None,
        typer.Option(help="Tacview ACMI file, or 'auto' (newest in Documents/Tacview)."),
    ] = None,
    acmi_player: Annotated[
        str | None, typer.Option(help="ACMI player: object id, Pilot, Name, CallSign or Group.")
    ] = None,
    acmi_facts: Annotated[
        bool, typer.Option("--acmi-facts", help="Also merge tv_* facts into outcomes.")
    ] = False,
    as_json: JsonOpt = False,
) -> None:
    """dcs.log [DMS.OUTCOME] -> state/outcomes/<mNN>.yaml, qualities, continuity, next mission."""
    import datetime
    import random

    from dms_core import outcomes as oc

    camp = campaign_dir.resolve()
    if not camp.is_dir():
        raise CliError(f"not a campaign folder: {campaign_dir}")
    try:
        arc, state = oc.load_debrief_inputs(camp)
    except (ValidationError, OSError) as exc:
        raise CliError(f"cannot load campaign state: {exc}") from None
    mission_id = mission
    if arc is not None:
        resolved = oc.resolve_arc_mission(arc, mission)
        if resolved is None:
            ids = ", ".join(m.id for m in arc.all_missions())
            raise CliError(f"mission '{mission}' not found in arc.yaml (missions: {ids})")
        mission_id = resolved

    paths = oc.explicit_log_paths(log.resolve()) if log is not None else oc.default_log_paths()
    if log is not None and not paths:
        raise CliError(f"not found: {log}")
    try:
        log_path, session = oc.find_mission_session(paths, mission_id)
        outcome_obj = oc.build_outcome(session, mission_id, log_path)
    except oc.DebriefError as exc:
        raise CliError(str(exc), 1) from None
    if acmi is not None:
        from .cmd_debrief_acmi import apply_acmi

        outcome_obj = apply_acmi(
            outcome_obj, camp, mission_id, acmi, player=acmi_player, merge_facts=acmi_facts
        )
    same_flight = oc.already_debriefed(camp, mission_id, outcome_obj)
    if same_flight and not force and not dry_run:
        raise CliError(
            f"this flight ({log_path}, session {outcome_obj.extra.get('session_start')}) is "
            f"already in {oc.outcome_path(camp, mission_id)}; use --force to re-apply",
            1,
        )
    rollback_notes: list[str] = []
    if same_flight and force:
        # Re-applying the same flight: undo its previous quality changes/flags first.
        state, rollback_notes = oc.rollback_previous(camp, mission_id, state, arc)
    rng = random.Random(seed) if seed is not None else None
    update = oc.apply_outcome(
        state,
        outcome_obj,
        mission_id,
        arc,
        rng,
        arc_effects=not no_arc_effects,
        force_arc_effects=force_arc_effects,
    )
    update.warnings[:0] = rollback_notes
    outcome_obj = outcome_obj.model_copy(
        update={
            "extra": {
                **outcome_obj.extra,
                "quality_changes": [c.to_dict() for c in update.changes],
                "flags_set": update.flags_set,
                "next_mission": update.next_mission,
                "next_reason": update.next_reason,
                "warnings": update.warnings,
            }
        }
    )
    written: list[Path] = []
    if not dry_run:
        entry = None
        if not no_continuity:
            today = datetime.date.today().isoformat()
            entry = oc.continuity_entry(mission_id, outcome_obj, update, today)
        # continuity -> qualities -> outcomes/<mNN>.yaml (the guard) last, each atomic
        written = oc.commit_debrief(camp, mission_id, outcome_obj, update, entry)

    if as_json:
        _echo(
            dumps(
                {
                    "mission_id": mission_id,
                    "log_file": str(log_path),
                    "outcome": outcome_obj.model_dump(mode="json", exclude_none=True),
                    "qualities": update.state.model_dump(mode="json"),
                    "next_mission": update.next_mission,
                    "next_reason": update.next_reason,
                    "warnings": update.warnings,
                    "written": [str(p) for p in written],
                    "dry_run": dry_run,
                }
            )
        )
        return
    ex = outcome_obj.extra
    _echo(f"log: {log_path} (session line {session.start_line}, {ex.get('session_start')})")
    _echo(
        f"mission: {mission_id}  result: {outcome_obj.result or 'unknown'}  "
        f"ended: {'yes' if ex.get('ended') else 'NO'}  records: {ex.get('records')}  "
        f"t={outcome_obj.time or 0:.0f}s"
    )
    _echo(f"outcomes: {json.dumps(outcome_obj.outcomes, ensure_ascii=False)}")
    _echo(f"beats fired ({len(ex.get('beats_fired', []))}): {', '.join(ex.get('beats_fired', []))}")
    for c in update.changes:
        _echo(f"quality {c.quality}: {c.before} -> {c.after} ({c.reason})")
    if not update.changes:
        _echo("quality: no changes")
    _echo("flags: " + (", ".join(f"{k}={v}" for k, v in update.flags_set.items()) or "none"))
    for issue in ex.get("log_errors", []):
        _echo(f"LOG ERROR line {issue['line']} [{issue['module']}] {issue['message']}")
    for issue in ex.get("log_warnings", []):
        _echo(f"log warning line {issue['line']} [{issue['module']}] {issue['message']}")
    for m in ex.get("malformed_lines", []):
        _echo(f"skipped malformed [DMS.OUTCOME] line {m['line']}: {m['reason']}")
    for w in update.warnings:
        _echo(f"warning: {w}")
    from .cmd_debrief_acmi import report_lines

    for line in report_lines(outcome_obj):
        _echo(line)
    _echo(f"next mission: {update.next_mission or '(none)'} ({update.next_reason})")
    if dry_run:
        _echo("dry run: nothing written")
    for p in written:
        _echo(f"wrote {p}")


_SLUG = re.compile(r"^[a-z0-9][a-z0-9-]*$")


@app.command("new-campaign")
@_guard
def new_campaign(
    slug: Annotated[str, typer.Argument(help="lower-case-slug")],
    with_example: Annotated[
        bool,
        typer.Option(
            "--with-example",
            help="Also copy the template's example mission and outcome (skipped by default).",
        ),
    ] = False,
) -> None:
    """Create campaigns/<slug> from campaigns/_template (example files skipped by default)."""
    if not _SLUG.match(slug) or slug == "_template":
        raise CliError("slug must be lower-case letters, digits and hyphens, e.g. 'dustoff-valley'")
    root = _root()
    dest = root / "campaigns" / slug
    if dest.exists():
        raise CliError(f"{dest} already exists")
    template = root / "campaigns" / "_template"
    if template.is_dir():
        ignore = None if with_example else shutil.ignore_patterns("*example*")
        shutil.copytree(template, dest, ignore=ignore)
        skipped = "" if with_example else " (example files skipped; --with-example keeps them)"
        _echo(f"copied {template} -> {dest}{skipped}")
    else:
        _echo(f"created {dest} (no _template found; empty skeleton)")
    for sub in ("missions", os.path.join("state", "outcomes")):
        (dest / sub).mkdir(parents=True, exist_ok=True)
    _echo("next: write premise.md, then use the story-writer skill to produce bible.yaml")


if __name__ == "__main__":  # pragma: no cover
    app()
