# Radio realism

> "Pilots don't talk nonsense." Story lives in the gaps around procedure. The less a voice says,
> the more each word lands.

## Format

`<who you're calling>, <who you are>, <message>.` Callsign first, every time.

- "Dusty, Hatay Ops, picture clean, proceed to the box."
- Reply: "Hatay Ops, Dusty, wilco." The player's replies are implied. Don't voice the player.
- Numbers: "one-one", "two thousand", "heading zero-niner-zero", "five miles". Say grids as
  "grid Lima-Charlie four-five-two-one", and minimise them in voice lines.
- Repeat only for emphasis under stress: "Check fire, check fire."

## Brevity glossary (use correctly or not at all)

| Term | Meaning |
|---|---|
| copy / roger | received and understood (copy is more common on tactical nets) |
| wilco | will comply |
| say again | repeat |
| say status | report your condition |
| stand by | wait |
| picture | the overall air/ground situation ("picture clean") |
| tally / no joy | target in sight / not in sight |
| visual / blind | friendly in sight / not in sight |
| contact | radar or sensor contact; ground: "in contact" = engaged by enemy |
| spike / mud spike | RWR: airborne radar track / surface threat tracking ("mud spike, two o'clock, Six") |
| nails / buddy spike | RWR: airborne radar search / friendly radar |
| singer | RWR: SAM launch |
| magnum | friendly anti-radiation missile launched |
| defending | defensive manoeuvre ("Two, defending south, missile") |
| fence in / fence out | combat checks on / off |
| judy | aircrew has the intercept; the controller goes quiet |
| pop-up / fade / vanished | new group inside threat range / contact lost / lost, correlated to a shot |
| merged / commit / leaker / scram | visual fight / intercept the group / threat through the layer / withdraw now |
| angels / cherubs | thousands of feet MSL / hundreds AGL |
| IN / OFF + direction | attack run starting / finished ("One-one, IN from the west") |
| continue / continue dry | proceed with the run / proceed, no release |
| cleared to engage | Type 3 control: multiple attacks in a window |
| good readback | JTAC confirms the aircrew read back correctly |
| naked | no RWR indications |
| bingo / joker | fuel to return / fuel to start planning return |
| winchester | out of weapons |
| splash | target destroyed (A2A); for ground strikes prefer "good effect" / "target destroyed" |
| rifle | AGM (Maverick/Hellfire) away |
| cleared hot | ordnance release authorised (JTAC terminal control) |
| abort, abort, abort | stop the attack immediately |
| check fire | stop firing (friendlies/civilians) |
| danger close | friendlies inside minimum safe distance |
| troops in contact (TIC) | friendlies under fire, priority request |
| RTB | return to base |
| push | go to frequency / proceed to point ("push button two") |
| on station / off station | arrived / leaving the area |
| BDA | battle damage assessment |
| out | end of transmission, no reply expected (never "over and out") |

Full verified table (ATP 1-02.1 paraphrase): guide §2. **Pickle** and **shack** are slang, not
in ATP 1-02.1: avoid them for crisp professional voices.

## Formats that must be exact

- **Bullseye, never "bulls".** AWACS picture in bullseye format: "Python, Magic, picture, single
  group bullseye zero-four-zero, three-five, two-five thousand, hot, hostile."
- **BRAA** with no "for" or "at": "Python, Magic, BRAA one-eight-three, ten, two thousand, hot."
  Aspect is hot, flank, beam or drag. (The `brevity_misuse` lint checks both.)
- **9-line readback**: aircrew reads back lines 4, 6 and the restrictions; JTAC answers "good
  readback". Line numbers are understood, not spoken. Format: guide §1.3. A full 9-line or
  talk-on is too long for one transmission (`line_too_long`): split it into 2–3 chained beats
  (lines 1–3, 4–6, 7–9 + remarks) with `delay_sec: 3-5`.
- **Laser sequence** [unv]: aircraft "ten seconds" → "laser on" → JTAC "lasing" → aircraft
  "spot" → after impact "terminate".

## Net discipline

- AWACS limits itself to the picture, threat calls and handoffs. When the player is engaged
  ("judy", merged, defending), AWACS goes quiet: no picture calls during PEAK unless they carry a
  pop-up or a threat.
- Silence is fine; filler is not. No random chatter in quiet stretches.

## Register by speaker

- **Ops/command:** calm, sparse, decides things. Relays intel in one sentence.
- **Tower/ATC:** formula (runway, wind, clearance). Slightly bored. No drama.
- **Ground teams:** short, factual, a little breathless in contact. Clock/cardinal directions,
  distance in metres, landmarks.
- **Other aircrew:** coolest voices on the net. Weapon calls, fuel, positions.
- Stress shows as *fewer words* and repetition, never swearing tirades or shouting in capitals.

## Don't write this (from `supporting Files/Generic Voice Lines.md`)

| Avoid | Why | Instead |
|---|---|---|
| "Splash one! Hell YEAH!" | cheering on the net | "Dusty, Kestrel, good effect. Vehicle burning." |
| "We need close air NOW! We're getting HAMMERED!" | no callsign, no information | "Dusty, Mule Actual, troops in contact, east side of the road, two hundred metres. Need you on station." |
| "THAT'S what I'm talking about! Don't stop now — MORE, MORE!" | not a radio call | "Good hits. Second vehicle moving north. Your call." |
| "Weapons free, gentlemen. Let's get this done." | movie line | "Dusty, Ops, weapons free on armed targets." |
| "Time to earn your paycheck." | flavour with no function | cut it |

## Rules of thumb

- Every transmission has a function: inform, request, direct, or acknowledge.
- One idea per transmission. A second idea means a second line.
- Max 12 words for `terse` speakers, 20 for `normal`, 30 for `chatty`, and ≤8 s spoken
  (`line_too_long`); anything that can fire mid-fight ≤12 words (`peak_chatter`).
- Emotion lives in delivery notes and audio tags, not in adjectives.
- Character shows through *what* someone chooses to report and small habits (a tower controller
  who always says "welcome back"; seed these in the bible `voice.notes`), not through speeches.
- Variants must change information or rhythm: "Two technicals, north side" / "Vehicles moving,
  north of the canal, two of them" / "Kestrel has movement north, light vehicles".
- No real-world unit callsigns or real people unless the bible sources them.
