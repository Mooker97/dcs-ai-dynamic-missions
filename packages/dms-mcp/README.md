# dms-mcp

This package is a FastMCP server over stdio. It exposes six coarse DMS tools to any MCP client:
`validate`, `plan`, `build`, `check`, `schema` and `campaign_status`. The tools call `dms_core` and
`dms_gen` directly. The contract is in [docs/CONTRACTS.md, "MCP server"](../../docs/CONTRACTS.md#mcp-server-packagesdms-mcp-v08).

```bash
uv sync --all-packages
uv run dms-mcp          # serves on stdio; normally launched by the MCP client
uv run pytest packages/dms-mcp
```

Relative paths in tool arguments resolve against the repo root. That root is `$DMS_ROOT` if set,
otherwise the uv workspace found from the working directory.

## Claude Code

The repo root's `.mcp.json` registers the server for Claude Code as `dms` (project scope,
`uv run dms-mcp`, started in the repo root). The server must be enabled in `/mcp`: if it was
rejected once, it sits in `disabledMcpjsonServers` in `.claude/settings.local.json` and Claude Code
won't ask again, so enable it from `/mcp` (or remove it from that list). Then the tools show up as
`mcp__dms__validate` and so on. `tests/test_stdio.py` exercises exactly that command line over
real stdio.

To use the server from another directory or another client, point it at the repo explicitly:

```json
{
  "mcpServers": {
    "dms": {
      "type": "stdio",
      "command": "uv",
      "args": ["run", "--directory", "C:/path/to/DMS", "dms-mcp"],
      "env": { "DMS_ROOT": "C:/path/to/DMS" }
    }
  }
}
```

A built `.miz` with a clean `check` counts as "implemented, not flown". It is not done until
it has been flown in DCS ([ADR 0009](../../docs/adr/0009-definition-of-done-requires-flight.md)).
