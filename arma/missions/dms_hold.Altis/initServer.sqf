/*
	initServer.sqf - DMS "Hold the OP": server-authoritative setup and fail monitor.
	Flow: params + seed -> mod check -> site -> wave plan (seeded, fixed draw order) -> squad + static at
	      the OP -> task + marker -> mortar and air menus -> fail monitors -> director -> (test harness).
*/
DMS_cfg = call DMS_fnc_config;
DMS_debug = (["DMS_debug", 0] call BIS_fnc_getParamValue) == 1;
DMS_testMode = (["DMS_testMode", 0] call BIS_fnc_getParamValue) == 1;
DMS_testMinutes = ["DMS_testMinutes", 45] call BIS_fnc_getParamValue;
DMS_timeScale = 1;
DMS_testStartDist = 0;
DMS_testAssist = 0;
if (DMS_testMode) then {
	DMS_timeScale = ((["DMS_testTimeScale", 100] call BIS_fnc_getParamValue) max 1) / 100;
	DMS_testStartDist = ["DMS_testStartDist", 0] call BIS_fnc_getParamValue;
	DMS_testAssist = ["DMS_testAssist", 0] call BIS_fnc_getParamValue;
};
DMS_testForce = ["DMS_testForce", 0] call BIS_fnc_getParamValue; // 1 = wipe the squad, 2 = force an overrun
publicVariable "DMS_debug";

private _seedParam = ["DMS_seed", 0] call BIS_fnc_getParamValue;
if (_seedParam <= 0) then { _seedParam = 1 + floor (random 99999); }; // dms-allow-random (seed 0 = pick one, it is logged)
DMS_seed = ["SEED", _seedParam] call DMS_fnc_rng;

DMS_over = false;
DMS_player = objNull;
DMS_squad = grpNull;
DMS_static = objNull;
DMS_staticGunner = objNull;
DMS_enemyGroups = [];
DMS_waves = [];
DMS_wavePlan = [];
DMS_sbfVeh = objNull;
DMS_sbfPos = [0, 0, 0];
DMS_siteName = "none";
DMS_artyMissions = 0;
DMS_airLeft = 0;
DMS_airOnStation = false;

private _cfg = DMS_cfg;

// ---------------------------------------------------------------- player (needed for the mod-failure message too)
if (!DMS_testMode) then {
	if (isMultiplayer) then {
		private _tw = time;
		waitUntil { sleep 1; ((allPlayers - (entities "HeadlessClient_F")) isNotEqualTo []) || {time - _tw > 120} };
		private _pl = allPlayers - (entities "HeadlessClient_F");
		if (_pl isNotEqualTo []) then { DMS_player = _pl select 0; };
	} else {
		DMS_player = player;
	};
};

// ---------------------------------------------------------------- required mods
private _missing = call DMS_fnc_mods;
if (DMS_testMode) then { ["CHECK", ["mods", _missing isEqualTo [], [_missing joinString "; ", "all present"] select (_missing isEqualTo [])]] call DMS_fnc_testMode; };
if (_missing isNotEqualTo []) exitWith {
	private _text = format ["DMS Hold the OP needs CBA_A3, ACE, LAMBS_Danger, RHSAFRF and RHSUSAF.\nMissing:\n%1", _missing joinString "\n"];
	if (!isNull DMS_player) then { _text remoteExecCall ["hint", DMS_player]; };
	["initServer done (mods missing, ending)"] call DMS_fnc_log;
	["DMS_FailMods", false, format ["missing mods: %1", _missing joinString "; "]] call DMS_fnc_end;
};

// ---------------------------------------------------------------- site and seeded plan (fixed draw order)
private _sites = _cfg get "sites";
private _siteParam = ["DMS_site", 0] call BIS_fnc_getParamValue;
private _site = ["PICK", _sites] call DMS_fnc_rng;
if (_siteParam > 0 && {_siteParam <= count _sites}) then { _site = _sites select (_siteParam - 1); };
_site params ["_siteName", "_siteXY", "_rearBearing", "_enemyBearings"];
DMS_siteName = _siteName;
DMS_opCenter = [_siteXY select 0, _siteXY select 1, 0];
DMS_rearBearing = _rearBearing;
DMS_enemyBearings = _enemyBearings;
// threat sector: the mean of the enemy approach bearings (vector mean, so 315 and 45 average to 0)
private _sx = 0;
private _sy = 0;
{ _sx = _sx + sin _x; _sy = _sy + cos _x; } forEach _enemyBearings;
DMS_threatBearing = ((_sx atan2 _sy) + 360) mod 360;

[format ["Start: seed=%1 site='%2' op=%3 rear=%4 threat=%5 debug=%6 test=%7",
	DMS_seed, _siteName, DMS_opCenter, _rearBearing, round DMS_threatBearing, DMS_debug, DMS_testMode]] call DMS_fnc_log;
if (DMS_testMode) then {
	[format ["Test: timeScale=%1 waveDist=%2 assist=%3 force=%4 minutes=%5", DMS_timeScale, DMS_testStartDist, DMS_testAssist, DMS_testForce, DMS_testMinutes]] call DMS_fnc_log;
};
["PLAN"] call DMS_fnc_waves;

// ---------------------------------------------------------------- squad and static gun
if (DMS_testMode) then {
	// SP/hosted test: park the local player out of the way; the AI squad does the work.
	if (hasInterface && {!isNull player}) then {
		private _pl = player;
		[_pl] joinSilent (createGroup [west, true]);
		_pl allowDamage false;
		_pl setCaptive true;
		hideObjectGlobal _pl;
		_pl setPosATL (DMS_opCenter getPos [600, _rearBearing]);
	};
	DMS_squad = createGroup [west, true];
} else {
	DMS_squad = group DMS_player;
};
["SQUAD"] call DMS_fnc_op;
["STATIC"] call DMS_fnc_op;
DMS_squad setFormation "WEDGE";
if (DMS_testMode && {hasInterface} && {!isNull player}) then { (leader DMS_squad) switchCamera "EXTERNAL"; };

// ---------------------------------------------------------------- task and markers
private _mk = createMarker ["DMS_mk_op", DMS_opCenter];
_mk setMarkerShape "ELLIPSE";
_mk setMarkerSize [_cfg get "opMarkerRadius", _cfg get "opMarkerRadius"];
_mk setMarkerBrush "Border";
_mk setMarkerColor "ColorBLUFOR";
private _mt = createMarker ["DMS_mk_op_label", DMS_opCenter];
_mt setMarkerType "b_recon";
_mt setMarkerText "OP";

[true, "DMS_t_hold",
	["Hold the observation post against the Russian motor-rifle attack until the relief element arrives. Mortars and one attack-helicopter sortie are on call (comm menu 0-8). Do not let the enemy take the OP.", "Hold the OP", ""],
	DMS_opCenter, "ASSIGNED", 1, true, "defend"] call BIS_fnc_taskCreate;

if (DMS_debug) then {
	private _dm = createMarker ["DMS_dbg_sbf", DMS_sbfPos];
	_dm setMarkerType "mil_triangle";
	_dm setMarkerColor "ColorOPFOR";
	_dm setMarkerText "SBF";
};

// ---------------------------------------------------------------- support, monitors, director, test harness
[] spawn {
	sleep 5;
	["INIT"] call DMS_fnc_support;
	["INIT"] call DMS_fnc_air;
};

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
["OVERRUN"] spawn DMS_fnc_op;
["RUN"] spawn DMS_fnc_waves;

if (DMS_testMode) then { [] spawn { sleep 6; ["RUN"] spawn DMS_fnc_testMode; }; };
["initServer done"] call DMS_fnc_log;
