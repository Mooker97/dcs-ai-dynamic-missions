# campaigns/

Story-first workspaces. Each campaign is a folder of schema-validated YAML and Markdown that
Claude skills write and the `dms` CLI compiles. **Files are the memory**: agents read the bible,
arc, state and continuity ledger instead of remembering.

## Layout (docs/CONTRACTS.md)

```
campaigns/<slug>/
  premise.md                 user's pitch + interview answers + mode rationale      (story-writer)
  bible.yaml                 setting, factions→DCS, characters + voices, sources    (story-writer)
  arc.yaml                   acts, missions, dramatic questions, qualities, branches (campaign-planner)
  continuity.md              APPEND-ONLY ledger of canon changes and outcomes        (all)
  state/qualities.yaml       current quality values, campaign flags, outcomes        (debriefer)
  state/outcomes/<mNN>.yaml  merged [DMS.OUTCOME] record for each flown mission      (debriefer)
  missions/mNN-<slug>/
    mission-spec.yaml        declarative mission (areas, roles, dynamic intent)     (mission-designer)
    beats.yaml               storylets → DMS_CONFIG.beats                           (mission-designer)
    lines.yaml               voice lines, 3-5 variants per beat                     (mission-designer, voice-director)
    briefing.md              5-paragraph order + intel narrative                    (mission-designer)
    kneeboard.md             one-page repeat of paragraphs 3-5                      (mission-designer)
    voice/                   rendered .ogg                                          (dms voice)
    out/                     plan.json, mNN.miz, check report                       (dms plan/build/check)
```

## Workflow

| Step | Skill / command | Output |
|---|---|---|
| 1 | `story-writer` | premise.md, bible.yaml, continuity.md |
| 2 | `campaign-planner` | arc.yaml, state/qualities.yaml |
| 3 | `mission-designer` (next mission only) | missions/mNN-<slug>/* |
| 4 | `voice-director` | voice plan, `uv run dms voice <lines.yaml> --dry-run`, then render |
| 5 | `dms-build` | `uv run dms validate` → `plan` → `voice` → `build` → `check` → out/mNN.miz |
| 6 | fly it in DCS | dcs.log contains `[DMS.OUTCOME] {json}` lines |
| 7 | `debriefer` | state/outcomes/mNN.yaml, qualities, continuity, next mission |

Missions are designed **after** the previous one is flown, so branches cost nothing.

## Schemas

JSON Schemas in `schemas/` (regenerate with `uv run dms schema`), from the pydantic models in
`packages/dms-core/src/dms_core/schemas/`: `story-bible`, `campaign-arc`, `qualities`,
`mission-spec`, `beats`, `voice-lines`, `mission-outcome`. Every model rejects unknown keys.

Quick check of a whole campaign without the CLI:

```bash
uv run python -c "import yaml,sys;from pathlib import Path;from dms_core.schemas import *;r=Path(sys.argv[1]);L=lambda p:yaml.safe_load((r/p).read_text(encoding='utf-8'));b=StoryBible.model_validate(L('bible.yaml'));CampaignArc.model_validate(L('arc.yaml'));Qualities.model_validate(L('state/qualities.yaml'));[print(m.name,validate_mission_bundle(MissionSpec.model_validate(L(m.relative_to(r)/'mission-spec.yaml')),BeatSheet.model_validate(L(m.relative_to(r)/'beats.yaml')),VoiceLineSet.model_validate(L(m.relative_to(r)/'lines.yaml')),b)) for m in sorted((r/'missions').iterdir())]" campaigns/dustoff-valley
```

## Conventions

- Slugs and ids are `lower_snake_case` or `kebab-case`; mission ids are `mNN-<slug>`.
- Mission outcomes become campaign flags named `<mNN>_<key>` (e.g. `m01_player_lost`) for arc branches.
- Guaranteed beats carry a `# GUARANTEED` comment and cover the arc entry's `key_beats`.
- Real people never get invented quotes. Historical claims carry `source_url` and `confidence`.
- Radio is callsign-first and terse. Nobody cheers on the net.

## Contents

- `_template/`: commented skeletons of every file. Copy it to start a campaign.
- `dustoff-valley/`: worked example (fictional, Syria, AH-64D). Bible, five-mission arc, and
  m01 First Light fully designed (24 beats, 73 line variants).
