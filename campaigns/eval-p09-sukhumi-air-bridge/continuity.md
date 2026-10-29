# Continuity ledger

<!-- APPEND-ONLY. Every agent that changes canon or records an outcome adds a dated entry at the bottom.
     Never rewrite earlier entries; correct them with a new entry that references the old one.
     Mission designers read this whole file before writing a mission. -->

## Canon at start

- 16 Sept 1993: the Abkhaz offensive on Sukhumi has begun; the Sochi ceasefire is dead. Georgian
  heavy artillery was withdrawn under the ceasefire and has not come back.
- Sukhumi and Babushara airfield are held by the Georgian garrison. The front runs along the
  Gumista river north-west of the city and through the hills north of it.
- The coast road south-east (Ochamchire, Gali, the Inguri) is still open, but Mingrelia beyond the
  Inguri is in Zviadist hands in places. The Zugdidi corridor is not safe for government aircraft.
- The 2nd Transport Helicopter Detachment at Senaki has two flyable Mi-8s: Merani 2-1 (the
  player) and Merani 2-2 (Capt. Levan Dolidze). Fuel at Senaki is rationed by sortie.
- Characters alive: Gelashvili (Kolkhi, Senaki ops), Abashidze (Babushara tower), Beridze
  (Granite, Babushara apron), Dolidze (Merani 2-2), Tsiklauri (flight engineer, intercom).
- No radar SAMs anywhere in the campaign.

## Open threads

- [ ] The list: Granite's list of who gets a seat is always longer than the aircraft (story-writer; pays off in the last mission).
- [ ] Fuel: Dolidze knows where unsigned fuel can be found at Babushara (story-writer; touched in m01, paid off in act 2).
- [ ] The airliners: civilian aircraft are still flying into Babushara; what happens to them changes the bridge (story-writer; real events of 21-23 Sept, act 2).
- [ ] Mingrelia: the route home crosses people who used to be on the same side (story-writer; any mission).

## Log

### 2026-10-29 — story-writer — campaign created
- Seeded from premise.md (eval premise p09, blind run). Mode adapted; bible validated on the first pass.

### 2026-10-29 — campaign-planner — arc planned
- Act 1 "The Bridge": m01-first-run (TRANSPORT), m02-sister-ship (CSAR), optional m02b-walking-out (CSAR, reached if m02_crew_rescued is not set).
- Act 2 "The Last Seats": m03-night-shuttle (TRANSPORT), m04-gumista-guns (RECON), m05-last-flight-out (TRANSPORT).
- Qualities: garrison_supply 1, refugees_saved 0, airframes 2, fuel 1, approach_threat 1.
- Outcome keys: m01 cargo_delivered, refugees_carried, fuel_found, player_lost, landed · m02 crew_rescued, player_lost, player_hit, landed · m02b crew_rescued, player_lost, landed · m03 cargo_delivered, refugees_carried, player_lost, landed · m04 guns_found, player_lost, landed · m05 refugees_carried, granite_evacuated, player_lost, landed.
- Threads: fuel (m01 fuel_found → m03/m05), the airliners (m03), Mingrelia (m01, m03), the list (m05).

### 2026-10-29 — mission-designer — m01-first-run designed
- Ramp and air variants. Known ZU-23 position 5 NM north of Babushara; possible second gun east of the field or at the Gumista mouth; possible Zviadist roadblock on the Zugdidi/Khobi road.
- New canon: the detachment S2 is Capt. D. Japaridze (unvoiced). Merani's ops frequency is 251.0 AM. A normal load out of Babushara is 24 people.
- Outcome keys emitted: cargo_delivered, refugees_carried (24), fuel_found (50% roll), player_lost, landed.

### 2026-10-29 — mission-designer — m02-sister-ship designed
- 19 Sept: Merani 2-2 was hit by the ZU-23 in the hills toward the Tkvarcheli pocket and force-landed 6 NM north-west of Ochamchire. Four crew alive, one with a leg injury.
- The crew goes silent 50 minutes after launch if nobody reaches them (crew_rescued false → m02b-walking-out).
- Continuity beats read m01_player_lost (spare airframe) and m01_fuel_found (Granite's drums). The briefing and kneeboard use conditional blocks on the same flags.
- Outcome keys emitted: crew_rescued, player_lost, player_hit, landed.
