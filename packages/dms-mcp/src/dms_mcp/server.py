"""``dms-mcp``: a FastMCP stdio server exposing ten coarse DMS tools.

Six workflow tools (validate, plan, build, check, schema, campaign_status) and four read-only
helpers (catalog, outcome, doctor, voice_estimate).

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
    "campaign_status(slug) to see what exists, catalog(kind, ...) for valid DCS type names, "
    "voice_estimate(mission) for a no-cost voice estimate, outcome() to read the last flight's "
    "[DMS.OUTCOME] lines and doctor() to check the toolchain. Paths may be relative to the "
    "repo root. "
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
    strict: Annotated[
        bool, Field(description="Count warnings (incl. quality-lint warnings) as errors.")
    ] = False,
    lint: Annotated[
        bool,
        Field(
            description="Run the mission-quality lint (rule ids in the issue problem text as "
            "'[code]', with a 'Fix:' hint). arc.yaml gets the campaign-wide arc rules."
        ),
    ] = True,
) -> dict[str, Any]:
    """Schema + cross-file + planner checks + mission-quality lint. Returns ok, error/warning
    counts and issues (path, problem, suggestions, severity)."""
    return ops.guarded(ops.validate)(path, lint=lint, strict=strict)


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
    variant: Annotated[
        str | None,
        Field(
            description="Player-flight start variant (e.g. 'ramp', 'air'). Null builds every "
            "variant (<id>-<variant>.miz each, <id>.miz = first); with test, the variant the AI "
            "proxy comes from."
        ),
    ] = None,
) -> dict[str, Any]:
    """Build <mission>/out/<id>.miz from out/plan.json (planning first if it is missing), embed
    the Lua runtime, then run the structural check. With player-flight variants, one .miz per
    variant is built and checked ('variants' in the result). Returns the .miz path(s), notes and
    check."""
    return ops.guarded(ops.build)(mission_dir, test, variant=variant)


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


# ---- read-only helpers -------------------------------------------------------------------------


@mcp.tool()
def catalog(
    kind: Annotated[str, Field(description="units | templates | airbases | mission-types.")],
    era: Annotated[
        str | None, Field(description="Era id (e.g. modern, cold_war) or a year (e.g. 1985).")
    ] = None,
    coalition: Annotated[str | None, Field(description="blue | red | neutral.")] = None,
    role: Annotated[str | None, Field(description="Role or tag, e.g. sam_short, mbt, cas.")] = None,
    category: Annotated[
        str | None, Field(description="Domain for units/templates, e.g. ground, air, ship.")
    ] = None,
    theater: Annotated[
        str | None, Field(description="DCS map for kind=airbases, e.g. Caucasus, Syria.")
    ] = None,
) -> dict[str, Any]:
    """Read-only grounding lookup (like `dms catalog <kind> --json`): DCS unit types, group
    templates, airbases on a map, or mission types. Use it instead of guessing type names.
    Returns kind, count and rows."""
    return ops.guarded(ops.catalog)(kind, era, coalition, role, category, theater)


@mcp.tool()
def outcome(
    log_path: Annotated[
        str | None,
        Field(
            description="dcs.log or its Logs folder. Null: the newest stable/openbeta dcs.log "
            "under Saved Games."
        ),
    ] = None,
    mission_id: Annotated[str | None, Field(description="Only this mission id.")] = None,
) -> dict[str, Any]:
    """Read-only parse of [DMS.OUTCOME] lines from dcs.log (like `dms outcome --json`). Writes
    nothing; campaign debriefs stay with the CLI (`dms debrief`). Returns log, count, records and
    a per-mission summary."""
    return ops.guarded(ops.outcome)(log_path, mission_id)


@mcp.tool()
def doctor() -> dict[str, Any]:
    """Read-only toolchain check (like `dms doctor --json`): packages, Lua 5.1, ffmpeg, voice key
    presence, DCS folders, Lua bundle, Git LFS, uv. ok is false when any check FAILs. Returns
    checks (name, status, detail, fix)."""
    return ops.guarded(ops.doctor)()


@mcp.tool()
def voice_estimate(
    mission: Annotated[str, Field(description="Mission folder or its lines.yaml.")],
    offline: Annotated[
        bool, Field(description="Estimate placeholder tone clips (0 credits) instead.")
    ] = False,
) -> dict[str, Any]:
    """Dry-run cost estimate of voicing a mission (like `dms voice --dry-run`). Never calls
    ElevenLabs and renders nothing. Returns lines to render, cached count, characters, credits
    and per-line detail."""
    return ops.guarded(ops.voice_estimate)(mission, offline)


def main() -> None:
    """Console entry point: serve over stdio."""
    mcp.run(transport="stdio")


if __name__ == "__main__":  # pragma: no cover
    main()
