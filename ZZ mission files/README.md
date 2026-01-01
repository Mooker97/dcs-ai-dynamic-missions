# Mission-Specific Scripts

This folder contains **mission-specific Lua scripts** that are tailored to individual missions.

---

## When to Use This Folder

Place scripts here when they are:

- Custom triggers for a specific mission
- Unique spawn logic that won't be reused
- Mission-specific event handlers
- One-off narrative scripts
- Initialization scripts that configure library modules for a specific mission

---

## When to Use `lua-dump/` Instead

Place scripts in `lua-dump/` when they are:

- Reusable across multiple missions
- Generic systems (spawners, comms, tracking)
- Utility functions
- Feature modules that can be configured for any mission

---

## Folder Organization

Organize by mission name:

```
ZZ mission files/
├── Operation-Thunder/
│   ├── init.lua           # Mission initialization
│   ├── custom-triggers.lua
│   └── narrative.lua
│
├── Training-Mission-01/
│   ├── init.lua
│   └── training-events.lua
│
└── Caucasus-Campaign-01/
    ├── init.lua
    ├── phase1-triggers.lua
    └── phase2-triggers.lua
```

---

## Typical Mission Init Script

```lua
-- Operation Thunder - init.lua
-- Load after all lua-dump library scripts

-- Configure systems for this mission
DMS.AWACS.configure({
    callsign = "Darkstar",
    checkInterval = 20
})

DMS.Reinforcements.waveOnEnemyCount(1, {"QRF-1", "QRF-2"}, 5)
DMS.Reinforcements.waveOnTime(2, {"Armor-Reinforcement"}, 1200)

DMS.Victory.addWinCondition("destroy_hq",
    DMS.Victory.Conditions.destroyAll({"Enemy-HQ"}),
    {description = "Destroy enemy headquarters", required = true}
)

-- Start all systems
DMS.AWACS.start()
DMS.Reinforcements.start()
DMS.Victory.start()
DMS.BDA.start()
```

---

## Why "ZZ"?

The `ZZ` prefix ensures this folder sorts to the **bottom** of the directory listing, keeping it separate from the library folders and making it easy to find mission-specific content.
