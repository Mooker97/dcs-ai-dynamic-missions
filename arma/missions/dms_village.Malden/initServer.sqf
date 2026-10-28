/*
	initServer.sqf - DMS "Village Sweep": server-authoritative setup and fail monitor.
	Flow: params + seed -> mod/class check -> village -> approach + counterattack rolls -> squad on foot ~700 m out
	      + Bradley -> insurgent garrison (LAMBS) -> tasks + AO marker -> clear monitor -> (test harness).
*/
DMS_cfg = call DMS_fnc_config;
DMS_debug = (["DMS_debug", 0] call BIS_fnc_getParamValue) == 1;
DMS_testMode = (["DMS_testMode", 0] call BIS_fnc_getParamValue) == 1;
DMS_testMinutes = ["DMS_testMinutes", 45] call BIS_fnc_getParamValue;
DMS_timeScale = 1;
if (DMS_testMode) then { DMS_timeScale = ((["DMS_testTimeScale", 100] call BIS_fnc_getParamValue) max 1) / 100; };
private _cfg = DMS_cfg;
private _startDist = _cfg get "startDistance";
DMS_testAssist = 0;
if (DMS_testMode) then {
	private _sd = ["DMS_testStartDist", 0] call BIS_fnc_getParamValue;
	if (_sd > 0) then { _startDist = _sd; };
	DMS_testAssist = ["DMS_testAssist", 0] call BIS_fnc_getParamValue;
};
DMS_testForce = ["DMS_testForce", 0] call BIS_fnc_getParamValue; // 1 = Bradley destroyed after the clear, 2 = squad wiped after the clear
publicVariable "DMS_debug";

private _seedParam = ["DMS_seed", 0] call BIS_fnc_getParamValue;
if (_seedParam <= 0) then { _seedParam = 1 + floor (random 99999); }; // dms-allow-random (seed 0 = pick one, it is logged)
DMS_seed = ["SEED", _seedParam] call DMS_fnc_rng;

DMS_over = false;
DMS_siteName = "none";
DMS_player = objNull;
DMS_squad = grpNull;
DMS_ifv = objNull;
DMS_ifvLost = false;
DMS_technical = objNull;
DMS_defenders = [];
DMS_enemyGroups = [];
DMS_villageCleared = false;
DMS_counterUnits = [];
DMS_counterVehicles = [];
DMS_counterSpawned = -1;
DMS_counterDismounted = -1;
DMS_testAssisted = 0;
DMS_testResults = createHashMap;

// ---------------------------------------------------------------- required mods and classes
private _req = _cfg get "requiredMods";
private _missing = (_req select {!isClass (configFile >> "CfgPatches" >> (_x select 1))}) apply {_x select 0};
private _loaded = (_req select {isClass (configFile >> "CfgPatches" >> (_x select 1))}) apply {_x select 0};
if (isClass (configFile >> "CfgPatches" >> "ace_medical")) then { _loaded pushBack "ACE medical"; };
[format ["Mods: %1%2", [_loaded joinString ", ", "none"] select (_loaded isEqualTo []),
	["", format ["; MISSING: %1", _missing joinString ", "]] select (_missing isNotEqualTo [])]] call DMS_fnc_log;
private _classes = [_cfg get "squadLeaderClass", _cfg get "ifvClass", _cfg get "technicalClass"]
	+ (_cfg get "squadClasses") + (_cfg get "rpgTeam") + (_cfg get "counterTruckClasses") + (_cfg get "counterInfantry");
{ _classes append _x; } forEach (_cfg get "garrisonGroups");
private _badClasses = (_classes arrayIntersect _classes) select {!isClass (configFile >> "CfgVehicles" >> _x)};
if (_badClasses isNotEqualTo []) then { [format ["Missing classes (skipped where possible): %1", _badClasses], "WARN"] call DMS_fnc_log; };
if (DMS_testMode) then { ["CHECK", ["mods", _missing isEqualTo [] && {_badClasses isEqualTo []}, format ["missing mods %1, missing classes %2", _missing, _badClasses]]] call DMS_fnc_testMode; };
if (_missing isNotEqualTo [] || {!isClass (configFile >> "CfgVehicles" >> (_cfg get "ifvClass"))} || {!isClass (configFile >> "CfgVehicles" >> (_cfg get "squadLeaderClass"))}) exitWith {
	private _msg = format ["Village Sweep needs CBA_A3, ACE3, LAMBS Danger and RHS AFRF + USAF + GREF. Missing: %1", [_missing joinString ", ", "RHS classes"] select (_missing isEqualTo [])];
	[_msg, "WARN"] call DMS_fnc_log;
	_msg remoteExecCall ["hint", 0];
	["DMS_FailMods", false, "missing mods"] call DMS_fnc_end;
	["initServer done"] call DMS_fnc_log;
};

// ---------------------------------------------------------------- village and seeded rolls (fixed draw order)
private _village = ["PICK", [["DMS_village", 0] call BIS_fnc_getParamValue]] call DMS_fnc_village;
if (_village isEqualTo []) exitWith {
	["No usable village found on this map", "WARN"] call DMS_fnc_log;
	["DMS_FailSetup", false, "no usable village"] call DMS_fnc_end;
	["initServer done"] call DMS_fnc_log;
};
_village params ["_vName", "_vCenter", "_vHouses"];
DMS_siteName = _vName;
DMS_villageCenter = _vCenter;
DMS_villageHouses = _vHouses;
DMS_enemySide = ["SIDE", [((_cfg get "garrisonGroups") select 0) select 0]] call DMS_fnc_village;
if (DMS_enemySide == resistance) then { resistance setFriend [west, 0]; west setFriend [resistance, 0]; };

// Approach: the first seeded bearing whose start point and line to the village are dry and not in another town.
private _dryLine = {
	params ["_a", "_b"];
	([0.25, 0.5, 0.75, 1] findIf {surfaceIsWater (_a vectorAdd ((_b vectorDiff _a) vectorMultiply _x))}) < 0
};
private _bearings = ["SHUFFLE", _cfg get "approachBearings"] call DMS_fnc_rng;
DMS_startBearing = _bearings select 0;
{
	private _p = DMS_villageCenter getPos [_startDist, _x];
	if ([DMS_villageCenter, [_p select 0, _p select 1, 0]] call _dryLine && {(count (["HOUSES", [_p, 60]] call DMS_fnc_village)) < 3}) exitWith { DMS_startBearing = _x; };
} forEach _bearings;

// Counterattack: from the far side (at least 90 degrees off the approach), on a road.
private _cBearings = (["SHUFFLE", _cfg get "approachBearings"] call DMS_fnc_rng) select {(abs ((((_x - DMS_startBearing) + 540) mod 360) - 180)) >= 90};
private _cDist = ["RANGE", _cfg get "counterDistance"] call DMS_fnc_rng;
private _cSpawn = [];
{
	private _p = DMS_villageCenter getPos [_cDist, _x];
	if ([DMS_villageCenter, [_p select 0, _p select 1, 0]] call _dryLine) exitWith { _cSpawn = ["ROAD", [_p, 400]] call DMS_fnc_findPos; };
} forEach _cBearings;
if (_cSpawn isEqualTo []) then {
	_cSpawn = ["ROAD", [DMS_villageCenter getPos [_cDist, DMS_startBearing + 180], 400]] call DMS_fnc_findPos;
	["Counterattack: no dry far-side bearing, using the opposite side", "WARN"] call DMS_fnc_log;
};
private _cLocs = nearestLocations [_cSpawn, ["NameVillage", "NameCity", "NameCityCapital", "NameLocal"], 1500];
DMS_rolls = createHashMapFromArray [
	["counterSpawn", _cSpawn],
	["counterOrigin", [format ["grid %1", mapGridPosition _cSpawn], format ["near %1", text (_cLocs select 0)]] select (_cLocs isNotEqualTo [])],
	["counterDelay", ["RANGE", _cfg get "counterDelay"] call DMS_fnc_rng],
	["counterDismountDist", ["RANGE", _cfg get "counterDismount"] call DMS_fnc_rng],
	["counterTechnical", ["CHANCE", _cfg get "counterTechnicalChance"] call DMS_fnc_rng]
];
DMS_start = ["FLAT", [DMS_villageCenter getPos [_startDist, DMS_startBearing], 0, (_startDist * 0.15) min 120, 10]] call DMS_fnc_findPos;

[format ["Start: seed=%1 village='%2' center=%3 houses=%4 start=%5 bearing=%6 enemy=%7 debug=%8 test=%9",
	DMS_seed, _vName, DMS_villageCenter apply {round _x}, count _vHouses, DMS_start apply {round _x}, DMS_startBearing, DMS_enemySide, DMS_debug, DMS_testMode]] call DMS_fnc_log;
if (DMS_testMode) then { [format ["Test: timeScale=%1 startDist=%2 assist=%3 force=%4", DMS_timeScale, round _startDist, DMS_testAssist, DMS_testForce]] call DMS_fnc_log; };
[format ["Rolls: counterattack %1 at %2 after %3 s, dismount %4 m, technical=%5",
	DMS_rolls get "counterOrigin", _cSpawn apply {round _x}, round (DMS_rolls get "counterDelay"),
	round (DMS_rolls get "counterDismountDist"), DMS_rolls get "counterTechnical"]] call DMS_fnc_log;

// ---------------------------------------------------------------- squad
private _sqClasses = (_cfg get "squadClasses") select {isClass (configFile >> "CfgVehicles" >> _x)};
if (DMS_testMode) then {
	// SP/hosted test: park the local player out of the way; the AI squad does the work.
	if (hasInterface && {!isNull player}) then {
		private _pl = player;
		[_pl] joinSilent (createGroup [west, true]);
		_pl allowDamage false;
		_pl setCaptive true;
		hideObjectGlobal _pl;
		_pl setPosATL (DMS_start getPos [40, DMS_startBearing]);
	};
	DMS_squad = createGroup [west, true];
	_sqClasses = [_cfg get "squadLeaderClass"] + _sqClasses;
} else {
	if (isMultiplayer) then {
		private _tw = time;
		waitUntil { sleep 1; ((allPlayers - (entities "HeadlessClient_F")) isNotEqualTo []) || {time - _tw > 120} };
		private _pls = allPlayers - (entities "HeadlessClient_F");
		if (_pls isNotEqualTo []) then { DMS_player = _pls select 0; };
	} else {
		DMS_player = player;
	};
	if (isNull DMS_player) then {
		["No player found, the squad is AI only", "WARN"] call DMS_fnc_log;
		DMS_squad = createGroup [west, true];
		_sqClasses = [_cfg get "squadLeaderClass"] + _sqClasses;
	} else {
		DMS_squad = group DMS_player;
		private _lo = getUnitLoadout (configFile >> "CfgVehicles" >> (_cfg get "squadLeaderClass"));
		[DMS_player, _lo] remoteExecCall ["setUnitLoadout", DMS_player];
	};
};
{
	private _u = DMS_squad createUnit [_x, DMS_start, [], 5, "NONE"];
	_u setSkill (_cfg get "squadSkill");
} forEach _sqClasses;
DMS_squad setFormation "WEDGE";
DMS_squad setBehaviour "AWARE";

private _face = DMS_start getDir DMS_villageCenter;
{
	private _p = (DMS_start getPos [4 * floor (_forEachIndex / 2), _face + 180]) getPos [[-3, 3] select (_forEachIndex mod 2), _face + 90];
	[_x, [_p select 0, _p select 1, 0]] remoteExecCall ["setPosATL", _x];
	[_x, _face] remoteExecCall ["setDir", _x];
} forEach (units DMS_squad);
if (DMS_testMode && {hasInterface} && {!isNull player}) then { (leader DMS_squad) switchCamera "EXTERNAL"; };

// ---------------------------------------------------------------- Bradley, insurgents
private _ifvPos = ["FLAT", [DMS_start getPos [_cfg get "ifvOffset", DMS_startBearing], 0, 40, 8]] call DMS_fnc_findPos;
["INIT", [_ifvPos, _ifvPos getDir DMS_villageCenter]] call DMS_fnc_ifv;
["DEFEND"] call DMS_fnc_village;

// ---------------------------------------------------------------- tasks, markers
private _fuzz = DMS_villageCenter getPos [["RANGE", _cfg get "aoMarkerFuzz"] call DMS_fnc_rng, ["RANGE", [0, 360]] call DMS_fnc_rng];
private _mk = createMarker ["DMS_mk_ao", _fuzz];
_mk setMarkerShape "ELLIPSE";
_mk setMarkerSize [_cfg get "aoMarkerRadius", _cfg get "aoMarkerRadius"];
_mk setMarkerBrush "FDiagonal";
_mk setMarkerColor "ColorOPFOR";

[true, "DMS_t_clear",
	[format ["Insurgents hold %1. Clear the village with your squad and the attached Bradley. Expect them to dig into the houses and to have RPGs.", _vName], format ["Clear %1", _vName], ""],
	objNull, "ASSIGNED", 1, true, "attack"] call BIS_fnc_taskCreate;
[true, "DMS_t_ifv",
	["Keep the attached M2A3 Bradley in the fight. Orders through the comm menu (0-8): move up, hold and overwatch, suppress a marked position.", "Keep the Bradley", ""],
	objNull, "CREATED", 0, false, "armor"] call BIS_fnc_taskCreate;

if (DMS_debug) then {
	{
		private _dm = createMarker [format ["DMS_dbg_%1", _forEachIndex], getPosATL _x];
		_dm setMarkerType "mil_dot";
		_dm setMarkerColor "ColorRed";
	} forEach DMS_defenders;
	private _cm = createMarker ["DMS_dbg_counter", _cSpawn];
	_cm setMarkerType "mil_start";
	_cm setMarkerText "counterattack";
};

// ---------------------------------------------------------------- monitors, test harness
["MONITOR"] spawn DMS_fnc_village;

[] spawn {
	waitUntil {
		sleep 2;
		DMS_over || {!isNull DMS_player && {!alive DMS_player}} || {({alive _x} count (units DMS_squad)) == 0}
	};
	if (DMS_over) exitWith {};
	if (!isNull DMS_player && {!alive DMS_player}) then {
		["DMS_FailDead", false, "player killed"] call DMS_fnc_end;
	} else {
		["DMS_FailDead", false, "squad wiped out"] call DMS_fnc_end;
	};
};

if (DMS_testMode) then { ["RUN"] spawn DMS_fnc_testMode; };
["initServer done"] call DMS_fnc_log;
