# 0011. Retire the regex MizParser / miz-modifier approach

Status: Accepted · 2026-10-27 · Supersedes the pre-rebuild CLAUDE.md rule "always use MizParser"

## Context

Before the rebuild, every `.miz` edit went through `MizParser`: extract, apply regex to the Lua
text, repackage. CLAUDE.md made this mandatory. The approach was chosen to avoid pydcs's
environment and load errors (see [`../reference/lessons.md`](../reference/lessons.md)), but regex
over nested Lua tables turned out to be fragile.

## Decision

- The regex approach is retired.
- Its code stays in `legacy/miz-modification/` as reference only.
- New code uses lupa-based miz I/O in `dms_core` (ADR 0002) and pydcs generation (ADR 0001).

## Consequences

- Old docs and commands that mention `MizParser`, `miz-modifier` or `knowledge/mcp-light` are
  historical.
- The `/dms` command now points at the CLI and skills.
