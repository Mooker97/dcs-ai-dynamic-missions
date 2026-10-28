/*
	DMSA_fnc_ambientAdd - register an ambient "base life" site (server only).
	[_siteId, _centerPos, _opts] call DMSA_fnc_ambientAdd -> _siteId ("" on error)

	_opts (hashmap, all optional):
	  activeRadius    600     any watcher within this -> staggered spawn
	  despawnRadius   900     all watchers beyond this for despawnDelay s -> delete everything (hysteresis)
	  despawnDelay    30      s
	  maxUnits        24      hard cap on ambient men (crews included)
	  maxVehicles     4       hard cap on ambient vehicles (traffic, parked, helicopter)
	  faction         "auto"  "auto" | "vanilla_nato" | "rhs_usarmy" | "rhs_usmc"
	  side            preset  side of the ambient groups
	  classes         -       hashmap overriding preset lists: infantry sentry worker driver traffic parked heli
	  idleGroups      3       groups of 2-3 men idling (BIS_fnc_ambientAnim) next to buildings
	  sentries        2       gate/road-entrance sentries
	  workParty       true    parked vehicle with 3 men working on it
	  traffic         2       0-3 vehicles driving a loop on the base roads
	  heli            true    transport helicopter that lands, waits and leaves
	  heliFirstDelay  [60, 180]   s after activation
	  heliInterval    [300, 600]  s between visits
	  heliWait        [40, 90]    s on the ground
	  heliSpawnDist   3500    m, where the helicopter appears and leaves to
	  invulnerable    false   true = allowDamage false on all ambient units/vehicles
	  watchPlayers    true    players activate the site
	  watchers        []      extra objects that activate the site (also global DMSA_watchers)
	  pollInterval    5       s
	  seed            DMS_seed if defined, else 1
	Ambient objects and groups carry the variable "DMSA_ambient" = _siteId; exclude them from
	mission logic with (_x getVariable ["DMSA_ambient", ""]) == "".
*/
params [["_id", "", [""]], ["_center", [], [[]]], ["_opts", createHashMap, [createHashMap]]];

if (!isServer) exitWith { ["ambientAdd must run on the server", "ERROR"] call DMSA_fnc_ambientLog; "" };
if (_id == "" || {count _center < 2}) exitWith { [format ["ambientAdd: bad arguments id='%1' center=%2", _id, _center], "ERROR"] call DMSA_fnc_ambientLog; "" };
if (isNil "DMSA_sites") then { DMSA_sites = createHashMap; };
if (_id in DMSA_sites) exitWith { [format ["[%1] already registered, ignoring", _id], "WARN"] call DMSA_fnc_ambientLog; "" };
_center = [_center select 0, _center select 1, 0];

// ---------------------------------------------------------------- options
private _defaults = [
	["activeRadius", 600], ["despawnRadius", 900], ["despawnDelay", 30], ["maxUnits", 24], ["maxVehicles", 4],
	["faction", "auto"], ["idleGroups", 3], ["sentries", 2], ["workParty", true], ["traffic", 2], ["heli", true],
	["heliFirstDelay", [60, 180]], ["heliInterval", [300, 600]], ["heliWait", [40, 90]], ["heliSpawnDist", 3500],
	["invulnerable", false], ["watchPlayers", true], ["watchers", []], ["pollInterval", 5],
	["seed", missionNamespace getVariable ["DMS_seed", 1]], ["classes", createHashMap]
];
private _o = +_opts;
{ if (!((_x select 0) in _o)) then { _o set [_x select 0, _x select 1]; }; } forEach _defaults;
_o set ["despawnRadius", (_o get "despawnRadius") max ((_o get "activeRadius") + 50)];
_o set ["traffic", ((_o get "traffic") max 0) min 3];
_o set ["despawnDelay", (_o get "despawnDelay") max 1];
_o set ["pollInterval", (_o get "pollInterval") max 1];

if (isNil "DMSA_rngState") then { ["SEED", _o get "seed"] call DMSA_fnc_ambientRng; };

// ---------------------------------------------------------------- classes (preset + overrides, verified with isClass)
private _preset = [_o get "faction"] call DMSA_fnc_ambientPresets;
private _classes = createHashMap;
private _dropped = [];
private _over = _o get "classes";
{
	private _list = if (_x in _over) then { _over get _x } else { _preset get _x };
	private _ok = _list select {isClass (configFile >> "CfgVehicles" >> _x)};
	_dropped append (_list - _ok);
	_classes set [_x, _ok];
} forEach ["infantry", "sentry", "worker", "driver", "traffic", "parked", "heli"];
if (_dropped isNotEqualTo []) then {
	[format ["[%1] classes missing in this game config, dropped: %2", _id, _dropped], "WARN"] call DMSA_fnc_ambientLog;
};
if ((_classes get "infantry") isEqualTo [] && {(_preset get "name") != "vanilla_nato"}) then {
	[format ["[%1] preset %2 has no usable infantry (mod not loaded?), falling back to vanilla_nato", _id, _preset get "name"], "WARN"] call DMSA_fnc_ambientLog;
	_preset = ["vanilla_nato"] call DMSA_fnc_ambientPresets;
	{ _classes set [_x, (_preset get _x) select {isClass (configFile >> "CfgVehicles" >> _x)}]; } forEach ["infantry", "sentry", "worker", "driver", "traffic", "parked", "heli"];
};
{ if ((_classes get _x) isEqualTo []) then { _classes set [_x, _classes get "infantry"]; }; } forEach ["sentry", "worker", "driver"];
private _side = if ("side" in _opts) then { _opts get "side" } else { _preset get "side" };

// ---------------------------------------------------------------- survey (once; positions reused on every activation)
private _r = _o get "activeRadius";
private _probe = (_classes get "infantry") param [0, "B_Soldier_F"];

// Road loop for traffic: spread road points (>= 120 m apart), ordered by bearing so the loop goes round the base.
private _roads = (_center nearRoads (_r * 0.7)) apply {getPosATL _x};
private _loop = [];
{
	private _p = _x;
	if ((count _loop) < 6 && {(_loop findIf {(_x distance2D _p) < 120}) < 0}) then { _loop pushBack [_p select 0, _p select 1, 0]; };
} forEach (["SHUFFLE", _roads] call DMSA_fnc_ambientRng);
private _byDir = _loop apply {[_center getDir _x, _x]};
_byDir sort true;
_loop = _byDir apply {_x select 1};

// Idle spots: next to buildings that have building positions (barracks, cargo houses, hangars), facing the open side.
private _spots = [];
{
	private _b = _x;
	if ((count _spots) < ((_o get "idleGroups") + 3) && {(_b buildingPos -1) isNotEqualTo []}) then {
		private _bb = boundingBoxReal _b;
		private _half = ((((_bb select 1) select 0) - ((_bb select 0) select 0)) max (((_bb select 1) select 1) - ((_bb select 0) select 1))) / 2;
		private _cand = (getPosATL _b) getPos [(_half min 25) + 2, _b getDir _center];
		private _free = _cand findEmptyPosition [0, 12, _probe];
		if (_free isNotEqualTo [] && {!surfaceIsWater _free} && {(_spots findIf {(_x distance2D _free) < 30}) < 0}) then {
			_spots pushBack [_free select 0, _free select 1, 0];
		};
	};
} forEach (nearestObjects [_center, ["House"], _r * 0.6]);

// Sentry posts: vanilla bar gates first, else the outermost road points (entrances), each [pos, facing].
private _gates = [];
{
	if ((count _gates) < (_o get "sentries")) then {
		private _g = getPosATL _x;
		private _p = _g getPos [4, (_g getDir _center) + 90];
		_gates pushBack [[_p select 0, _p select 1, 0], _center getDir _g];
	};
} forEach (nearestObjects [_center, ["Land_BarGate_F"], _r * 0.8]);
private _gateSrc = "bar gates";
if ((count _gates) < (_o get "sentries")) then {
	_gateSrc = format ["%1 bar gates + road entrances", count _gates];
	private _outer = ((_center nearRoads (_r * 0.75)) apply {getPosATL _x}) select {(_x distance2D _center) > (_r * 0.35)};
	private _picked = [];
	if (_outer isNotEqualTo []) then {
		private _far = _outer apply {[_x distance2D _center, _x]};
		_far sort false;
		_picked pushBack ((_far select 0) select 1);
		while {(count _picked) < ((_o get "sentries") - (count _gates)) && {(count _picked) < (count _outer)}} do {
			private _best = [];
			private _bestD = -1;
			{
				private _p = _x;
				private _d = 1e9;
				{ _d = _d min (_p distance2D _x); } forEach _picked;
				if (_d > _bestD) then { _bestD = _d; _best = _p; };
			} forEach _outer;
			if (_bestD < 60) exitWith {};
			_picked pushBack _best;
		};
	};
	{
		private _p = _x getPos [5, (_center getDir _x) + 90];
		_gates pushBack [[_p select 0, _p select 1, 0], _center getDir _x];
	} forEach _picked;
};

// Work party: a parking spot beside the road nearest the centre.
private _work = [];
private _inner = (_center nearRoads (_r * 0.4)) apply {getPosATL _x};
if (_inner isNotEqualTo []) then {
	private _near = _inner apply {[_x distance2D _center, _x]};
	_near sort true;
	private _rp = (_near select 0) select 1;
	private _cls = (_classes get "parked") param [0, "B_Truck_01_transport_F"];
	private _free = (_rp getPos [9, (_rp getDir _center) + 0]) findEmptyPosition [0, 25, _cls];
	if (_free isNotEqualTo [] && {!surfaceIsWater _free}) then { _work = [_free select 0, _free select 1, 0]; };
};
if (_work isEqualTo [] && {_spots isNotEqualTo []}) then { _work = _spots select ((count _spots) - 1); };

// Helicopter landing spot: an existing helipad, else a flat empty spot.
private _pad = [];
private _padSrc = "none";
private _pads = nearestObjects [_center, ["HeliH"], _r];
if (_pads isNotEqualTo []) then {
	private _hp = getPosATL (_pads select 0);
	_pad = [_hp select 0, _hp select 1, 0];
	_padSrc = typeOf (_pads select 0);
} else {
	for "_i" from 1 to 40 do {
		if (_pad isEqualTo []) then {
			private _c = _center getPos [["RANGE", [60, _r * 0.6]] call DMSA_fnc_ambientRng, ["RANGE", [0, 360]] call DMSA_fnc_ambientRng];
			private _flat = _c isFlatEmpty [12, -1, 0.15, 12, 0, false, objNull];
			if (_flat isNotEqualTo []) then { _pad = [_flat select 0, _flat select 1, 0]; _padSrc = "flat ground"; };
		};
	};
};

// ---------------------------------------------------------------- register
private _st = createHashMapFromArray [
	["id", _id], ["center", _center], ["opts", _o], ["classes", _classes], ["side", _side], ["faction", _preset get "name"],
	["active", false], ["spawning", false], ["removed", false], ["gen", 0],
	["units", []], ["vehicles", []], ["groups", []], ["objects", []],
	["loop", _loop], ["spots", _spots], ["gates", _gates], ["work", _work], ["pad", _pad],
	["activations", 0], ["heliSpawned", 0], ["heliLanded", 0], ["trafficStart", []], ["lastSpawn", createHashMap]
];
DMSA_sites set [_id, _st];

[format ["[%1] site added center=%2 faction=%3 side=%4 active=%5 despawn=%6 delay=%7 caps=%8u/%9v",
	_id, [round (_center select 0), round (_center select 1)], _preset get "name", _side, _r, _o get "despawnRadius",
	_o get "despawnDelay", _o get "maxUnits", _o get "maxVehicles"]] call DMSA_fnc_ambientLog;
[format ["[%1] survey: roads=%2 loopPoints=%3 idleSpots=%4 sentryPosts=%5 (%6) work=%7 pad=%8 (%9)",
	_id, count _roads, count _loop, count _spots, count _gates, _gateSrc,
	[_work apply {round _x}, "none"] select (_work isEqualTo []), [_pad apply {round _x}, "none"] select (_pad isEqualTo []), _padSrc]] call DMSA_fnc_ambientLog;
if ((count _loop) < 2 && {(_o get "traffic") > 0}) then { [format ["[%1] fewer than 2 road points within %2 m: no traffic", _id, round (_r * 0.7)], "WARN"] call DMSA_fnc_ambientLog; };

_st set ["monitor", [_id] spawn DMSA_fnc_ambientMonitor];
_id
