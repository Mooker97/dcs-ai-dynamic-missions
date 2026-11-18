# 0013. Vendor pinned plugins as text; DMS adapters load after `dms.lua`

Status: Accepted · 2026-10-29

## Context

ADR 0003 makes MIST, Skynet-IADS and MOOSE optional, pinned plugins loaded before `dms.lua`.
It left open how they are pinned and stored, and how DMS code talks to a plugin without the
core depending on it. Skynet needs MIST. Skynet builds an IADS from group names, but DMS spawns
SAM groups at runtime (`DMS_<poolOrTemplate>_<n>`), after any load-time setup script has run.

## Decision

- Vendor the upstream release files byte-for-byte under `lua/plugins/<name>/<version>/` with
  their licences, as normal git text (`*.lua text eol=lf`), not LFS: they are source, diffable,
  and the builder must read them from a plain checkout. MOOSE uses the comment-stripped
  `Moose_.lua` release asset (~4 MB).
- Pins (tag, URL, sha256) are code: `dms_gen.plugins.PLUGINS`, mirrored in
  `lua/plugins/PINS.md`. A test checks the vendored bytes against both; `dms check` warns
  (`plugin_unpinned`) when an embedded plugin differs.
- A mission opts in with `MissionSpec.plugins`. The generator owns order and dependencies:
  `mist -> moose -> skynet -> dms_config.lua -> dms.lua -> adapters`.
- Glue lives in **adapters** (`lua/plugins/adapters/`), not in `lua/src/dms/`. An adapter loads
  after `dms.lua`, uses only the DMS core API (Log, Clock, Bus, safeCall), reads plugin globals
  with `rawget`, and no-ops with one log line when its plugin is missing. The Skynet adapter
  adds prefix-matching SAM groups at load and on `spawner.spawned`.

## Consequences

- The DMS bundle and core stay plugin-free; removing `plugins:` from a spec removes every trace.
- The repo grows by ~4.7 MB of third-party Lua (GPL-3 MIST/MOOSE, Apache-2 Skynet); they are
  only embedded in missions that ask for them.
- Upgrading a plugin is a new version folder plus a pin change, and needs a flight (ADR 0009).
