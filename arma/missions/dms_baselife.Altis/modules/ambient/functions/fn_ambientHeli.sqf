/*
	DMSA_fnc_ambientHeli - helicopter visits for one activation of a site (scheduled, server).
	[_siteId, _gen] spawn DMSA_fnc_ambientHeli;   started by DMSA_fnc_ambientSpawn
	Loop while the site stays in generation _gen: wait (heliFirstDelay, then heliInterval), fly a
	transport helicopter in from heliSpawnDist, land at the surveyed pad, wait heliWait on the
	ground, fly out the other side and delete it once it is far away. Every wait is bounded.
	Stats: site "heliSpawned" / "heliLanded".
*/
params [["_id", "", [""]], ["_gen", 0, [0]]];
if (isNil "DMSA_sites" || {!(_id in DMSA_sites)}) exitWith {};
private _st = DMSA_sites get _id;
private _o = _st get "opts";
private _center = _st get "center";
private _padPos = _st get "pad";

private _live = { !(_st get "removed") && {(_st get "active")} && {(_st get "gen") == _gen} };
private _waitLive = {
	params ["_secs"];
	private _end = time + _secs;
	waitUntil { sleep 2; time >= _end || {!(call _live)} };
	call _live
};

// Invisible pad so the AI lands on the exact spot; deleted with the site.
private _padObj = createVehicle ["Land_HelipadEmpty_F", _padPos, [], 0, "CAN_COLLIDE"];
_padObj setVariable ["DMSA_ambient", _id];
(_st get "objects") pushBack _padObj;

private _delay = ["RANGE", _o get "heliFirstDelay"] call DMSA_fnc_ambientRng;
while {call _live} do {
	private _ok = [_delay] call _waitLive;
	_delay = ["RANGE", _o get "heliInterval"] call DMSA_fnc_ambientRng;
	private _unitsLeft = (_o get "maxUnits") - ({!isNull _x} count (_st get "units"));
	private _vehLeft = (_o get "maxVehicles") - ({!isNull _x} count (_st get "vehicles"));
	if (_ok && {_unitsLeft < 4 || {_vehLeft < 1}}) then {
		[format ["[%1] heli skipped: caps (units left %2, vehicles left %3)", _id, _unitsLeft, _vehLeft]] call DMSA_fnc_ambientLog;
		_ok = false;
	};
	if (_ok) then {
		private _cls = ["PICK", (_st get "classes") get "heli"] call DMSA_fnc_ambientRng;
		private _dirIn = ["RANGE", [0, 360]] call DMSA_fnc_ambientRng;
		private _from = _center getPos [_o get "heliSpawnDist", _dirIn];
		private _heli = createVehicle [_cls, [_from select 0, _from select 1, 150], [], 0, "FLY"];
		createVehicleCrew _heli;
		private _crew = crew _heli;
		private _g = group (driver _heli);
		_heli setVariable ["DMSA_ambient", _id];
		if (_o get "invulnerable") then { _heli allowDamage false; };
		(_st get "vehicles") pushBack _heli;
		{
			_x setVariable ["DMSA_ambient", _id];
			_x setVariable ["lambs_danger_disableAI", true, true];
			_x setCaptive false;
			if (_o get "invulnerable") then { _x allowDamage false; };
			(_st get "units") pushBack _x;
		} forEach _crew;
		_g setVariable ["DMSA_ambient", _id];
		_g setVariable ["lambs_danger_disableGroupAI", true, true];
		_g setBehaviour "CARELESS";
		_g setCombatMode "BLUE";
		(_st get "groups") pushBack _g;
		_heli flyInHeight 80;
		private _wp = _g addWaypoint [_padPos, 0];
		_wp setWaypointType "MOVE";
		_wp setWaypointSpeed "NORMAL";
		_st set ["heliSpawned", (_st get "heliSpawned") + 1];
		[format ["[%1] heli %2 inbound from %3 m (bearing %4) to the pad at %5", _id, _cls, _o get "heliSpawnDist", round _dirIn, _padPos apply {round _x}]] call DMSA_fnc_ambientLog;

		// Approach, then land.
		private _t = time;
		waitUntil { sleep 2; !(call _live) || {!alive _heli} || {(_heli distance2D _padPos) < 250} || {(time - _t) > 300} };
		private _landed = false;
		if ((call _live) && {alive _heli} && {(_heli distance2D _padPos) < 250}) then {
			_heli land "LAND";
			_t = time;
			waitUntil { sleep 2; !(call _live) || {!alive _heli} || {(isTouchingGround _heli) && {((getPosATL _heli) select 2) < 2}} || {(time - _t) > 150} };
			_landed = (call _live) && {alive _heli} && {isTouchingGround _heli};
		};
		if (_landed) then {
			_st set ["heliLanded", (_st get "heliLanded") + 1];
			[format ["[%1] heli %2 landed %3 m from the pad", _id, _cls, round (_heli distance2D _padPos)]] call DMSA_fnc_ambientLog;
			[["RANGE", _o get "heliWait"] call DMSA_fnc_ambientRng] call _waitLive;
		} else {
			if (call _live) then { [format ["[%1] heli %2 did not land (alive=%3, %4 m from the pad)", _id, _cls, alive _heli, round (_heli distance2D _padPos)], "WARN"] call DMSA_fnc_ambientLog; };
		};

		// Leave on the far side and delete once out of sight.
		if ((call _live) && {alive _heli}) then {
			private _to = _center getPos [_o get "heliSpawnDist", _dirIn + (["RANGE", [150, 210]] call DMSA_fnc_ambientRng)];
			_heli land "NONE";
			private _wpOut = _g addWaypoint [[_to select 0, _to select 1, 0], 0];
			_wpOut setWaypointType "MOVE";
			_wpOut setWaypointSpeed "FULL";
			_g setCurrentWaypoint _wpOut;
			_heli flyInHeight 120;
			[format ["[%1] heli %2 departing", _id, _cls]] call DMSA_fnc_ambientLog;
			_t = time;
			waitUntil { sleep 3; !(call _live) || {!alive _heli} || {(_heli distance2D _center) > ((_o get "heliSpawnDist") * 0.8)} || {(time - _t) > 300} };
		};
		// Remove it (also covers a despawn that ran while it was being created) unless a player is aboard.
		// A wreck on an active site stays (tracked) until the site despawns.
		if (!isNull _heli && {(alive _heli) || {!(call _live)}} && {((crew _heli) findIf {isPlayer _x}) < 0}) then {
			{ _heli deleteVehicleCrew _x; } forEach (crew _heli);
			deleteVehicle _heli;
			_st set ["units", (_st get "units") - _crew];
			_st set ["vehicles", (_st get "vehicles") - [_heli]];
			[_g] spawn {
				params ["_g"];
				sleep 1;
				if (!isNull _g && {(units _g) isEqualTo []}) then { deleteGroup _g; };
			};
			_st set ["groups", (_st get "groups") - [_g]];
			[format ["[%1] heli %2 removed (%3)", _id, _cls, ["site inactive", "left the area"] select (call _live)]] call DMSA_fnc_ambientLog;
		};
	};
};
if (!(call _live) && {!isNull _padObj}) then { deleteVehicle _padObj; };
[format ["[%1] heli thread stopped (gen %2)", _id, _gen], "DEBUG"] call DMSA_fnc_ambientLog;
