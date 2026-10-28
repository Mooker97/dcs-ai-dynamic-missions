/*
	initServer.sqf - DMS "The Hill": server-authoritative setup and fail monitor.
	Flow: params + seed -> site -> squad on foot ~1 km out -> compound/garrison/intel -> task + AO marker
	      -> mortar menu -> alarm monitor -> (test harness).
*/
DMS_cfg = call DMS_fnc_config;
DMS_debug = (["DMS_debug", 0] call BIS_fnc_getParamValue) == 1;
DMS_testMode = (["DMS_testMode", 0] call BIS_fnc_getParamValue) == 1;
DMS_testMinutes = ["DMS_testMinutes", 45] call BIS_fnc_getParamValue;
DMS_timeScale = 1;
if (DMS_testMode) then { DMS_timeScale = ((["DMS_testTimeScale", 100] call BIS_fnc_getParamValue) max 1) / 100; };
private _startDist = DMS_cfg get "startDistance";
private _lzDist = DMS_cfg get "lzDistance";
DMS_testAssist = 0;
if (DMS_testMode) then {
	private _sd = ["DMS_testStartDist", 0] call BIS_fnc_getParamValue;
	if (_sd > 0) then { _startDist = _sd; };
	DMS_testAssist = ["DMS_testAssist", 0] call BIS_fnc_getParamValue;
};
DMS_testForce = ["DMS_testForce", 0] call BIS_fnc_getParamValue; // 1 = destroy the exfil heli, 2 = wipe the squad
publicVariable "DMS_debug";

private _seedParam = ["DMS_seed", 0] call BIS_fnc_getParamValue;
if (_seedParam <= 0) then { _seedParam = 1 + floor (random 99999); }; // dms-allow-random (seed 0 = pick one, it is logged)
DMS_seed = ["SEED", _seedParam] call DMS_fnc_rng;

DMS_over = false;
DMS_alarm = false;
DMS_alarmTime = -1;
DMS_intelTaken = false;
DMS_exfilActive = false;
DMS_exfilLanded = false;
DMS_exfilBoarded = false;
DMS_exfilHeli = objNull;
DMS_exfilHoldSince = -1;
DMS_player = objNull;
DMS_enemyGroups = [];
DMS_patrolGroup = grpNull;
publicVariable "DMS_intelTaken";

private _cfg = DMS_cfg;

// ---------------------------------------------------------------- site and seeded rolls (fixed draw order)
private _sites = _cfg get "sites";
private _siteParam = ["DMS_site", 0] call BIS_fnc_getParamValue;
private _site = ["PICK", _sites] call DMS_fnc_rng;
if (_siteParam > 0 && {_siteParam <= count _sites}) then { _site = _sites select (_siteParam - 1); };
_site params ["_siteName", "_siteXY", "_siteDir", "_startBearing", "_qrfXY", "_qrfNames", ["_siteMode", "BUILD"]];
DMS_siteName = _siteName;
DMS_startBearing = _startBearing;
DMS_siteMode = _siteMode;
DMS_compoundCenter = if (_siteMode == "OUTPOST") then {
	[_siteXY select 0, _siteXY select 1, 0]
} else {
	["FLAT", [_siteXY, 0, _cfg get "siteSnapRadius", _cfg get "clearRadius"]] call DMS_fnc_findPos
};
DMS_start = ["FLAT", [DMS_compoundCenter getPos [_startDist, _startBearing], 0, (_startDist * 0.15) min 150, 10]] call DMS_fnc_findPos;
DMS_lz = ["FLAT", [DMS_compoundCenter getPos [_lzDist, _startBearing], 0, (_lzDist * 0.4) min 150, 25, true]] call DMS_fnc_findPos;

private _w1 = ["INT", [0, 1]] call DMS_fnc_rng;
DMS_rolls = createHashMapFromArray [
	["wave1Spawn", ["ROAD", [_qrfXY select _w1, 400]] call DMS_fnc_findPos],
	["wave1SpawnName", _qrfNames select _w1],
	["wave2Spawn", ["ROAD", [_qrfXY select (1 - _w1), 400]] call DMS_fnc_findPos],
	["wave2SpawnName", _qrfNames select (1 - _w1)],
	["wave1Delay", ["RANGE", _cfg get "wave1Delay"] call DMS_fnc_rng],
	["wave2Delay", ["RANGE", _cfg get "wave2Delay"] call DMS_fnc_rng]
];
[format ["Start: seed=%1 site='%2' mode=%8 center=%3 start=%4 lz=%5 debug=%6 test=%7",
	DMS_seed, _siteName, DMS_compoundCenter, DMS_start, DMS_lz, DMS_debug, DMS_testMode, _siteMode]] call DMS_fnc_log;
if (DMS_testMode) then { [format ["Test: timeScale=%1 startDist=%2 lzDist=%3 assist=%4 force=%5", DMS_timeScale, round _startDist, round _lzDist, DMS_testAssist, DMS_testForce]] call DMS_fnc_log; };
[format ["Rolls: wave1 from %1 after %2 s, wave2 from %3 after +%4 s",
	DMS_rolls get "wave1SpawnName", round (DMS_rolls get "wave1Delay"),
	DMS_rolls get "wave2SpawnName", round (DMS_rolls get "wave2Delay")]] call DMS_fnc_log;

// ---------------------------------------------------------------- squad
private _sqClasses = +(_cfg get "squadClasses");
if (DMS_testMode) then {
	// SP/hosted test: park the local player out of the way; the AI squad does the work.
	if (hasInterface && {!isNull player}) then {
		private _pl = player;
		[_pl] joinSilent (createGroup [west, true]);
		_pl allowDamage false;
		_pl setCaptive true;
		hideObjectGlobal _pl;
		_pl setPosATL (DMS_start getPos [30, _startBearing]);
	};
	DMS_squad = createGroup [west, true];
	_sqClasses = [_cfg get "squadLeaderClass"] + _sqClasses;
} else {
	if (isMultiplayer) then {
		waitUntil { sleep 1; (allPlayers - (entities "HeadlessClient_F")) isNotEqualTo [] };
		DMS_player = (allPlayers - (entities "HeadlessClient_F")) select 0;
	} else {
		DMS_player = player;
	};
	DMS_squad = group DMS_player;
};
{
	private _u = DMS_squad createUnit [_x, DMS_start, [], 5, "NONE"];
	_u setSkill (_cfg get "squadSkill");
} forEach _sqClasses;
DMS_squad setFormation "WEDGE";
DMS_squad setBehaviour "AWARE";

private _face = DMS_start getDir DMS_compoundCenter;
{
	private _p = (DMS_start getPos [4 * floor (_forEachIndex / 2), _face + 180]) getPos [[-3, 3] select (_forEachIndex mod 2), _face + 90];
	[_x, [_p select 0, _p select 1, 0]] remoteExecCall ["setPosATL", _x];
	[_x, _face] remoteExecCall ["setDir", _x];
} forEach (units DMS_squad);
if (DMS_testMode && {hasInterface} && {!isNull player}) then { (leader DMS_squad) switchCamera "EXTERNAL"; };

// ---------------------------------------------------------------- compound, intel, task, markers
[DMS_compoundCenter, _siteDir, _siteMode] call DMS_fnc_spawnCompound;
["INIT", [DMS_intel]] call DMS_fnc_intel;
createVehicle ["Land_HelipadEmpty_F", DMS_lz, [], 0, "CAN_COLLIDE"];

private _fuzz = DMS_compoundCenter getPos [["RANGE", _cfg get "aoMarkerFuzz"] call DMS_fnc_rng, ["RANGE", [0, 360]] call DMS_fnc_rng];
private _mk = createMarker ["DMS_mk_ao", _fuzz];
_mk setMarkerShape "ELLIPSE";
_mk setMarkerSize [_cfg get "aoMarkerRadius", _cfg get "aoMarkerRadius"];
_mk setMarkerBrush "FDiagonal";
_mk setMarkerColor "ColorOPFOR";

[true, "DMS_t_intel",
	["A CSAT detachment holds a small compound inside the marked area. Clear it and retrieve the intel (laptop). Expect a reaction force once they know you are there.", "Retrieve the intel", ""],
	objNull, "ASSIGNED", 1, true, "documents"] call BIS_fnc_taskCreate;

if (DMS_debug) then {
	{
		private _dm = createMarker [format ["DMS_dbg_%1", _forEachIndex], getPosATL _x];
		_dm setMarkerType "mil_dot";
		_dm setMarkerColor "ColorRed";
	} forEach DMS_garrison;
	{
		private _qm = createMarker [format ["DMS_dbg_qrf_%1", _forEachIndex], DMS_rolls get _x];
		_qm setMarkerType "mil_start";
		_qm setMarkerText _x;
	} forEach ["wave1Spawn", "wave2Spawn"];
};

// ---------------------------------------------------------------- support, alarm, fail monitor, test harness
[] spawn {
	sleep 5;
	["INIT"] call DMS_fnc_support;
};
["MONITOR"] spawn DMS_fnc_qrf;

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
