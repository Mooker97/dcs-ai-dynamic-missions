# DMS Repository Versioning & Feature Roadmap

## Document Purpose

This file serves as the **single source of truth for DMS project versioning**. It tracks:
- **Completed features** with their exact capabilities
- **In-progress work** with current status
- **Planned features** for future releases
- **Release versions** and their defining functionality

Each version represents a complete, tested feature set that adds measurable value to the mission generation system. Use this document to understand project maturity, plan implementation work, and communicate progress to stakeholders.

### Development Strategy

**v0.1.0 - v0.2.0 Focus**: Lua Library Foundation
- Both versions prioritize **Lua library development** as it provides the best ROI on development time
- v0.1.0: Random spawn scripts using pre-placed units
- v0.2.0: Dynamic spawn scripts that generate groups using trigger zones
- Subsequent versions (v0.3.0+) will build mission generation and AI capabilities on this solid Lua foundation

---

## v0.1 - Random Spawning (Lua Library) ✅

**Phase**: Lua Library Foundation
**Overall Status**: Complete

### v0.1 Overview

The v0.1 umbrella provides the foundation for Lua-based spawning systems. It generates reusable Lua scripts for randomly spawning pre-placed units from the Mission Editor with customizable timing and quantities.

---

### v0.1.0 - Random Spawn Script Generation (COMPLETE) ✅

**Release Date**: 2025-12-08
**Status**: Production Ready

#### What v0.1.0 Does

Generates reusable Lua scripts for randomly spawning pre-placed units in DCS missions. Given a list of units positioned in the Mission Editor, produces customizable spawn scripts that randomize spawn timing and quantities. Mission creators integrate the scripts with minimal modification.

#### Core Capabilities

- ✅ **Random Spawn Scripts**: Creates complete, functional Lua spawner scripts with randomization
- ✅ **Pre-placed Unit Detection**: Reads units pre-positioned in Mission Editor
- ✅ **Customizable Behavior**: Spawn timing intervals, randomization seeds, quantity variance
- ✅ **Debug Logging**: Integrated debug system for mission troubleshooting
- ✅ **Script Validation**: Basic syntax and structure validation before deployment
- ✅ **Mission Integration**: Scripts directly embed in .miz mission files

#### How It Works

1. **Input**: List of units pre-placed in Mission Editor (ME)
2. **Processing**: Generate spawn scripts with randomization parameters
3. **Output**: Lua script that handles random spawning of those units during mission runtime
4. **Mission Creator**: Integrates script and adjusts parameters for their mission (spawn zones, timing)

#### Known Limitations (v0.1.0)

- Spawns only pre-placed units (cannot generate new groups/units from scratch)
- Manual parameter adjustment required per mission (spawn zones, timing intervals)
- No automatic coordinate transformation (mission creator manually sets positions)
- Spawn logic is basic (random intervals without advanced scheduling)
- No terrain collision detection for spawn positions
- No trigger zone support (addressed in v0.2.0)

#### Files & Architecture

**Key Components**:
- `lua-library/` - Core Lua framework for spawn system
- `miz-modifier/` - Mission file manipulation and script injection
- Script generation pipeline in MCP server

**Example Output**:
```lua
-- Generated spawn script (lua-library/spawn-pool.lua pattern)
DMS.SpawnPool = {
    spawns = {
        {name = "alpha-air-1", template = "f16_template", interval = 30},
        {name = "bravo-ground-1", template = "mrap_template", interval = 45},
    },
    config = {
        spawnZone = {x = 12345, y = 67890, radius = 5000},
        startDelay = 10,
        debugMode = true,
    }
}
```

#### Testing Status

- ✅ Lua syntax validated
- ✅ Script integration tested in Dustoff Corridor mission
- ✅ Debug logging verified in DCS.log
- ✅ Basic spawn scenarios functional
- ⚠️ Edge cases documented, handled in v0.2.0

#### Lessons from v0.1.0

1. **MizParser First** - All .miz modifications use MizParser, not pydcs
2. **String-based Lua** - Direct Lua manipulation via regex, not object serialization
3. **Debug Logging Essential** - All spawned groups must have debug output for troubleshooting
4. **FOW Integration Critical** - Spawned groups must register with FOW system immediately
5. **Configuration Over Code** - Mission creators adjust behavior via Lua tables, not by editing code

---

## v0.2 - Dynamic Spawning & Event Handling (Lua Library) 🔄

**Phase**: Lua Library Enhancement
**Overall Status**: v0.2.0 Complete / v0.2.1 In Progress / v0.2.2-v0.2.13 Planned

### v0.2 Overview

The v0.2 umbrella encompasses a complete dynamic mission system extending from core spawning through advanced mission mechanics:

**Core Systems (v0.2.0-v0.2.5)**:
- **v0.2.0**: Dynamic group generation from templates into spawn zones
- **v0.2.1**: Mission event monitoring and reactive spawning
- **v0.2.2**: AI group behavior and tactical decision-making
- **v0.2.3**: Mission settings, error handling, and diagnostics
- **v0.2.4**: Flag events and player communication systems
- **v0.2.5**: Fog of war and quality-of-life enhancements

**Stability & Expansions (v0.2.6-v0.2.13)**:
- **v0.2.6**: Bug fixes and stability for core systems
- **v0.2.7**: Waypoints and unit movement control
- **v0.2.8**: Scoring and objective tracking systems
- **v0.2.9**: Advanced triggers and scripting framework
- **v0.2.10**: Randomization improvements and scenario control
- **v0.2.11**: Mission Lua file generation simplification
- **v0.2.12**: Bug fixes and refinement round 2
- **v0.2.13**: Polish and nice-to-have improvements

Together, these create a comprehensive Lua library foundation enabling mission creators to build highly interactive, dynamic DCS missions with sophisticated behavior, scoring, and replayability.

---

### v0.2.0 - Dynamic Spawn Script Generation (COMPLETE) ✅

**Status**: Production Ready

#### What v0.2.0 Does

Generates Lua scripts that dynamically create and spawn groups/units from templates to fill spawn zones. Mission creators define spawn zones, unit templates, and quantities; the system generates code that spawns units to populate those zones during mission runtime.

#### Core Capabilities

- ✅ **Dynamic Group Generation**: Creates units on-demand from templates (not just pre-placed)
- ✅ **Template-based Spawning**: Reusable unit/group templates for flexible composition
- ✅ **Spawn Zone Population**: Fills defined zones with spawned groups
- ✅ **Quantity Management**: Maintains desired unit counts in zones
- ✅ **Integration with v0.1.0**: Builds on random spawn foundation with dynamic generation

#### Key Differences from v0.1.0

- ✨ **Generates Groups**: Creates units from scratch (not just randomizing pre-placed)
- ✨ **Template System**: Reusable templates for any unit type/composition
- ✨ **Zone Filling**: Automatically populates spawn zones to target quantities
- ✨ **Dynamic Lifecycle**: Spawns/despawns based on mission state

#### Implementation Details

- Zone-based spawning system integrated into Lua library
- Template matching and instantiation
- Spawn point calculation within zones
- Group composition from template definitions

---

### v0.2.1 - Basic Mission Event Handling (IN PROGRESS) 🔄

**Status**: Active Development

#### What v0.2.1 Does

Extends v0.2.0 with event monitoring and reactive behavior. Tracks mission events (groups entering/exiting zones, group destruction, player engagement) and triggers spawned content in response to those events.

#### Core Capabilities (In Progress)

- 🔄 **Group Zone Detection**: Triggers when groups enter/exit defined zones
- 🔄 **Destruction Monitoring**: Detects when spawned groups are destroyed
- 🔄 **Event-Driven Responses**: Execute actions based on mission events
- 🔄 **State Tracking**: Maintain mission state between events
- 🔄 **Reactive Spawning**: Spawn reinforcements or new threats based on player actions

#### Planned Features

- [ ] Zone enter/exit event handlers
- [ ] Group destruction detection
- [ ] Engagement/combat event tracking
- [ ] Event queue and processing system
- [ ] State machine for mission progression
- [ ] Event-triggered spawn sequences

---

### v0.2.2 - AI Group Behavior (PLANNED)

**Status**: Planned

#### What v0.2.2 Does

Extends v0.2.1 with intelligent behavior systems for spawned groups. Defines how AI-controlled groups behave, make tactical decisions, and respond to player actions. Builds mission realism and challenge through sophisticated group behaviors rather than just spawn mechanics.

#### Core Capabilities (Planned)

- 🤖 **AI Decision Trees**: Intelligent behavior selection based on mission state
- 🤖 **Tactical Responses**: Groups adapt to player actions (evade, attack, defend)
- 🤖 **Formation Control**: Maintain formations and coordinate group movements
- 🤖 **Threat Assessment**: Evaluate threats and prioritize targets
- 🤖 **Behavior Profiles**: Different AI personalities (aggressive, defensive, evasive)

#### Planned Features

- [ ] Behavior definition system (Lua tables)
- [ ] Decision trees for AI choices
- [ ] Patrol and engagement patterns
- [ ] Formation flying for aircraft groups
- [ ] Retreat/reinforcement logic
- [ ] Behavior event triggers

---

### v0.2.3 - Mission Settings & Utilities (PLANNED)

**Status**: Planned

#### What v0.2.3 Does

Provides mission-wide configuration, error handling, and diagnostic utilities. Centralizes settings management, error logging, debug systems, and provides tools for mission creators to configure and troubleshoot their missions.

#### Core Capabilities (Planned)

- ⚙️ **Centralized Settings**: Mission-wide configuration system
- ⚙️ **Error Handling**: Graceful error management and recovery
- ⚙️ **Debug Logging**: Comprehensive debug output system
- ⚙️ **Diagnostics**: Mission health checks and validation
- ⚙️ **Performance Monitoring**: Track and report performance metrics

#### Planned Features

- [ ] Settings configuration system
- [ ] Error logging and reporting
- [ ] Debug output modes (verbose, silent, production)
- [ ] Mission validation checklist
- [ ] Performance profiling tools
- [ ] Crash recovery systems

---

### v0.2.4 - Flag Events & Player Communications (PLANNED)

**Status**: Planned

#### What v0.2.4 Does

Implements DCS flag-based event handling and player communication systems. Allows missions to trigger behaviors based on custom flags, communicate mission objectives and status to players, and provide in-mission feedback via messages, sounds, and screen notifications.

#### Core Capabilities (Planned)

- 📡 **Flag Events**: Respond to custom DCS flag state changes
- 📡 **Player Messaging**: Send structured messages to player
- 📡 **Audio Cues**: Play sounds for important events
- 📡 **Screen Notifications**: Display mission updates on HUD
- 📡 **Briefing Updates**: Dynamic mission briefing changes

#### Planned Features

- [ ] Flag event listeners
- [ ] Flag state management
- [ ] Message queue system
- [ ] Audio notification system
- [ ] Screen markup and HUD updates
- [ ] Dynamic briefing callbacks

---

### v0.2.5 - Fog of War & Quality of Life Features (PLANNED)

**Status**: Planned

#### What v0.2.5 Does

Implements advanced dynamic features that enhance mission immersion and realism. Adds fog of war systems for hidden enemy detection, together with quality-of-life improvements that make missions more engaging and responsive to player actions.

#### Core Capabilities (Planned)

- 👁️ **Fog of War**: Hide enemy groups until discovered by proximity or combat
- 👁️ **Discovery Mechanics**: Players reveal enemies through reconnaissance
- 👁️ **Dynamic Difficulty**: Adjust threat levels based on player performance
- 👁️ **Environmental Effects**: Weather, time-of-day impact on visibility
- 👁️ **Mission Pacing**: Control reinforcement timing and enemy distribution

#### Planned Features

- [ ] FOW registration and state tracking
- [ ] Proximity-based group revelation
- [ ] Combat event revelation system
- [ ] Difficulty scaling algorithms
- [ ] Performance optimization for many hidden groups
- [ ] Environmental visibility factors
- [ ] Dynamic reinforcement timing
- [ ] Threat distribution algorithms

#### Dependencies

- Extends v0.2.1 (Event Handling) - Uses event system for discoveries
- Extends v0.2.3 (Settings & Utilities) - Configurable FOW parameters
- Complements v0.2.2 (AI Behavior) - AI reacts to being discovered

---

### v0.2.6 - Bug Fixes & Stability (PLANNED)

**Status**: Planned (post v0.2.5)

#### What v0.2.6 Does

Stabilization and bug fix release for v0.2 core systems. Addresses issues discovered in v0.2.0-v0.2.5, improves performance, and refines existing functionality before moving to new feature expansions.

#### Focus Areas

- 🐛 **Bug Fixes**: Address issues in spawn system, event handling, AI behavior
- 🐛 **Performance**: Optimize expensive operations across all v0.2.x systems
- 🐛 **Stability**: Edge case handling and robustness improvements
- 🐛 **Polish**: Code cleanup and refinement in existing modules

#### Bug List
- Units can spawn on top of buildings
- Fog opf war not reliable

---

### v0.2.7 - Waypoints & Unit Movement (PLANNED)

**Status**: Planned

#### What v0.2.7 Does

Enables dynamic waypoint creation and movement of spawned units. Mission creators can define routes, patrol patterns, and move spawned groups around the mission area, giving spawned units realistic movement behavior and operational patterns.

#### Core Capabilities (Planned)

- 🗺️ **Waypoint Generation**: Create waypoints for spawned groups
- 🗺️ **Patrol Patterns**: Define patrol routes and movement patterns
- 🗺️ **Route Planning**: Calculate efficient routes between objectives
- 🗺️ **Dynamic Movement**: Change unit routes based on mission events
- 🗺️ **Formation Movement**: Coordinate multi-group movements

#### Planned Features

- [ ] Waypoint definition system
- [ ] Route generation from zone to zone
- [ ] Patrol pattern templates
- [ ] Speed and altitude control
- [ ] Route modification on events
- [ ] Formation flying patterns

---

### v0.2.8 - Scoring & Objectives (PLANNED)

**Status**: Planned

#### What v0.2.8 Does

Advanced objective tracking and scoring system. Defines mission objectives with completion conditions, tracks player progress, and calculates scores based on performance. Mission creators can define complex objective structures with multiple branches and scoring modifiers.

#### Core Capabilities (Planned)

- 🎯 **Objective Tracking**: Define and monitor mission objectives
- 🎯 **Completion Conditions**: Complex success/failure conditions
- 🎯 **Scoring System**: Calculate scores based on actions and outcomes
- 🎯 **Objective Events**: Trigger behaviors when objectives complete
- 🎯 **Performance Metrics**: Track and report mission performance

#### Planned Features

- [ ] Objective definition system (nested objectives)
- [ ] Condition evaluation engine
- [ ] Score calculation and bonuses
- [ ] Objective state tracking
- [ ] Event triggers on objective changes
- [ ] Performance reporting and AAR integration

---

### v0.2.9 - Triggers & Scripting Framework (PLANNED)

**Status**: Planned

#### What v0.2.9 Does

Expands trigger capabilities and provides a comprehensive scripting framework for mission creators. Advanced trigger system with complex condition evaluation and more flexible Lua scripting hooks, enabling sophisticated mission logic.

#### Core Capabilities (Planned)

- ⚙️ **Advanced Triggers**: Complex conditional triggers with AND/OR logic
- ⚙️ **Trigger Actions**: Execute multiple actions on trigger conditions
- ⚙️ **Scripting Hooks**: Injection points for custom Lua scripts
- ⚙️ **Condition Builders**: Time-based, state-based, proximity-based conditions
- ⚙️ **Event Integration**: Connect triggers to all mission events

#### Planned Features

- [ ] Trigger condition system (AND/OR/NOT logic)
- [ ] Action queue system
- [ ] Custom event definitions
- [ ] Scripting hook system
- [ ] Condition validators
- [ ] Trigger debugging tools

---

### v0.2.10 - Randomization Improvements (PLANNED)

**Status**: Planned

#### What v0.2.10 Does

Enhanced randomization system giving mission creators fine-grained control over randomization behavior. Allows creators to define scenario variations, control randomness parameters, and create diverse mission experiences while maintaining predictability when desired.

#### Core Capabilities (Planned)

- 🎲 **Scenario Variations**: Define multiple mission scenario types
- 🎲 **Randomization Control**: Specify which elements randomize and how much
- 🎲 **Seeded Randomization**: Repeatable scenarios with seed values
- 🎲 **Distribution Control**: Control probability distributions of spawns
- 🎲 **Dynamic Difficulty**: Adjust randomization based on difficulty level

#### Planned Features

- [ ] Scenario definition system
- [ ] Randomization parameter configuration
- [ ] Seed-based reproducibility
- [ ] Probability distribution controls
- [ ] Weighted selection for spawns
- [ ] Difficulty-based randomization scaling

---

### v0.2.11 - Mission Lua File Generation (PLANNED)

**Status**: Planned

#### What v0.2.11 Does

Simplifies the process of generating Lua files that can be directly imported into DCS mission files. Mission creators define mission behavior in simple configuration, and the system generates complete, importable Lua scripts ready to inject into .miz files.

#### Core Capabilities (Planned)

- 📝 **Lua Code Generation**: Generate complete, formatted Lua code
- 📝 **Module Organization**: Structure generated code for importability
- 📝 **Configuration to Code**: Convert mission config to executable Lua
- 📝 **Syntax Validation**: Ensure generated Lua is valid and runnable
- 📝 **Code Formatting**: Professional formatting and documentation

#### Planned Features

- [ ] Lua generation from mission configuration
- [ ] Modular code organization
- [ ] Automatic function generation
- [ ] Syntax validation and linting
- [ ] Code formatting and comments
- [ ] Import helpers for .miz integration

---

### v0.2.12 - Bug Fixes & Refinement Round 2 (PLANNED)

**Status**: Planned (post v0.2.11)

#### What v0.2.12 Does

Second comprehensive bug fix and refinement cycle for v0.2 systems. Addresses issues discovered during v0.2.7-v0.2.11 development, improves performance of new systems, and ensures stability and reliability across all expanded functionality.

#### Focus Areas

- 🐛 **Bug Fixes**: Address issues in waypoints, scoring, triggers, randomization
- 🐛 **Performance**: Optimize new systems (waypoints, objectives, triggers)
- 🐛 **Stability**: Edge case handling for complex trigger scenarios
- 🐛 **Integration**: Ensure all v0.2.x systems work together seamlessly

---

### v0.2.13 - Polish & Nice-to-Have Improvements (PLANNED)

**Status**: Planned (final v0.2 release)

#### What v0.2.13 Does

Final polish release for v0.2 library. Includes approximately 5 quality-of-life and nice-to-have improvements that enhance usability and user experience without adding major new features.

#### Planned Improvements

- ✨ **Improved Error Messages**: More helpful and actionable error feedback
- ✨ **Configuration Validation**: Better upfront validation of mission configurations
- ✨ **Performance Profiling**: Built-in tools for mission creators to profile their missions
- ✨ **Example Missions**: Sample/template missions showing best practices
- ✨ **Documentation & Guides**: Comprehensive guides for common mission patterns

---

## v0.3 - ElevenLabs Audio Integration (PARTIAL) 🎙️

**Status**: Partial Implementation (integration pending)
**Phase**: Audio & Immersion

### v0.3 Overview

ElevenLabs integration for generating high-quality audio from text prompts and playing them within DCS missions. A significant portion of the implementation is complete but not yet integrated into the existing mission systems. Once integrated, mission creators can add dynamic audio narration, briefings, and in-mission communications via text prompts.

---

### v0.3.0 - ElevenLabs Audio Generation (PARTIAL) 🎙️

**Status**: Implementation In Progress

#### What v0.3.0 Does

Generates audio files from text prompts using ElevenLabs API and integrates them into DCS missions via Lua scripts. Mission creators can define text strings that get converted to natural-sounding audio, which can then be triggered at mission events or specific times.

#### Core Capabilities (Partial)

- 🎙️ **Text-to-Speech Generation**: Convert text prompts to audio via ElevenLabs API
- 🎙️ **Voice Selection**: Choose from multiple ElevenLabs voices
- 🎙️ **Audio File Management**: Store and organize generated audio files
- 🎙️ **Lua Activation**: Trigger audio playback from mission Lua scripts
- 🎙️ **Event-Driven Audio**: Play audio on mission events (zone entry, group destroyed, etc.)

#### Current Implementation Status

- ✅ ElevenLabs API integration (done, needs integration)
- ✅ Audio file generation and caching (done, needs integration)
- ✅ Voice management system (done, needs integration)
- ⏳ Lua mission integration (pending)
- ⏳ Event-triggered audio playback (pending)
- ⏳ Audio queue system (pending)

#### Planned Features

- [ ] Integrate audio generation into mission creation pipeline
- [ ] Lua audio trigger system
- [ ] Audio queue and scheduling
- [ ] Multiple voice support
- [ ] Audio caching and reuse
- [ ] Performance optimization for large audio sets

#### Integration Points

- v0.2.1 (Event Handling) - Trigger audio on mission events
- v0.2.4 (Flag Events & Comms) - Audio for player communications

---

## v0.4 - MIZ File Reading & Extraction (PLANNED)

**Status**: Planned
**Phase**: Mission Input

### v0.4 Overview

Reads and extracts mission setup information from pre-created .miz files. Instead of manually specifying zones and groups, mission creators can use the Mission Editor to create their setup and have the system automatically extract all necessary configuration. This dramatically simplifies mission creation workflow.

---

### v0.4.0 - MIZ File Structure Reading (PLANNED)

**Status**: Planned

#### What v0.4.0 Does

Parses existing .miz mission files to extract zone definitions, group placements, and mission configuration. Mission creators create their mission layout in the DCS Mission Editor, and the system reads that file to automatically populate spawn zones, group definitions, and mission parameters.

#### Core Capabilities (Planned)

- 📖 **Zone Extraction**: Read trigger zones from mission file
- 📖 **Group Detection**: Extract unit groups and their properties
- 📖 **Configuration Parsing**: Read mission settings and parameters
- 📖 **Coalition Identification**: Identify blue/red side setup
- 📖 **Coordinate Extraction**: Get precise spawn positions from groups

#### Workflow

1. **Input**: User creates mission in Mission Editor with zones and groups
2. **Processing**: Read .miz file and extract all zone/group definitions
3. **Output**: Automatically populate DMS with zones, templates, and configuration
4. **Result**: Mission creator only needs to define behavior, not setup

#### Planned Features

- [ ] Zone definition extraction
- [ ] Group template generation from placed units
- [ ] Coalition and side detection
- [ ] Coordinate system validation
- [ ] Conflict detection and warnings
- [ ] Configuration export/import

#### Dependencies

- Uses MizParser from miz-modifier library
- Builds on v0.1 & v0.2 foundation systems

---

## v0.5 - Basic MIZ File Modifications (PLANNED)

**Status**: Planned
**Phase**: Mission Output

### v0.5 Overview

Applies modifications to .miz mission files based on extracted data (v0.4) and v0.2 mission configurations. Mission creators can modify existing missions with updated spawning, events, and behaviors. Bridges from reading missions (v0.4) to writing/modifying them.

---

### v0.5.0 - Basic MIZ Modifications (PLANNED)

**Status**: Planned

#### What v0.5.0 Does

Applies DMS-generated content to existing .miz files. Takes configured spawning, events, and behaviors and injects them into mission files, allowing mission creators to modify missions with dynamic content without manual Lua editing.

#### Core Capabilities (Planned)

- ✏️ **Script Injection**: Inject generated Lua scripts into .miz files
- ✏️ **Trigger Modification**: Add new triggers and modify existing ones
- ✏️ **Zone Updates**: Add or modify spawn zones in mission
- ✏️ **Group Modification**: Update existing groups and add new ones
- ✏️ **Configuration Persistence**: Save DMS configuration with mission

#### Planned Features

- [ ] Lua script injection into .miz files
- [ ] Trigger creation and modification
- [ ] Zone definition updates
- [ ] Group creation from templates
- [ ] Mission configuration serialization
- [ ] Backup and rollback functionality

#### Dependencies

- Uses v0.4 (MIZ Reading) - Extract original mission structure
- Uses v0.2.11 (Lua Generation) - Generate injection code
- Uses miz-modifier library (MizParser)

---

## v0.6 - AI-Powered Mission Design (FUTURE)

**Target**: Q3 2026
**Status**: Planned
**Phase**: Intelligence

### v0.6 Overview

Leverage Claude AI to design mission parameters based on player skill level, preferred aircraft, and playstyle preferences. Uses extracted mission data (v0.4), modification capabilities (v0.5), and audio capabilities (v0.3) to create and customize personalized, adaptive missions.

### Planned Features

- [ ] Player profile analysis
- [ ] Adaptive difficulty scaling
- [ ] Personalized threat composition
- [ ] Loadout recommendations
- [ ] Dynamic mission tweaks based on performance
- [ ] AI-generated briefing audio
- [ ] Mission recommendation system

---

## Feature Dependency Graph

```
v0.1 (Random Spawning)
  └─ v0.1.0 (Random Spawn Scripts)
    ↓
v0.2 (Dynamic Spawning & Events - Comprehensive)
  ├─ v0.2.0 (Dynamic Spawn Generation)
  ├─ v0.2.1 (Event Handling) ← Extends v0.2.0
  ├─ v0.2.2 (AI Behavior) ← Extends v0.2.1
  ├─ v0.2.3 (Settings & Utilities) ← Supports all v0.2.x
  ├─ v0.2.4 (Flag Events & Comms) ← Extends v0.2.1
  ├─ v0.2.5 (FOW & QOL) ← Extends v0.2.1, v0.2.3
  ├─ v0.2.6 (Bug Fixes Round 1)
  ├─ v0.2.7 (Waypoints & Movement) ← Extends v0.2.0
  ├─ v0.2.8 (Scoring & Objectives) ← Extends v0.2.1
  ├─ v0.2.9 (Triggers & Scripting) ← Extends all v0.2.x
  ├─ v0.2.10 (Randomization) ← Extends v0.2.0, v0.2.7
  ├─ v0.2.11 (Lua Generation) ← Integrates all v0.2.x
  ├─ v0.2.12 (Bug Fixes Round 2)
  └─ v0.2.13 (Polish & QOL) ← Final v0.2 release
    ↓
v0.3 (Audio Integration) ← Uses v0.2 events & comms
    └─ v0.3.0 (ElevenLabs Audio)
    ↓
v0.4 (MIZ File Reading) ← Uses MizParser
    └─ v0.4.0 (Zone & Group Extraction)
    ↓
v0.5 (Basic MIZ Modifications) ← Uses v0.4 + v0.2.11
    └─ v0.5.0 (Lua Injection & Miz Writes)
    ↓
v0.6 (AI Mission Design) ← Uses v0.3, v0.4, v0.5
```

---

## Current Development Focus

**Active Work**: v0.2.0 complete, v0.2.1 in progress
**Next Priority**: Complete v0.2.1 event handling
**Blocking Issues**: None

