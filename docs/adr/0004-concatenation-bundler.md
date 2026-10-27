# 0004. Concatenation bundler for the Lua runtime

Status: Accepted · 2026-10-27

## Context

The DCS mission environment sanitizes `require`, `package.loadlib`, `os`, `io` and `lfs`. Each
DO SCRIPT FILE is a separate resource in the `.miz`, and trigger order controls load order.

## Decision

- `tools/bundle_lua.py` (also `dms bundle-lua`) concatenates `lua/src/dms/*.lua` into one
  `dist/dms.lua`, following `lua/manifest.txt` order. It stamps `DMS.VERSION` into the output.
- Every module starts with the guard `DMS = DMS or {}; DMS.X = DMS.X or {}`.
- The generator injects `dms.lua` first, then `dms_config.lua` (`DMS_CONFIG = {...}`).
- `init.lua`, last in the manifest, starts the modules.

This mirrors the Liberation/Retribution plugin model: ordered DO SCRIPT FILEs, with options passed
as Lua globals.

## Consequences

- There is one artifact to inject and to check with `luac -p` in CI.
- Modules talk to each other through globals on `DMS`, so manifest order matters.
- `dist/` is build output and is git-ignored.
