/*
	DMS_fnc_config
	ALL mission tunables live here as plain data so a generator can rewrite this file later.
	Returns a HashMap. Positions are Livonia (Enoch) world [x, y] in metres.
	Every class name below was checked in the mod PBOs (see CLASSES.md).
	Site anchors are TO VERIFY: they were chosen between the named places of the Enoch terrain config
	(CfgWorlds >> Enoch >> Names, read from map_enoch.pbo), not measured in-game. The scripts snap each
	anchor to a small forest clearing at runtime (fn_findPos "FOREST") and log what they found.
*/

createHashMapFromArray [
	// ---------------------------------------------------------------- sites
	// [name, anchorXY (TO VERIFY), startBearing (battery -> team insertion point, also the battery's rear)]
	["sites", [
		["Forest south-west of Nadbor", [4300, 3300], 130],
		["Forest west of Rodzanica hill", [7800, 2900], 200],
		["Forest between Lembork and Borek", [9000, 7700], 270]
	]],
	["siteSearchRadius", 500], // anchor -> battery snap radius
	["siteClearRadius", 14], // trees and bushes hidden around the battery so the tubes fit
	["mapMargin", 400],

	// ---------------------------------------------------------------- geometry
	["startDistance", 1800], // team insertion, on foot
	["pickupDistance", 1600], // exfil pickup from the battery
	["pickupBearingOffset", [100, 150]], // degrees either side of the start bearing (seeded side)
	["searchBoxSize", 1000], // side of the square search box marker
	["searchBoxFuzz", [150, 350]], // box centre offset from the battery

	// ---------------------------------------------------------------- recon team (RHS USAF, USMC Force Recon woodland)
	["teamLeaderClass", "rhsusf_usmc_recon_marpat_wd_teamleader"],
	["teamClasses", ["rhsusf_usmc_recon_marpat_wd_marksman", "rhsusf_usmc_recon_marpat_wd_autorifleman", "rhsusf_usmc_recon_marpat_wd_rifleman"]],
	["teamSkill", 0.65],
	["leaderDesignator", "Laserdesignator"],
	["leaderDesignatorBattery", "Laserbatteries"],

	// ---------------------------------------------------------------- enemy (RHS AFRF, MSV in EMR)
	["batteryClass", "rhs_2b14_82mm_msv"],
	["batteryTubes", 3],
	["batterySpacing", 12],
	["siteKillNeeded", 2], // tubes out (destroyed or crew dead) for the battery to count as neutralized
	["tubeDamageOut", 0.75],
	// [class, [dx, dy], relDir] props in the battery frame (+y = firing direction), not part of the kill count
	["siteProps", [
		["CamoNet_OPFOR_open_F", [0, -16], 0],
		["Box_East_Ammo_F", [-2, -15], 0],
		["Box_East_Ammo_F", [2, -15], 90]
	]],
	["garrisonClasses", ["rhs_msv_emr_junior_sergeant", "rhs_msv_emr_rifleman", "rhs_msv_emr_machinegunner", "rhs_msv_emr_LAT"]],
	["garrisonCampRange", 50],
	["patrolClasses", ["rhs_msv_emr_rifleman", "rhs_msv_emr_grenadier", "rhs_msv_emr_machinegunner", "rhs_msv_emr_marksman"]],
	// [size, radius] per LAMBS patrol around the battery
	["patrols", [[3, 250], [2, 450]]],
	["enemySkill", [
		["general", 0.5], ["aimingAccuracy", 0.2], ["aimingShake", 0.25], ["aimingSpeed", 0.35],
		["spotDistance", 0.6], ["spotTime", 0.5], ["courage", 0.6], ["reloadSpeed", 0.5], ["commanding", 0.5]
	]],
	["alarmKnowsAbout", 1.5],

	// the battery's own fire: a few rounds every few minutes at a far target, an audible clue
	["harassFire", true],
	["harassInterval", [300, 600]],
	["harassRange", 3000],
	["harassRounds", 2],
	["harassTubes", 2],

	// ---------------------------------------------------------------- QRF (on foot, LAMBS taskHunt)
	["qrfClasses", ["rhs_msv_emr_sergeant", "rhs_msv_emr_rifleman", "rhs_msv_emr_machinegunner", "rhs_msv_emr_grenadier", "rhs_msv_emr_at", "rhs_msv_emr_rifleman"]],
	["qrfDistance", 1300], // from the battery, on its far side
	["qrfMinTeamDistance", 800],
	["qrfDelay", [240, 420]],
	["qrfHuntRadius", 2500],
	["qrfHuntCycle", 45],

	// ---------------------------------------------------------------- fire support (virtual 155 mm battery)
	["strikeMissions", 3],
	["strikeRounds", 6],
	["strikeAmmo", "Sh_155mm_AMOS"],
	["strikeCEP", 30],
	["strikeProcessTime", [90, 150]],
	["strikeTimeOfFlight", 40],
	["strikeInterval", [2, 5]],
	["strikeDangerClose", 200],
	["strikeReattackRadius", 150], // a later strike this close to a neutralized battery confirms it (no observer needed)

	// ---------------------------------------------------------------- BDA and exfil
	["bdaRange", 400],
	["bdaCloseRange", 60], // this close counts without a line-of-sight check
	["bdaVisibility", 0.25],
	["pickupRadius", 40],
	["pickupTeamRadius", 150],
	["pickupClearRadius", 250],
	["pickupHold", 10],
	["timeLimit", 5400], // s for the battery to be neutralized

	// ---------------------------------------------------------------- test mode
	["testOpDistances", [400, 250, 120]],
	["testOpHold", 90],
	["testFindRange", 400],
	["testReportDistance", 260],
	["testReportError", [0, 15]],
	["testBdaDistance", 180],
	["testExpected", [
		"mods", "spawn_site", "spawn_enemy", "spawn_team", "found", "report", "strike", "alarm",
		"site_neutralized", "bda", "exfil", "outcome_win"
	]]
]
