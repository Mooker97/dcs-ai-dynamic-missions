# 0005. CLI and Claude Code skills before an MCP server

Status: Accepted · 2026-10-27

## Context

An MCP server adds a process boundary, schema plumbing and extra debugging cost. Inside Claude
Code, a CLI plus skills already lets Claude read and write files, run commands and follow
procedures.

## Decision

- Build the `dms` CLI (typer) first, with `validate`, `plan`, `voice`, `build`, `check`, `schema`
  and `bundle-lua`.
- Add `.claude/skills/*` for the story and build procedures.
- In v0.8, add an MCP server (FastMCP over stdio, ~6 coarse tools with pydantic return types) as a
  thin wrapper over the same library functions.

## Consequences

- Every capability can be scripted and tested from a shell.
- Clients other than Claude Code have to wait for v0.8.
- MCP tools must not contain logic that the CLI lacks.

## Update (2026-10-29)

The MCP server shipped in v0.8 with six tools (`validate`, `plan`, `build`, `check`, `schema`,
`campaign_status`). They return plain `dict[str, Any]` JSON payloads, not pydantic models as
the decision above anticipated. The CLI has since grown `run`, `install`, `doctor`, `outcome`,
`debrief`, `new-campaign` and `catalog`.
