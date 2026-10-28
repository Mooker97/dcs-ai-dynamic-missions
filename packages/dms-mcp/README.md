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

## Example `.mcp.json`

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
