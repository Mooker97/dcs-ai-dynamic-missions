/*
	DMS_fnc_config - tunables for the "Base life" test mission. Returns a hashmap.
	Site centres are the centroids of real military-structure clusters measured in-engine by the
	diag run (docs/arma/kb/sites-verified.md, "Large bases"). Whether each one plays well as a
	"base with life" (roads, helipad, open apron) is TO VERIFY: the ambient module logs what it
	finds there (survey line) on every run.
*/
createHashMapFromArray [
	["sites", [
		["AAC airfield military area", [16001, 17042]],
		["Pyrgos military base", [17422, 13167]]
	]],
	["siteIds", ["aac", "pyrgos"]],
	["squadClasses", ["B_Soldier_TL_F", "B_Soldier_F", "B_soldier_AR_F", "B_medic_F"]],
	["playerClass", "B_Soldier_TL_F"],
	["factions", ["auto", "vanilla_nato", "rhs_usarmy", "rhs_usmc"]],
	["activeRadius", 600],
	["despawnRadius", 900],
	["despawnDelay", 30],
	["testHeliFirstDelay", [15, 30]],
	["testHeliInterval", [120, 180]],
	["testFarDist", 2500],
	["testActivateTimeout", 120],
	["testTrafficWait", 120],
	["testHeliTimeout", 420],
	["testExpected", [
		"spawn_squad",
		"ambient_activated",
		"ambient_spawned",
		"ambient_layers",
		"ambient_caps",
		"ambient_tagged",
		"ambient_lambs_off",
		"ambient_traffic_moving",
		"ambient_heli_landed",
		"ambient_hysteresis",
		"ambient_despawned",
		"ambient_reactivated",
		"outcome_win"
	]]
]
