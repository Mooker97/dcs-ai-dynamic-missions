# Faction → DCS mapping

Every faction must compile to something the generator can place: one DCS country, a coalition, and
era-correct DCS unit type ids (`FactionDCS`).

```yaml
factions:
  - id: red_regulars
    name: "Northern Valley Defence Command"
    description: "Regime army remnant holding the valley approaches."
    doctrine: "Static AAA belts, mobile SHORAD, artillery from dispersed hides."
    dcs:
      country: Syria                 # exactly one DCS country
      coalition: red                 # blue | red | neutral
      units: [ZSU-23-4 Shilka, Osa 9A33 ln, BMP-1, T-55, Ural-375 ZU-23]
      tech_veneer: null
  - id: red_militia                  # a second country means a second faction
    name: "Orontes Brigades"
    dcs: {country: Insurgents, coalition: red, units: [ZU-23 Emplacement, Land_Rover_101_FC, Infantry AK]}
```

Missions list the countries again in `blue_countries` / `red_countries` in mission-spec.yaml, and
threats and pools reference faction ids.

## Player coalition first

The player's coalition is fixed by the airframe, not the politics. Run
`uv run dms catalog units --era <year> --category plane` (or `helicopter`) and read the
`coalitions` column for the player aircraft: Mi-8MT, Mi-24P and Ka-50 are red; F-16C_50,
A-10C_2, AH-64D_BLK_II and UH-1H are blue. The player's faction takes that coalition, and every
enemy faction takes the other one, even when that looks backwards (a Georgian Mi-8 crew in 1993
makes Georgia red and the Abkhaz forces blue). Write the choice into `canon_rules`. Briefings and
radio lines use the story's names, never "blue" or "red".

## Choosing countries

- The country decides liveries, AI voice language and which units the Mission Editor allows. Pick
  the closest real operator. For irregulars use `Insurgents` (technicals, infantry, ZU-23 trucks).
- One coalition can include several factions with different countries. Blue and red must never
  share a country.
- For neutral civilians, use `coalition: neutral`, often with the host nation as the country.

## Era-correct units (examples; verify with the catalog / pydcs data)

| Era | Red air defence | Red ground | Blue ground |
|---|---|---|---|
| 1970s–80s | ZSU-23-4, S-60, SA-2/3/6/8, SA-9 | T-55, T-62, BMP-1, BTR-60 | M-60, M-113 |
| 1990s–2000s | ZSU-23-4, SA-8, SA-13, SA-15, SA-6, 2S6 Tunguska | T-72, BMP-2, BTR-80, BM-21 | M-1 Abrams, M-2 Bradley, Hummer |
| 2010s+ | SA-15, SA-19, SA-22 (Pantsir), SA-11, SA-10 | T-90, BMP-3, BTR-82A | M-1A2, Stryker variants, Leopard 2 |
| Irregulars, any era | ZU-23 on truck, MANPADS (SA-18/Igla) | technicals, infantry AK/RPG | — |

Type ids differ from display names. The grounding tools (`list_units(era, coalition, role)`) are the
source of truth. When in doubt, list representative units here and let missions describe threats
by `role` (mission-spec `ThreatRole`: sam_short, sam_medium, sam_long, aaa, manpads, armor, ifv,
technicals, infantry, artillery, fighters, attack_helicopters, ship, hvt). `dms plan` chooses the
exact types.

## Tech veneer (fantasy / sci-fi / invented gear)

DCS can't add units, so fiction gets a **veneer**: fiction names over real DCS types. `tech_veneer`
is one free-text string that records the mapping and why, and line writers use the fiction names.

```yaml
dcs:
  country: Russia
  coalition: red
  units: [Mi-24P, T-72B, ZSU-23-4 Shilka, Osa 9A33 ln]
  tech_veneer: >-
    "Wyvern assault gunship" = Mi-24P; "Lancer battle tank" = T-72B; "Skyhook flak battery" =
    ZSU-23-4 Shilka; "Ironwatch radar spire" = Osa 9A33 ln. Chosen for matching silhouette and role.
```

Rules:
- Keep silhouettes and capabilities believable. A "dragon" that is really an Su-25 flies low and
  attacks ground targets.
- One fiction name maps to one DCS type, and the mapping never changes mid-campaign (add a
  `canon_rules` line).
- Player aircraft keep their real cockpit. Only the fiction around them changes.

## Sanity checks

- Does each expected mission type have a fitting threat (SEAD needs radar SAMs, CAS needs armour or
  infantry)?
- Can the player aircraft survive the strongest unit at the planned realism?
- Is the unit list small (5–12 types) so it stays consistent across missions?
