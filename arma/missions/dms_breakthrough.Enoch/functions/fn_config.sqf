/*
	DMS_fnc_config
	ALL mission tunables live here as plain data so a generator can rewrite this file later.
	Returns a HashMap. Positions are Livonia (Enoch, 12.8 km square) world [x, y] in metres.

	Sites were picked offline and checked in-engine (see CLASSES.md "Terrain data"):
	- village positions are the map's own location points (map_enoch.pbo, CfgWorlds >> Enoch >> Names);
	- each approach is the road centreline from the terrain's road shapefile (map_enoch_data.pbo
	  roads\roads.shp, false easting 200000 removed), traced 3 km out from the village along "road"/"main road"
	  segments and resampled every ~100 m, listed start -> village;
	- a dedicated-server diag run (2026-10-29) measured trees beside each approach: these three had the most
	  open ground 250-500 m either side of the road and treeline spots 1.0-1.7 km out with line of sight to it.
	Everything else (crossroads, treeline and ATGM positions, the BMP's spot, the phase line) is derived at
	run time and logged.
*/

createHashMapFromArray [
	// ---------------------------------------------------------------- sites: [name, villageXY, approach route start -> village]
	["sites", [
		["Bielawa, from the Lukow road", [1573, 9677], [
			[3452, 11619], [3360, 11578], [3271, 11522], [3197, 11470], [3131, 11384], [3101, 11306], [3072, 11210], [3040, 11101],
			[2983, 11010], [2922, 10928], [2871, 10872], [2803, 10796], [2734, 10717], [2663, 10635], [2593, 10553], [2533, 10484],
			[2475, 10414], [2428, 10322], [2343, 10258], [2257, 10202], [2185, 10130], [2109, 10091], [2024, 10104], [1899, 10094],
			[1829, 10031], [1771, 9971], [1694, 9925], [1583, 9883], [1493, 9833], [1465, 9755], [1574, 9749]
		]],
		["Topolin, from the Radacz road", [1858, 7330], [
			[4102, 8436], [4011, 8479], [3971, 8558], [3923, 8656], [3860, 8718], [3777, 8742], [3719, 8686], [3638, 8610],
			[3588, 8545], [3539, 8443], [3493, 8370], [3425, 8278], [3347, 8196], [3288, 8142], [3194, 8073], [3124, 8034],
			[3022, 7983], [2937, 7937], [2861, 7894], [2791, 7821], [2737, 7735], [2634, 7701], [2530, 7701], [2452, 7659],
			[2359, 7606], [2271, 7555], [2182, 7505], [2109, 7458], [2018, 7406], [1932, 7384], [1879, 7331]
		]],
		["Grabin, from the Zapadlisko road", [10666, 11025], [
			[8316, 9671], [8417, 9688], [8513, 9704], [8587, 9769], [8641, 9860], [8706, 9933], [8774, 9990], [8861, 10058],
			[8926, 10129], [8995, 10211], [9078, 10236], [9181, 10259], [9259, 10270], [9379, 10271], [9478, 10296], [9489, 10362],
			[9575, 10384], [9647, 10457], [9743, 10519], [9816, 10551], [9919, 10599], [10006, 10660], [10069, 10712], [10152, 10780],
			[10231, 10846], [10309, 10913], [10363, 10987], [10431, 11057], [10520, 11126], [10587, 11090], [10661, 11004]
		]]
	]],
	["crossroadsSnap", 150], // the crossroads is the road segment with 3+ connections nearest the village point
	["tankStartIndex", 3], // the tank starts on this route point; the Bradleys on the points behind it
	["phaseLineDistance", 1000], // m from the crossroads: crossing it triggers the pre-planned strike
	["objMarkerRadius", 300],
	["objMarkerFuzz", [50, 120]],
	["mapMargin", 200],

	// ---------------------------------------------------------------- player tank (RHS USAF, US Army woodland)
	// The mission.sqm slot is a vanilla B_Soldier_TL_F so the mission loads without RHS and the mod check can end
	// it cleanly. At start the player gets the combat crewman loadout and is moved into the commander's seat.
	["playerSlotClass", "B_Soldier_TL_F"],
	["playerLoadoutClass", "rhsusf_army_ucp_combatcrewman"],
	["tankClasses", ["rhsusf_m1a2sep1wd_usarmy", "rhsusf_m1a2sep1d_usarmy"]],
	["tankCommanderTurret", [0, 0]],
	["tankSkill", 0.7],
	["immobileHintDelay", 20], // s immobilised before the bail-out hint
	["immobileTimeout", 600], // s immobilised (alive, no win) before the attack is called off (draw)

	// ---------------------------------------------------------------- friendly section (2 Bradleys + a rifle squad)
	["ifvClasses", ["RHS_M2A3_wd", "RHS_M2A3"]],
	["ifvCount", 2],
	["ifvSkill", 0.6],
	["followDistance", [150, 250]], // Bradley 1 keeps this far behind the tank, Bradley 2 a further followGap
	["followGap", 100],
	["followUpdate", 5],
	["infLeaderClass", "rhsusf_army_ucp_squadleader"],
	["infClasses", [
		"rhsusf_army_ucp_teamleader", "rhsusf_army_ucp_autorifleman", "rhsusf_army_ucp_riflemanat",
		"rhsusf_army_ucp_grenadier", "rhsusf_army_ucp_machinegunner", "rhsusf_army_ucp_rifleman", "rhsusf_army_ucp_medic"
	]],
	["infSkill", 0.6],
	["dismountDistance", 300], // the Bradleys stop this far short of the crossroads to dismount the squad
	["dismountTrigger", 800], // ...once the village armour is down and the tank or a Bradley is this close
	["clearSearchRadius", 150], // the dismounts clear house by house within this of the crossroads (LAMBS taskCQB)

	// ---------------------------------------------------------------- enemy (RHS AFRF)
	["treelineTankClasses", ["rhs_t72bd_tv", "rhs_t72bb_tv"]],
	["treelineTanks", 2],
	["treelineBand", [1000, 1700]], // route distance from the crossroads where the treeline ambush sits
	["treelineOffset", [250, 700]], // m off the road
	["treelinePair", [40, 150]], // the second tank sits this far from the first, same treeline
	["atgmClasses", ["rhs_Metis_9k115_2_msv", "rhs_Kornet_9M133_2_msv"]],
	["atgmTeam", ["rhs_msv_emr_at", "rhs_msv_emr_rifleman"]],
	["atgmBand", [500, 1100]],
	["atgmOffset", [300, 600]],
	["atgmOppositeChance", 0.7], // the ATGM team takes the other flank from the tanks
	["villageIfvClasses", ["rhs_bmp2_msv", "rhs_bmp2d_msv"]],
	["villageIfvDistance", [150, 260]], // route distance from the crossroads
	["villageIfvOffset", [25, 60]],
	["villageLeaderClass", "rhs_msv_emr_sergeant"],
	["villageInfClasses", [
		"rhs_msv_emr_rifleman", "rhs_msv_emr_machinegunner", "rhs_msv_emr_grenadier", "rhs_msv_emr_rifleman",
		"rhs_msv_emr_LAT", "rhs_msv_emr_rifleman", "rhs_msv_emr_medic"
	]],
	["villageAtTeam", ["rhs_msv_emr_RShG2", "rhs_msv_emr_LAT"]],
	["garrisonRange", 90],
	["counterChance", 0.6],
	["counterDelay", 600], // s after the phase line before the counter-attack sets off (if not yet won)
	["counterDistance", 1500], // from the crossroads, on the far side
	["counterTankClasses", ["rhs_t72bd_tv", "rhs_t72bb_tv"]],
	["counterIfvClasses", ["rhs_bmp3_msv", "rhs_bmp2_msv"]],
	["enemySkill", [
		["general", 0.5], ["aimingAccuracy", 0.2], ["aimingShake", 0.25], ["aimingSpeed", 0.35],
		["spotDistance", 0.7], ["spotTime", 0.6], ["courage", 0.6], ["reloadSpeed", 0.5], ["commanding", 0.5]
	]],
	["contactDistance", 1100], // tank this close to a treeline tank = contact (also any enemy shot or hit)

	// ---------------------------------------------------------------- objective
	["villageRadius", 450], // enemy armour this close to the crossroads counts as village armour
	["clearRadius", 250],
	["clearMax", 2], // cleared: at most this many enemy men alive within clearRadius ...
	["clearFriendlyRadius", 200], // ... and the tank or a dismount within this of the crossroads
	["holdRadius", 75],
	["holdSeconds", 120], // or: the tank holds the crossroads this long with no enemy armour alive
	["armourCheckRadius", 3000],

	// ---------------------------------------------------------------- air support (A-10A, scripted bombs)
	// The jet flies a real pass for the visuals; the bombs are spawned above the aim point with a seeded CEP so
	// the strike is reliable (same idea as the virtual mortars and Hold's AH-64 fixes).
	["casUses", 2],
	["casClasses", ["RHS_A10"]],
	["casAmmo", ["Bo_Mk82", "rhs_ammo_mk82"]],
	["casProcessTime", 90],
	["casSpawnDistance", 6000], // from the aim point, from the friendly rear
	["casFlyHeight", 250],
	["casReleaseDistance", 700],
	["casTransitTimeout", 150],
	["casBombs", 2],
	["casCEP", 25],
	["casDangerClose", 200],
	["casDropHeight", 120],
	["ppBombs", 4], // pre-planned strike on the village defences at the phase line
	["ppCEP", 35],
	["ppProcessTime", 30],

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

	// ---------------------------------------------------------------- test mode
	["testRevealDistance", 2200], // the AI tank commander is told about enemies this close (stands in for the player's eyes)
	["testCasDistance", 1600], // test CAS 1 on the treeline tanks once the tank is this close
	["testHaltDistance", 450], // the AI tank waits this far short of the crossroads until the village armour is down
	["testTreelineTimeout", 900],
	["testVillageTimeout", 1200],
	["testExpected", [
		"spawn_tank", "spawn_section", "spawn_enemy", "contact", "cas_strike", "treeline_killed", "section_follow",
		"preplanned_strike", "section_dismount", "village_cleared", "outcome_win"
	]]
]
