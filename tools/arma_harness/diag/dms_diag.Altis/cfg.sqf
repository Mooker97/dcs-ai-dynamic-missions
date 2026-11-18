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
	// [name, approxCenterXY (TO VERIFY), compoundDir, startBearing (compound -> squad start, also the
	//  safe side for the LZ and the extraction approach), [qrfSpawnA_XY, qrfSpawnB_XY], [qrfNameA, qrfNameB]]
	["sites", [
		["Farmland east of Pyrgos", [17600, 13200], 58, 0, [[16800, 12700], [20200, 11700]], ["Pyrgos", "Chalkeia"]],
		["Countryside near Zaros", [10600, 12800], 56, 140, [[9100, 11800], [12500, 14300]], ["Zaros", "Neochori"]],
		["Plateau south of Frini", [14600, 20200], 22, 90, [[14000, 18700], [10300, 19100]], ["Athira", "Galati"]]
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

	// ---------------------------------------------------------------- compound composition
	// [kind, class, [dx, dy], relDir]; dx/dy in metres in the compound frame (+y = compoundDir).
	// kinds: BLD building (garrisoned via buildingPos), OBJ terrain-aligned prop,
	//        STATIC crewed static weapon, SENTRY fixed sentry post (class unused), INTEL table for the intel item
	["composition", [
		["BLD", "Land_Cargo_House_V1_F", [-9, 6], 90],
		["BLD", "Land_Cargo_House_V1_F", [9, 6], 270],
		["BLD", "Land_Cargo_Patrol_V1_F", [0, 17], 180],
		["OBJ", "CamoNet_OPFOR_open_F", [0, -3], 0],
		["INTEL", "Land_CampingTable_F", [0, -3], 0],
		["OBJ", "Box_East_Ammo_F", [2.5, -4.5], 0],
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
	["exfilHotRadius", 300],
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
