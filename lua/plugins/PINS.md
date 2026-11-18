# Pinned Lua plugins

Optional third-party scripts that a mission can opt into with `plugins: [...]` in
`mission-spec.yaml`. The DMS core never depends on them (ADR 0003). The generator embeds them as
separate `DO SCRIPT FILE` actions in this order (docs/CONTRACTS.md "Optional plugins"):

```
mist -> moose -> skynet -> dms_config.lua (-> dms_test.lua) -> dms.lua -> adapters/*
```

The source of truth for the pins is `PLUGINS` in `packages/dms-gen/src/dms_gen/plugins.py`;
`lua/test_lua_plugins.py` checks that this file, that registry and the vendored bytes agree, and
`dms check` warns (`plugin_unpinned`) when an embedded plugin's sha256 differs.

Files are vendored byte-for-byte from the tag (upstream already uses LF line endings), stored
as normal git text (`*.lua text eol=lf`, not LFS). sha256 is of the file as committed.

| Spec name | Version (tag) | Vendored file | Upstream | sha256 |
|---|---|---|---|---|
| `mist` | 4.5.126 | `mist/4.5.126/mist_4_5_126.lua` | https://github.com/mrSkortch/MissionScriptingTools/releases/tag/4.5.126 (`raw.githubusercontent.com/mrSkortch/MissionScriptingTools/4.5.126/mist_4_5_126.lua`) | `85e78e6cb5d2191b4148241e1a77c4884049b51295508d3d38b20793a0968c39` |
| `moose` | 2.9.19 | `moose/2.9.19/Moose_.lua` | https://github.com/FlightControl-Master/MOOSE/releases/tag/2.9.19 (release asset `Moose_.lua`, the comment-stripped build) | `3873e6d392e69177f0e18ae0a0766a2b64bd3c4ea55d112329f1cbaa82426ecd` |
| `skynet` | 3.3.0 | `skynet/3.3.0/skynet-iads-compiled.lua` | https://github.com/walder/Skynet-IADS/releases/tag/3.3.0 (`raw.githubusercontent.com/walder/Skynet-IADS/3.3.0/demo-missions/skynet-iads-compiled.lua`) | `6b95b407f99ddf3933addcf3cfda2288d53519af652ffb90b779c26ba7608ba7` |

Each version folder also holds the upstream licence (MIST: GPL-3.0, MOOSE: GPL-3.0,
Skynet-IADS: Apache-2.0).

Notes:

- These were the latest non-prerelease GitHub releases on 2026-10-29.
- MIST 4.5.126 sets `mist.build = 125` internally (upstream quirk); the file is the 4.5.126 tag.
- `skynet` requires `mist` (added automatically) and pulls in the DMS adapter
  `adapters/skynet_adapter.lua`, which loads after `dms.lua`, builds one IADS from SAM groups
  named with a prefix (default `DMS_`, i.e. DMS runtime spawns) and no-ops without Skynet.
- Upgrading: download the new tag into `<name>/<version>/`, update `PLUGINS` and this table,
  run `uv run pytest lua/test_lua_plugins.py`, and fly it before calling it done (ADR 0009).
