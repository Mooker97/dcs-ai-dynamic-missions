/*
	DMSA_fnc_ambientDespawn - delete everything a site has spawned (scheduled, server).
	[_siteId, _reason] call DMSA_fnc_ambientDespawn;
	Marks the site inactive (bumps its generation so the helicopter thread stops), deletes crews and
	vehicles, units (and their BIS_fnc_ambientAnim helper logic), helper objects, then the empty
	groups. A vehicle with a player aboard is left alone (logged) together with its crew.
*/
params [["_id", "", [""]], ["_reason", "", [""]]];
if (isNil "DMSA_sites" || {!(_id in DMSA_sites)}) exitWith {};
private _st = DMSA_sites get _id;
_st set ["active", false];
_st set ["gen", (_st get "gen") + 1];

// Let a spawn in progress notice the generation change (bounded).
private _t0 = time;
waitUntil { sleep 0.5; !(_st get "spawning") || {(time - _t0) > 30} };
_st set ["spawning", false];

private _nV = 0;
private _nU = 0;
private _kept = [];
{
	private _veh = _x;
	if (!isNull _veh) then {
		if (((crew _veh) findIf {isPlayer _x}) > -1) then {
			_kept pushBack _veh;
			_kept append (crew _veh);
		} else {
			{ _veh deleteVehicleCrew _x; _nU = _nU + 1; } forEach ((crew _veh) select {!isPlayer _x});
			deleteVehicle _veh;
			_nV = _nV + 1;
		};
	};
} forEach (_st get "vehicles");

{
	private _u = _x;
	if (!isNull _u && {!(_u in _kept)} && {!isPlayer _u}) then {
		// Helper logic BIS_fnc_ambientAnim attaches the unit to (unit variable "<fnc>__logic", read from
		// A3/Functions_F/Ambient/fn_ambientAnim.sqf). Concatenated: it is a variable, not a function.
		private _lg = _u getVariable [("BIS_fnc_ambientAnim" + "__logic"), objNull];
		if (!isNull _lg) then { deleteVehicle _lg; };
		detach _u;
		if ((vehicle _u) != _u) then {
			(vehicle _u) deleteVehicleCrew _u;
		} else {
			deleteVehicle _u;
		};
		_nU = _nU + 1;
	};
} forEach (_st get "units");

{ if (!isNull _x) then { deleteVehicle _x; }; } forEach (_st get "objects");

// Groups: deleteGroup needs them empty; unit deletion completes at the end of the frame.
private _groups = (_st get "groups") select {!isNull _x};
private _nG = 0;
for "_i" from 1 to 15 do {
	if (_groups isNotEqualTo []) then {
		sleep 0.2;
		private _empty = _groups select {(units _x) isEqualTo []};
		{ deleteGroup _x; } forEach _empty;
		_nG = _nG + (count _empty);
		_groups = _groups - _empty;
	};
};

_st set ["vehicles", _kept select {!(_x isKindOf "CAManBase")}];
_st set ["units", _kept select {_x isKindOf "CAManBase"}];
_st set ["groups", _groups];
_st set ["objects", []];
_st set ["trafficStart", []];
[format ["[%1] despawn (%2): removed units=%3 vehicles=%4 groups=%5 kept=%6 groupsLeft=%7",
	_id, _reason, _nU, _nV, _nG, count _kept, count _groups]] call DMSA_fnc_ambientLog;
