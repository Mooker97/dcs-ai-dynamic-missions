-- Unit Templates for Dynamic Spawning
-- Provides unit dictionary and group templates for coalition.addGroup()
-- Requires: utils/mission-settings.lua
-- Place in mission via DO SCRIPT FILE

DMS = DMS or {}
DMS.UnitTemplates = {}

-- ============================================================
-- UNIT DICTIONARY
-- Verified unit type strings with descriptions
-- ============================================================

DMS.UnitTemplates.Units = {
    -- ========================================
    -- AIR DEFENSE - RADAR GUIDED
    -- ========================================
    ["2S6 Tunguska"] = {
        type = "2S6 Tunguska",
        category = "AA",
        description = "Combined gun/missile SPAAG. 30mm cannons + SA-19 missiles. Deadly to helicopters within 8km.",
        threat = "HIGH",
        country = "RUSSIA",
    },
    ["Strela-10M3"] = {
        type = "Strela-10M3",
        category = "AA",
        description = "IR-guided SAM on MT-LB chassis. 5km range. Low altitude threat.",
        threat = "MEDIUM",
        country = "RUSSIA",
    },
    ["ZSU-23-4 Shilka"] = {
        type = "ZSU-23-4 Shilka",
        category = "AA",
        description = "Quad 23mm radar-guided AAA. 2.5km effective range. High rate of fire.",
        threat = "MEDIUM",
        country = "RUSSIA",
    },

    -- ========================================
    -- AIR DEFENSE - GUN SYSTEMS
    -- ========================================
    ["Ural-375 ZU-23"] = {
        type = "Ural-375 ZU-23",
        category = "AA",
        description = "ZU-23-2 twin 23mm on Ural truck. Mobile AA. 2.5km range.",
        threat = "MEDIUM",
        country = "RUSSIA",
    },
    ["tt_ZU-23"] = {
        type = "tt_ZU-23",
        category = "AA",
        description = "ZU-23-2 on technical pickup. Fast, light AA. Insurgent favorite.",
        threat = "MEDIUM",
        country = "INSURGENT",
    },
    ["ZU-23 Emplacement"] = {
        type = "ZU-23 Emplacement",
        category = "AA",
        description = "Static ZU-23-2 twin 23mm. Dug-in position. 2.5km range.",
        threat = "MEDIUM",
        country = "RUSSIA",
    },

    -- ========================================
    -- AIR DEFENSE - MANPADS
    -- ========================================
    ["SA-18 Igla-S manpad"] = {
        type = "SA-18 Igla-S manpad",
        category = "AA",
        description = "Igla-S MANPADS. IR-guided, 5km range. Hard to spot infantry.",
        threat = "HIGH",
        country = "RUSSIA",
    },
    ["Soldier stinger"] = {
        type = "Soldier stinger",
        category = "AA",
        description = "Stinger MANPADS. IR-guided, 4.5km range. US forces.",
        threat = "HIGH",
        country = "USA",
    },

    -- ========================================
    -- ARMOR - TANKS
    -- ========================================
    ["T-72B3"] = {
        type = "T-72B3",
        category = "ARMOR",
        description = "Modernized T-72. 125mm gun, ERA armor. Main Russian MBT.",
        threat = "HIGH",
        country = "RUSSIA",
    },
    ["CHAP_T90M"] = {
        type = "CHAP_T90M",
        category = "ARMOR",
        description = "T-90M advanced MBT. 125mm gun, modern FCS. Top-tier threat.",
        threat = "HIGH",
        country = "RUSSIA",
    },
    ["T62M"] = {
        type = "T62M",
        category = "ARMOR",
        description = "Upgraded T-62. 115mm gun. Older but still dangerous.",
        threat = "MEDIUM",
        country = "RUSSIA",
    },
    ["T-55"] = {
        type = "T-55",
        category = "ARMOR",
        description = "Cold War era MBT. 100mm gun. Common in insurgent forces.",
        threat = "LOW",
        country = "INSURGENT",
    },
    ["M-1 Abrams"] = {
        type = "M-1 Abrams",
        category = "ARMOR",
        description = "US main battle tank. 120mm gun. Heavy armor.",
        threat = "HIGH",
        country = "USA",
    },

    -- ========================================
    -- ARMOR - IFV/APC
    -- ========================================
    ["BMP-1"] = {
        type = "BMP-1",
        category = "ARMOR",
        description = "Soviet IFV. 73mm gun + AT-3 missile. Carries infantry.",
        threat = "MEDIUM",
        country = "RUSSIA",
    },
    ["BMP-2"] = {
        type = "BMP-2",
        category = "ARMOR",
        description = "Improved IFV. 30mm autocannon + AT-5 missile. Common.",
        threat = "MEDIUM",
        country = "RUSSIA",
    },
    ["BMP-3"] = {
        type = "BMP-3",
        category = "ARMOR",
        description = "Modern IFV. 100mm gun + 30mm + AT-10 missile. Dangerous.",
        threat = "HIGH",
        country = "RUSSIA",
    },
    ["BTR-60"] = {
        type = "BTR-60",
        category = "ARMOR",
        description = "8-wheeled APC. 14.5mm KPVT. Troop transport.",
        threat = "LOW",
        country = "RUSSIA",
    },
    ["BTR-80"] = {
        type = "BTR-80",
        category = "ARMOR",
        description = "Improved 8-wheeled APC. 14.5mm KPVT. Fast on roads.",
        threat = "LOW",
        country = "RUSSIA",
    },
    ["BRDM-2"] = {
        type = "BRDM-2",
        category = "ARMOR",
        description = "Amphibious scout car. 14.5mm KPVT. Recon vehicle.",
        threat = "LOW",
        country = "RUSSIA",
    },
    ["CHAP_BMPT"] = {
        type = "CHAP_BMPT",
        category = "ARMOR",
        description = "BMPT Terminator. Twin 30mm + AT missiles. Tank support.",
        threat = "HIGH",
        country = "RUSSIA",
    },
    ["M-2 Bradley"] = {
        type = "M-2 Bradley",
        category = "ARMOR",
        description = "US IFV. 25mm chain gun + TOW missiles. Dangerous.",
        threat = "MEDIUM",
        country = "USA",
    },
    ["M1126 Stryker ICV"] = {
        type = "M1126 Stryker ICV",
        category = "ARMOR",
        description = "US 8-wheeled APC. 12.7mm or 40mm. Troop carrier.",
        threat = "LOW",
        country = "USA",
    },
    ["M1128 Stryker MGS"] = {
        type = "M1128 Stryker MGS",
        category = "ARMOR",
        description = "Stryker with 105mm gun. Mobile fire support.",
        threat = "MEDIUM",
        country = "USA",
    },
    ["MaxxPro_MRAP"] = {
        type = "MaxxPro_MRAP",
        category = "ARMOR",
        description = "MRAP armored vehicle. Mine resistant. Light weapons.",
        threat = "LOW",
        country = "USA",
    },

    -- ========================================
    -- TECHNICALS & ARMED VEHICLES
    -- ========================================
    ["tt_KORD"] = {
        type = "tt_KORD",
        category = "TECHNICAL",
        description = "Technical with KORD 12.7mm HMG. Fast, light firepower.",
        threat = "LOW",
        country = "INSURGENT",
    },
    ["HL_KORD"] = {
        type = "HL_KORD",
        category = "EMPLACEMENT",
        description = "KORD 12.7mm on tripod. Static MG position.",
        threat = "LOW",
        country = "RUSSIA",
    },
    ["M1043 HMMWV Armament"] = {
        type = "M1043 HMMWV Armament",
        category = "TECHNICAL",
        description = "Armed Humvee with M2 .50 cal or Mk19. Light patrol.",
        threat = "LOW",
        country = "USA",
    },

    -- ========================================
    -- INFANTRY
    -- ========================================
    ["Soldier AK"] = {
        type = "Soldier AK",
        category = "INFANTRY",
        description = "Infantry with AK-74. Basic rifleman.",
        threat = "LOW",
        country = "RUSSIA",
    },
    ["Infantry AK"] = {
        type = "Infantry AK",
        category = "INFANTRY",
        description = "Infantry with AK variant. Insurgent fighter.",
        threat = "LOW",
        country = "INSURGENT",
    },
    ["Soldier RPG"] = {
        type = "Soldier RPG",
        category = "INFANTRY",
        description = "Infantry with RPG-7. Anti-armor/helicopter threat.",
        threat = "MEDIUM",
        country = "RUSSIA",
    },
    ["Paratrooper RPG-16"] = {
        type = "Paratrooper RPG-16",
        category = "INFANTRY",
        description = "Paratrooper with RPG-16. Elite AT infantry.",
        threat = "MEDIUM",
        country = "RUSSIA",
    },
    ["Soldier M4"] = {
        type = "Soldier M4",
        category = "INFANTRY",
        description = "US Infantry with M4 carbine. Basic rifleman.",
        threat = "LOW",
        country = "USA",
    },
    ["Soldier M249"] = {
        type = "Soldier M249",
        category = "INFANTRY",
        description = "US Infantry with M249 SAW. Squad automatic weapon.",
        threat = "LOW",
        country = "USA",
    },
    ["JTAC"] = {
        type = "JTAC",
        category = "INFANTRY",
        description = "Joint Terminal Attack Controller. Laser designator.",
        threat = "LOW",
        country = "USA",
    },

    -- ========================================
    -- TRANSPORT & LOGISTICS
    -- ========================================
    ["Ural-375"] = {
        type = "Ural-375",
        category = "TRANSPORT",
        description = "Soviet 6x6 cargo truck. Common logistics vehicle.",
        threat = "NONE",
        country = "RUSSIA",
    },
    ["KAMAZ Truck"] = {
        type = "KAMAZ Truck",
        category = "TRANSPORT",
        description = "Modern Russian cargo truck. Logistics.",
        threat = "NONE",
        country = "RUSSIA",
    },
    ["GAZ-3308"] = {
        type = "GAZ-3308",
        category = "TRANSPORT",
        description = "Light Russian cargo truck. Transport.",
        threat = "NONE",
        country = "RUSSIA",
    },
    ["ZIL-135"] = {
        type = "ZIL-135",
        category = "TRANSPORT",
        description = "Heavy 8x8 truck. TEL vehicle base.",
        threat = "NONE",
        country = "RUSSIA",
    },
    ["ATMZ-5"] = {
        type = "ATMZ-5",
        category = "TRANSPORT",
        description = "Fuel tanker truck. Logistics target.",
        threat = "NONE",
        country = "RUSSIA",
    },
    ["Hummer"] = {
        type = "Hummer",
        category = "TRANSPORT",
        description = "Unarmed HMMWV. Light transport.",
        threat = "NONE",
        country = "USA",
    },
    ["M978 HEMTT Tanker"] = {
        type = "M978 HEMTT Tanker",
        category = "TRANSPORT",
        description = "US fuel tanker. Heavy logistics.",
        threat = "NONE",
        country = "USA",
    },
    ["M 818"] = {
        type = "M 818",
        category = "TRANSPORT",
        description = "US 5-ton cargo truck. Standard logistics.",
        threat = "NONE",
        country = "USA",
    },

    -- ========================================
    -- ARTILLERY
    -- ========================================
    ["2B11 mortar"] = {
        type = "2B11 mortar",
        category = "ARTILLERY",
        description = "120mm heavy mortar. Indirect fire support.",
        threat = "MEDIUM",
        country = "RUSSIA",
    },
    ["MLRS"] = {
        type = "MLRS",
        category = "ARTILLERY",
        description = "M270 MLRS. 227mm rockets. Area saturation.",
        threat = "HIGH",
        country = "USA",
    },
    ["CHAP_M142_ATACMS_M48"] = {
        type = "CHAP_M142_ATACMS_M48",
        category = "ARTILLERY",
        description = "HIMARS with ATACMS. Precision strike. HVT.",
        threat = "HIGH",
        country = "USA",
    },
    ["L118_Unit"] = {
        type = "L118_Unit",
        category = "ARTILLERY",
        description = "L118 Light Gun. 105mm towed howitzer.",
        threat = "MEDIUM",
        country = "USA",
    },
}

-- ============================================================
-- GROUP TEMPLATES
-- Pre-defined unit compositions for spawning
-- ============================================================

DMS.UnitTemplates.Groups = {
    -- ========================================
    -- AA GROUPS - RADAR
    -- ========================================
    ["tunguska"] = {
        name = "tunguska",
        displayName = "2S6 Tunguska",
        description = "Single Tunguska SPAAG. High threat to helicopters.",
        category = "AA",
        country = country.id.RUSSIA,
        task = "Ground Nothing",
        units = {
            {type = "2S6 Tunguska", skill = "Random"},
        },
    },
    ["tunguska_pair"] = {
        name = "tunguska_pair",
        displayName = "Tunguska Pair",
        description = "Two Tunguskas providing overlapping coverage.",
        category = "AA",
        country = country.id.RUSSIA,
        task = "Ground Nothing",
        units = {
            {type = "2S6 Tunguska", skill = "Random"},
            {type = "2S6 Tunguska", skill = "Random"},
        },
    },
    ["shilka"] = {
        name = "shilka",
        displayName = "ZSU-23-4 Shilka",
        description = "Single Shilka AAA. Radar-guided quad 23mm.",
        category = "AA",
        country = country.id.RUSSIA,
        task = "Ground Nothing",
        units = {
            {type = "ZSU-23-4 Shilka", skill = "Random"},
        },
    },
    ["strela_section"] = {
        name = "strela_section",
        displayName = "Strela-10 Section",
        description = "Two Strela-10 SAMs. IR-guided low altitude threat.",
        category = "AA",
        country = country.id.RUSSIA,
        task = "Ground Nothing",
        units = {
            {type = "Strela-10M3", skill = "Random"},
            {type = "Strela-10M3", skill = "Random"},
        },
    },

    -- ========================================
    -- AA GROUPS - GUN SYSTEMS
    -- ========================================
    ["zu23_truck"] = {
        name = "zu23_truck",
        displayName = "ZU-23 on Ural",
        description = "Ural truck with ZU-23-2. Mobile AA.",
        category = "AA",
        country = country.id.RUSSIA,
        task = "Ground Nothing",
        units = {
            {type = "Ural-375 ZU-23", skill = "Random"},
        },
    },
    ["zu23_technical"] = {
        name = "zu23_technical",
        displayName = "ZU-23 Technical",
        description = "Pickup with ZU-23-2. Fast insurgent AA.",
        category = "AA",
        country = country.id.INSURGENTS,
        task = "Ground Nothing",
        units = {
            {type = "tt_ZU-23", skill = "Random"},
        },
    },
    ["zu23_battery"] = {
        name = "zu23_battery",
        displayName = "ZU-23 Battery",
        description = "Two ZU-23 trucks. Overlapping AA coverage.",
        category = "AA",
        country = country.id.RUSSIA,
        task = "Ground Nothing",
        units = {
            {type = "Ural-375 ZU-23", skill = "Random"},
            {type = "Ural-375 ZU-23", skill = "Random"},
        },
    },

    -- ========================================
    -- AA GROUPS - MANPADS
    -- ========================================
    ["manpads_team"] = {
        name = "manpads_team",
        displayName = "MANPADS Team",
        description = "Two Igla gunners. Hard to spot, deadly.",
        category = "AA",
        country = country.id.RUSSIA,
        task = "Ground Nothing",
        units = {
            {type = "SA-18 Igla-S manpad", skill = "Random"},
            {type = "SA-18 Igla-S manpad", skill = "Random"},
        },
    },
    ["manpads_single"] = {
        name = "manpads_single",
        displayName = "MANPADS Gunner",
        description = "Single Igla gunner. Concealed threat.",
        category = "AA",
        country = country.id.RUSSIA,
        task = "Ground Nothing",
        units = {
            {type = "SA-18 Igla-S manpad", skill = "Random"},
        },
    },

    -- ========================================
    -- ARMOR GROUPS
    -- ========================================
    ["t72_platoon"] = {
        name = "t72_platoon",
        displayName = "T-72 Platoon",
        description = "Two T-72B3 tanks. Heavy armor threat.",
        category = "ARMOR",
        country = country.id.RUSSIA,
        task = "Ground Nothing",
        units = {
            {type = "T-72B3", skill = "Random"},
            {type = "T-72B3", skill = "Random"},
        },
    },
    ["t72_single"] = {
        name = "t72_single",
        displayName = "T-72 Tank",
        description = "Single T-72B3. Main battle tank.",
        category = "ARMOR",
        country = country.id.RUSSIA,
        task = "Ground Nothing",
        units = {
            {type = "T-72B3", skill = "Random"},
        },
    },
    ["bmp_section"] = {
        name = "bmp_section",
        displayName = "BMP Section",
        description = "Two BMP-2 IFVs. Infantry support.",
        category = "ARMOR",
        country = country.id.RUSSIA,
        task = "Ground Nothing",
        units = {
            {type = "BMP-2", skill = "Random"},
            {type = "BMP-2", skill = "Random"},
        },
    },
    ["btr_squad"] = {
        name = "btr_squad",
        displayName = "BTR Squad",
        description = "Three BTR-80 APCs. Troop transport.",
        category = "ARMOR",
        country = country.id.RUSSIA,
        task = "Ground Nothing",
        units = {
            {type = "BTR-80", skill = "Random"},
            {type = "BTR-80", skill = "Random"},
            {type = "BTR-80", skill = "Random"},
        },
    },
    ["recon_patrol"] = {
        name = "recon_patrol",
        displayName = "Recon Patrol",
        description = "BRDM-2 scout car. Light recon.",
        category = "ARMOR",
        country = country.id.RUSSIA,
        task = "Ground Nothing",
        units = {
            {type = "BRDM-2", skill = "Random"},
        },
    },

    -- ========================================
    -- TECHNICAL/INSURGENT GROUPS
    -- ========================================
    ["technical_mg"] = {
        name = "technical_mg",
        displayName = "Technical (MG)",
        description = "Pickup with KORD HMG. Fast harassment.",
        category = "TECHNICAL",
        country = country.id.INSURGENTS,
        task = "Ground Nothing",
        units = {
            {type = "tt_KORD", skill = "Random"},
        },
    },
    ["technical_pair"] = {
        name = "technical_pair",
        displayName = "Technical Pair",
        description = "Two armed technicals. Mobile firepower.",
        category = "TECHNICAL",
        country = country.id.INSURGENTS,
        task = "Ground Nothing",
        units = {
            {type = "tt_KORD", skill = "Random"},
            {type = "tt_KORD", skill = "Random"},
        },
    },
    ["technical_aa_mg"] = {
        name = "technical_aa_mg",
        displayName = "Mixed Technicals",
        description = "One ZU-23 and one MG technical.",
        category = "TECHNICAL",
        country = country.id.INSURGENTS,
        task = "Ground Nothing",
        units = {
            {type = "tt_ZU-23", skill = "Random"},
            {type = "tt_KORD", skill = "Random"},
        },
    },

    -- ========================================
    -- INFANTRY GROUPS
    -- ========================================
    ["infantry_squad"] = {
        name = "infantry_squad",
        displayName = "Infantry Squad",
        description = "Four riflemen with one RPG. Basic squad.",
        category = "INFANTRY",
        country = country.id.RUSSIA,
        task = "Ground Nothing",
        units = {
            {type = "Soldier AK", skill = "Random"},
            {type = "Soldier AK", skill = "Random"},
            {type = "Soldier AK", skill = "Random"},
            {type = "Soldier RPG", skill = "Random"},
        },
    },
    ["infantry_fireteam"] = {
        name = "infantry_fireteam",
        displayName = "Infantry Fireteam",
        description = "Three riflemen. Light infantry.",
        category = "INFANTRY",
        country = country.id.RUSSIA,
        task = "Ground Nothing",
        units = {
            {type = "Soldier AK", skill = "Random"},
            {type = "Soldier AK", skill = "Random"},
            {type = "Soldier AK", skill = "Random"},
        },
    },
    ["rpg_team"] = {
        name = "rpg_team",
        displayName = "RPG Team",
        description = "Two RPG gunners. Anti-armor ambush.",
        category = "INFANTRY",
        country = country.id.RUSSIA,
        task = "Ground Nothing",
        units = {
            {type = "Soldier RPG", skill = "Random"},
            {type = "Soldier RPG", skill = "Random"},
        },
    },
    ["mg_nest"] = {
        name = "mg_nest",
        displayName = "MG Nest",
        description = "KORD HMG with security. Static position.",
        category = "INFANTRY",
        country = country.id.RUSSIA,
        task = "Ground Nothing",
        units = {
            {type = "HL_KORD", skill = "Random"},
            {type = "Soldier AK", skill = "Random"},
        },
    },

    -- ========================================
    -- MIXED/COMBINED ARMS
    -- ========================================
    ["checkpoint"] = {
        name = "checkpoint",
        displayName = "Checkpoint",
        description = "BTR with infantry. Road checkpoint.",
        category = "MIXED",
        country = country.id.RUSSIA,
        task = "Ground Nothing",
        units = {
            {type = "BTR-80", skill = "Random"},
            {type = "Soldier AK", skill = "Random"},
            {type = "Soldier AK", skill = "Random"},
            {type = "Soldier RPG", skill = "Random"},
        },
    },
    ["ambush_team"] = {
        name = "ambush_team",
        displayName = "Ambush Team",
        description = "RPG team with MANPADS. Anti-helo ambush.",
        category = "MIXED",
        country = country.id.RUSSIA,
        task = "Ground Nothing",
        units = {
            {type = "Soldier RPG", skill = "Random"},
            {type = "Soldier RPG", skill = "Random"},
            {type = "SA-18 Igla-S manpad", skill = "Random"},
        },
    },
    ["aa_ambush"] = {
        name = "aa_ambush",
        displayName = "AA Ambush",
        description = "ZU-23 with MANPADS backup. Layered AA.",
        category = "AA",
        country = country.id.RUSSIA,
        task = "Ground Nothing",
        units = {
            {type = "Ural-375 ZU-23", skill = "Random"},
            {type = "SA-18 Igla-S manpad", skill = "Random"},
            {type = "SA-18 Igla-S manpad", skill = "Random"},
        },
    },
    ["convoy_escort"] = {
        name = "convoy_escort",
        displayName = "Convoy Escort",
        description = "BTR with trucks. Supply convoy.",
        category = "MIXED",
        country = country.id.RUSSIA,
        task = "Ground Nothing",
        units = {
            {type = "BTR-80", skill = "Random"},
            {type = "KAMAZ Truck", skill = "Random"},
            {type = "KAMAZ Truck", skill = "Random"},
            {type = "BTR-80", skill = "Random"},
        },
    },

    -- ========================================
    -- QRF / REINFORCEMENT GROUPS
    -- ========================================
    ["qrf_light"] = {
        name = "qrf_light",
        displayName = "Light QRF",
        description = "Two technicals. Fast response.",
        category = "QRF",
        country = country.id.INSURGENTS,
        task = "Ground Nothing",
        units = {
            {type = "tt_KORD", skill = "Random"},
            {type = "tt_KORD", skill = "Random"},
        },
    },
    ["qrf_medium"] = {
        name = "qrf_medium",
        displayName = "Medium QRF",
        description = "BMP with BTR. Mechanized response.",
        category = "QRF",
        country = country.id.RUSSIA,
        task = "Ground Nothing",
        units = {
            {type = "BMP-2", skill = "Random"},
            {type = "BTR-80", skill = "Random"},
        },
    },
    ["qrf_heavy"] = {
        name = "qrf_heavy",
        displayName = "Heavy QRF",
        description = "T-72 with BMP. Heavy response.",
        category = "QRF",
        country = country.id.RUSSIA,
        task = "Ground Nothing",
        units = {
            {type = "T-72B3", skill = "Random"},
            {type = "BMP-2", skill = "Random"},
        },
    },
}

-- ============================================================
-- CUSTOM GROUP BUILDER
-- ============================================================

--- Create a custom group definition from an array of unit types
-- @param name string Unique group name
-- @param units table Array of unit definitions: {type, skill?, offset?}
-- @param options table Optional: {displayName, description, category, country, task}
-- @return table Group definition ready for spawning
-- @example
--   local myGroup = DMS.UnitTemplates.createGroup("my_ambush", {
--       {type = "2S6 Tunguska"},
--       {type = "SA-18 Igla-S manpad"},
--       {type = "SA-18 Igla-S manpad"},
--   }, {
--       displayName = "Custom AA Ambush",
--       description = "Tunguska with MANPADS support",
--   })
function DMS.UnitTemplates.createGroup(name, units, options)
    options = options or {}

    -- Build units array with defaults
    local processedUnits = {}
    for i, unit in ipairs(units) do
        local unitDef = {
            type = unit.type,
            skill = unit.skill or "Random",
        }
        -- Allow custom offset for formation control
        if unit.offset then
            unitDef.offset = unit.offset
        end
        table.insert(processedUnits, unitDef)
    end

    -- Determine country from first unit if not specified
    local defaultCountry = country.id.RUSSIA
    if options.country then
        defaultCountry = options.country
    else
        local firstUnitDef = DMS.UnitTemplates.Units[units[1].type]
        if firstUnitDef then
            if firstUnitDef.country == "USA" then
                defaultCountry = country.id.USA
            elseif firstUnitDef.country == "INSURGENT" then
                defaultCountry = country.id.INSURGENTS
            end
        end
    end

    -- Build group definition
    local groupDef = {
        name = name,
        displayName = options.displayName or name,
        description = options.description or "Custom group",
        category = options.category or "CUSTOM",
        country = defaultCountry,
        task = options.task or "Ground Nothing",
        units = processedUnits,
        isCustom = true,
    }

    return groupDef
end

--- Register a custom group as a reusable template
-- @param name string Template name (will be used to reference it)
-- @param units table Array of unit definitions
-- @param options table Optional group options
-- @return table The registered template
-- @example
--   DMS.UnitTemplates.register("heavy_aa_site", {
--       {type = "2S6 Tunguska"},
--       {type = "2S6 Tunguska"},
--       {type = "Strela-10M3"},
--       {type = "SA-18 Igla-S manpad"},
--   }, {
--       displayName = "Heavy AA Site",
--       description = "Layered air defense with radar and IR systems",
--       category = "AA",
--   })
function DMS.UnitTemplates.register(name, units, options)
    local template = DMS.UnitTemplates.createGroup(name, units, options)
    DMS.UnitTemplates.Groups[name] = template

    if DMS.Settings and DMS.Settings.isDebug() then
        env.info(string.format("[Templates] Registered custom template: %s (%d units)", name, #units))
    end

    return template
end

--- Quick spawn a custom group without registering it
-- Uses DynamicSpawn directly if available
-- @param name string Group name for spawned group
-- @param units table Array of unit definitions
-- @param position table {x, y} spawn position
-- @param options table Optional: heading, country, formation
-- @return string|nil Group name if spawned successfully
-- @example
--   DMS.UnitTemplates.spawnCustom("ambush_1", {
--       {type = "Soldier RPG"},
--       {type = "Soldier RPG"},
--       {type = "SA-18 Igla-S manpad"},
--   }, {x = 123456, y = 654321}, {heading = 180})
function DMS.UnitTemplates.spawnCustom(name, units, position, options)
    options = options or {}

    -- Create the group definition
    local groupDef = DMS.UnitTemplates.createGroup(name, units, {
        country = options.country,
    })

    -- Check if DynamicSpawn is available
    if DMS.DynamicSpawn and DMS.DynamicSpawn.spawnGroupDirect then
        return DMS.DynamicSpawn.spawnGroupDirect(groupDef, position, options)
    end

    -- Fallback: use coalition.addGroup directly
    local heading = options.heading or 0
    local headingRad = math.rad(heading)

    -- Build unit data
    local unitData = {}
    for i, unit in ipairs(groupDef.units) do
        local offsetX = (i - 1) * 20  -- 20m spacing in line
        table.insert(unitData, {
            type = unit.type,
            name = string.format("%s-%d", name, i),
            x = position.x + offsetX * math.cos(headingRad),
            y = position.y + offsetX * math.sin(headingRad),
            heading = headingRad,
            skill = unit.skill,
        })
    end

    -- Build group data
    local groupData = {
        name = name,
        task = groupDef.task,
        units = unitData,
    }

    -- Spawn via coalition.addGroup
    local group = coalition.addGroup(groupDef.country, Group.Category.GROUND, groupData)

    if group then
        if DMS.Settings and DMS.Settings.isDebug() then
            env.info(string.format("[Templates] Spawned custom group: %s (%d units)", name, #units))
        end
        return name
    end

    return nil
end

--- Create a group from a mix of existing templates
-- @param name string New group name
-- @param templateNames table Array of template names to combine
-- @param options table Optional group options
-- @return table Combined group definition
-- @example
--   local combined = DMS.UnitTemplates.combineTemplates("mega_defense", {
--       "tunguska_pair",
--       "manpads_team",
--       "infantry_squad",
--   })
function DMS.UnitTemplates.combineTemplates(name, templateNames, options)
    options = options or {}
    local allUnits = {}

    for _, templateName in ipairs(templateNames) do
        local template = DMS.UnitTemplates.Groups[templateName]
        if template then
            for _, unit in ipairs(template.units) do
                table.insert(allUnits, {
                    type = unit.type,
                    skill = unit.skill,
                })
            end
        else
            env.warning(string.format("[Templates] Template not found for combine: %s", templateName))
        end
    end

    return DMS.UnitTemplates.createGroup(name, allUnits, options)
end

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

--- Get a unit definition by type string
-- @param unitType string The DCS unit type string
-- @return table|nil Unit definition or nil
function DMS.UnitTemplates.getUnit(unitType)
    return DMS.UnitTemplates.Units[unitType]
end

--- Get a group template by name
-- @param templateName string The template name
-- @return table|nil Template definition or nil
function DMS.UnitTemplates.getTemplate(templateName)
    return DMS.UnitTemplates.Groups[templateName]
end

--- List all templates by category
-- @param category string|nil Category filter (AA, ARMOR, INFANTRY, etc.)
-- @return table Array of template names
function DMS.UnitTemplates.listTemplates(category)
    local result = {}
    for name, template in pairs(DMS.UnitTemplates.Groups) do
        if not category or template.category == category then
            table.insert(result, name)
        end
    end
    table.sort(result)
    return result
end

--- List all unit types by category
-- @param category string|nil Category filter
-- @return table Array of unit type strings
function DMS.UnitTemplates.listUnits(category)
    local result = {}
    for unitType, def in pairs(DMS.UnitTemplates.Units) do
        if not category or def.category == category then
            table.insert(result, unitType)
        end
    end
    table.sort(result)
    return result
end

--- Print template info (for debugging)
-- @param templateName string Template to describe
function DMS.UnitTemplates.describe(templateName)
    local template = DMS.UnitTemplates.Groups[templateName]
    if not template then
        env.info(string.format("[Templates] Template not found: %s", templateName))
        return
    end

    env.info(string.format("[Templates] %s - %s", template.displayName, template.description))
    env.info(string.format("[Templates]   Category: %s, Units: %d", template.category, #template.units))
    for i, unit in ipairs(template.units) do
        local unitDef = DMS.UnitTemplates.Units[unit.type]
        local threat = unitDef and unitDef.threat or "UNKNOWN"
        env.info(string.format("[Templates]   [%d] %s (%s) - %s", i, unit.type, unit.skill, threat))
    end
end

-- ============================================================
-- INITIALIZATION
-- ============================================================

if DMS.Settings and DMS.Settings.isDebug() then
    local templateCount = 0
    local unitCount = 0
    for _ in pairs(DMS.UnitTemplates.Groups) do templateCount = templateCount + 1 end
    for _ in pairs(DMS.UnitTemplates.Units) do unitCount = unitCount + 1 end
    env.info(string.format("[Templates] Loaded %d unit types, %d group templates", unitCount, templateCount))
end

-- Export
_G.DMS = DMS
