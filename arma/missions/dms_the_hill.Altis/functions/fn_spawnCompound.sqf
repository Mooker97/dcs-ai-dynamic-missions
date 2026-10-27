/*
	DMS_fnc_spawnCompound - build the compound, its CSAT garrison and the intel item (server only).
	[_center, _dir] call DMS_fnc_spawnCompound;
	Sets: DMS_compoundObjects, DMS_garrison, DMS_enemyGroups, DMS_patrolGroup, DMS_intel
*/
params ["_center", "_dir"];
private _cfg = DMS_cfg;
private _skills = _cfg get "enemySkill";
private _objects = [];
private _buildings = [];
private _statics = [];
private _sentryPosts = [];
private _intelTable = objNull;

// Clear vegetation, rocks and walls so the composition does not clip into terrain objects.
{ hideObjectGlobal _x } forEach (nearestTerrainObjects [_center, ["TREE", "SMALL TREE", "BUSH", "ROCK", "ROCKS", "FENCE", "WALL"], _cfg get "clearRadius", false, true]);

private _toWorld = {
	params ["_off"];
	_off params ["_dx", "_dy"];
	[(_center select 0) + (_dx * cos _dir) + (_dy * sin _dir), (_center select 1) - (_dx * sin _dir) + (_dy * cos _dir), 0]
};
private _applySkill = {
	params ["_unit"];
	{ _unit setSkill _x } forEach _skills;
};

{
	_x params ["_kind", "_cls", "_off", ["_rel", 0]];
	private _pos = [_off] call _toWorld;
	private _wdir = (_dir + _rel) mod 360;
	if (_kind == "SENTRY") then {
		_sentryPosts pushBack [_pos, _wdir];
	} else {
		if (isClass (configFile >> "CfgVehicles" >> _cls)) then {
			private _obj = createVehicle [_cls, _pos, [], 0, "CAN_COLLIDE"];
			_obj setDir _wdir;
			_obj setPosATL _pos;
			if (_kind == "OBJ") then { _obj setVectorUp (surfaceNormal _pos); };
			_objects pushBack _obj;
			switch (_kind) do {
				case "BLD": { _buildings pushBack _obj; };
				case "STATIC": { _statics pushBack _obj; };
				case "INTEL": { _intelTable = _obj; };
				default {};
			};
		} else {
			[format ["Missing class %1 (skipped)", _cls], "WARN"] call DMS_fnc_log;
		};
	};
} forEach (_cfg get "composition");

// ---------------------------------------------------------------- intel item on the table
private _intelCls = _cfg get "intelClass";
private _intelPos = [_center select 0, _center select 1, 0];
if (!isNull _intelTable) then {
	_intelPos = _intelTable modelToWorld [0, 0, ((boundingBoxReal _intelTable) select 1) select 2];
};
DMS_intel = createVehicle [_intelCls, _intelPos, [], 0, "CAN_COLLIDE"];
DMS_intel setPos _intelPos;
DMS_intel setDir (getDir _intelTable);
DMS_intel allowDamage false;
DMS_intel enableSimulationGlobal false;
_objects pushBack DMS_intel;

// ---------------------------------------------------------------- garrison
private _grpG = createGroup [east, true];

// Sentries at fixed posts.
{
	_x params ["_p", "_d"];
	private _u = _grpG createUnit [_cfg get "sentryClass", _p, [], 0, "CAN_COLLIDE"];
	_u setPosATL _p;
	_u setDir _d;
	_u setUnitPos "UP";
	doStop _u;
	[_u] call _applySkill;
} forEach _sentryPosts;

// Riflemen inside buildings. PATH disabled: they hold and reinforce their positions instead of charging.
private _bpos = [];
{ _bpos append (_x buildingPos -1); } forEach _buildings;
_bpos = ["SHUFFLE", _bpos] call DMS_fnc_rng;
private _n = (_cfg get "garrisonCount") min (count _bpos);
if (_n < (_cfg get "garrisonCount")) then {
	[format ["Only %1 building positions for %2 garrison units", count _bpos, _cfg get "garrisonCount"], "WARN"] call DMS_fnc_log;
};
for "_i" from 0 to (_n - 1) do {
	private _p = _bpos select _i;
	private _u = _grpG createUnit [["PICK", _cfg get "garrisonClasses"] call DMS_fnc_rng, _p, [], 0, "CAN_COLLIDE"];
	_u setPosATL _p;
	_u setDir (_center getDir _p);
	_u disableAI "PATH";
	[_u] call _applySkill;
};

// Static gunners.
private _groups = [_grpG];
{
	createVehicleCrew _x;
	{ [_x] call _applySkill; } forEach (crew _x);
	_groups pushBack (group (gunner _x));
} forEach _statics;

// Small patrol.
private _grpP = createGroup [east, true];
private _pp = ["FLAT", [_center, 40, 80, 3]] call DMS_fnc_findPos;
for "_i" from 1 to (_cfg get "patrolSize") do {
	private _u = _grpP createUnit [["PICK", _cfg get "garrisonClasses"] call DMS_fnc_rng, _pp, [], 3, "NONE"];
	[_u] call _applySkill;
};
[_grpP, _center, _cfg get "patrolRadius"] call BIS_fnc_taskPatrol;
_grpP setSpeedMode "LIMITED";
_groups pushBack _grpP;

{
	_x setBehaviour "SAFE";
	_x setCombatMode "YELLOW";
} forEach _groups;

private _garrison = [];
{ _garrison append (units _x); } forEach _groups;

// A casualty raises the alarm (the defenders notice their losses).
{
	_x addEventHandler ["Killed", {
		if (!(missionNamespace getVariable ["DMS_alarm", false])) then { ["ALARM", ["casualty"]] call DMS_fnc_qrf; };
	}];
} forEach _garrison;

DMS_compoundObjects = _objects;
DMS_garrison = _garrison;
DMS_enemyGroups = _groups;
DMS_patrolGroup = _grpP;

[format ["Compound built: %1 objects, %2 defenders (%3 sentries, %4 in buildings, %5 statics, %6 patrol)",
	count _objects, count _garrison, count _sentryPosts, _n, count _statics, count units _grpP]] call DMS_fnc_log;
