/*
	initServer.sqf - DMS "Base life": the player (or the test squad) starts at a real Altis base
	with an ambient "base life" site (arma/modules/ambient, functions DMSA_fnc_*).
	Normal play: walk around; leave beyond 900 m for 30 s and the activity is removed, come back
	and it returns. Test mode: fn_testMode drives the activate -> despawn -> reactivate cycle.
*/
DMS_cfg = call DMS_fnc_config;
DMS_debug = (["DMS_debug", 0] call BIS_fnc_getParamValue) == 1;
DMS_testMode = (["DMS_testMode", 0] call BIS_fnc_getParamValue) == 1;
DMS_testMinutes = ["DMS_testMinutes", 20] call BIS_fnc_getParamValue;
DMSA_debug = DMS_debug;
publicVariable "DMS_debug";
DMS_over = false;

private _seedParam = ["DMS_seed", 0] call BIS_fnc_getParamValue;
if (_seedParam <= 0) then { _seedParam = 1 + floor (random 99999); }; // dms-allow-random (seed 0 = pick one, it is logged)
DMS_seed = ["SEED", _seedParam] call DMS_fnc_rng;

private _cfg = DMS_cfg;
private _sites = _cfg get "sites";
private _siteIdx = ((["DMS_site", 1] call BIS_fnc_getParamValue) max 1) min (count _sites);
(_sites select (_siteIdx - 1)) params ["_siteName", "_siteXY"];
DMS_siteName = _siteName;
DMS_siteId = (_cfg get "siteIds") select (_siteIdx - 1);
DMS_baseCenter = [_siteXY select 0, _siteXY select 1, 0];
private _factions = _cfg get "factions";
DMS_faction = _factions select ((((["DMS_faction", 0] call BIS_fnc_getParamValue) max 0)) min ((count _factions) - 1));

// A dry, open spot near the centre for the player / test squad.
DMS_baseStart = DMS_baseCenter findEmptyPosition [5, 80, "B_Soldier_F"];
if (DMS_baseStart isEqualTo []) then { DMS_baseStart = DMS_baseCenter; };
DMS_baseStart = [DMS_baseStart select 0, DMS_baseStart select 1, 0];

[format ["Start: seed=%1 site='%2' center=%3 start=%4 faction=%5 debug=%6 test=%7",
	DMS_seed, _siteName, DMS_baseCenter, DMS_baseStart apply {round _x}, DMS_faction, DMS_debug, DMS_testMode]] call DMS_fnc_log;

if (DMS_testMode) then {
	// SP/hosted test: park the local player out of the way; the AI test squad is the only watcher.
	if (hasInterface && {!isNull player}) then {
		private _pl = player;
		_pl allowDamage false;
		_pl setCaptive true;
		hideObjectGlobal _pl;
		_pl setPosATL (DMS_baseStart getPos [15, 0]);
	};
} else {
	private _pl = objNull;
	if (isMultiplayer) then {
		private _t0 = time;
		waitUntil { sleep 1; ((allPlayers - (entities "HeadlessClient_F")) isNotEqualTo []) || {(time - _t0) > 120} };
		_pl = (allPlayers - (entities "HeadlessClient_F")) param [0, objNull];
	} else {
		_pl = player;
	};
	if (!isNull _pl) then { [_pl, DMS_baseStart] remoteExecCall ["setPosATL", _pl]; };
};

// ---------------------------------------------------------------- the ambient site
private _opts = createHashMapFromArray [
	["faction", DMS_faction],
	["activeRadius", _cfg get "activeRadius"],
	["despawnRadius", _cfg get "despawnRadius"],
	["despawnDelay", _cfg get "despawnDelay"],
	["watchPlayers", !DMS_testMode],
	["seed", DMS_seed]
];
if (DMS_testMode) then {
	_opts set ["heliFirstDelay", _cfg get "testHeliFirstDelay"];
	_opts set ["heliInterval", _cfg get "testHeliInterval"];
};
[DMS_siteId, DMS_baseCenter, _opts] call DMSA_fnc_ambientAdd;

if (DMS_testMode) then { ["RUN"] spawn DMS_fnc_testMode; };
private _mods = [["CBA", "cba_main"], ["ACE", "ace_main"], ["LAMBS", "lambs_danger"], ["RHS USAF", "rhsusf_main"], ["RHS AFRF", "rhs_main"]]
	select {isClass (configFile >> "CfgPatches" >> (_x select 1))} apply {_x select 0};
[format ["Mods: %1", [_mods joinString ", ", "none (vanilla)"] select (_mods isEqualTo [])]] call DMS_fnc_log;
["initServer done"] call DMS_fnc_log;
