/*
	DMS_fnc_config - "Village Sweep" tunables as plain data (a generator can rewrite this file later).
	Returns a HashMap. Positions are Malden 2035 world [x, y] in metres.
	Village centres are the map's own location positions, read from CfgWorlds >> Malden >> Names in
	Argo\Addons\map_malden.pbo (see CLASSES.md). How many enterable houses each one has is NOT verified:
	the scripts count them at runtime, log the result and skip a village outside villageHouses.
	Class names were found in the mod PBOs (CLASSES.md) and are checked again with isClass at start.
*/

createHashMapFromArray [
	// ---------------------------------------------------------------- required mods: [label, CfgPatches class]
	// RHS GREF needs RHS AFRF (rhsgref_main requires rhs_main_loadorder), so AFRF is required too.
	["requiredMods", [
		["CBA_A3", "cba_main"],
		["ACE3", "ace_main"],
		["LAMBS Danger", "lambs_danger"],
		["LAMBS Waypoints", "lambs_wp"],
		["RHS AFRF", "rhs_main"],
		["RHS USAF", "rhsusf_main"],
		["RHS GREF", "rhsgref_main"]
	]],

	// ---------------------------------------------------------------- villages
	// [label, mapLocationXY]: the nearest NameVillage/NameCity location within villageSnap of mapLocationXY is used.
	["villages", [
		["Arudy", [5537, 6983]],
		["Houdan", [7121, 6075]],
		["Goisse", [3585, 8520]]
	]],
	["villageSnap", 300],
	["villageRadius", 130],
	["villageHouses", [5, 45]],
	["houseMinPositions", 2],
	["approachBearings", [0, 45, 90, 135, 180, 225, 270, 315]],
	["startDistance", 700],
	["ifvOffset", 30],
	["aoMarkerRadius", 200],
	["aoMarkerFuzz", [20, 60]],

	// ---------------------------------------------------------------- player squad (US Army, RHS USAF, OCP)
	// The mission.sqm slot is a vanilla class so the mission still loads without RHS (and then says why it
	// stops); the player gets the RHS squad leader's loadout at start.
	["playerSlotClass", "B_Soldier_SL_F"],
	["squadLeaderClass", "rhsusf_army_ocp_squadleader"],
	["squadClasses", [
		"rhsusf_army_ocp_teamleader", "rhsusf_army_ocp_autorifleman", "rhsusf_army_ocp_grenadier", "rhsusf_army_ocp_riflemanat",
		"rhsusf_army_ocp_teamleader", "rhsusf_army_ocp_autorifleman", "rhsusf_army_ocp_grenadier", "rhsusf_army_ocp_medic"
	]],
	["squadSkill", 0.6],

	// ---------------------------------------------------------------- Bradley (AI crew, comm-menu orders)
	["ifvClass", "RHS_M2A3"],
	["ifvSkill", 0.6],
	["ifvStandoff", 25],
	["ifvMoveTimeout", 240],
	["ifvSuppressSeconds", 20],
	["ifvSuppressMaxRange", 1500],
	["ifvDangerClose", 50],
	["ifvSuppressCooldown", 30],

	// ---------------------------------------------------------------- insurgents (RHS GREF ChDKZ)
	// Each garrison group holds the buildings within garrisonRange of a seeded house (lambs_wp_fnc_taskGarrison).
	["garrisonGroups", [
		["rhsgref_ins_squadleader", "rhsgref_ins_rifleman_akm", "rhsgref_ins_machinegunner", "rhsgref_ins_rifleman"],
		["rhsgref_ins_rifleman_aks74", "rhsgref_ins_arifleman_rpk", "rhsgref_ins_grenadier", "rhsgref_ins_rifleman_akm"]
	]],
	// The RPG team holds the house nearest the approach side of the village.
	["rpgTeam", ["rhsgref_ins_grenadier_rpg", "rhsgref_ins_rifleman_RPG26", "rhsgref_ins_rifleman"]],
	["rpgTeamOffset", 60],
	["garrisonRange", 35],
	["technicalClass", "rhsgref_ins_uaz_dshkm"],
	["technicalChance", 0.6],
	// grounded AI: decent spotting, poor raw accuracy, low courage (irregulars)
	["enemySkill", [
		["general", 0.45], ["aimingAccuracy", 0.15], ["aimingShake", 0.25], ["aimingSpeed", 0.3],
		["spotDistance", 0.6], ["spotTime", 0.5], ["courage", 0.4], ["reloadSpeed", 0.45], ["commanding", 0.4]
	]],
	// cleared: at most this fraction of the defenders alive within clearRadius, and a squad member inside holdRadius
	["clearFraction", 0.15],
	["clearRadius", 250],
	["holdRadius", 150],

	// ---------------------------------------------------------------- counterattack
	["counterDelay", [90, 180]],
	["counterDistance", [1300, 1700]],
	["counterTruckClasses", ["rhsgref_ins_ural", "rhsgref_ins_gaz66"]],
	["counterInfantry", [
		"rhsgref_ins_squadleader", "rhsgref_ins_rifleman_akm", "rhsgref_ins_machinegunner", "rhsgref_ins_grenadier_rpg",
		"rhsgref_ins_rifleman_aks74", "rhsgref_ins_rifleman", "rhsgref_ins_medic", "rhsgref_ins_rifleman_RPG26"
	]],
	["counterTechnicalChance", 0.5],
	["counterDismount", [300, 450]],
	["counterCqbRadius", 120],
	// beaten: at most this fraction of the counterattack infantry alive and any technical's gun silenced
	["counterBeatenFraction", 0.2],
	["holdConsolidate", 60],
	["holdStallTime", 1500],

	// ---------------------------------------------------------------- test mode
	["testIfvAfter", 120],
	["testStage", 250],
	["testClearTimeout", 1800],
	["testExpected", [
		"mods", "spawn_village", "spawn_defenders", "spawn_squad", "spawn_bradley", "ifv_move", "ifv_suppress", "ifv_hold",
		"village_cleared", "counterattack", "village_held", "outcome_win"
	]]
]
