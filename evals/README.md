# DMS evals

The golden prompt eval suite from ROADMAP v0.8. It has two halves, and neither one calls an LLM
or the network:

| Path | What |
|---|---|
| `specs/gNN-*/` | 8 hand-written golden missions (`bible.yaml`, `mission-spec.yaml`, `beats.yaml`, `lines.yaml`, `expect.yaml`). They must pass validate, plan, build and check, with the same plan every time. |
| `premises/pNN-*.yaml` | 30 campaign premises (6 historical, 8 adapted, 11 fictional, 5 fantasy) on 10 DCS maps, each with the properties an adherent campaign must have. |
| `run.py` | The runner: `--golden`, `--score`, `--lint-premises`. |
| `test_evals.py` | The pytest that keeps everything green in CI. `evals` is in the root `testpaths`. |

## Golden specs (regression)

```bash
uv run python evals/run.py --golden                 # table, exit 1 if any golden fails
uv run python evals/run.py --golden --only g02-caucasus-ka50-red --json out/golden.json
uv run pytest evals                                 # same checks, ~5 s
```

For each golden, the runner calls the same library code as `dms validate → plan → build → check`
(the `dms_cli` helpers). Output goes to a temp dir, so nothing is written into `specs/`. Each
golden is scored on these stages:

- **validate**: 0 errors, and no more warnings than `expect.max_warnings`.
- **plan**: it plans, and planning it twice with the fixed `seed` gives byte-identical plans.
- **build / check**: the `.miz` builds and `dms check` reports OK.
- **expect**: the theater, mission type and player aircraft match, the plan has at least
  `min_groups` groups, and the runtime beat, pool, encounter and voice counts match exactly.
- **coverage**: every line a beat references exists, and every line points at a real beat and is
  used. Every voiced beat has at least 2 variants, and every speaker is in the cast. Every
  objective `success_flag` is set by some beat. Some beat ends the mission in success, at least
  one beat is `guaranteed`, and every encounter telegraph beat exists.

| Golden | Map, year | Player | Type |
|---|---|---|---|
| g01-syria-a10-cas | Syria 2016 | A-10C_2 | CAS |
| g02-caucasus-ka50-red | Caucasus 2008 | Ka-50_3 (red) | CAS |
| g03-persiangulf-f18-strike | PersianGulf 2019 | FA-18C_hornet | STRIKE |
| g04-nevada-f16-sead | Nevada 2022 | F-16C_50 | SEAD |
| g05-afghanistan-ch47-transport | Afghanistan 2011 | CH-47Fbl1 | TRANSPORT |
| g06-sinai-f4-strike | Sinai 1974 | F-4E-45MC | STRIKE |
| g07-marianas-f14-cap | MarianaIslands 1988 | F-14B | CAP |
| g08-syria-oh58-convoy | Syria 2014 | OH58D | CONVOY_ESCORT |

A golden can go red after an intentional planner change, for example a different group count.
When that happens, check the new output with `uv run dms run evals/specs/<id> --skip-voice`, then
update `expect.yaml` in the same commit, and say why in the commit message. Delete the `out/`
folder that `dms run` leaves behind (it is gitignored).

## Premise scoring (LLM output quality)

The runner never generates anything itself. A person, or Claude Code, runs the skills for one
premise, and the runner then scores what they wrote.

1. Pick a premise, for example `evals/premises/p12-manbij-overwatch.yaml`.
2. **story-writer**: give it the `prompt` text verbatim, and ask it to set up
   `campaigns/eval-p12/` (premise.md, bible.yaml, continuity.md). For historical or adapted
   premises, answer the interview questions with what the premise says, and otherwise accept the
   skill's defaults. Do not steer it towards the expected properties.
3. **campaign-planner**: "plan the campaign" for `campaigns/eval-p12` (writes arc.yaml and
   state/qualities.yaml).
4. **mission-designer**: "design m01" (and more missions if you want a deeper score). The skill
   runs `dms validate` and repairs, for at most 3 loops.
5. Score it:

   ```bash
   uv run python evals/run.py --score campaigns/eval-p12 --premise p12-manbij-overwatch \
       --json evals/results/p12.json        # add --no-build to skip plan/build/check
   ```

In Claude Code, one prompt per premise is enough: *"Run story-writer with the prompt in
evals/premises/p12-manbij-overwatch.yaml into campaigns/eval-p12, then campaign-planner, then
mission-designer for m01. Don't read the premise's `expect` block."* Keep generated eval campaigns
out of git, or delete them after scoring. `evals/results/` is not tracked either.

### What `--score` checks

| Category | Checks |
|---|---|
| files | premise.md, bible.yaml, arc.yaml, continuity.md, state/qualities.yaml and at least one designed mission exist |
| schema | bible and arc validate against `StoryBible` / `CampaignArc`, and `dms validate` gives 0 errors per mission |
| premise | the theater, era range and content mode match. Player and enemy sides exist, and some characters are voiced (historical bibles must also cite sources). The arc's mission count is in range, it has the required mission types, and its player aircraft are in `airframes` (or match `airframe_role` and the coalition). Each mission matches the theater, era, aircraft, coalition and bible mode |
| arc | the arc defines qualities and has branches, every branch target exists, and every mission lists key beats |
| coverage | the same beat and line coverage checks as the goldens, run per mission |
| build | each mission plans, builds a `.miz`, and `dms check` reports OK |
| story | each `story_elements[*]` is found by keyword (`any_of`, case-insensitive) in premise.md, bible, arc, continuity, briefings, kneeboards or lines |

The output is a table plus every failed check, or JSON (`--json PATH`, `--json-stdout`).
`score = passed / total`. With `--min-score 0.9`, the run exits 1 below that threshold.

The story check is only a keyword heuristic, so treat it as a smoke signal, not a judgement of
quality. Read the bible before you trust a low story score.

## Premise file format

The model is `Premise` in `run.py` (`extra="forbid"`). `--lint-premises` checks every premise
against `dms_core.catalog`: the airframes must exist, be player-flyable, be flown by the expected
coalition and have the expected role, and their catalog eras must overlap the premise era. The
genre must also map to the right mode (fantasy uses mode `fictional` with a tech veneer).

```yaml
id: p10-strait-escort
title: Hormuz Shepherd
genre: adapted                 # historical | adapted | fictional | fantasy
prompt: "2019, the Strait of Hormuz. ..."
expect:
  theater: PersianGulf
  era: [2019, 2020]
  mode: adapted
  player_coalition: blue
  airframes: [FA-18C_hornet]
  airframe_role: multirole
  missions: [4, 6]             # arc.yaml mission count
  mission_types: [ESCORT, CAP] # must each appear in the arc
  story_elements:
    - {id: roe, description: "Restrictive ROE", any_of: [rules of engagement, weapons tight]}
```

The premises are original. None of them recreates a commercial DCS campaign. The historical ones
are built on documented events and leave real people silent. The catalog has no WWII player
aircraft yet, so no premise uses Normandy or TheChannel.
