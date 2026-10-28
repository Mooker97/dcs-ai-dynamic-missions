/*
	DMS_fnc_village - village choice, insurgent garrison and the "cleared" monitor (server only).
	["HOUSES", [_pos, _radius]] call     -> enterable houses (>= houseMinPositions building positions) near _pos
	["MEASURE", [_pos]] call             -> [centroid, houses]: houses re-counted around their own centroid
	["PICK", [_param]] call              -> [label, center, houses] or [] (seeded; _param 1..3 forces a village)
	["SIDE", [_class]] call              -> side of a CfgVehicles class (from its config "side" number)
	["DEFEND"] call                      -> garrison groups + RPG team (LAMBS taskGarrison) + optional technical
	["MONITOR"] spawn                    -> waits until the village is cleared, then schedules the counterattack
*/
params [["_mode", "", [""]], ["_args", [], [[]]]];
private _cfg = DMS_cfg;

switch (_mode) do {
	case "HOUSES": {
		_args params ["_pos", ["_radius", 130]];
		private _min = _cfg get "houseMinPositions";
		(nearestObjects [_pos, ["House"], _radius]) select {alive _x && {count (_x buildingPos -1) >= _min}}
	};

	case "MEASURE": {
		_args params ["_pos"];
		private _r = _cfg get "villageRadius";
		private _houses = ["HOUSES", [_pos, _r]] call DMS_fnc_village;
		// (no exitWith here: the case block's value is the function's return value)
		private _res = [[_pos select 0, _pos select 1, 0], []];
		if (_houses isNotEqualTo []) then {
			private _sx = 0;
			private _sy = 0;
			{ _sx = _sx + ((getPosATL _x) select 0); _sy = _sy + ((getPosATL _x) select 1); } forEach _houses;
			private _c = [_sx / (count _houses), _sy / (count _houses), 0];
			_res = [_c, ["HOUSES", [_c, _r]] call DMS_fnc_village];
		};
		_res
	};

	case "PICK": {
		_args params [["_param", 0]];
		private _locs = nearestLocations [[worldSize / 2, worldSize / 2], ["NameVillage", "NameCity", "NameCityCapital"], worldSize];
		(_cfg get "villageHouses") params ["_minH", "_maxH"];
		private _cands = [];
		{
			_x params ["_label", "_xy"];
			private _near = (_locs select {(locationPosition _x) distance2D _xy < (_cfg get "villageSnap")}) apply {[(locationPosition _x) distance2D _xy, _x]};
			if (_near isEqualTo []) then {
				[format ["Village %1: no map location within %2 m of %3 (skipped)", _label, _cfg get "villageSnap", _xy], "WARN"] call DMS_fnc_log;
			} else {
				_near sort true;
				private _loc = (_near select 0) select 1;
				(["MEASURE", [locationPosition _loc]] call DMS_fnc_village) params ["_c", "_houses"];
				private _ok = (count _houses) >= _minH && {(count _houses) <= _maxH} && {!(surfaceIsWater _c)};
				[format ["Village %1: location '%2' (%3) at %4, centroid %5, %6 enterable houses within %7 m -> %8",
					_label, text _loc, type _loc, locationPosition _loc apply {round _x}, _c apply {round _x}, count _houses,
					_cfg get "villageRadius", ["skipped", "candidate"] select _ok]] call DMS_fnc_log;
				if (_ok) then { _cands pushBack [_label, _c, _houses]; };
			};
		} forEach (_cfg get "villages");
		if (_cands isEqualTo []) then {
			// Fallback: any named village on the map with a usable number of houses (sorted for determinism).
			["No configured village usable, scanning the map", "WARN"] call DMS_fnc_log;
			private _all = [];
			{
				(["MEASURE", [locationPosition _x]] call DMS_fnc_village) params ["_c", "_houses"];
				if ((count _houses) >= _minH && {(count _houses) <= _maxH} && {!(surfaceIsWater _c)}) then {
					_all pushBack [text _x, _c, _houses];
				};
			} forEach (_locs select {type _x == "NameVillage"});
			_all sort true;
			_cands = _all select [0, 3];
			[format ["Map scan: %1 usable villages: %2", count _all, _all apply {_x select 0}]] call DMS_fnc_log;
		};
		private _pick = [];
		if (_cands isNotEqualTo []) then {
			_pick = ["PICK", _cands] call DMS_fnc_rng;
			if (_param > 0 && {_param <= count (_cfg get "villages")}) then {
				private _want = ((_cfg get "villages") select (_param - 1)) select 0;
				private _i = _cands findIf {(_x select 0) == _want};
				if (_i >= 0) then { _pick = _cands select _i; } else { [format ["Village param %1 (%2) is not usable, using the seeded pick", _param, _want], "WARN"] call DMS_fnc_log; };
			};
		};
		_pick
	};

	case "SIDE": {
		_args params ["_cls"];
		[east, west, resistance, civilian] select (((getNumber (configFile >> "CfgVehicles" >> _cls >> "side")) max 0) min 3)
	};

	case "DEFEND": {
		private _center = DMS_villageCenter;
		private _skills = _cfg get "enemySkill";
		private _side = DMS_enemySide;
		private _defenders = [];
		private _groups = [];
		private _range = _cfg get "garrisonRange";
		private _valid = { (_this select {isClass (configFile >> "CfgVehicles" >> _x)}) };

		private _garrison = {
			params ["_classes", "_anchor", "_tag"];
			private _grp = createGroup [DMS_enemySide, true];
			{
				private _u = _grp createUnit [_x, getPosATL _anchor, [], 3, "NONE"];
				{ _u setSkill _x } forEach (DMS_cfg get "enemySkill");
				_u addEventHandler ["Killed", {
					params ["_unit", "_killer"];
					[format ["Defender killed by %1 (%2) at %3 m", typeOf _killer, side (group _killer), round (_unit distance2D _killer)], "DEBUG"] call DMS_fnc_log;
				}];
			} forEach _classes;
			_grp setBehaviour "AWARE";
			_grp setCombatMode "YELLOW";
			// [group, position, range, area, teleport, sortByHeight, exitCondition (-2 random), patrol]
			[_grp, getPosATL _anchor, DMS_cfg get "garrisonRange", [], true, true, -2, false] call lambs_wp_fnc_taskGarrison;
			[format ["Garrison %1: %2 units on %3 (%4 enterable houses within %5 m)", _tag, count (units _grp), typeOf _anchor,
				count (["HOUSES", [getPosATL _anchor, DMS_cfg get "garrisonRange"]] call DMS_fnc_village), DMS_cfg get "garrisonRange"]] call DMS_fnc_log;
			_grp
		};

		// Anchors: seeded houses at least 2 x garrisonRange apart, so the groups hold different parts of the village.
		private _houses = ["SHUFFLE", DMS_villageHouses] call DMS_fnc_rng;
		private _rpgSpot = _center getPos [_cfg get "rpgTeamOffset", DMS_startBearing];
		private _byRpg = DMS_villageHouses apply {[_x distance2D _rpgSpot, _x]};
		_byRpg sort true;
		private _rpgAnchor = (_byRpg select 0) select 1;
		private _anchors = [_rpgAnchor];
		{
			private _classes = _x call _valid;
			private _anchor = _houses findIf {private _h = _x; (_anchors findIf {(_x distance2D _h) < 2 * _range}) < 0};
			private _house = if (_anchor < 0) then { _houses select (_forEachIndex mod (count _houses)) } else { _houses select _anchor };
			_anchors pushBack _house;
			if (_classes isNotEqualTo []) then { _groups pushBack ([_classes, _house, format ["%1", _forEachIndex + 1]] call _garrison); };
		} forEach (_cfg get "garrisonGroups");
		private _rpgClasses = (_cfg get "rpgTeam") call _valid;
		if (_rpgClasses isNotEqualTo []) then { _groups pushBack ([_rpgClasses, _rpgAnchor, "RPG"] call _garrison); };

		// Optional technical parked on a village road, crew holds there.
		DMS_technical = objNull;
		private _techCls = _cfg get "technicalClass";
		if ((["CHANCE", _cfg get "technicalChance"] call DMS_fnc_rng) && {isClass (configFile >> "CfgVehicles" >> _techCls)}) then {
			private _p = ["ROAD", [_center, 90]] call DMS_fnc_findPos;
			private _tech = createVehicle [_techCls, _p, [], 0, "NONE"];
			private _roads = _p nearRoads 15;
			_tech setDir ([_center getDir _p, getDir (_roads select 0)] select (_roads isNotEqualTo []));
			createVehicleCrew _tech;
			private _tg = group (effectiveCommander _tech);
			{ private _c = _x; { _c setSkill _x } forEach _skills; } forEach (crew _tech);
			_tg setBehaviour "AWARE";
			_tg setCombatMode "YELLOW";
			doStop (crew _tech);
			_groups pushBack _tg;
			DMS_technical = _tech;
			[format ["Technical %1 parked at %2 (%3 m from the centre)", typeOf _tech, _p apply {round _x}, round (_p distance2D _center)]] call DMS_fnc_log;
		};

		{ _defenders append (units _x); } forEach _groups;
		DMS_defenders = _defenders;
		DMS_enemyGroups = _groups;
		[format ["Defenders: %1 in %2 groups (side %3)", count _defenders, count _groups, _side]] call DMS_fnc_log;
	};

	case "MONITOR": {
		private _total = count DMS_defenders;
		private _thr = floor (_total * (_cfg get "clearFraction"));
		private _r = _cfg get "clearRadius";
		private _hold = _cfg get "holdRadius";
		[format ["Clear monitor: cleared when <= %1 of %2 defenders are alive within %3 m and the squad is inside %4 m", _thr, _total, _r, _hold]] call DMS_fnc_log;
		waitUntil {
			sleep 5;
			DMS_over || {
				({alive _x && {_x distance2D DMS_villageCenter < _r}} count DMS_defenders) <= _thr
				&& {((units DMS_squad) findIf {alive _x && {_x distance2D DMS_villageCenter < _hold}}) > -1}
			}
		};
		if (DMS_over) exitWith {};
		DMS_villageCleared = true;
		private _left = {alive _x && {_x distance2D DMS_villageCenter < _r}} count DMS_defenders;
		[format ["Village cleared at t=%1: %2 of %3 defenders left", round time, _left, _total]] call DMS_fnc_log;
		if (DMS_testMode) then { ["CHECK", ["village_cleared", true, format ["t=%1 left=%2/%3 assisted=%4", round time, _left, _total, DMS_testAssisted]]] call DMS_fnc_testMode; };
		["DMS_t_clear", "SUCCEEDED"] call BIS_fnc_taskSetState;
		[true, "DMS_t_hold",
			["The village is clear. Expect the insurgents to try to take it back. Hold it.", "Hold the village", ""],
			DMS_villageCenter, "ASSIGNED", 1, true, "defend"] call BIS_fnc_taskCreate;
		["SCHEDULE"] spawn DMS_fnc_counter;
	};
	default {};
};
