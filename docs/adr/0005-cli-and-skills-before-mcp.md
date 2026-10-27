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
