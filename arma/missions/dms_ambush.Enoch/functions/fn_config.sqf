/*
	DMS_fnc_config
	ALL mission tunables live here as plain data so a generator can rewrite this file later.
	Returns a HashMap. Positions are Livonia (Enoch, 12.8 km square) world [x, y] in metres.
	Site centres were picked offline from the terrain's own road shapefile (map_enoch_data.pbo
	roads\roads.shp, UTM false easting 200000 removed) and town positions (map_enoch.pbo CfgWorlds
	Names): rural stretches of "road"/"main road" more than 2 km from any village with at least 1.8 km
	of connected road in both directions. They are still TO VERIFY in-engine: the scripts snap to the
	nearest real road segment (fn_route) and log what they found.
*/

createHashMapFromArray [
	// ---------------------------------------------------------------- sites (kill zones), TO VERIFY in-engine
	// [name, killZoneXY]. Everything else (road trace, convoy entry/exit, kill line, ambush position,
	// squad start, rally point) is derived from the road network at run time.
	["sites", [
		["Forest road between Gieraltow and Dolnik", [9765, 2666]],
		["Main road between Polana and Huta", [3339, 4449]],
		["Main road south of Karlin", [12062, 6532]]
	]],
	["roadTypes", ["ROAD", "MAIN ROAD"]],
	["roadSnapRadius", 300],
	["entryDistance", 2000], // road metres from the kill zone to the lead vehicle's spawn point
	["exitDistance", 1500], // road metres the trace continues past the kill zone (last waypoint)
	["killLineDistance", 500], // road metres past the kill zone; a vehicle beyond this has escaped
	["waypointSpacing", 250],
	["ambushDistance", [170, 240]], // ambush position, metres from the road (perpendicular, terrain picks the side)
	["startDistance", 800], // squad start, metres from the ambush position (away from the road)
	["rpDistance", 1000], // rally point, metres from the ambush position (away from the road)
	["rpMinRouteDistance", 700], // the rally point stays at least this far from the convoy's road
	["rpRadius", 60],
	["mapMargin", 200],
	["killZoneMarkerRadius", 120],

	// ---------------------------------------------------------------- player squad (RHS USMC, woodland MARPAT)
	// The mission.sqm slot is a vanilla B_Soldier_TL_F, so the mission loads without RHS and the mod check can
	// end it cleanly. At start the player gets the squadLeaderClass loadout.
	["playerSlotClass", "B_Soldier_TL_F"],
	["squadLeaderClass", "rhsusf_usmc_marpat_wd_teamleader"],
	["squadClasses", [
		"rhsusf_usmc_marpat_wd_autorifleman_m249", "rhsusf_usmc_marpat_wd_grenadier", "rhsusf_usmc_marpat_wd_riflemanat",
		"rhsusf_usmc_marpat_wd_javelin", "rhsusf_usmc_marpat_wd_rifleman", "rhsusf_navy_marpat_wd_medic"
	]],
	["squadSkill", 0.6],

	// ---------------------------------------------------------------- convoy (RHS AFRF motor rifles, EMR)
	// [role, vehicleClass, dismountCount]; order = march order. "TRUCK" rows after the first are optional
	// and rolled (convoyTrucks).
	["convoy", [
		["LEAD", "rhs_tigr_msv", 0],
		["APC", "rhs_btr80_msv", 0],
		["TRUCK", "RHS_Ural_MSV_01", 8],
		["TRUCK", "RHS_Ural_Open_MSV_01", 8]
	]],
	["convoyTrucks", [1, 2]],
	["convoyGap", 50], // metres between vehicles at spawn
	["convoyDelay", [600, 960]], // s after mission start until the convoy sets off (seeded)
	["convoyEtaSpeed", 7], // m/s used only for the briefing's arrival window
	["dismountLeaderClass", "rhs_msv_emr_sergeant"],
	["dismountClasses", ["rhs_msv_emr_rifleman", "rhs_msv_emr_rifleman", "rhs_msv_emr_machinegunner", "rhs_msv_emr_grenadier", "rhs_msv_emr_LAT", "rhs_msv_emr_RShG2", "rhs_msv_emr_at", "rhs_msv_emr_medic", "rhs_msv_emr_efreitor"]],
	["dismountStopTimeout", 20],
	["huntDelay", 45], // s after dismounting before LAMBS taskHunt sends the dismounts after the ambushers
	["huntRadius", 700],
	["enemySkill", [
		["general", 0.5], ["aimingAccuracy", 0.18], ["aimingShake", 0.25], ["aimingSpeed", 0.35],
		["spotDistance", 0.7], ["spotTime", 0.6], ["courage", 0.6], ["reloadSpeed", 0.5], ["commanding", 0.5]
	]],
	["detectKnowsAbout", 1.5], // a convoy group knowing this much about a squad member = ambush compromised
	["escapeFailCount", 2], // this many vehicles past the kill line = mission failed
	["ineffectiveMaxAlive", 2], // convoy is combat ineffective with no working vehicle and at most this many men left
	["fledDistance", 900], // convoy men further than this from the kill zone no longer count
	["stuckWarn", 120],

	// ---------------------------------------------------------------- rally point pickup (RHS USMC)
	["rpVehicles", ["rhsusf_m1025_w_m2", "rhsusf_m998_w_4dr"]],

	// ---------------------------------------------------------------- mods (CfgPatches classes, checked at init)
	// [label, CfgPatches class, required]
	["mods", [
		["CBA", "cba_main", true],
		["ACE", "ace_main", true],
		["LAMBS Danger", "lambs_danger", true],
		["LAMBS Waypoints", "lambs_wp", true],
		["RHS AFRF", "rhs_main", true],
		["RHS USAF", "rhsusf_main", true],
		["RHS GREF", "rhsgref_main", false]
	]],

	// ---------------------------------------------------------------- mortars (virtual 81 mm section, Hill pattern)
	["artyMissions", 2],
	["artyRoundsFFE", 4],
	["artySpotRounds", 2],
	["artyProcessTime", 60],
	["artyTimeOfFlight", 25],
	["artyCEP", 50],
	["artyAdjustedCEP", 25],
	["artyAdjustWindow", 150],
	["artyDangerClose", 150],
	["artyAmmo", "Sh_82mm_AMOS"],
	["artyInterval", [3, 6]],

	// ---------------------------------------------------------------- test mode
	["testSetupTimeout", 900],
	["testConvoyTimeout", 1500],
	["testInitiateDistance", 150],
	["testFightTimeout", 900],
	["testRpTimeout", 1200],
	["testExpected", [
		"spawn_route", "spawn_squad", "spawn_rp", "squad_in_position", "convoy_spawned", "contact",
		"artillery", "convoy_ineffective", "rp_reached", "outcome_win"
	]]
]
