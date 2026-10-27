# Dustoff Corridor - Voice Line Script

Complete voice line script for mission audio, organized by character and event.

---

## Implementation Status

| Flag Range | Status | Count | Description |
|------------|--------|-------|-------------|
| **100-102** | ✅ Implemented | 3 | Mission start/victory/defeat |
| **110-116** | ✅ Implemented | 7 | Zone transition position reports |
| **117-118** | ✅ Implemented | 2 | Combat events (taking fire, casualties) |
| **119** | ✅ Implemented | 1 | A-10 check-in (spawn) |
| **120-127** | ⏸️ Future Expansion | 8 | A-10 weapon calls & engagements |
| **Total Ready** | **13 voice lines** | | **Ready for generation** |
| **Total Planned** | **21 voice lines** | | **Full mission scope** |

---

## Flag Mapping Reference

| Flag # | Event | Audio File | Character |
|--------|-------|------------|-----------|
| **100** | Mission Start | `mission_start.mp3` | Convoy Commander |
| **101** | Mission Victory | `mission_victory.mp3` | Convoy Commander |
| **102** | Mission Defeat | `mission_defeat.mp3` | Convoy Commander |
| **110** | Convoy enters Alpha Zone | `convoy_alpha_enter.mp3` | Convoy Commander |
| **111** | Convoy exits Alpha Zone | `convoy_alpha_exit.mp3` | Convoy Commander |
| **112** | Convoy enters Bravo Zone | `convoy_bravo_enter.mp3` | Convoy Commander |
| **113** | Convoy exits Bravo Zone | `convoy_bravo_exit.mp3` | Convoy Commander |
| **114** | Convoy enters Charlie Zone | `convoy_charlie_enter.mp3` | Convoy Commander |
| **115** | Convoy exits Charlie Zone | `convoy_charlie_exit.mp3` | Convoy Commander |
| **116** | Convoy arrives FOB-Victory | `convoy_arrived.mp3` | Convoy Commander |
| **117** | Convoy takes first hit | `convoy_taking_fire.mp3` | Convoy Commander |
| **118** | Convoy vehicle destroyed | `convoy_casualty.mp3` | Convoy Commander |
| **119** | A-10 enters AO | `a10_checkin.mp3` | A-10 Pilot |
| **120** | A-10 fires Maverick | `a10_rifle.mp3` | A-10 Pilot |
| **121** | A-10 gun run | `a10_gun_run.mp3` | A-10 Pilot |
| **122** | A-10 target destroyed | `a10_target_killed.mp3` | A-10 Pilot |
| **123** | A-10 engaging multiple | `a10_engaging_multiple.mp3` | A-10 Pilot |
| **124** | A-10 rockets away | `a10_rockets.mp3` | A-10 Pilot |
| **125** | A-10 winchester/RTB | `a10_winchester.mp3` | A-10 Pilot |
| **126** | A-10 reacquiring targets | `a10_reacquiring.mp3` | A-10 Pilot |
| **127** | A-10 splash confirmation | `a10_splash.mp3` | A-10 Pilot |

---

## 11Labs Voice Generation Prompts

### Convoy Commander Voice Profile

```
Create a male military convoy commander voice with the following characteristics:

- Age: 35-45 years old, seasoned NCO (Sergeant or Staff Sergeant)
- Tone: Professional, calm under pressure, confident
- Delivery: Clear radio transmission quality, slight radio filter acceptable
- Accent: American military, neutral regional accent
- Emotional state: Focused, alert, but not panicked (even under fire)
- Speaking pace: Measured and deliberate, easy to understand during combat
- Background: Ground vehicle commander coordinating with air support

The character is calling in position reports and status updates over military radio during a convoy escort mission in hostile territory. Even when under fire, he maintains composure and clear communication.

Voice should sound like a veteran ground unit leader who has seen combat before and knows how to communicate effectively under stress. Think of the tone used by real military radio operators - professional, direct, no wasted words.
```

### A-10 Pilot Voice Profile

```
Create a male A-10 Warthog pilot voice with the following characteristics:

- Age: 30-40 years old, experienced CAS pilot
- Tone: Cool, professional, relaxed confidence (typical fighter pilot)
- Delivery: Helmet microphone quality, slight compression acceptable
- Accent: American military aviator
- Emotional state: Calm and focused, this is routine work
- Speaking pace: Quick but clear, clipped military radio brevity
- Background: Close air support pilot, comfortable in the A-10

The character is a veteran ground attack pilot checking in with ground forces and calling weapon releases. Professional but with the trademark "Hawg driver" confidence - these pilots are known for their laid-back demeanor even in combat.

Voice should have that classic fighter pilot sound - smooth, confident, using proper brevity codes. This is another day at the office for this pilot.
```

---

## Voice Line Script - Full Text

### Mission State (Convoy Commander)

#### Flag 100 - Mission Start
**File:** `mission_start.mp3`

**Text:**
> "Dustoff, this is Convoy Actual. We're rolling out now. Stick close, we're expecting contact."

---

#### Flag 101 - Mission Victory
**File:** `mission_victory.mp3`

**Text:**
> "Dustoff, Convoy Actual. We've reached the FOB. All vehicles accounted for. Outstanding work up there. Convoy Actual, out."

---

#### Flag 102 - Mission Defeat (Convoy Destroyed)
**File:** `mission_defeat.mp3`

**Text:**
> "Dustoff... we're... we're not gonna make it. Too many casualties. Mission... failed..."

*(Delivery note: Strained, wounded, fading. This is the last transmission before convoy is overrun.)*

---

### Position Reports (Convoy Commander)

#### Flag 110 - Entering Alpha Zone
**File:** `convoy_alpha_enter.mp3`

**Text:**
> "Convoy entering Alpha sector."

---

#### Flag 111 - Exiting Alpha Zone
**File:** `convoy_alpha_exit.mp3`

**Text:**
> "Convoy clear of Alpha, continuing route."

---

#### Flag 112 - Entering Bravo Zone
**File:** `convoy_bravo_enter.mp3`

**Text:**
> "Convoy entering Bravo sector."

---

#### Flag 113 - Exiting Bravo Zone
**File:** `convoy_bravo_exit.mp3`

**Text:**
> "Convoy clear of Bravo, continuing route."

---

#### Flag 114 - Entering Charlie Zone
**File:** `convoy_charlie_enter.mp3`

**Text:**
> "Convoy entering Charlie sector."

---

#### Flag 115 - Exiting Charlie Zone
**File:** `convoy_charlie_exit.mp3`

**Text:**
> "Convoy clear of Charlie, final approach beginning."

---

#### Flag 116 - Arrived at Destination
**File:** `convoy_arrived.mp3`

**Text:**
> "Convoy has reached destination. All vehicles accounted for, standing by for orders."

---

### Combat Events (Convoy Commander)

#### Flag 117 - Taking Fire
**File:** `convoy_taking_fire.mp3`

**Text:**
> "Contact! Contact! We are taking fire!"

*(Delivery note: Urgent but controlled. This is the first moment of contact.)*

---

#### Flag 118 - Vehicle Destroyed
**File:** `convoy_casualty.mp3`

**Text:**
> "Vehicle destroyed! We're taking casualties! Dustoff, we need immediate air support!"

*(Delivery note: Stressed, urgent. Situation is serious but commander is still in control.)*

---

### A-10 CAS (A-10 Pilot)

#### Flag 119 - Check In
**File:** `a10_checkin.mp3`

**Text:**
> "Convoy Actual, Hawg One-One checking in. I've got eyes on multiple hostile contacts. ETA two minutes to engagement range."

---

### ⏸️ Future Expansion - A-10 Weapons & Engagement Lines (Flags 120-127)

**Status:** Not yet implemented - Reserved for future mission expansion

These voice lines are planned for future implementation when A-10 weapon triggers are added to the mission. The text and audio files will be generated when needed.

---

#### Flag 120 - Maverick Launch
**File:** `a10_rifle.mp3`

**Text:**
> "Hawg One-One, rifle."

*(Delivery note: Quick, clipped. Standard weapon release call. "Rifle" is brevity code for AGM-65 Maverick launch.)*

---

#### Flag 121 - Gun Run
**File:** `a10_gun_run.mp3`

**Text:**
> "Hawg One-One, in hot with the gun."

*(Delivery note: Focused, steady. Standard gun run callout before engaging with the GAU-8.)*

---

#### Flag 122 - Target Destroyed
**File:** `a10_target_killed.mp3`

**Text:**
> "Good kill on that BMP. Target destroyed."

*(Delivery note: Professional, matter-of-fact confirmation.)*

---

#### Flag 123 - Engaging Multiple Targets
**File:** `a10_engaging_multiple.mp3`

**Text:**
> "Multiple armor contacts. I'm going to make a few passes here. Stay clear of the target area."

*(Delivery note: Calm, informing friendly forces of extended engagement.)*

---

#### Flag 124 - Rockets Away
**File:** `a10_rockets.mp3`

**Text:**
> "Hawg One-One, rockets away."

*(Delivery note: Quick brevity call. Standard rocket launch callout.)*

---

#### Flag 125 - Winchester / RTB
**File:** `a10_winchester.mp3`

**Text:**
> "Convoy Actual, Hawg One-One is winchester. Good kills on multiple armor targets. RTB for rearm. Good luck down there."

*(Delivery note: Relaxed, satisfied. Winchester = out of weapons. RTB = returning to base.)*

---

#### Flag 126 - Reacquiring Targets
**File:** `a10_reacquiring.mp3`

**Text:**
> "Coming back around, reacquiring targets."

*(Delivery note: Calm, workmanlike. Setting up for another pass.)*

---

#### Flag 127 - Splash Confirmation
**File:** `a10_splash.mp3`

**Text:**
> "Splash one Shilka. That AAA is off the board."

*(Delivery note: Satisfied, confirming kill on AA threat. "Splash" = target destroyed.)*

---

## File Naming Convention

All audio files should be saved as:
- **Format:** MP3 or OGG (DCS compatible)
- **Naming:** Lowercase, underscores, descriptive
- **Location:** `elevenlabs-integration/mission-audio/dustoff-corridor/`

### Full File List

**✅ Ready to Generate (13 files - Currently Implemented)**

**Mission State (3 files):**
1. `mission_start.mp3` - Flag 100
2. `mission_victory.mp3` - Flag 101
3. `mission_defeat.mp3` - Flag 102

**Convoy Position Reports (7 files):**
4. `convoy_alpha_enter.mp3` - Flag 110
5. `convoy_alpha_exit.mp3` - Flag 111
6. `convoy_bravo_enter.mp3` - Flag 112
7. `convoy_bravo_exit.mp3` - Flag 113
8. `convoy_charlie_enter.mp3` - Flag 114
9. `convoy_charlie_exit.mp3` - Flag 115
10. `convoy_arrived.mp3` - Flag 116

**Convoy Combat (2 files):**
11. `convoy_taking_fire.mp3` - Flag 117
12. `convoy_casualty.mp3` - Flag 118

**A-10 CAS (1 file):**
13. `a10_checkin.mp3` - Flag 119

---

**⏸️ Future Expansion (8 files - Not Yet Implemented)**

**A-10 Weapons & Engagements:**
14. `a10_rifle.mp3` - Flag 120
15. `a10_gun_run.mp3` - Flag 121
16. `a10_target_killed.mp3` - Flag 122
17. `a10_engaging_multiple.mp3` - Flag 123
18. `a10_rockets.mp3` - Flag 124
19. `a10_winchester.mp3` - Flag 125
20. `a10_reacquiring.mp3` - Flag 126
21. `a10_splash.mp3` - Flag 127

---

## Mission Editor Integration

### Flag Trigger Setup

For each flag, create a trigger in Mission Editor:

**Trigger Format:**
```
TYPE:     FLAG IS TRUE
Condition: Flag [###] is TRUE
Action:    SOUND TO COALITION → Blue → [filename.mp3]
```

**Example - Flag 110:**
```
Name: "Convoy Alpha Enter Audio"
Condition: FLAG IS TRUE → Flag 110
Action: SOUND TO COALITION → Blue → convoy_alpha_enter.mp3
```

Repeat for all **currently implemented flags (100-102, 110-119)**.

**Note:** Flags 120-127 are reserved for future expansion.

---

## Voice Acting Direction Notes

### Convoy Commander Tone Progression

| Situation | Delivery |
|-----------|----------|
| Position Reports (110-116) | Calm, routine, professional |
| Mission Start (100) | Confident, alert |
| Taking Fire (117) | Urgent, elevated but controlled |
| Casualties (118) | Stressed, desperate but not panicked |
| Victory (101) | Relieved, grateful |
| Defeat (102) | Wounded, fading, resigned |

### A-10 Pilot Tone Progression

| Situation | Delivery |
|-----------|----------|
| Check-in (119) | Professional, confident entry |
| Weapon Calls (120, 121, 124) | Quick, clipped brevity codes |
| Target Confirmed (122, 127) | Satisfied, professional |
| Multiple Targets (123) | Calm, informative |
| Reacquiring (126) | Matter-of-fact, workmanlike |
| Winchester (125) | Relaxed, job done |

**Overall A-10 Character:** Classic fighter pilot cool - even when engaging targets, it's just another day at work. Voice should be smooth, confident, using proper military brevity. The A-10 pilot is experienced, competent, and has that trademark "Hawg driver" laid-back confidence.

---

## 11Labs Generation Tips

### Settings Recommendations

- **Stability:** 50-60% (allows natural variation)
- **Clarity:** 70-80% (clear radio comms)
- **Style Exaggeration:** 30-40% (subtle character)
- **Speaker Boost:** Enabled (consistent voice)

### Character Consistency

Generate all Convoy Commander lines with the same voice model/settings to maintain character continuity. Same for A-10 Pilot lines.

Consider saving the voice settings as a preset in 11Labs for:
- "Convoy Commander - Dustoff Corridor"
- "A-10 Pilot - Dustoff Corridor"

### Quality Check

After generation, check each line for:
- ✅ Clear pronunciation
- ✅ Consistent volume levels
- ✅ Appropriate emotion/stress
- ✅ No audio artifacts
- ✅ Proper radio feel (can add light radio filter in post)

---

## Alternative Line Variations (Optional)

If you want more variety, consider generating 2-3 variations of key lines:

**Convoy Taking Fire (117) - Variations:**
- "Contact! We're taking fire!"
- "Ambush! Ambush! We're under fire!"
- "Convoy under attack! Taking effective fire!"

**A-10 Check-In (119) - Variations:**
- "Convoy Actual, Hawg One-One checking in. I see multiple targets. Commencing attack run."
- "Hawg One-One on station. I've got good visual on hostiles. Engaging now."
- "Convoy Actual, Hawg One-One. Tally multiple armor targets. Moving to engage."

Then randomly select which variation plays in-game for more immersion.

---

## Production Checklist

**Current Implementation (13 voice lines):**

- [ ] Generate Convoy Commander voice in 11Labs (12 lines)
- [ ] Generate A-10 Pilot voice in 11Labs (1 line - check-in only)
- [ ] Export all 13 audio files
- [ ] Normalize audio levels (ensure consistent volume)
- [ ] (Optional) Add radio filter effect for authenticity
- [ ] Move files to `elevenlabs-integration/mission-audio/dustoff-corridor/`
- [ ] Create 13 flag triggers in Mission Editor (100-102, 110-119)
- [ ] Link audio files to respective flags
- [ ] Test in-game audio playback for each flag
- [ ] Adjust timing/volume as needed
- [ ] Test A-10 check-in audio (flag 119)
- [ ] Test convoy progression (Alpha → Bravo → Charlie → Arrival)

**Future Expansion (when flags 120-127 implemented):**

- [ ] Generate additional 8 A-10 weapon/engagement lines
- [ ] Add weapon event triggers to mission
- [ ] Test A-10 voice lines sequence (check-in → attacks → winchester)

---

## Testing Notes

### In-Game Audio Test Procedure

**Test sequence for currently implemented flags (100-102, 110-119):**

1. **Mission Start (Flag 100)** - Verify audio plays at mission start
2. **Zone Progression (Flags 110-116)** - As convoy moves, verify position reports:
   - Alpha enter/exit (110-111)
   - Bravo enter/exit (112-113)
   - Charlie enter/exit (114-115)
   - Arrival at FOB (116)
3. **Combat Events (Flags 117-118)** - Trigger combat:
   - First hit on convoy (117)
   - Vehicle destroyed (118)
4. **A-10 Check-in (Flag 119)** - Verify A-10 spawn audio with 2-minute ETA
5. **Mission End (Flags 101-102)** - Complete or fail mission, verify appropriate audio
6. **Volume Check** - Ensure all audio is clear over combat noise

### Flag Debugging

If audio doesn't play:
- Check flag is being set (use `trigger.action.outText()` to confirm)
- Verify audio file path in Mission Editor trigger
- Check file format compatibility (MP3 or OGG)
- Confirm trigger condition is "FLAG IS TRUE" not "FLAG EQUALS"

---

Good luck with voice generation! The convoy commander and A-10 pilot characters are really going to bring the mission to life. The back-and-forth between ground and air will create an immersive combat experience.
