/*
	DMS_fnc_config - "Hold the OP"
	ALL mission tunables live here as plain data so a generator can rewrite this file later.
	Returns a HashMap. Positions are Altis world [x, y] in metres. Times are seconds of real play
	(test mode scales the mission-logic delays through DMS_fnc_t).
	Every mod class below was found in the installed mod PBOs (see CLASSES.md); the mission also checks
	each one with isClass at start and ends with a clear message if any is missing.
*/

createHashMapFromArray [
	// ---------------------------------------------------------------- sites
	// [name, centerXY, rearBearing, enemyBearings]
	// centerXY: centroid of a vanilla terrain outpost, measured in-engine (docs/arma/kb/sites-verified.md).
	// rearBearing: the friendly side (verified dry and open at 350 m and 1000 m); air support and the
	//   relief come from here and no enemy wave uses it.
	// enemyBearings: approach directions the waves may use (TO VERIFY: not measured; each wave spawn is
	//   snapped at runtime to dry, flat ground out of sight of the OP and the result is logged).
	["sites", [
		["OP Agia Triada (outpost south of Agia Triada)", [16586, 19008], 270, [30, 90, 135, 180, 210]],
		["OP Agios Petros (outpost north of Agios Petros)", [20602, 18810], 90, [180, 225, 270, 315]]
	]],
	["outpostClasses", ["Land_Cargo_HQ_V1_F", "Land_Cargo_House_V1_F", "Land_Cargo_Patrol_V1_F", "Land_Cargo_Tower_V1_F"]],
	["opRadius", 60], // the OP area: structures searched, overrun check
	["opMarkerRadius", 60],

	// ---------------------------------------------------------------- required mods (checked at init)
	// [label, CfgPatches class] - logged; the real gate is the class and function checks below
	["modPatches", [["CBA_A3", "cba_main"], ["ACE", "ace_main"], ["LAMBS_Danger", "lambs_danger"], ["LAMBS waypoints", "lambs_wp"], ["RHSAFRF", "rhs_main"], ["RHSUSAF", "rhsusf_main"]]],
	["modFunctions", ["lambs_wp_fnc_taskAssault", "lambs_wp_fnc_taskCreep", "lambs_wp_fnc_taskRush"]],

	// ---------------------------------------------------------------- player squad (US Army, RHSUSAF, OCP)
	// The mission.sqm slot is a vanilla class so the mission loads (and can report missing mods) without
	// RHS; the player gets the RHS squad leader loadout at start.
	["playerSlotClass", "B_Soldier_SL_F"],
	["playerLoadoutClass", "rhsusf_army_ocp_squadleader"],
	["squadLeaderClass", "rhsusf_army_ocp_squadleader"],
	["squadClasses", ["rhsusf_army_ocp_teamleader", "rhsusf_army_ocp_autorifleman", "rhsusf_army_ocp_grenadier",
		"rhsusf_army_ocp_rifleman", "rhsusf_army_ocp_riflemanat", "rhsusf_army_ocp_machinegunner", "rhsusf_army_ocp_medic"]],
	["squadSkill", 0.6],
	["staticGunnerClass", "rhsusf_army_ocp_rifleman"], // this squad member starts on the static gun
	["staticClasses", ["RHS_M2StaticMG_D", "RHS_MK19_TriPod_D"]], // first existing wins
	["staticRing", [6, 30]],
	["squadInBuildings", 4], // at most this many start in tower/house positions (highest first)

	// ---------------------------------------------------------------- enemy (Russian motor rifles, RHSAFRF, EMR summer)
	["enemyLeaderClass", "rhs_msv_emr_sergeant"],
	["enemyClasses", ["rhs_msv_emr_rifleman", "rhs_msv_emr_rifleman", "rhs_msv_emr_machinegunner", "rhs_msv_emr_LAT",
		"rhs_msv_emr_grenadier", "rhs_msv_emr_arifleman", "rhs_msv_emr_RShG2", "rhs_msv_emr_medic"]],
	// grounded AI: decent spotting, poor raw accuracy
	["enemySkill", [
		["general", 0.5], ["aimingAccuracy", 0.18], ["aimingShake", 0.25], ["aimingSpeed", 0.35],
		["spotDistance", 0.7], ["spotTime", 0.6], ["courage", 0.6], ["reloadSpeed", 0.5], ["commanding", 0.5]
	]],
	// waves: list of groups [tactic, size, bearingOffset]; tactic CREEP = lambs taskCreep onto the OP,
	// ASSAULT = lambs taskAssault to an assault position short of the OP, then taskRush
	["waves", [
		[["CREEP", 6, 0]],
		[["ASSAULT", 7, 0], ["CREEP", 6, 40]],
		[["ASSAULT", 8, 0]]
	]],
	["waveSpawnDistance", [900, 1150]],
	["waveAssaultDistance", 180], // ASSAULT groups run to here, then rush the OP
	["waveTrackRadius", 250], // LAMBS creep/rush look for targets this far from the OP centre
	["waveBrokenFraction", 0.25], // a wave is broken when at most this fraction is alive
	["prepTime", [150, 240]], // s from start to wave 1
	["waveGapMax", [300, 420]], // the next wave comes when this one is broken, or at most this long after it
	["waveGapMin", 90], // ... but never sooner than this
	["reliefDelay", 120], // relief arrives this long after the last wave is broken
	["reliefMaxAfterLast", 600], // ... or at the latest this long after the last wave spawned
	["overrunTime", 60], // enemy holding the OP area with no friendlies for this long = fail

	// ---------------------------------------------------------------- support-by-fire vehicle (arrives with wave 2)
	// It moves to a stand-off position with line of sight to the OP and holds there; it never assaults.
	// It withdraws when wave 2 is broken. Low gunnery skill: it suppresses, it is not a sniper.
	["sbfWave", 2],
	["sbfClasses", ["rhs_btr80_msv", "rhs_bmp2_msv"]],
	["sbfDistance", [800, 1000]],
	["sbfApproach", 600], // spawns this much further out and drives in
	["sbfSkill", [["general", 0.4], ["aimingAccuracy", 0.08], ["aimingShake", 0.6], ["aimingSpeed", 0.3], ["spotDistance", 0.5], ["spotTime", 0.4]]],
	["sbfMoveTimeout", 300],

	// ---------------------------------------------------------------- mortars (virtual 81 mm M252 section)
	["artyMissions", 3],
	["artyRoundsFFE", 6],
	["artySpotRounds", 2],
	["artyProcessTime", 60],
	["artyTimeOfFlight", 25],
	["artyCEP", 50],
	["artyAdjustedCEP", 25],
	["artyAdjustWindow", 150],
	["artyDangerClose", 200],
	["artyAmmo", "Sh_82mm_AMOS"], // vanilla 82 mm HE shell, ballistically close to the 81 mm M821
	["artyInterval", [3, 6]],

	// ---------------------------------------------------------------- air support (one AH-64D attack run)
	["airClasses", ["RHS_AH64D_CS", "RHS_AH64D"]],
	["airProcessTime", 120], // tasking and launch from a strip alert
	["airSpawnDistance", 7000], // from the OP, along the rear bearing
	["airFlyHeight", 80],
	["airDangerClose", 150],
	["airSearchRadius", 200], // targets within this of the mark are passed to the crew
	["airOnStation", 180], // s over the target area
	["airTransitTimeout", 400],

	// ---------------------------------------------------------------- test mode
	["testWaveSpawnDistance", 450], // used when DMS_testStartDist > 0 (at least this far)
	["testExpected", [
		"mods", "spawn_squad", "spawn_static", "mortar_danger_close", "air_danger_close",
		"wave1", "wave2", "wave3", "sbf_in_position", "mortar", "air_requested", "air_on_station", "outcome_win"
	]]
]
