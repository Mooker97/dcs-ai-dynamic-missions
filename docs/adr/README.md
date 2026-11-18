# Architecture Decision Records

These are short records of decisions that shape DMS, each written as Context / Decision / Consequences.
To change a decision, add a new ADR that supersedes the old one. Don't rewrite history.

| # | Decision | Status |
|---|---|---|
| [0001](0001-pydcs-for-generation-only.md) | pydcs builds new missions only | Accepted |
| [0002](0002-lupa-dict-round-trip-for-editing.md) | Edit existing missions via a lupa dict round-trip | Accepted |
| [0003](0003-own-lua-core-optional-moose.md) | Own Lua core on the raw DCS API; MOOSE/Skynet as optional plugins | Accepted |
| [0004](0004-concatenation-bundler.md) | Concatenation bundler for Lua (no `require` in DCS) | Accepted |
| [0005](0005-cli-and-skills-before-mcp.md) | CLI + Claude Code skills before an MCP server | Accepted |
| [0006](0006-llm-writes-validated-files.md) | LLMs write schema-validated files; code compiles them | Accepted |
| [0007](0007-randomness-split.md) | Python decides the possibility space; Lua picks the instance | Accepted |
| [0008](0008-fog-of-war-hidden-plus-marks.md) | Fog of war = spawn-time `hidden` + F10 marks | Accepted |
| [0009](0009-definition-of-done-requires-flight.md) | Definition of Done requires a DCS flight test | Accepted |
| [0010](0010-git-lfs-for-binaries.md) | Git LFS for `.miz` fixtures and audio | Accepted |
| [0011](0011-retire-regex-mizparser.md) | Retire the regex MizParser / miz-modifier approach | Accepted |
| [0012](0012-multiple-game-backends.md) | Support multiple game backends (DCS first, Arma 3 second) | Accepted |
| [0013](0013-vendored-plugins-and-adapters.md) | Vendor pinned plugins as text; DMS adapters load after `dms.lua` | Accepted |

Template:

```markdown
# NNNN. Title
Status: Proposed | Accepted | Superseded by NNNN · YYYY-MM-DD
## Context
## Decision
## Consequences
```
