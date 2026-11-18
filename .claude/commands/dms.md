---
description: DMS mode - build or edit DCS missions with the dms CLI and the DMS skills
---

# DMS mode

You are working on DCS missions with DMS. $ARGUMENTS

1. **Pick the right tool.** Use a skill if one covers the task:
   - **dms-quickstart**, for "make me a mission/campaign about X" or any one-line premise:
     one question round, then story -> arc -> mission -> `dms run --install` -> fly card
   - story-writer → campaign-planner → mission-designer, for authoring
   - voice-director, for audio
   - dms-build, to run validate → plan → voice → build → check
   - debriefer, after a flight

   Otherwise use the CLI: `uv run dms validate | plan | voice | build | check | schema | bundle-lua
   | install | doctor`. Run `uv run dms doctor` first when something environmental fails.
2. **Write files, not code.** Author YAML that matches the schemas (`uv run dms schema` exports
   JSON Schema). Run `dms validate`, then repair, for at most 3 loops. Leave coordinates, unit
   types and IDs to `dms plan`.
3. **Never round-trip a user's `.miz` through pydcs.** To inspect or edit an existing mission, use
   `dms_core` miz I/O (lupa) or `dms check`.
4. **Work in a campaign folder.** Use `campaigns/<slug>/missions/mNN-<slug>/`, and write build
   output to `out/`, which is git-ignored.
5. **Be honest about status.** After a build, tell the user to fly the mission and check `dcs.log`
   for `[DMS]` errors (see CLAUDE.md for log paths). It isn't done until it has been flown.

References: `docs/CONTRACTS.md`, `docs/reference/dcs-scripting-gotchas.md`,
`docs/reference/miz-format.md`.
