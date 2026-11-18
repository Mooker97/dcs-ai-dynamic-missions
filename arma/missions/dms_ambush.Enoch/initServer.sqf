/*
	initServer.sqf - DMS "Ambush": server-authoritative setup and fail monitor.
	Flow: params + seed -> mod check -> site + seeded rolls -> road trace, kill zone, ambush position, start, RP
	      -> squad on foot ~800 m out (hold fire) -> RP vehicles, markers, task, briefing data -> mortar menu
	      -> convoy schedule -> fail monitor -> (test harness).
*/
DMS_cfg = call DMS_fnc_config;
DMS_debug = (["DMS_debug", 0] call BIS_fnc_getParamValue) == 1;
DMS_testMode = (["DMS_testMode", 0] call BIS_fnc_getParamValue) == 1;
DMS_testMinutes = ["DMS_testMinutes", 45] call BIS_fnc_getParamValue;
DMS_timeScale = 1;
if (DMS_testMode) then { DMS_timeScale = ((["DMS_testTimeScale", 100] call BIS_fnc_getParamValue) max 1) / 100; };
private _startDist = DMS_cfg get "startDistance";
DMS_testAssist = 0;
if (DMS_testMode) then {
	private _sd = ["DMS_testStartDist", 0] call BIS_fnc_getParamValue;
	if (_sd > 0) then { _startDist = _sd; };
	DMS_testAssist = ["DMS_testAssist", 0] call BIS_fnc_getParamValue;
};
DMS_testForce = ["DMS_testForce", 0] call BIS_fnc_getParamValue; // 1 = convoy escapes, 2 = squad wiped
publicVariable "DMS_debug";

private _seedParam = ["DMS_seed", 0] call BIS_fnc_getParamValue;
if (_seedParam <= 0) then { _seedParam = 1 + floor (random 99999); }; // dms-allow-random (seed 0 = pick one, it is logged)
DMS_seed = ["SEED", _seedParam] call DMS_fnc_rng;

DMS_over = false;
DMS_siteName = "";
DMS_player = objNull;
DMS_squad = grpNull;
DMS_contact = false;
DMS_contactTime = -1;
DMS_convoySpawned = false;
DMS_convoyIneffective = false;
DMS_convoy = [];
DMS_convoyGroup = grpNull;
DMS_convoyMen = [];
DMS_convoyStartMen = 0;
DMS_rpActive = false;
DMS_rpVehicles = [];
publicVariable "DMS_contact";
publicVariable "DMS_convoySpawned";

private _cfg = DMS_cfg;

// ---------------------------------------------------------------- required mods
private _missing = call DMS_fnc_mods;
if (_missing isNotEqualTo []) exitWith {
	private _msg = format ["DMS Ambush needs these mods: %1. Load CBA_A3, ACE, LAMBS Danger, RHS AFRF and RHS USAF.", _missing joinString ", "];
	[_msg] spawn {
		params ["_msg"];
		sleep 2;
		_msg remoteExecCall ["hint", 0];
	};
	["DMS_FailMods", false, format ["missing mods: %1", _missing joinString ", "]] call DMS_fnc_end;
};

// ---------------------------------------------------------------- site and seeded rolls (fixed draw order)
private _sites = _cfg get "sites";
private _siteParam = ["DMS_site", 0] call BIS_fnc_getParamValue;
private _site = ["PICK", _sites] call DMS_fnc_rng;
if (_siteParam > 0 && {_siteParam <= count _sites}) then { _site = _sites select (_siteParam - 1); };
_site params ["_siteName", "_siteXY"];
DMS_siteName = _siteName;
private _fromForward = ["CHANCE", 0.5] call DMS_fnc_rng;
DMS_rolls = createHashMapFromArray [
	["fromForward", _fromForward],
	["convoyTrucks", ["INT", _cfg get "convoyTrucks"] call DMS_fnc_rng],
	["convoyDelay", ["RANGE", _cfg get "convoyDelay"] call DMS_fnc_rng],
	["windowSkew", ["RANGE", [2, 6]] call DMS_fnc_rng]
];

DMS_route = ["SITE", [_siteXY, _fromForward, _startDist]] call DMS_fnc_route;
if (isNil "DMS_route") exitWith {
	["DMS_FailSetup", false, format ["no usable road near %1", _siteXY]] call DMS_fnc_end;
};
DMS_start = DMS_route get "start";
private _kz = DMS_route get "killZone";
private _ambush = DMS_route get "ambush";
private _inPts = DMS_route get "inPts";
private _fromBrg = _kz getDir (_inPts select ((count _inPts - 1) min 25));
private _compass = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"] select ((round (_fromBrg / 45)) mod 8);

[format ["Start: seed=%1 site='%2' killZone=%3 ambush=%4 start=%5 rp=%6 debug=%7 test=%8",
	DMS_seed, _siteName, _kz, _ambush, DMS_start, DMS_route get "rp", DMS_debug, DMS_testMode]] call DMS_fnc_log;
[format ["Route: snapped %1 m from the site point, road '%2', convoy from the %3 (travel %4 deg), in %5 m, out %6 m, kill line %7, %8 waypoints",
	round (_kz distance2D _siteXY), (getRoadInfo (DMS_route get "road")) select 0, _compass, round (DMS_route get "travelDir"),
	round (DMS_route get "inLength"), round (DMS_route get "outLength"), DMS_route get "killLine", count (DMS_route get "waypoints")]] call DMS_fnc_log;
[format ["Rolls: trucks=%1 convoyDelay=%2 s fromForward=%3", DMS_rolls get "convoyTrucks", round (DMS_rolls get "convoyDelay"), _fromForward]] call DMS_fnc_log;
if (DMS_testMode) then { [format ["Test: timeScale=%1 startDist=%2 assist=%3 force=%4", DMS_timeScale, round _startDist, DMS_testAssist, DMS_testForce]] call DMS_fnc_log; };

// ---------------------------------------------------------------- squad (RHS USMC rifle squad with AT)
private _sqClasses = +(_cfg get "squadClasses");
if (DMS_testMode) then {
	// SP/hosted test: park the local player out of the way; the AI squad does the work.
	if (hasInterface && {!isNull player}) then {
		private _pl = player;
		[_pl] joinSilent (createGroup [west, true]);
		_pl allowDamage false;
		_pl setCaptive true;
		hideObjectGlobal _pl;
		_pl setPosATL (DMS_start getPos [30, DMS_route get "awayDir"]);
	};
	DMS_squad = createGroup [west, true];
	_sqClasses = [_cfg get "squadLeaderClass"] + _sqClasses;
} else {
	if (isMultiplayer) then {
		private _tw = time;
		waitUntil { sleep 1; ((allPlayers - (entities "HeadlessClient_F")) isNotEqualTo []) || {time - _tw > 600} };
		DMS_player = (allPlayers - (entities "HeadlessClient_F")) param [0, objNull];
	} else {
		DMS_player = player;
	};
	DMS_squad = group DMS_player;
	// The slot is a vanilla team leader (no RHS dependency in mission.sqm); give it the RHS USMC loadout.
	private _tmp = (createGroup [west, true]) createUnit [_cfg get "squadLeaderClass", [0, 0, 0], [], 0, "CAN_COLLIDE"];
	private _loadout = getUnitLoadout _tmp;
	private _tmpGrp = group _tmp;
	deleteVehicle _tmp;
	deleteGroup _tmpGrp;
	if (!isNull DMS_player) then { [DMS_player, _loadout] remoteExecCall ["setUnitLoadout", DMS_player]; };
};
{
	private _u = DMS_squad createUnit [_x, DMS_start, [], 5, "NONE"];
	_u setSkill (_cfg get "squadSkill");
} forEach _sqClasses;
DMS_squad setFormation "WEDGE";
DMS_squad setBehaviour "AWARE";
// Hold fire until the ambush is sprung (DMS_fnc_convoy CONTACT sets YELLOW). The player can override.
[DMS_squad, "GREEN"] remoteExecCall ["setCombatMode", leader DMS_squad];

private _face = DMS_start getDir _ambush;
{
	private _p = (DMS_start getPos [4 * floor (_forEachIndex / 2), _face + 180]) getPos [[-3, 3] select (_forEachIndex mod 2), _face + 90];
	[_x, [_p select 0, _p select 1, 0]] remoteExecCall ["setPosATL", _x];
	[_x, _face] remoteExecCall ["setDir", _x];
} forEach (units DMS_squad);
if (DMS_testMode && {hasInterface} && {!isNull player}) then { (leader DMS_squad) switchCamera "EXTERNAL"; };
[format ["Squad: %1 units at %2, %3 m from the ambush position", count (units DMS_squad), DMS_start, round (DMS_start distance2D _ambush)]] call DMS_fnc_log;

// ---------------------------------------------------------------- rally point, markers, task, briefing data
["INIT"] call DMS_fnc_rp;

private _mkKz = createMarker ["DMS_mk_kz", _kz];
_mkKz setMarkerShape "ELLIPSE";
_mkKz setMarkerSize [_cfg get "killZoneMarkerRadius", _cfg get "killZoneMarkerRadius"];
_mkKz setMarkerBrush "FDiagonal";
_mkKz setMarkerColor "ColorOPFOR";
private _mkKzT = createMarker ["DMS_mk_kz_t", _kz];
_mkKzT setMarkerType "hd_objective";
_mkKzT setMarkerColor "ColorOPFOR";
_mkKzT setMarkerText "Kill zone";
private _mkAm = createMarker ["DMS_mk_ambush", _ambush];
_mkAm setMarkerType "hd_ambush";
_mkAm setMarkerColor "ColorBLUFOR";
_mkAm setMarkerText "Ambush position";
private _mkKl = createMarker ["DMS_mk_killline", DMS_route get "killLine"];
_mkKl setMarkerType "hd_end";
_mkKl setMarkerColor "ColorOPFOR";
_mkKl setMarkerText "Kill line";

[true, "DMS_t_ambush",
	[format ["A Russian motor-rifle convoy will use this road, coming from the %1. Set up on the marked ambush position, spring the ambush in the kill zone and destroy the convoy before it gets past the kill line.", _compass], "Ambush the convoy", ""],
	_kz, "ASSIGNED", 1, true, "destroy"] call BIS_fnc_taskCreate;

private _hhmm = {
	params ["_h"];
	_h = (_h + 24) mod 24;
	private _hh = floor _h;
	private _mm = floor ((_h - _hh) * 60);
	format ["%1%2:%3%4", ["", "0"] select (_hh < 10), _hh, ["", "0"] select (_mm < 10), _mm]
};
private _eta = (DMS_rolls get "convoyDelay") + (_cfg get "entryDistance") / (_cfg get "convoyEtaSpeed");
private _w0 = dayTime + ((_eta / 60) - (DMS_rolls get "windowSkew")) / 60;
DMS_brief = [_siteName, _compass, [_w0] call _hhmm, [_w0 + 10 / 60] call _hhmm, _cfg get "artyMissions", _cfg get "artySpotRounds", _cfg get "artyRoundsFFE"];
publicVariable "DMS_brief";

if (DMS_debug) then {
	{
		private _dm = createMarker [format ["DMS_dbg_wp_%1", _forEachIndex], _x];
		_dm setMarkerType "mil_dot";
		_dm setMarkerColor "ColorRed";
		_dm setMarkerText str _forEachIndex;
	} forEach (DMS_route get "waypoints");
};

// ---------------------------------------------------------------- support, convoy, fail monitor, test harness
[] spawn {
	sleep 5;
	["INIT"] call DMS_fnc_support;
};
["SCHEDULE"] spawn DMS_fnc_convoy;

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
