# Dawn Scout

Legacy armed-scout mission. All enemies are placed in the Mission Editor as **late-activated**
groups, and three `DO SCRIPT` triggers at mission start randomise which ones appear:

| Script | What it does |
|--------|--------------|
| `random-spawn.lua` | Rolls each placed group on its own and activates it on success: `AAA-1..4` 65%, six `Infantry-*` groups 33%, eleven `Tech-*` groups 25%. |
| `random-spawn-aa.lua` | 35% chance to activate exactly one 2S6 Tunguska, picked at random from `AA-17`..`AA-32`. |
| `random-spawn-hvt.lua` | 15% chance to activate the `hvt-1` supply convoy 12-14 min in, and to set user flag `100` (an ME trigger plays the radio callout). |

- **Fixture:** `tests/fixtures/miz/dawn-scout.miz`
- **Audio:** `assets/audio/missions/dawn-scout/` (`mission-start.wav`, `clear-to-land.wav`), plus generic lines from `data/voice/lines/generic.yaml`

These scripts use plain `math.random` and `trigger.action.activateGroup`, with no DMS runtime.
They are kept as the simplest "placed pool + chance" pattern, which the spawner module generalises.
