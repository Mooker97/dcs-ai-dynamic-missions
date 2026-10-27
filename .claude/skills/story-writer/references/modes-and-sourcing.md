# Modes and sourcing

`mode` (StoryBible) tells every later agent how much of the story may be invented. Missions
inherit it as `content_mode` in mission-spec.yaml.

| Mode | Use when | Invented | Must be sourced |
|---|---|---|---|
| `historical` | Re-creating a real operation (e.g. Desert Storm, Bekaa 1982) | Only the player's own flight and its minor radio traffic | Dates, units, aircraft, weapons, places, outcomes |
| `adapted` | Real setting/conflict with invented characters or events | Specific engagements, characters, timeline shifts (say what changed in `canon_rules`) | The real anchor events and the equipment/era |
| `fictional` | Invented conflict, usually on real terrain | Everything political and narrative | Geography and equipment, when they carry weight |

Pick `fictional` when the political premise never happened. That stops later agents from trying
to "source" invented events. Record the reason as the first `canon_rules` entry, e.g.
`"Mode fictional: the coalition operation is invented; Hatay geography and AH-64D capabilities are real."`

## Claims (`Source`)

```yaml
sources:
  - claim: "The Orontes river runs through Antakya in Turkey's Hatay province."
    source_url: "https://www.britannica.com/place/Orontes-River"
    confidence: high        # high: primary/official or cross-checked reputable reference
                            # medium: single reputable secondary source
                            # low: uncited wiki, forum, memory; flavour only
    note: null              # caveats, conflicting sources
```

Timeline events carry their own citation inline:

```yaml
timeline:
  - date: "2026-03-12"
    event: "Forward elements secure Hatay airfield."
    fictional: true          # invented: no source
  - date: "1939-06"
    event: "Hatay becomes part of Turkey."
    fictional: false
    source: {claim: "Hatay State joined Turkey in 1939.", source_url: "https://...", confidence: high}
```

## Real people

- Set `real_person: true` and give their role a source.
- **Never invent quotes**, opinions, decisions or private conversations for real people. They can
  be referred to ("orders from CENTCOM"), never voiced. Don't give them a `voice` block.
- When a scene needs a voice, create a fictional subordinate (`real_person: false`).
- Living private individuals never appear.

## Research with subagents (historical / adapted)

Launch research agents in parallel (Agent tool, general-purpose), each with a narrow brief and a
fixed return format:

> Research: which USAF/USN units flew SEAD over western Iraq on 17–19 Jan 1991, with aircraft
> types and weapons. Use WebSearch/WebFetch. Return ≤10 items as YAML
> `{claim, source_url, confidence, note}`. Prefer official histories, books and reputable
> journalism. Mark anything you could not cross-check `confidence: low`. Don't speculate.

Typical briefs:
- order of battle
- aircraft and weapon availability by date
- geography and place names as they appear on the DCS map
- callsign conventions of the era
- weather and season

Merge the results, de-duplicate, and keep only what the story uses. Low-confidence claims may drive
flavour, never plot.

## Hygiene rules

- Files are memory: write facts into the bible, never "remember" them between sessions.
- If DCS lacks the historical unit, say so in `canon_rules` and name the stand-in (e.g. "SA-6
  stands in for the SA-11 battery reported at X"). Put it in the faction's `tech_veneer` too.
- Never present invented intelligence as real. Fictional briefings say so in their
  classification line.
