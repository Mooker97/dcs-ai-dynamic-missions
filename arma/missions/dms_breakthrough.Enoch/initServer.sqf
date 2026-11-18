/*
	initServer.sqf - DMS "Breakthrough": server-authoritative setup.
	Flow: params + seed -> mod check -> site + seeded layout (crossroads, treeline, ATGM, BMP, phase line)
	      -> tank (player in the commander's seat) -> Bradley section -> enemy -> markers, task, briefing data
	      -> A-10 menu -> monitors (tank/fail, contact, section follow + losses, objective, counter-attack) -> (test harness).
*/
DMS_cfg = call DMS_fnc_config;
DMS_debug = (["DMS_debug", 0] call BIS_fnc_getParamValue) == 1;
DMS_testMode = (["DMS_testMode", 0] call BIS_fnc_getParamValue) == 1;
DMS_testMinutes = ["DMS_testMinutes", 45] call BIS_fnc_getParamValue;
DMS_timeScale = 1;
if (DMS_testMode) then { DMS_timeScale = ((["DMS_testTimeScale", 100] call BIS_fnc_getParamValue) max 1) / 100; };
private _startDist = 0;
DMS_testAssist = 0;
DMS_testAssisted = 0;
if (DMS_testMode) then {
	private _sd = ["DMS_testStartDist", 0] call BIS_fnc_getParamValue;
	if (_sd >= 1500) then { _startDist = _sd; }; // shorter runs must still pass the treeline
	DMS_testAssist = ["DMS_testAssist", 0] call BIS_fnc_getParamValue;
};
DMS_testForce = ["DMS_testForce", 0] call BIS_fnc_getParamValue; // 1 = tank destroyed after first contact
publicVariable "DMS_debug";

private _seedParam = ["DMS_seed", 0] call BIS_fnc_getParamValue;
if (_seedParam <= 0) then { _seedParam = 1 + floor (random 99999); }; // dms-allow-random (seed 0 = pick one, it is logged)
DMS_seed = ["SEED", _seedParam] call DMS_fnc_rng;

DMS_over = false;
DMS_siteName = "";
DMS_player = objNull;
DMS_tank = objNull;
DMS_tankGroup = grpNull;
DMS_contact = false;
DMS_contactTime = -1;
DMS_plCrossed = false;
DMS_plTime = -1;
DMS_ifvs = [];
DMS_inf = grpNull;
DMS_dismounted = false;
DMS_followSamples = [];
DMS_treeline = [];
DMS_villageArmour = [];
DMS_counterSpawned = false;
publicVariable "DMS_contact";

private _cfg = DMS_cfg;

// ---------------------------------------------------------------- required mods
private _missing = call DMS_fnc_mods;
if (_missing isNotEqualTo []) exitWith {
	private _msg = format ["DMS Breakthrough needs these mods: %1. Load CBA_A3, ACE, LAMBS Danger, RHS AFRF and RHS USAF.", _missing joinString ", "];
	[_msg] spawn {
		params ["_msg"];
		sleep 2;
		_msg remoteExecCall ["hint", 0];
	};
	["DMS_FailMods", false, format ["missing mods: %1", _missing joinString ", "]] call DMS_fnc_end;
};
private _classes = [_cfg get "playerLoadoutClass", _cfg get "infLeaderClass", _cfg get "villageLeaderClass"] + (_cfg get "tankClasses") + (_cfg get "ifvClasses")
	+ (_cfg get "infClasses") + (_cfg get "treelineTankClasses") + (_cfg get "atgmClasses") + (_cfg get "atgmTeam") + (_cfg get "villageIfvClasses")
	+ (_cfg get "villageInfClasses") + (_cfg get "villageAtTeam") + (_cfg get "counterTankClasses") + (_cfg get "counterIfvClasses") + (_cfg get "casClasses");
private _bad = (_classes arrayIntersect _classes) select {!isClass (configFile >> "CfgVehicles" >> _x)};
if (_bad isNotEqualTo []) then { [format ["Missing classes (fallbacks used where listed): %1", _bad], "WARN"] call DMS_fnc_log; };

// ---------------------------------------------------------------- site and seeded layout (fixed draw order)
private _sites = _cfg get "sites";
private _siteParam = ["DMS_site", 0] call BIS_fnc_getParamValue;
private _site = ["PICK", _sites] call DMS_fnc_rng;
if (_siteParam > 0 && {_siteParam <= count _sites}) then { _site = _sites select (_siteParam - 1); };
DMS_siteName = _site select 0;
DMS_layout = ["LAYOUT", [_site, _startDist]] call DMS_fnc_site;
private _xr = DMS_layout get "crossroads";
private _start = DMS_layout get "start";
private _compass = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"] select ((round ((DMS_layout get "rear") / 45)) mod 8); // where the attack comes from

[format ["Start: seed=%1 site='%2' crossroads=%3 start=%4 (%5 m to go by road, %6 m straight) phaseLine=%7 debug=%8 test=%9",
	DMS_seed, DMS_siteName, _xr apply {round _x}, _start apply {round _x}, round ((DMS_layout get "toGo") select (DMS_layout get "startIndex")),
	round (_start distance2D _xr), (DMS_layout get "phaseLine") apply {round _x}, DMS_debug, DMS_testMode]] call DMS_fnc_log;
[format ["Layout: crossroads %1 m from the village point, treeline %2 (side %3), ATGM %4 (side %5), BMP %6, counter-attack from %7",
	round (_xr distance2D (DMS_layout get "village")), (DMS_layout get "treeline") apply {(_x select 0) apply {round _x}}, DMS_layout get "treelineSide",
	((DMS_layout get "atgm") select 0) apply {round _x}, DMS_layout get "atgmSide", ((DMS_layout get "bmp") select 0) apply {round _x},
	(DMS_layout get "counter") apply {round _x}]] call DMS_fnc_log;
if (DMS_testMode) then { [format ["Test: timeScale=%1 startDist=%2 assist=%3 force=%4", DMS_timeScale, _startDist, DMS_testAssist, DMS_testForce]] call DMS_fnc_log; };

// ---------------------------------------------------------------- player and tank
if (DMS_testMode) then {
	// SP/hosted test: park the local player out of the way; the AI tank does the work.
	if (hasInterface && {!isNull player}) then {
		private _pl = player;
		[_pl] joinSilent (createGroup [west, true]);
		_pl allowDamage false;
		_pl setCaptive true;
		hideObjectGlobal _pl;
		_pl setPosATL (_start getPos [60, (DMS_layout get "startDir") + 90]);
	};
} else {
	if (isMultiplayer) then {
		private _tw = time;
		waitUntil { sleep 1; ((allPlayers - (entities "HeadlessClient_F")) isNotEqualTo []) || {time - _tw > 600} };
		DMS_player = (allPlayers - (entities "HeadlessClient_F")) param [0, objNull];
	} else {
		DMS_player = player;
	};
};
private _route = DMS_layout get "route";
private _tank = ["INIT", [_start, DMS_layout get "startDir"]] call DMS_fnc_tank;
if (isNull _tank) exitWith { ["DMS_FailSetup", false, "no tank class exists"] call DMS_fnc_end; };
if (DMS_testMode && {hasInterface} && {!isNull player}) then { _tank switchCamera "EXTERNAL"; };

// ---------------------------------------------------------------- friendly section, enemy
["INIT"] call DMS_fnc_section;
["INIT"] call DMS_fnc_enemy;

// ---------------------------------------------------------------- markers, task, briefing data (fuzzed: no enemy positions)
private _fz = DMS_layout get "objFuzz";
private _mkO = createMarker ["DMS_mk_obj", _fz];
_mkO setMarkerShape "ELLIPSE";
_mkO setMarkerSize [_cfg get "objMarkerRadius", _cfg get "objMarkerRadius"];
_mkO setMarkerBrush "FDiagonal";
_mkO setMarkerColor "ColorOPFOR";
private _mkOT = createMarker ["DMS_mk_obj_t", _fz];
_mkOT setMarkerType "hd_objective";
_mkOT setMarkerColor "ColorOPFOR";
_mkOT setMarkerText "OBJ crossroads";
private _mkPl = createMarker ["DMS_mk_pl", DMS_layout get "phaseLine"];
_mkPl setMarkerType "hd_flag";
_mkPl setMarkerColor "ColorBLUFOR";
_mkPl setMarkerText "PL BLUE";
private _mkSt = createMarker ["DMS_mk_start", _start];
_mkSt setMarkerType "hd_start";
_mkSt setMarkerColor "ColorBLUFOR";
_mkSt setMarkerText "LD";

private _vname = (DMS_siteName splitString ",") select 0;
[true, "DMS_t_village",
	[format ["Advance from the line of departure, break through the Russian screen and take the crossroads in %1. Destroy the armour in the village and let the infantry clear it, or hold the crossroads with no enemy armour left.", _vname], format ["Take %1 crossroads", _vname], ""],
	_fz, "ASSIGNED", 1, true, "attack"] call BIS_fnc_taskCreate;

DMS_brief = [DMS_siteName, _compass, round (_start distance2D _xr), _cfg get "casUses", _cfg get "phaseLineDistance"];
publicVariable "DMS_brief";

if (DMS_debug) then {
	{
		private _dm = createMarker [format ["DMS_dbg_rt_%1", _forEachIndex], _x];
		_dm setMarkerType "mil_dot";
		_dm setMarkerColor "ColorBlue";
		_dm setMarkerText str _forEachIndex;
	} forEach _route;
};

// ---------------------------------------------------------------- support and monitors
[] spawn {
	sleep 5;
	["INIT"] call DMS_fnc_air;
};
["MONITOR"] spawn DMS_fnc_tank;
["WATCH"] spawn DMS_fnc_enemy;
["SCHEDULE"] spawn DMS_fnc_enemy;
["FOLLOW"] spawn DMS_fnc_section;
["LOSSES"] spawn DMS_fnc_section;
[] spawn DMS_fnc_objective;

if (DMS_testMode) then { ["RUN"] spawn DMS_fnc_testMode; };
["initServer done"] call DMS_fnc_log;
