"""``dms-mcp``: a FastMCP stdio server exposing six coarse DMS tools.

Relative paths resolve against the repo root (``$DMS_ROOT`` or the uv workspace found from the
working directory). Every tool returns a dict with ``ok``; fixable failures come back as
``{"ok": false, "error": "..."}`` rather than protocol errors.
"""

from __future__ import annotations

from typing import Annotated, Any

from mcp.server.fastmcp import FastMCP
from pydantic import Field

from . import ops

INSTRUCTIONS = (
    "DMS turns campaign YAML into DCS World .miz missions. Typical loop for a mission folder "
    "(campaigns/<slug>/missions/mNN-<slug>): validate -> fix YAML (max 3 loops) -> plan -> "
    "build -> read the check result. Use schema(name) for the exact file format and "
    "campaign_status(slug) to see what exists. Paths may be relative to the repo root. "
    "Nothing here flies the mission; a built .miz is 'implemented, not flown'."
)

mcp = FastMCP("dms", instructions=INSTRUCTIONS, log_level="WARNING")


@mcp.tool()
def validate(
    path: Annotated[
        str,
        Field(
            description="Mission folder or mission-spec.yaml (validates spec, beats, lines and "
            "the nearest bible), or a bible.yaml / arc.yaml / qualities.yaml file."
        ),
    ],
) -> dict[str, Any]:
    """Schema + cross-file + planner checks. Returns ok, error/warning counts and issues
    (path, problem, suggestions, severity)."""
    return ops.guarded(ops.validate)(path)


@mcp.tool()
def plan(
    mission_dir: Annotated[str, Field(description="Mission folder or mission-spec.yaml.")],
    seed: Annotated[
        int | None, Field(description="Planner seed; omit for the spec's or a derived one.")
    ] = None,
) -> dict[str, Any]:
    """Compile the mission into an exact, seeded <mission>/out/plan.json. Returns the plan path,
    seed, player groups and counts (groups, zones, triggers, resources, runtime)."""
    return ops.guarded(ops.plan)(mission_dir, seed)


@mcp.tool()
def build(
    mission_dir: Annotated[str, Field(description="Mission folder or mission-spec.yaml.")],
    test: Annotated[
        bool,
        Field(
            description="Build the headless test variant (AI player proxy, out/<id>-test.miz) "
            "instead of the flyable mission."
        ),
    ] = False,
) -> dict[str, Any]:
    """Build <mission>/out/<id>.miz from out/plan.json (planning first if it is missing), embed
    the Lua runtime, then run the structural check. Returns the .miz path, notes and check."""
    return ops.guarded(ops.build)(mission_dir, test)


@mcp.tool()
def check(
    miz_path: Annotated[str, Field(description="Path to a .miz file.")],
) -> dict[str, Any]:
    """Structural check of a .miz (IDs, slots, resources, DMS_CONFIG, Lua syntax, fog of war).
    Returns ok, issues (severity, code, message, where) and stats."""
    return ops.guarded(ops.check)(miz_path)


@mcp.tool()
def schema(
    name: Annotated[
        str,
        Field(
            description="story-bible | campaign-arc | qualities | mission-spec | beats | "
            "voice-lines | build-plan | runtime-config | mission-outcome (or the model class "
            "name, e.g. MissionSpec)."
        ),
    ],
) -> dict[str, Any]:
    """JSON Schema of one DMS file format; field descriptions double as authoring guidance."""
    return ops.guarded(ops.schema)(name)


@mcp.tool()
def campaign_status(
    campaign_slug: Annotated[str, Field(description="Folder name under campaigns/.")],
) -> dict[str, Any]:
    """Campaign overview: qualities/flags, debriefed outcomes, and per mission whether it is
    designed, voiced, planned, built, which out/ files exist and the last check result."""
    return ops.guarded(ops.campaign_status)(campaign_slug)


def main() -> None:
    """Console entry point: serve over stdio."""
    mcp.run(transport="stdio")


if __name__ == "__main__":  # pragma: no cover
    main()
