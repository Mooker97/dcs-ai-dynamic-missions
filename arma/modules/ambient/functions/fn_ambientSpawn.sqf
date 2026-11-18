/*
	DMSA_fnc_ambientSpawn - staggered spawn of every ambient layer for one site (scheduled, server).
	[_siteId] call DMSA_fnc_ambientSpawn;   called by the monitor on activation
	Order (each layer checks the hard caps first): sentries, idle groups, work party, traffic,
	then the helicopter thread. Every unit/vehicle/group is tagged "DMSA_ambient" = _siteId,
	opted out of LAMBS Danger and set to combat mode BLUE (never fires).
*/
params [["_id", "", [""]]];
if (isNil "DMSA_sites" || {!(_id in DMSA_sites)}) exitWith {};
private _st = DMSA_sites get _id;
private _o = _st get "opts";
private _cls = _st get "classes";
private _side = _st get "side";
private _center = _st get "center";
private _gen = _st get "gen";
_st set ["spawning", true];

private _live = { !(_st get "removed") && {(_st get "active")} && {(_st get "gen") == _gen} };
private _unitsLeft = { (_o get "maxUnits") - ({!isNull _x} count (_st get "units")) };
private _vehLeft = { (_o get "maxVehicles") - ({!isNull _x} count (_st get "vehicles")) };

// Group: tagged, LAMBS off, relaxed, never fires.
private _mkGroup = {
	params [["_beh", "SAFE"]];
	private _g = createGroup [_side, true];
	_g setVariable ["DMSA_ambient", _id];
	_g setVariable ["lambs_danger_disableGroupAI", true, true];
	_g setBehaviour _beh;
	_g setCombatMode "BLUE";
	(_st get "groups") pushBack _g;
	_g
};
// Common setup for anything the module creates.
private _tagObj = {
	params ["_obj"];
	_obj setVariable ["DMSA_ambient", _id];
	if (_o get "invulnerable") then { _obj allowDamage false; };
	if (_obj isKindOf "CAManBase") then {
		_obj setVariable ["lambs_danger_disableAI", true, true];
		_obj setCaptive false;
		(_st get "units") pushBack _obj;
	} else {
		(_st get "vehicles") pushBack _obj;
	};
	_obj
};
private _mkUnit = {
	params ["_g", "_type", "_pos", "_dir"];
	private _u = _g createUnit [_type, _pos, [], 0, "CAN_COLLIDE"];
	_u setPosATL [_pos select 0, _pos select 1, 0];
	_u setDir _dir;
	[_u] call _tagObj
};

private _n = createHashMapFromArray [["sentries", 0], ["idle", 0], ["work", 0], ["traffic", 0]];

// ---------------------------------------------------------------- sentries: stand at the entrances, watch outwards
{
	_x params ["_pos", "_face"];
	if ((call _live) && {(call _unitsLeft) >= 1}) then {
		private _g = ["SAFE"] call _mkGroup;
		private _u = [_g, ["PICK", _cls get "sentry"] call DMSA_fnc_ambientRng, _pos, _face] call _mkUnit;
		_u disableAI "PATH";
		_u setUnitPos "UP";
		_u doWatch (_pos getPos [100, _face]);
		_n set ["sentries", (_n get "sentries") + 1];
		sleep 0.5;
	};
} forEach ((_st get "gates") select [0, _o get "sentries"]);

// ---------------------------------------------------------------- idle groups: 2-3 men idling next to buildings
private _sets = ["STAND", "STAND_IA", "SIT_LOW", "KNEEL", "WATCH1", "WATCH2"];
{
	private _spot = _x;
	if ((call _live) && {(call _unitsLeft) >= 2}) then {
		private _size = (["INT", [2, 3]] call DMSA_fnc_ambientRng) min (call _unitsLeft);
		private _g = ["SAFE"] call _mkGroup;
		private _a0 = ["RANGE", [0, 360]] call DMSA_fnc_ambientRng;
		for "_i" from 0 to (_size - 1) do {
			private _p = _spot getPos [1.6, _a0 + (_i * (360 / _size))];
			private _u = [_g, ["PICK", _cls get "infantry"] call DMSA_fnc_ambientRng, [_p select 0, _p select 1, 0], _p getDir _spot] call _mkUnit;
			[_u, ["PICK", _sets] call DMSA_fnc_ambientRng, "ASIS"] call BIS_fnc_ambientAnim;
			_n set ["idle", (_n get "idle") + 1];
			sleep 0.3;
		};
		sleep 0.5;
	};
} forEach ((_st get "spots") select [0, _o get "idleGroups"]);

// ---------------------------------------------------------------- work party: a parked vehicle and men working on it
private _work = _st get "work";
if ((_o get "workParty") && {_work isNotEqualTo []} && {call _live} && {(call _vehLeft) >= 1} && {(call _unitsLeft) >= 2} && {(_cls get "parked") isNotEqualTo []}) then {
	private _vdir = ["RANGE", [0, 360]] call DMSA_fnc_ambientRng;
	private _veh = createVehicle [["PICK", _cls get "parked"] call DMSA_fnc_ambientRng, _work, [], 0, "NONE"];
	_veh setDir _vdir;
	_veh setFuel 0.6;
	[_veh] call _tagObj;
	private _g = ["SAFE"] call _mkGroup;
	private _jobs = [["REPAIR_VEH_STAND", 90], ["REPAIR_VEH_KNEEL", 270], ["KNEEL", 180]];
	{
		_x params ["_set", "_side2"];
		if ((call _unitsLeft) >= 1) then {
			private _p = _veh getPos [2.6, _vdir + _side2];
			private _u = [_g, ["PICK", _cls get "worker"] call DMSA_fnc_ambientRng, [_p select 0, _p select 1, 0], _p getDir _veh] call _mkUnit;
			[_u, _set, "ASIS"] call BIS_fnc_ambientAnim;
			_n set ["work", (_n get "work") + 1];
			sleep 0.3;
		};
	} forEach _jobs;
};

// ---------------------------------------------------------------- traffic: vehicles driving a loop on the base roads
private _loop = _st get "loop";
private _starts = [];
if ((count _loop) >= 2 && {(_cls get "traffic") isNotEqualTo []}) then {
	for "_k" from 0 to ((_o get "traffic") - 1) do {
		if ((call _live) && {(call _vehLeft) >= 1} && {(call _unitsLeft) >= 1}) then {
			private _i0 = (_k * (floor ((count _loop) / ((_o get "traffic") max 1)))) mod (count _loop);
			private _order = (_loop select [_i0, 99]) + (_loop select [0, _i0]);
			private _start = _order select 0;
			private _veh = createVehicle [["PICK", _cls get "traffic"] call DMSA_fnc_ambientRng, _start, [], 0, "NONE"];
			_veh setDir (_start getDir (_order select 1));
			[_veh] call _tagObj;
			private _g = ["CARELESS"] call _mkGroup;
			private _drv = _g createUnit [["PICK", _cls get "driver"] call DMSA_fnc_ambientRng, _start, [], 5, "NONE"];
			[_drv] call _tagObj;
			_drv moveInDriver _veh;
			_g setSpeedMode "LIMITED";
			_veh limitSpeed 30;
			{
				private _wp = _g addWaypoint [_x, 0];
				_wp setWaypointType "MOVE";
				_wp setWaypointSpeed "LIMITED";
				_wp setWaypointBehaviour "CARELESS";
				_wp setWaypointCombatMode "BLUE";
				_wp setWaypointCompletionRadius 15;
			} forEach ((_order select [1, 99]) + [_start]);
			private _cyc = _g addWaypoint [_order select 1, 0];
			_cyc setWaypointType "CYCLE";
			_cyc setWaypointCompletionRadius 15;
			_starts pushBack [_veh, getPosATL _veh];
			_n set ["traffic", (_n get "traffic") + 1];
			sleep 1;
		};
	};
};
_st set ["trafficStart", _starts];

// ---------------------------------------------------------------- helicopter cycle (own thread, exits when the site deactivates)
private _heli = (_o get "heli") && {(_st get "pad") isNotEqualTo []} && {(_cls get "heli") isNotEqualTo []};
if (_heli && {call _live}) then { [_id, _gen] spawn DMSA_fnc_ambientHeli; };

_st set ["lastSpawn", _n];
_st set ["spawning", false];
[format ["[%1] spawned units=%2 vehicles=%3 groups=%4 (sentries=%5 idle=%6 work=%7 traffic=%8 heli=%9) faction=%10",
	_id, {!isNull _x} count (_st get "units"), {!isNull _x} count (_st get "vehicles"), {!isNull _x} count (_st get "groups"),
	_n get "sentries", _n get "idle", _n get "work", _n get "traffic",
	["off", "scheduled"] select _heli, _st get "faction"]] call DMSA_fnc_ambientLog;
if ((call _unitsLeft) <= 0) then { [format ["[%1] unit cap %2 reached, some layers trimmed", _id, _o get "maxUnits"], "DEBUG"] call DMSA_fnc_ambientLog; };
