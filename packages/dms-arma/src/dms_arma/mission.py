"""Spec -> mission folder: copy the template mission and write its `functions/fn_config.sqf`.

Only the config is generated today; `mission.sqm`, `description.ext` and the scripts come from
the template unchanged (see docs/arma/BACKEND.md for what is left).
"""

from __future__ import annotations

import re
import shutil
from pathlib import Path
from typing import Any

import yaml

from .config import emit_config
from .kb import Issue, check_functions, check_spec
from .spec import ArmaMissionSpec

CONFIG_PATH = Path("functions") / "fn_config.sqf"
_SITE_TEXTS = re.compile(
    r"class\s+DMS_site\s*\{(?:[^{}]|\{[^{}]*\})*?texts\[\]\s*=\s*\{([^}]*)\}", re.DOTALL
)


def load_spec(path: Path) -> ArmaMissionSpec:
    """Load a YAML (or JSON) spec file and validate it."""
    data: Any = yaml.safe_load(path.read_text(encoding="utf-8"))
    return ArmaMissionSpec.model_validate(data)


class _SpecDumper(yaml.SafeDumper):  # type: ignore[misc]
    """Compact YAML: leaf lists in flow style, integral floats as ints."""


def _repr_list(dumper: yaml.SafeDumper, data: list[Any]) -> yaml.Node:
    flow = all(not isinstance(v, list | dict) for v in data) or all(
        isinstance(v, list) and all(not isinstance(w, list | dict) for w in v) for v in data
    )
    return dumper.represent_sequence("tag:yaml.org,2002:seq", data, flow_style=flow and bool(data))


def _repr_float(dumper: yaml.SafeDumper, data: float) -> yaml.Node:
    if data.is_integer():
        return dumper.represent_int(int(data))
    return dumper.represent_float(data)


_SpecDumper.add_representer(list, _repr_list)
_SpecDumper.add_representer(float, _repr_float)


def dump_spec(spec: ArmaMissionSpec) -> str:
    """Serialise a spec to YAML (stable key order: model field order)."""
    data = spec.model_dump(mode="json")
    return str(yaml.dump(data, Dumper=_SpecDumper, sort_keys=False, allow_unicode=True, width=100))


def check_template(spec: ArmaMissionSpec, folder: Path) -> list[Issue]:
    """Template consistency: the DMS_site param in description.ext must list every site."""
    ext = folder / "description.ext"
    if not ext.is_file():
        return [Issue("error", str(ext), "template has no description.ext")]
    m = _SITE_TEXTS.search(ext.read_text(encoding="utf-8", errors="replace"))
    if m is None:
        return []
    choices = len(re.findall(r'"(?:[^"]|"")*"', m.group(1))) - 1  # first entry is "From seed"
    if choices != len(spec.sites.sites):
        return [
            Issue(
                "error",
                "description.ext Params/DMS_site",
                f"lists {choices} sites but the spec has {len(spec.sites.sites)}",
            )
        ]
    return []


def build_mission(
    spec: ArmaMissionSpec,
    template: Path,
    out: Path,
    *,
    source: str = "",
    overwrite: bool = False,
) -> list[Issue]:
    """Copy `template` to `out`, write the generated config, run the KB/template checks.

    Never writes inside `template`. Returns all issues (errors and unverified classes); the
    folder is written even when there are issues so it can be inspected.
    """
    template, out = template.resolve(), out.resolve()
    if out == template or out.is_relative_to(template):
        raise ValueError(f"refusing to write into the template: {out}")
    if not (template / CONFIG_PATH).is_file():
        raise FileNotFoundError(f"not a DMS Arma mission (no {CONFIG_PATH}): {template}")
    if out.exists():
        if not overwrite:
            raise FileExistsError(f"{out} exists (pass overwrite=True)")
        shutil.rmtree(out)
    shutil.copytree(template, out)
    text = emit_config(spec, source=source)
    (out / CONFIG_PATH).write_bytes(text.encode("utf-8"))
    issues = check_spec(spec) + check_template(spec, out)
    for path in sorted(out.rglob("*")):
        if path.suffix.lower() in {".sqf", ".ext", ".hpp", ".sqm"}:
            body = path.read_text(encoding="utf-8", errors="replace")
            issues += check_functions(body, str(path.relative_to(out)))
    return issues
