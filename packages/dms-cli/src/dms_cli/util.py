"""Helpers for the ``dms`` CLI: repo/mission path resolution, YAML loading, issue rendering."""

from __future__ import annotations

import dataclasses
import json
import re
import tomllib
import types
import typing
from collections.abc import Iterable, Sequence
from pathlib import Path
from typing import Any

import yaml  # type: ignore[import-untyped,unused-ignore]
from pydantic import BaseModel, ValidationError

SPEC_FILE = "mission-spec.yaml"
BEATS_FILE = "beats.yaml"
LINES_FILE = "lines.yaml"
BIBLE_FILE = "bible.yaml"
PLAN_FILE = "plan.json"
VOICE_MANIFEST = Path("voice") / "manifest.json"


class CliError(Exception):
    """A user-facing error: printed as ``error: <msg>`` and exits with ``code``."""

    def __init__(self, message: str, code: int = 2) -> None:
        super().__init__(message)
        self.code = code


# ---- repo root ---------------------------------------------------------------------------------


def _is_workspace_root(path: Path) -> bool:
    pp = path / "pyproject.toml"
    if not pp.is_file():
        return False
    try:
        data = tomllib.loads(pp.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError):
        return False
    return "workspace" in data.get("tool", {}).get("uv", {})


def find_root(start: Path | None = None) -> Path:
    """Walk up from ``start`` (default cwd, then this file) to the uv workspace root."""
    starts = [start or Path.cwd(), Path(__file__).resolve()]
    for s in starts:
        s = s.resolve()
        for p in [s, *s.parents]:
            if _is_workspace_root(p):
                return p
    raise CliError("repo root not found (no pyproject.toml with [tool.uv.workspace]); use --root")


# ---- mission paths -----------------------------------------------------------------------------


@dataclasses.dataclass
class MissionPaths:
    dir: Path
    spec: Path
    beats: Path | None
    lines: Path | None
    bible: Path | None

    @property
    def out_dir(self) -> Path:
        return self.dir / "out"

    @property
    def voice_manifest(self) -> Path:
        return self.dir / VOICE_MANIFEST


def find_bible(start: Path, root: Path | None) -> Path | None:
    """Nearest ``bible.yaml`` walking up from ``start`` (stops at ``root``)."""
    start = start.resolve()
    stop = root.resolve() if root else None
    for p in [start, *start.parents]:
        cand = p / BIBLE_FILE
        if cand.is_file():
            return cand
        if stop is not None and p == stop:
            break
    return None


def resolve_mission(
    target: Path,
    *,
    beats: Path | None = None,
    lines: Path | None = None,
    bible: Path | None = None,
    root: Path | None = None,
) -> MissionPaths:
    """Resolve a mission dir or spec file into the conventional file set."""
    target = target.resolve()
    if target.is_dir():
        mdir, spec = target, target / SPEC_FILE
    elif target.is_file():
        mdir, spec = target.parent, target
    else:
        raise CliError(f"not found: {target}")
    if not spec.is_file():
        raise CliError(f"no {SPEC_FILE} in {mdir}")

    def _pick(explicit: Path | None, name: str) -> Path | None:
        if explicit is not None:
            if not explicit.is_file():
                raise CliError(f"not found: {explicit}")
            return explicit.resolve()
        cand = mdir / name
        return cand if cand.is_file() else None

    bible_path = _pick(bible, BIBLE_FILE) if bible else find_bible(mdir, root)
    return MissionPaths(mdir, spec, _pick(beats, BEATS_FILE), _pick(lines, LINES_FILE), bible_path)


def mission_dir_for_plan(plan_path: Path) -> Path:
    """``<mission>/out/plan.json`` -> ``<mission>``; otherwise the plan's own folder."""
    parent = plan_path.resolve().parent
    return parent.parent if parent.name == "out" else parent


def load_yaml(path: Path) -> Any:
    try:
        return yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        raise CliError(f"{path.name}: invalid YAML: {exc}", code=1) from exc


# ---- issues ------------------------------------------------------------------------------------


@dataclasses.dataclass
class Finding:
    """A normalised validation finding (from pydantic or the planner)."""

    path: str
    problem: str
    suggestions: list[str] = dataclasses.field(default_factory=list)
    severity: str = "error"

    def to_dict(self) -> dict[str, Any]:
        return dataclasses.asdict(self)

    def render(self) -> str:
        s = f"{self.severity.upper()} {self.path}: {self.problem}"
        if self.suggestions:
            s += " | try: " + ", ".join(self.suggestions)
        return s


def finding_from(obj: Any) -> Finding:
    """Accept a dms_core ``Issue`` (or any object/dict with path/problem/suggestions/severity)."""
    if isinstance(obj, Finding):
        return obj
    data = obj.model_dump() if isinstance(obj, BaseModel) else obj
    if not isinstance(data, dict):
        data = {k: getattr(obj, k, None) for k in ("path", "problem", "suggestions", "severity")}
    return Finding(
        path=str(data.get("path") or ""),
        problem=str(data.get("problem") or data.get("message") or obj),
        suggestions=[str(s) for s in (data.get("suggestions") or [])],
        severity=str(data.get("severity") or "error"),
    )


def loc_to_path(loc: Sequence[int | str]) -> str:
    out = ""
    for part in loc:
        if isinstance(part, int):
            out += f"[{part}]"
        else:
            out += ("." if out else "") + str(part)
    return out


def _flatten(ann: Any) -> list[Any]:
    origin = typing.get_origin(ann)
    if origin is typing.Annotated:
        return _flatten(typing.get_args(ann)[0])
    if origin in (typing.Union, types.UnionType):
        return [t for a in typing.get_args(ann) for t in _flatten(a)]
    return [ann]


def _models(anns: Iterable[Any]) -> list[type[BaseModel]]:
    return [a for a in anns if isinstance(a, type) and issubclass(a, BaseModel)]


def _has_literal(model: type[BaseModel], value: str) -> bool:
    for f in model.model_fields.values():
        for a in _flatten(f.annotation):
            if typing.get_origin(a) is typing.Literal and value in typing.get_args(a):
                return True
    return False


def models_at(model: type[BaseModel], loc: Sequence[int | str]) -> list[type[BaseModel]]:
    """Best-effort: the pydantic model classes that live at ``loc`` inside ``model``."""
    state: list[Any] = [model]
    for part in loc:
        flat = [t for a in state for t in _flatten(a)]
        nxt: list[Any] = []
        if isinstance(part, int):
            for a in flat:
                args = typing.get_args(a)
                if typing.get_origin(a) in (list, tuple, set, Sequence) and args:
                    nxt.extend(x for x in args if x is not Ellipsis)
        else:
            for m in _models(flat):
                if part in m.model_fields:
                    nxt.append(m.model_fields[part].annotation)
            if not nxt:  # discriminated-union tag in the loc
                for a in flat:
                    if typing.get_origin(a) is dict:
                        nxt.append(typing.get_args(a)[-1])
                tagged = [m for m in _models(flat) if _has_literal(m, part)]
                nxt.extend(tagged)
        state = nxt
        if not state:
            return []
    return _models([t for a in state for t in _flatten(a)])


_QUOTED = re.compile(r"'([^']*)'")


def _close(value: str, choices: Iterable[str], n: int = 3) -> list[str]:
    import difflib

    return difflib.get_close_matches(value, list(choices), n=n, cutoff=0.5)


def pydantic_findings(exc: ValidationError, filename: str, model: type[BaseModel]) -> list[Finding]:
    """Render pydantic errors as LLM-friendly path / problem / suggestion findings."""
    out: list[Finding] = []
    for err in exc.errors(include_url=False):
        loc = tuple(err.get("loc", ()))
        etype = str(err.get("type", ""))
        ctx = err.get("ctx") or {}
        path = f"{filename}:{loc_to_path(loc)}" if loc else filename
        problem = str(err.get("msg", "invalid"))
        sugg: list[str] = []
        if etype in ("literal_error", "enum"):
            sugg = _QUOTED.findall(str(ctx.get("expected", "")))
            got = err.get("input")
            if isinstance(got, str):
                close = _close(got, sugg)
                sugg = close + [s for s in sugg if s not in close]
            problem = f"invalid value {err.get('input')!r}; {problem}"
        elif etype == "union_tag_invalid":
            sugg = _QUOTED.findall(str(ctx.get("expected_tags", "")))
        elif etype == "extra_forbidden":
            key = str(loc[-1]) if loc else ""
            allowed = sorted({f for m in models_at(model, loc[:-1]) for f in m.model_fields})
            problem = f"unknown field '{key}' (remove it or fix the spelling)"
            sugg = _close(key, allowed) or allowed[:12]
        elif etype == "missing":
            key = str(loc[-1]) if loc else ""
            problem = f"required field '{key}' is missing"
            for m in models_at(model, loc[:-1]):
                f = m.model_fields.get(key)
                if f is not None and f.description:
                    sugg = [f"add '{key}': {f.description}"]
                    break
        out.append(Finding(path, problem, sugg))
    return out


# ---- misc --------------------------------------------------------------------------------------


def to_jsonable(obj: Any) -> Any:
    if isinstance(obj, BaseModel):
        return obj.model_dump(mode="json")
    if dataclasses.is_dataclass(obj) and not isinstance(obj, type):
        return {f.name: to_jsonable(getattr(obj, f.name)) for f in dataclasses.fields(obj)}
    if isinstance(obj, dict):
        return {str(k): to_jsonable(v) for k, v in obj.items()}
    if isinstance(obj, list | tuple | set):
        return [to_jsonable(v) for v in obj]
    if isinstance(obj, Path):
        return str(obj)
    if hasattr(obj, "to_dict") and callable(obj.to_dict):
        return to_jsonable(obj.to_dict())
    return obj


def dumps(obj: Any) -> str:
    return json.dumps(to_jsonable(obj), indent=2, ensure_ascii=False, default=str)


def latest_mtime(paths: Iterable[Path]) -> float:
    return max((p.stat().st_mtime for p in paths if p.is_file()), default=0.0)
