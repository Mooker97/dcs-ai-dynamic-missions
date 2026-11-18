# Desert Scout

Legacy armed-scout mission, a sibling of Dawn Scout. All enemies are placed in the Mission Editor
as **late-activated** groups, and `DO SCRIPT` triggers randomise which ones appear:

| Script | What it does |
|--------|--------------|
| `random-spawn.lua` | Rolls each placed group on its own and activates it on success: `Tech-1..10` 25%, `Infantry-1..4` 33%. |
| `random-spawn-delayed.lua` | Same pool and chances, but each successful group activates after a random 60-180 s delay. Use this instead of `random-spawn.lua`, not as well as it. |
| `random-spawn-aa.lua` | 35% chance to activate exactly one AA group, picked at random from `AA-1`..`AA-16`. |
| `random-spawn-hvt.lua` | 10% chance to activate the `hvt-1` supply convoy 12-14 min in, and to set user flag `100` for the radio callout. |

- **Fixture:** `tests/fixtures/miz/desert-scout.miz`
- **Audio:** no mission-specific takes. Uses generic lines from `data/voice/lines/generic.yaml`.

These scripts use plain `math.random`, `timer.scheduleFunction` and `trigger.action.activateGroup`, with no DMS runtime.
