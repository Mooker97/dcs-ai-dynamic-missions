"""Library operations behind the MCP tools. Every function returns a JSON-able ``dict``.

These call ``dms_core`` / ``dms_gen`` directly (never the ``dms`` executable) and reuse the path
and issue helpers in ``dms_cli.util``. Errors the caller can fix come back as
``{"ok": False, "error": ...}`` instead of exceptions, so an MCP client always gets a result.
"""

from __future__ import annotations

import dataclasses
import importlib.util
import json
import os
import tempfile
from collections.abc import Callable
from pathlib import Path
from types import ModuleType
from typing import Any

from dms_cli.util import (
    PLAN_FILE,
    CliError,
    Finding,
    MissionPaths,
    find_root,
    finding_from,
    latest_mtime,
    load_yaml,
    pydantic_findings,
    resolve_mission,
    to_jsonable,
)
from pydantic import BaseModel, ValidationError

#: Last check result, written next to the .miz by ``build`` and ``check``.
CHECK_FILE = "check.json"
TEST_DIR = "test"
TEST_PLAN_FILE = "plan.test.json"
ROOT_ENV = "DMS_ROOT"

#: Standalone (non-mission) YAML files ``validate`` recognises by file name.
_DOC_FILES: dict[str, str] = {
    "bible.yaml": "story-bible",
    "arc.yaml": "campaign-arc",
    "qualities.yaml": "qualities",
}


class OpError(Exception):
    """A user-facing failure; becomes ``{"ok": False, "error": message}``."""


# ---- root / paths ------------------------------------------------------------------------------


def repo_root(root: Path | None = None) -> Path:
    """``root``, else ``$DMS_ROOT``, else the uv workspace found from cwd or this file."""
    if root is not None:
        return root.resolve()
    env = os.environ.get(ROOT_ENV)
    if env:
        return Path(env).resolve()
    return find_root()


def _resolve(path: str | Path, root: Path) -> Path:
    """Absolute paths stay; relative ones resolve against the repo root (not the server cwd)."""
    p = Path(path).expanduser()
    return (p if p.is_absolute() else root / p).resolve()


def _rel(path: Path, root: Path) -> str:
    try:
        return path.resolve().relative_to(root).as_posix()
    except ValueError:
        return str(path)


def guarded(fn: Callable[..., dict[str, Any]]) -> Callable[..., dict[str, Any]]:
    """Turn OpError/CliError into a structured failure result."""
    import functools

    @functools.wraps(fn)
    def wrapper(*args: Any, **kwargs: Any) -> dict[str, Any]:
        try:
            return fn(*args, **kwargs)
        except (OpError, CliError) as exc:
            return {"ok": False, "error": str(exc)}

    return wrapper


# ---- mission bundle ----------------------------------------------------------------------------


@dataclasses.dataclass
class Bundle:
    spec: Any
    beats: Any | None
    lines: Any | None
    bible: Any | None


def load_bundle(mp: MissionPaths) -> tuple[list[Finding], Bundle | None]:
    """Schema-validate spec/beats/lines/bible; ``None`` bundle when any file fails."""
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
    return findings, Bundle(**loaded)


def _semantic(b: Bundle) -> list[Finding]:
    from dms_gen import planner  # type: ignore[import-untyped,unused-ignore]

    issues = planner.validate(b.spec, beats=b.beats, lines=b.lines, bible=b.bible)
    return [finding_from(i) for i in issues]


def _issue_summary(findings: list[Finding]) -> dict[str, Any]:
    errs = sum(1 for f in findings if f.severity == "error")
    return {
        "ok": errs == 0,
        "errors": errs,
        "warnings": len(findings) - errs,
        "issues": [f.to_dict() for f in findings],
    }


def _mission(path: str | Path, root: Path) -> MissionPaths:
    return resolve_mission(_resolve(path, root), root=root)


def _require_bundle(mp: MissionPaths) -> Bundle:
    findings, bundle = load_bundle(mp)
    if bundle is None:
        detail = "; ".join(f.render() for f in findings[:10])
        raise OpError(f"schema errors (run validate and fix them first): {detail}")
    return bundle


# ---- validate ----------------------------------------------------------------------------------


def validate(path: str | Path, root: Path | None = None) -> dict[str, Any]:
    """Validate a mission (dir or mission-spec.yaml) or a bible/arc/qualities YAML file."""
    r = repo_root(root)
    target = _resolve(path, r)
    if target.is_file() and target.name in _DOC_FILES:
        return _validate_document(target, _DOC_FILES[target.name], r)
    mp = _mission(target, r)
    findings, bundle = load_bundle(mp)
    if bundle is not None:
        findings = findings + _semantic(bundle)
    files = {
        k: (_rel(v, r) if isinstance(v, Path) else None)
        for k, v in dataclasses.asdict(mp).items()
        if k != "dir"
    }
    return {"kind": "mission", "path": _rel(mp.dir, r), "files": files, **_issue_summary(findings)}


def _validate_document(path: Path, stem: str, root: Path) -> dict[str, Any]:
    from dms_core.schemas import DOCUMENT_MODELS

    model = DOCUMENT_MODELS[stem]
    findings: list[Finding] = []
    try:
        model.model_validate(load_yaml(path))
    except ValidationError as exc:
        findings = pydantic_findings(exc, path.name, model)
    return {"kind": stem, "path": _rel(path, root), **_issue_summary(findings)}


# ---- plan --------------------------------------------------------------------------------------


def _plan_obj(bundle: Bundle, seed: int | None, manifest: Path | None) -> Any:
    from dms_gen import planner

    try:
        return planner.plan_mission(
            bundle.spec,
            beats=bundle.beats,
            lines=bundle.lines,
            voice_manifest=manifest,
            seed=seed,
            bible=bundle.bible,
        )
    except (planner.PlanError, ValueError, KeyError) as exc:
        raise OpError(f"planning failed: {exc}") from exc


def plan_stats(plan: Any) -> dict[str, Any]:
    groups = list(plan.groups)
    players = [
        {
            "group": g.name,
            "type": g.units[0].type if g.units else None,
            "units": len(g.units),
            "frequency_mhz": getattr(g, "frequency_mhz", None) or getattr(g, "frequency", None),
        }
        for g in groups
        if getattr(g, "client", False)
    ]
    stats: dict[str, Any] = {
        "groups": len(groups),
        "zones": len(plan.zones),
        "triggers": len(plan.triggers),
        "resources": len(plan.resources),
    }
    rt = plan.runtime
    if rt is not None:
        stats["runtime"] = {
            "templates": len(rt.templates),
            "pools": len(rt.pools),
            "encounters": len(rt.encounters),
            "beats": len(rt.beats),
            "voice": len(rt.voice),
        }
    return {
        "mission_id": plan.mission_id,
        "seed": plan.seed,
        "theater": plan.theater,
        "players": players,
        "stats": stats,
    }


def _manifest(mp: MissionPaths) -> Path | None:
    return mp.voice_manifest if mp.voice_manifest.is_file() else None


def plan(
    mission_dir: str | Path, seed: int | None = None, root: Path | None = None
) -> dict[str, Any]:
    """Plan a mission into ``<mission>/out/plan.json``."""
    r = repo_root(root)
    mp = _mission(mission_dir, r)
    bundle = _require_bundle(mp)
    manifest = _manifest(mp)
    plan_obj = _plan_obj(bundle, seed, manifest)
    out = mp.out_dir / PLAN_FILE
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(plan_obj.model_dump_json(indent=2), encoding="utf-8")
    return {
        "ok": True,
        "plan": _rel(out, r),
        "voice_manifest": _rel(manifest, r) if manifest else None,
        **plan_stats(plan_obj),
    }


# ---- build -------------------------------------------------------------------------------------


def _load_tool(root: Path, name: str) -> ModuleType:
    path = root / "tools" / f"{name}.py"
    if not path.is_file():
        raise OpError(f"{path} not found")
    spec = importlib.util.spec_from_file_location(f"_dms_mcp_tool_{name}", path)
    if spec is None or spec.loader is None:
        raise OpError(f"cannot load {path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def bundle_lua(root: Path, out: Path) -> Path:
    """Run tools/bundle_lua.py into ``out``."""
    mod = _load_tool(root, "bundle_lua")
    try:
        result = mod.bundle(out, quiet=True)
    except SystemExit as exc:
        raise OpError(f"bundle_lua failed: {exc.code}") from None
    return Path(result) if result else out


def ensure_lua(root: Path, lua: Path | None = None) -> tuple[Path, str]:
    """The Lua bundle to embed; rebuilds ``dist/dms.lua`` when missing or stale."""
    if lua is not None:
        if not lua.is_file():
            raise OpError(f"lua bundle not found: {lua}")
        return lua.resolve(), "given"
    out = root / "dist" / "dms.lua"
    sources = [*sorted((root / "lua" / "src").rglob("*.lua")), root / "lua" / "manifest.txt"]
    if out.is_file() and out.stat().st_mtime >= latest_mtime(sources):
        return out, "up to date"
    reason = "missing" if not out.is_file() else "stale"
    bundle_lua(root, out)
    return out, f"rebuilt ({reason})"


def _write_runtime_config(plan: Any, cfg_dir: Path) -> Path | None:
    from dms_gen.planner import write_runtime_config

    res = next((x for x in plan.resources if Path(x.path).name == "dms_config.lua"), None)
    if res is None or plan.runtime is None:
        return None
    if not Path(res.source).is_absolute():
        res.source = str((cfg_dir / Path(res.source).name).resolve())
    cfg_dir.mkdir(parents=True, exist_ok=True)
    path = Path(write_runtime_config(plan, base_dir=cfg_dir))
    res.source = str(path.resolve())
    return path


def _resolve_resources(plan: Any, bases: list[Path]) -> None:
    for res in plan.resources:
        src = Path(res.source)
        if src.is_absolute():
            continue
        for base in bases:
            if (base / src).exists():
                res.source = str((base / src).resolve())
                break


def _attach_lua(plan: Any, lua: Path, tmp: Path) -> str:
    from dms_core.schemas import PlanResource

    for res in plan.resources:
        if res.kind == "script" and "dms.lua" in (Path(res.path).name, Path(res.source).name):
            res.source = str(lua)
            return "linked"
    new: list[Any] = []
    if plan.runtime is not None and not any(
        Path(x.path).name == "dms_config.lua" for x in plan.resources
    ):
        cfg = tmp / "dms_config.lua"
        cfg.write_text(plan.runtime.to_lua_source(), encoding="utf-8")
        new.append(PlanResource(path="l10n/DEFAULT/dms_config.lua", source=str(cfg), kind="script"))
    new.append(PlanResource(path="l10n/DEFAULT/dms.lua", source=str(lua), kind="script"))
    plan.resources = new + list(plan.resources)
    return "added"


def _build_plan(
    plan: Any, mdir: Path, out: Path, root: Path, lua: Path | None, cfg_dir: Path
) -> tuple[Path, list[str]]:
    from dms_gen.builder import build_from_plan  # type: ignore[import-untyped,unused-ignore]

    out.parent.mkdir(parents=True, exist_ok=True)
    lua_path, lua_state = ensure_lua(root, lua)
    notes = [f"lua: {_rel(lua_path, root)} ({lua_state})"]
    with tempfile.TemporaryDirectory(prefix="dms-mcp-") as tmp:
        cfg = _write_runtime_config(plan, cfg_dir)
        if cfg is not None:
            notes.append(f"runtime config: {_rel(cfg, root)}")
        _resolve_resources(plan, [mdir, root, cfg_dir])
        notes.append(f"lua resource {_attach_lua(plan, lua_path, Path(tmp))}")
        missing = [x.source for x in plan.resources if not Path(x.source).exists()]
        if missing:
            raise OpError("missing resource files: " + ", ".join(missing))
        built = Path(build_from_plan(plan, out, base_dir=mdir))
    return built, notes


def _saved_seed(mp: MissionPaths) -> int | None:
    p = mp.out_dir / PLAN_FILE
    if not p.is_file():
        return None
    try:
        seed = json.loads(p.read_text(encoding="utf-8")).get("seed")
    except (OSError, ValueError):
        return None
    return seed if isinstance(seed, int) else None


def build(
    mission_dir: str | Path,
    test: bool = False,
    root: Path | None = None,
    lua: Path | None = None,
) -> dict[str, Any]:
    """Build ``<mission>/out/<id>.miz`` from out/plan.json (planned first when missing), then
    check it. ``test`` builds the headless variant ``out/<id>-test.miz`` instead."""
    from dms_core.schemas import BuildPlan

    r = repo_root(root)
    mp = _mission(mission_dir, r)
    notes: list[str] = []
    plan_path = mp.out_dir / PLAN_FILE
    if test:
        bundle = _require_bundle(mp)
        plan_obj = _plan_obj(bundle, _saved_seed(mp), _manifest(mp))
        from dms_gen.planner import make_test_plan, write_test_lua

        try:
            tb = make_test_plan(plan_obj, bundle.spec, bundle.beats)
        except ValueError as exc:
            raise OpError(f"test build failed: {exc}") from exc
        tdir = mp.out_dir / TEST_DIR
        test_lua = write_test_lua(tb, tdir)
        (tdir / TEST_PLAN_FILE).write_text(tb.plan.model_dump_json(indent=2), encoding="utf-8")
        notes.append(f"test: proxy '{tb.proxy}', route {tb.route_km} km, {tb.minutes:g} min")
        notes.append(f"test: wrote {_rel(test_lua, r)}")
        out = mp.out_dir / f"{tb.plan.mission_id}-test.miz"
        built, more = _build_plan(tb.plan, mp.dir, out, r, lua, tdir)
        harness = (
            f"uv run python tools/dcs_harness/run_mission.py {built} "
            f"--minutes {tb.minutes:g} --accel 16"
        )
        summary = plan_stats(tb.plan)
    else:
        if plan_path.is_file():
            try:
                plan_obj = BuildPlan.model_validate_json(plan_path.read_text(encoding="utf-8"))
            except ValidationError as exc:
                detail = "; ".join(
                    f.render() for f in pydantic_findings(exc, plan_path.name, BuildPlan)[:10]
                )
                raise OpError(f"{plan_path.name} is not a valid BuildPlan: {detail}") from None
        else:
            plan_obj = _plan_obj(_require_bundle(mp), None, _manifest(mp))
            plan_path.parent.mkdir(parents=True, exist_ok=True)
            plan_path.write_text(plan_obj.model_dump_json(indent=2), encoding="utf-8")
            notes.append(f"no plan.json; planned seed {plan_obj.seed} -> {_rel(plan_path, r)}")
        summary = plan_stats(plan_obj)
        out = mp.out_dir / f"{plan_obj.mission_id}.miz"
        built, more = _build_plan(plan_obj, mp.dir, out, r, lua, mp.out_dir)
        harness = None
    notes.extend(more)
    report = _check_and_record(built)
    result: dict[str, Any] = {
        "ok": bool(report["ok"]),
        "miz": _rel(built, r),
        "test": test,
        **summary,
        "notes": notes,
        "check": report,
    }
    if harness:
        result["harness"] = harness
    return result


# ---- check -------------------------------------------------------------------------------------


def _check_and_record(miz: Path) -> dict[str, Any]:
    from dms_gen.check import check_miz  # type: ignore[import-untyped,unused-ignore]

    data: dict[str, Any] = to_jsonable(check_miz(miz))
    record = miz.parent / CHECK_FILE
    try:
        existing = json.loads(record.read_text(encoding="utf-8")) if record.is_file() else {}
    except (OSError, ValueError):
        existing = {}
    if not isinstance(existing, dict):
        existing = {}
    existing[miz.name] = {**data, "checked_at": _now()}
    record.write_text(json.dumps(existing, indent=2), encoding="utf-8")
    return data


def _now() -> str:
    import datetime

    return datetime.datetime.now(datetime.UTC).isoformat(timespec="seconds")


def check(miz_path: str | Path, root: Path | None = None) -> dict[str, Any]:
    """Structural check of a .miz; the result is also recorded in ``check.json`` beside it."""
    r = repo_root(root)
    miz = _resolve(miz_path, r)
    if not miz.is_file():
        raise OpError(f"not found: {miz}")
    report = _check_and_record(miz)
    return {**report, "path": _rel(miz, r)}


# ---- schema ------------------------------------------------------------------------------------


def schema(name: str) -> dict[str, Any]:
    """JSON Schema for one document model (stem like ``mission-spec`` or a class name)."""
    from dms_core.schemas import DOCUMENT_MODELS

    key = name.strip().removesuffix(".schema.json").removesuffix(".yaml")
    by_class = {m.__name__.lower(): stem for stem, m in DOCUMENT_MODELS.items()}
    aliases = {"bible": "story-bible", "arc": "campaign-arc", "lines": "voice-lines"}
    stem = key if key in DOCUMENT_MODELS else by_class.get(key.lower()) or aliases.get(key)
    if stem is None:
        raise OpError(f"unknown schema {name!r}; available: {', '.join(DOCUMENT_MODELS)}")
    model = DOCUMENT_MODELS[stem]
    return {"ok": True, "name": stem, "model": model.__name__, "schema": model.model_json_schema()}


# ---- campaign status ---------------------------------------------------------------------------


def _out_files(out_dir: Path, root: Path) -> list[str]:
    if not out_dir.is_dir():
        return []
    return sorted(_rel(p, root) for p in out_dir.rglob("*") if p.is_file())


def _last_check(out_dir: Path) -> dict[str, Any] | None:
    record = out_dir / CHECK_FILE
    if not record.is_file():
        return None
    try:
        data = json.loads(record.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict):
        return None
    summary: dict[str, Any] = {}
    for miz, rep in data.items():
        if not isinstance(rep, dict):
            continue
        issues = rep.get("issues") or []
        summary[str(miz)] = {
            "ok": bool(rep.get("ok")),
            "checked_at": rep.get("checked_at"),
            "errors": sum(
                1 for i in issues if isinstance(i, dict) and i.get("severity") == "error"
            ),
            "warnings": sum(
                1 for i in issues if isinstance(i, dict) and i.get("severity") == "warning"
            ),
        }
    return summary


def campaign_status(campaign_slug: str, root: Path | None = None) -> dict[str, Any]:
    """Missions in ``campaigns/<slug>`` with their arc entry, outputs and last check result."""
    r = repo_root(root)
    camp = r / "campaigns" / campaign_slug
    if not campaign_slug or "/" in campaign_slug or "\\" in campaign_slug or not camp.is_dir():
        available = sorted(
            p.name for p in (r / "campaigns").glob("*") if p.is_dir() and not p.name.startswith("_")
        )
        raise OpError(f"no campaign {campaign_slug!r}; available: {', '.join(available)}")

    arc_titles: dict[str, str] = {}
    arc_order: list[str] = []
    arc = load_yaml(camp / "arc.yaml") if (camp / "arc.yaml").is_file() else None
    if isinstance(arc, dict):
        for act in arc.get("acts") or []:
            for m in (act or {}).get("missions") or []:
                if isinstance(m, dict) and m.get("id"):
                    arc_order.append(str(m["id"]))
                    arc_titles[str(m["id"])] = str(m.get("title") or "")

    qualities = (
        load_yaml(camp / "state" / "qualities.yaml")
        if (camp / "state" / "qualities.yaml").is_file()
        else None
    )
    outcomes_dir = camp / "state" / "outcomes"
    flown = sorted(p.stem for p in outcomes_dir.glob("*.yaml")) if outcomes_dir.is_dir() else []

    missions: list[dict[str, Any]] = []
    seen: set[str] = set()
    mdir_root = camp / "missions"
    for mdir in sorted(p for p in mdir_root.glob("*") if p.is_dir()) if mdir_root.is_dir() else []:
        seen.add(mdir.name)
        out_dir = mdir / "out"
        missions.append(
            {
                "id": mdir.name,
                "title": arc_titles.get(mdir.name),
                "designed": (mdir / "mission-spec.yaml").is_file(),
                "files": sorted(p.name for p in mdir.iterdir() if p.is_file()),
                "voiced": (mdir / "voice" / "manifest.json").is_file(),
                "planned": (out_dir / PLAN_FILE).is_file(),
                "built": sorted(p.name for p in out_dir.glob("*.miz")) if out_dir.is_dir() else [],
                "out": _out_files(out_dir, r),
                "last_check": _last_check(out_dir),
                "debriefed": mdir.name.split("-")[0] in flown or mdir.name in flown,
            }
        )
    undesigned = [
        {"id": mid, "title": arc_titles[mid], "designed": False}
        for mid in arc_order
        if mid not in seen
    ]
    q = qualities if isinstance(qualities, dict) else {}
    return {
        "ok": True,
        "campaign": campaign_slug,
        "path": _rel(camp, r),
        "title": arc.get("title") if isinstance(arc, dict) else None,
        "files": sorted(p.name for p in camp.iterdir() if p.is_file()),
        "qualities": q.get("values") or {},
        "flags": q.get("flags") or {},
        "next_mission": q.get("next_mission"),
        "outcomes": flown,
        "missions": missions,
        "arc_missions_not_designed": undesigned,
    }
