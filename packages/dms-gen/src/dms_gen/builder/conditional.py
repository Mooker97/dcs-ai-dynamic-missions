"""Plan-time conditional blocks in ``briefing.md`` / ``kneeboard.md`` (CONTRACTS "Debrief").

A directive is a whole line::

    <!-- if intel >= 2 and not m01_player_lost -->
    ...
    <!-- elif m01_window_held -->
    ...
    <!-- else -->
    ...
    <!-- endif -->

Conditions use the arc ``quality_effects`` grammar (:func:`dms_core.outcomes.parse_condition`)
and are evaluated against campaign state at plan time (``DMS_CONFIG.qualities`` and
``DMS_CONFIG.flags``). Blocks nest. Directive lines are removed; only the taken branch's lines
are kept. An unparseable condition or unbalanced block raises :class:`ValueError`.
"""

from __future__ import annotations

import re
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any

from dms_core.outcomes import condition_holds, parse_condition
from dms_core.schemas import BuildPlan

__all__ = ["plan_facts", "render_conditionals"]

_DIRECTIVE = re.compile(r"^\s*<!--\s*(if|elif|else|endif)\b(.*?)-->\s*$", re.IGNORECASE)


@dataclass
class _Frame:
    parent_active: bool  # the enclosing block is being emitted
    taken: bool  # some branch of this block has already been chosen
    active: bool  # the current branch is being emitted
    seen_else: bool
    line: int


def plan_facts(plan: BuildPlan) -> dict[str, Any]:
    """Facts for :func:`render_conditionals`: the plan's campaign flags, then qualities."""
    rt = plan.runtime
    if rt is None:
        return {}
    facts: dict[str, Any] = dict(rt.flags)
    facts.update(rt.qualities)
    return facts


def render_conditionals(md: str, facts: Mapping[str, Any], source: str = "markdown") -> str:
    """Resolve ``<!-- if/elif/else/endif -->`` blocks in ``md`` against ``facts``."""
    known = dict(facts)
    out: list[str] = []
    stack: list[_Frame] = []
    active = True
    for n, line in enumerate(md.splitlines(keepends=True), start=1):
        m = _DIRECTIVE.match(line)
        if m is None:
            if active:
                out.append(line)
            continue
        kind, rest = m.group(1).lower(), m.group(2).strip()
        where = f"{source}:{n}"
        if kind in ("if", "elif"):
            cond = parse_condition(rest)
            if cond is None:
                raise ValueError(f"{where}: invalid condition in '<!-- {kind} {rest} -->'")
            holds = condition_holds(cond, known)
            if kind == "if":
                stack.append(_Frame(active, holds, active and holds, False, n))
            else:
                if not stack or stack[-1].seen_else:
                    raise ValueError(f"{where}: '<!-- elif -->' without a matching if")
                f = stack[-1]
                f.active = f.parent_active and not f.taken and holds
                f.taken = f.taken or holds
        elif kind == "else":
            if rest:
                raise ValueError(f"{where}: '<!-- else -->' takes no condition (use elif)")
            if not stack or stack[-1].seen_else:
                raise ValueError(f"{where}: '<!-- else -->' without a matching if")
            f = stack[-1]
            f.active = f.parent_active and not f.taken
            f.taken = f.seen_else = True
        else:
            if rest:
                raise ValueError(f"{where}: '<!-- endif -->' takes no condition")
            if not stack:
                raise ValueError(f"{where}: '<!-- endif -->' without a matching if")
            stack.pop()
        active = stack[-1].active if stack else True
    if stack:
        raise ValueError(f"{source}:{stack[-1].line}: '<!-- if -->' is never closed (endif)")
    return "".join(out)
