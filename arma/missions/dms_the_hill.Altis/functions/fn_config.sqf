/*
	DMS_fnc_config
	ALL mission tunables live here as plain data so a generator can rewrite this file later.
	Returns a HashMap. Positions are Altis world [x, y] in metres.
	Coordinates marked TO VERIFY were taken from map knowledge, not measured in-game. The scripts
	snap them to nearby flat, clear ground (sites, start, LZ) or to the nearest road (QRF spawns),
	so small errors are tolerated.
*/

createHashMapFromArray [
	// ---------------------------------------------------------------- sites
	// [name, centerXY, compoundDir, startBearing (compound -> squad start, also the safe side for the LZ
	//  and the extraction approach), [qrfSpawnA_XY, qrfSpawnB_XY], [qrfNameA, qrfNameB], mode]
	// mode "OUTPOST": garrison the vanilla terrain outpost at centerXY (no snap; props placed on clear
	//   ground inside it). mode "BUILD": snap to flat open ground and build "composition".
	// Verified on a dedicated server with the diag sweep (docs/arma/kb/sites-verified.md): each centre is
	// the centroid of the outpost's cargo structures; start/LZ bearings point at dry, open ground; QRF
	// origins are the town centres from nearestLocations.
	["sites", [
		["Outpost between Zaros and Therisa", [10013, 11231], 0, 0, [[9092, 11962], [10619, 12237]], ["Zaros", "Therisa"], "OUTPOST"],
		["Outpost south of Agia Triada", [16586, 19008], 0, 270, [[17827, 18129], [16207, 17297]], ["Kalithea", "Telos"], "OUTPOST"],
		["Outpost north of Agios Petros", [20602, 18810], 0, 90, [[19339, 17642], [20885, 16959]], ["Agios Petros", "Paros"], "OUTPOST"]
	]],
	["outpostClasses", ["Land_Cargo_HQ_V1_F", "Land_Cargo_House_V1_F", "Land_Cargo_Patrol_V1_F", "Land_Cargo_Tower_V1_F"]],
	["outpostRadius", 60],
	// [kind, class, [minR, maxR], clearR] placed at seeded clear spots (no terrain objects within clearR);
	// kind OVER is placed on the intel table spot (camo net over the table)
	["outpostComposition", [
		["INTEL", "Land_CampingTable_F", [0, 30], 4],
		["OVER", "CamoNet_OPFOR_open_F", [0, 0], 0],
		["OBJ", "Box_East_Ammo_F", [0, 35], 2],
		["STATIC", "O_HMG_01_high_F", [12, 40], 3],
		["STATIC", "O_HMG_01_high_F", [12, 40], 3],
		["SENTRY", "", [20, 45], 2],
		["SENTRY", "", [20, 45], 2]
	]],
	["siteSnapRadius", 250],
	["clearRadius", 32],
	["startDistance", 1000],
	["lzDistance", 350],
	["aoMarkerRadius", 300],
	["aoMarkerFuzz", [50, 150]],

	// ---------------------------------------------------------------- player squad (NATO, vanilla loadouts)
	["squadLeaderClass", "B_Soldier_TL_F"],
	["squadClasses", ["B_soldier_AR_F", "B_Soldier_GL_F", "B_medic_F", "B_soldier_LAT_F", "B_soldier_M_F", "B_Soldier_F"]],
	["squadSkill", 0.6],

	// ---------------------------------------------------------------- built compound (mode "BUILD")
	// Land_Cargo_House_V1_F has 1 building position, _Patrol_V1_F 2, _HQ_V1_F 13 (diag sweep).
	// [kind, class, [dx, dy], relDir]; dx/dy in metres in the compound frame (+y = compoundDir).
	// kinds: BLD building (garrisoned via buildingPos), OBJ terrain-aligned prop,
	//        STATIC crewed static weapon, SENTRY fixed sentry post (class unused), INTEL table for the intel item
	["composition", [
		["BLD", "Land_Cargo_HQ_V1_F", [-10, 8], 90],
		["BLD", "Land_Cargo_House_V1_F", [11, 6], 270],
		["BLD", "Land_Cargo_Patrol_V1_F", [0, 17], 180],
		["OBJ", "CamoNet_OPFOR_open_F", [3, -6], 0],
		["INTEL", "Land_CampingTable_F", [3, -6], 0],
		["OBJ", "Box_East_Ammo_F", [5.5, -7.5], 0],
		["OBJ", "Land_BagBunker_Small_F", [-15, -15], 225],
		["OBJ", "Land_BagFence_Round_F", [15, -15], 135],
		["STATIC", "O_HMG_01_high_F", [15, -14], 135],
		["OBJ", "Land_BagFence_Round_F", [-15, 15], 315],
		["STATIC", "O_HMG_01_high_F", [-15, 14], 315],
		["OBJ", "Land_HBarrier_5_F", [-10, -20], 0],
		["OBJ", "Land_HBarrier_5_F", [10, -20], 0],
		["OBJ", "Land_HBarrier_5_F", [-20, -5], 90],
		["OBJ", "Land_HBarrier_5_F", [-20, 5], 90],
		["OBJ", "Land_HBarrier_5_F", [20, -5], 90],
		["OBJ", "Land_HBarrier_5_F", [20, 5], 90],
		["OBJ", "Land_BagFence_Long_F", [-8, 21], 0],
		["OBJ", "Land_BagFence_Long_F", [8, 21], 0],
		["OBJ", "Land_Razorwire_F", [-13, -25], 0],
		["OBJ", "Land_Razorwire_F", [13, -25], 0],
		["SENTRY", "", [0, -22], 180],
		["SENTRY", "", [18, 18], 45]
	]],
	["intelClass", "Land_Laptop_unfolded_F"],
	["intelHoldSeconds", 8],

	// ---------------------------------------------------------------- enemy (CSAT)
	["sentryClass", "O_Soldier_F"],
	["garrisonClasses", ["O_Soldier_F", "O_Soldier_F", "O_Soldier_AR_F", "O_Soldier_GL_F", "O_Soldier_LAT_F", "O_soldier_M_F"]],
	["garrisonCount", 5],
	["patrolSize", 3],
	["patrolRadius", 200],
	// grounded AI: decent spotting, poor raw accuracy
	["enemySkill", [
		["general", 0.5], ["aimingAccuracy", 0.18], ["aimingShake", 0.25], ["aimingSpeed", 0.35],
		["spotDistance", 0.7], ["spotTime", 0.6], ["courage", 0.6], ["reloadSpeed", 0.5], ["commanding", 0.5]
	]],
	["alarmKnowsAbout", 1.5],

	// ---------------------------------------------------------------- QRF
	// wave: [vehicleClasses (first existing wins), infantryClasses, infantryCount, dismountDistance [min, max]]
	["wave1", [
		["O_Truck_02_transport_F", "O_Truck_03_transport_F"],
		["O_Soldier_TL_F", "O_Soldier_F", "O_Soldier_AR_F", "O_Soldier_LAT_F", "O_Soldier_GL_F", "O_medic_F"],
		8, [350, 500]
	]],
	["wave2", [
		["O_APC_Wheeled_02_rcws_v2_F", "O_APC_Wheeled_02_rcws_F", "O_Truck_02_transport_F"],
		["O_Soldier_TL_F", "O_Soldier_F", "O_Soldier_AR_F", "O_Soldier_LAT_F", "O_Soldier_GL_F"],
		6, [450, 600]
	]],
	["wave1Delay", [300, 480]],
	["wave2Delay", [120, 240]],
	["wave2DragTime", 1200],
	["wave2QuickKill", 300],
	["qrfFlankOffset", 250],
	["qrfFlankAngle", 70],

	// ---------------------------------------------------------------- artillery (virtual 82 mm mortar section)
	["artyMissions", 3],
	["artyRoundsFFE", 5],
	["artySpotRounds", 3],
	["artyProcessTime", 60],
	["artyTimeOfFlight", 25],
	["artyCEP", 50],
	["artyAdjustedCEP", 25],
	["artyAdjustWindow", 150],
	["artyDangerClose", 150],
	["artyAmmo", "Sh_82mm_AMOS"],
	["artyInterval", [3, 6]],

	// ---------------------------------------------------------------- extraction
	["exfilHeliClass", "B_Heli_Transport_01_F"],
	["exfilSpawnDistance", 4000],
	["exfilHoldDistance", 1500],
	["exfilFlyHeight", 60],
	["exfilHotRadius", 200],
	["exfilHotVehicleRadius", 1200], // a known armed enemy vehicle this close also makes the LZ hot (covers RCWS range; at 600 an APC shot the heli down, 2026-10-28)
	["exfilReadyRadius", 75], // the heli comes in once the player (or, with no player, any squad member) is this close to the LZ
	["exfilReadyMaxWait", 600], // s the heli waits at the hold point for the squad to reach the LZ
	["exfilHotMaxHold", 300], // s the heli holds off a hot LZ before returning to base (request again)
	["exfilHotCount", 3],
	["exfilWaitOnGround", 150],
	["exfilBoardRadius", 400],
	["exfilDepartDistance", 1200],

	// ---------------------------------------------------------------- test mode
	["testArtyAt", 60],
	["testAlarmTimeout", 1200],
	["testIntelTimeout", 1800],
	["testExpected", [
		"spawn_compound", "spawn_garrison", "spawn_intel", "spawn_squad", "artillery", "alarm",
		"compound_cleared", "intel", "qrf_wave1", "exfil_requested", "exfil_landed", "exfil_boarded", "outcome_win"
	]]
]
