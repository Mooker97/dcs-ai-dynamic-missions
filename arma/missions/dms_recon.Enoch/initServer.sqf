/*
	initServer.sqf - DMS "Recon and Strike": server-authoritative setup and fail monitor.
	Flow: params + seed -> mod check -> battery site (seeded, snapped to a forest hide) -> start, pickup,
	      search box, QRF spawn points -> recon team -> battery, guard, patrols -> task + markers
	      -> fire-support menu, alarm monitor, BDA/exfil monitor, battery fire -> (test harness).
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
DMS_testForce = ["DMS_testForce", 0] call BIS_fnc_getParamValue; // 1 = kill the team right after the first report
publicVariable "DMS_debug";

private _seedParam = ["DMS_seed", 0] call BIS_fnc_getParamValue;
if (_seedParam <= 0) then { _seedParam = 1 + floor (random 99999); }; // dms-allow-random (seed 0 = pick one, it is logged)
DMS_seed = ["SEED", _seedParam] call DMS_fnc_rng;

DMS_over = false;
DMS_alarm = false;
DMS_alarmTime = -1;
DMS_siteName = "none";
DMS_siteNeutralized = false;
DMS_neutralizedTime = -1;
DMS_bdaDone = false;
DMS_bdaByStrike = false;
DMS_bdaReportedStrike = 0;
DMS_strikesLeft = 0;
DMS_strikesLanded = 0;
DMS_strikeBusy = false;
DMS_pickupSince = -1;
DMS_player = objNull;
DMS_team = grpNull;
DMS_qrfGroup = grpNull;
DMS_batteryGroup = grpNull;
DMS_enemyGroups = [];
DMS_tubes = [];
DMS_garrison = [];
DMS_siteObjects = [];

// ---------------------------------------------------------------- required mods (CfgPatches)
private _required = [["CBA", "cba_main"], ["ACE", "ace_main"], ["LAMBS Danger", "lambs_danger"], ["LAMBS waypoints", "lambs_wp"],
	["RHS AFRF", "rhs_main"], ["RHS USAF", "rhsusf_main"]];
private _optional = [["ACE medical", "ace_medical"], ["RHS GREF", "rhsgref_main"], ["RHS SAF", "rhssaf_main"]];
private _loaded = (_required + _optional) select {isClass (configFile >> "CfgPatches" >> (_x select 1))} apply {_x select 0};
private _missing = (_required select {!isClass (configFile >> "CfgPatches" >> (_x select 1))}) apply {_x select 0};
[format ["Mods: %1", [_loaded joinString ", ", "none"] select (_loaded isEqualTo [])]] call DMS_fnc_log;
if (_missing isNotEqualTo []) exitWith {
	private _msg = format ["Required mods missing: %1. Load CBA_A3, ACE, LAMBS_Danger, RHSAFRF and RHSUSAF.", _missing joinString ", "];
	[_msg, "WARN"] call DMS_fnc_log;
	_msg remoteExecCall ["hint", 0];
	if (DMS_testMode) then { ["CHECK", ["mods", false, _missing joinString ", "]] call DMS_fnc_testMode; };
	["DMS_FailMods", false, format ["missing mods: %1", _missing joinString ", "]] call DMS_fnc_end;
	["initServer done (mods missing)"] call DMS_fnc_log;
};
if (DMS_testMode) then { ["CHECK", ["mods", true, _loaded joinString ", "]] call DMS_fnc_testMode; };

// ---------------------------------------------------------------- site and seeded rolls (fixed draw order)
private _sites = _cfg get "sites";
private _siteParam = ["DMS_site", 0] call BIS_fnc_getParamValue;
private _site = ["PICK", _sites] call DMS_fnc_rng;
if (_siteParam > 0 && {_siteParam <= count _sites}) then { _site = _sites select (_siteParam - 1); };
_site params ["_siteName", "_anchor", "_startBearing"];
DMS_siteName = _siteName;
DMS_startBearing = _startBearing;
(["FOREST", [_anchor, _cfg get "siteSearchRadius"]] call DMS_fnc_findPos) params ["_center", "_forestScore"];
DMS_siteCenter = _center;
private _fireDir = (_startBearing + 180 + (["RANGE", [-30, 30]] call DMS_fnc_rng)) mod 360;
DMS_harassTarget = ["CLAMP", [_center getPos [_cfg get "harassRange", _fireDir]]] call DMS_fnc_findPos;

DMS_start = ["FLAT", [["CLAMP", [_center getPos [_startDist, _startBearing]]] call DMS_fnc_findPos, 0, (_startDist * 0.1) min 200, 10]] call DMS_fnc_findPos;
private _side = [-1, 1] select (["CHANCE", 0.5] call DMS_fnc_rng);
private _pickBrg = _startBearing + _side * (["RANGE", _cfg get "pickupBearingOffset"] call DMS_fnc_rng);
DMS_pickup = ["FLAT", [["CLAMP", [_center getPos [_cfg get "pickupDistance", _pickBrg]]] call DMS_fnc_findPos, 0, 250, 20, true]] call DMS_fnc_findPos;
private _boxCenter = _center getPos [["RANGE", _cfg get "searchBoxFuzz"] call DMS_fnc_rng, ["RANGE", [0, 360]] call DMS_fnc_rng];
private _qrfA = ["CLAMP", [_center getPos [_cfg get "qrfDistance", _startBearing + 180 + (["RANGE", [-40, 40]] call DMS_fnc_rng)]]] call DMS_fnc_findPos;
private _qrfB = ["CLAMP", [_center getPos [_cfg get "qrfDistance", _startBearing - _side * 90]]] call DMS_fnc_findPos;
DMS_qrfSpawn = ["ROAD", [_qrfA, 400]] call DMS_fnc_findPos;
DMS_qrfSpawnAlt = ["ROAD", [_qrfB, 400]] call DMS_fnc_findPos;

private _near = nearestLocations [_center, ["NameCity", "NameVillage", "NameLocal", "Hill"], 4000, _center];
private _nearText = if (_near isEqualTo []) then { "none within 4 km" } else {
	format ["%1 (%2 m)", text (_near select 0), round ((locationPosition (_near select 0)) distance2D _center)]
};
[format ["Start: seed=%1 site='%2' anchor=%3 battery=%4 grid %5 forestScore=%6 nearest=%7 start=%8 pickup=%9 debug=%10 test=%11",
	DMS_seed, _siteName, _anchor, _center, mapGridPosition _center, round _forestScore, _nearText, DMS_start, DMS_pickup, DMS_debug, DMS_testMode]] call DMS_fnc_log;
[format ["Rolls: fireDir=%1 harassTarget=%2 pickupBearing=%3 qrfSpawn=%4 qrfSpawnAlt=%5 boxCentre=%6",
	round _fireDir, mapGridPosition DMS_harassTarget, round (_pickBrg mod 360), mapGridPosition DMS_qrfSpawn, mapGridPosition DMS_qrfSpawnAlt, mapGridPosition _boxCenter]] call DMS_fnc_log;
if (DMS_testMode) then { [format ["Test: timeScale=%1 startDist=%2 assist=%3 force=%4", DMS_timeScale, round _startDist, DMS_testAssist, DMS_testForce]] call DMS_fnc_log; };

// ---------------------------------------------------------------- recon team
private _giveLaser = {
	params ["_u"];
	private _old = binocular _u;
	if (_old != "") then { _u removeWeapon _old; };
	_u addMagazine (DMS_cfg get "leaderDesignatorBattery");
	_u addWeapon (DMS_cfg get "leaderDesignator");
};
private _classes = +(_cfg get "teamClasses");
if (DMS_testMode) then {
	// SP/hosted test: park the local player out of the way; the AI team does the work.
	if (hasInterface && {!isNull player}) then {
		private _pl = player;
		[_pl] joinSilent (createGroup [west, true]);
		_pl allowDamage false;
		_pl setCaptive true;
		hideObjectGlobal _pl;
		_pl setPosATL (DMS_start getPos [30, _startBearing]);
	};
	DMS_team = createGroup [west, true];
	_classes = [_cfg get "teamLeaderClass"] + _classes;
} else {
	if (isMultiplayer) then {
		waitUntil { sleep 1; (allPlayers - (entities "HeadlessClient_F")) isNotEqualTo [] };
		DMS_player = (allPlayers - (entities "HeadlessClient_F")) select 0;
	} else {
		DMS_player = player;
	};
	DMS_team = group DMS_player;
};
{
	private _u = DMS_team createUnit [_x, DMS_start, [], 5, "NONE"];
	_u setSkill (_cfg get "teamSkill");
} forEach _classes;
if (DMS_testMode) then { [leader DMS_team] call _giveLaser; };
DMS_team setFormation "STAG COLUMN";
DMS_team setBehaviour "AWARE";

private _face = DMS_start getDir _boxCenter;
{
	private _p = (DMS_start getPos [4 * floor (_forEachIndex / 2), _face + 180]) getPos [[-3, 3] select (_forEachIndex mod 2), _face + 90];
	[_x, [_p select 0, _p select 1, 0]] remoteExecCall ["setPosATL", _x];
	[_x, _face] remoteExecCall ["setDir", _x];
} forEach (units DMS_team);
if (DMS_testMode && {hasInterface} && {!isNull player}) then { (leader DMS_team) switchCamera "EXTERNAL"; };

// ---------------------------------------------------------------- battery, task, markers
["SPAWN", [_center, _fireDir]] call DMS_fnc_site;

private _box = (_cfg get "searchBoxSize") / 2;
private _mk = createMarker ["DMS_mk_box", _boxCenter];
_mk setMarkerShape "RECTANGLE";
_mk setMarkerSize [_box, _box];
_mk setMarkerBrush "Border";
_mk setMarkerColor "ColorOPFOR";
private _mkT = createMarker ["DMS_mk_box_label", _boxCenter getPos [_box, 0]];
_mkT setMarkerType "hd_unknown";
_mkT setMarkerColor "ColorOPFOR";
_mkT setMarkerText "Search area";

[true, "DMS_t_find",
	["A Russian 82 mm mortar battery (3 tubes) is hiding in the forest inside the search area. Find it without being seen, report it for a fire mission (laser spot or cursor/map position: the rounds land where you report), and confirm the kill by observation.", "Find and strike the battery", ""],
	objNull, "ASSIGNED", 1, true, "destroy"] call BIS_fnc_taskCreate;

if (DMS_debug) then {
	private _dm = createMarker ["DMS_dbg_battery", _center];
	_dm setMarkerType "mil_destroy";
	_dm setMarkerColor "ColorRed";
	_dm setMarkerText "battery";
	{
		private _qm = createMarker [format ["DMS_dbg_qrf_%1", _forEachIndex], _x];
		_qm setMarkerType "mil_start";
		_qm setMarkerText "QRF";
	} forEach [DMS_qrfSpawn, DMS_qrfSpawnAlt];
};

// ---------------------------------------------------------------- support, monitors, fail monitor, test harness
[] spawn {
	sleep 5;
	["INIT"] call DMS_fnc_strike;
};
["MONITOR"] spawn DMS_fnc_alarm;
["MONITOR"] spawn DMS_fnc_bda;
["HARASS"] spawn DMS_fnc_site;

[] spawn {
	waitUntil {
		sleep 2;
		DMS_over || {!isNull DMS_player && {!alive DMS_player}} || {({alive _x} count (units DMS_team)) == 0}
	};
	if (DMS_over) exitWith {};
	if (!isNull DMS_player && {!alive DMS_player}) then {
		["DMS_FailDead", false, "player killed"] call DMS_fnc_end;
	} else {
		["DMS_FailDead", false, "team wiped out"] call DMS_fnc_end;
	};
};

if (DMS_testMode) then { ["RUN"] spawn DMS_fnc_testMode; };
["initServer done"] call DMS_fnc_log;
