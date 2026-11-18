/*
	DMS_fnc_op - set up the observation post (server only).
	["SQUAD"] call DMS_fnc_op;    create the AI squad in DMS_squad, give the player the RHS loadout,
	                              spread everyone over the OP (tower positions first) and hold them there
	["STATIC"] call DMS_fnc_op;   place the static HMG/GMG at a clear spot, facing the threat sector, crewed
	["OVERRUN"] spawn DMS_fnc_op; fail if the enemy holds the OP area with no friendlies for overrunTime
	Uses DMS_opCenter, DMS_threatBearing.
*/
params [["_mode", "", [""]], ["_args", [], [[]]]];
private _cfg = DMS_cfg;

switch (_mode) do {
	case "SQUAD": {
		private _classes = +(_cfg get "squadClasses");
		if (isNull DMS_player) then { _classes = [_cfg get "squadLeaderClass"] + _classes; };
		{
			private _u = DMS_squad createUnit [_x, DMS_opCenter, [], 5, "NONE"];
			_u setSkill (_cfg get "squadSkill");
		} forEach _classes;
		if (!isNull DMS_player && {local DMS_player}) then {
			// TO VERIFY in-engine: setUnitLoadout with a CfgVehicles config entry.
			DMS_player setUnitLoadout (configFile >> "CfgVehicles" >> (_cfg get "playerLoadoutClass"));
			[format ["Player loadout set from %1", _cfg get "playerLoadoutClass"]] call DMS_fnc_log;
		};

		// Fighting positions: building positions of the outpost's towers/houses (highest first), then
		// clear ground spread round the OP.
		private _blds = nearestObjects [DMS_opCenter, _cfg get "outpostClasses", _cfg get "opRadius"];
		private _bpos = [];
		{ { _bpos pushBack [(_x select 2), _x]; } forEach (_x buildingPos -1); } forEach _blds;
		_bpos sort false;
		_bpos = _bpos apply {_x select 1};
		private _nPos = count _bpos;
		private _units = (units DMS_squad) select {_x != DMS_player};
		private _gunner = _units findIf {typeOf _x == (_cfg get "staticGunnerClass")};
		DMS_staticGunner = objNull;
		if (_gunner > -1) then { DMS_staticGunner = _units select _gunner; };
		private _taken = [];
		private _placed = 0;
		private _inBld = 0;
		{
			private _u = _x;
			private _p = [];
			if (_u != DMS_staticGunner && {_bpos isNotEqualTo []} && {_inBld < (_cfg get "squadInBuildings")}) then {
				_p = _bpos deleteAt 0;
				_inBld = _inBld + 1;
			} else {
				private _c = ["CLEAR", [DMS_opCenter, 8, 35, 1.5, _taken]] call DMS_fnc_findPos;
				if (_c isNotEqualTo []) then { _p = _c; _taken pushBack _c; };
			};
			if (_p isNotEqualTo []) then {
				_u setPosATL _p;
				_placed = _placed + 1;
			};
			_u setDir (DMS_threatBearing + ((_forEachIndex - 3) * 25));
			doStop _u;
		} forEach _units;
		if (!isNull DMS_player) then {
			if ((DMS_player distance2D DMS_opCenter) > 40) then {
				private _c = ["CLEAR", [DMS_opCenter, 0, 20, 1, _taken]] call DMS_fnc_findPos;
				if (_c isEqualTo []) then { _c = [DMS_opCenter select 0, DMS_opCenter select 1, 0]; };
				[DMS_player, _c] remoteExecCall ["setPosATL", DMS_player];
				[DMS_player, DMS_threatBearing] remoteExecCall ["setDir", DMS_player];
			};
		};
		DMS_squad setBehaviour "AWARE";
		DMS_squad setCombatMode "YELLOW";
		[format ["Squad: %1 units at the OP, %2 placed (%3 building positions from %4 structures)",
			count (units DMS_squad), _placed, _nPos, count _blds]] call DMS_fnc_log;
	};

	case "STATIC": {
		private _list = _cfg get "staticClasses";
		private _idx = _list findIf {isClass (configFile >> "CfgVehicles" >> _x)};
		if (_idx < 0) exitWith { ["Static weapon: no class exists", "WARN"] call DMS_fnc_log; };
		(_cfg get "staticRing") params ["_rMin", "_rMax"];
		private _pos = ["CLEAR", [DMS_opCenter getPos [(_rMin + _rMax) / 2, DMS_threatBearing], 0, _rMax / 2, 3, []]] call DMS_fnc_findPos;
		if (_pos isEqualTo []) then { _pos = ["CLEAR", [DMS_opCenter, _rMin, _rMax, 2, []]] call DMS_fnc_findPos; };
		if (_pos isEqualTo []) then {
			_pos = [DMS_opCenter select 0, DMS_opCenter select 1, 0];
			["Static weapon: no clear spot found, using the OP centre", "WARN"] call DMS_fnc_log;
		};
		DMS_static = createVehicle [_list select _idx, _pos, [], 0, "CAN_COLLIDE"];
		DMS_static setDir DMS_threatBearing;
		DMS_static setPosATL _pos;
		if (!isNull DMS_staticGunner) then { DMS_staticGunner moveInGunner DMS_static; };
		[format ["Static: %1 at %2 m from the OP centre facing %3, gunner %4",
			typeOf DMS_static, round (DMS_static distance2D DMS_opCenter), round DMS_threatBearing,
			[typeOf DMS_staticGunner, "none"] select (isNull DMS_staticGunner)]] call DMS_fnc_log;
	};

	case "OVERRUN": {
		private _r = _cfg get "opRadius";
		private _need = [_cfg get "overrunTime", 20] call DMS_fnc_t;
		private _since = -1;
		while {!DMS_over} do {
			sleep 5;
			private _east = {alive _x && {side (group _x) == east} && {_x distance2D DMS_opCenter < _r}} count allUnits;
			private _west = {alive _x && {side (group _x) == west} && {!captive _x} && {_x distance2D DMS_opCenter < _r}} count allUnits;
			if (_east > 0 && {_west == 0}) then {
				if (_since < 0) then {
					_since = time;
					[format ["OP contested: %1 enemy inside %2 m, no friendlies", _east, _r], "WARN"] call DMS_fnc_log;
					if (!isNull DMS_player) then { "The enemy is inside the OP. Retake it or the position is lost." remoteExecCall ["hintSilent", DMS_player]; };
				};
				if (time - _since >= _need) exitWith {
					["DMS_FailOverrun", false, format ["OP overrun (%1 enemy, no friendlies for %2 s)", _east, round (time - _since)]] call DMS_fnc_end;
				};
			} else {
				if (_since >= 0) then {
					_since = -1;
					[format ["OP no longer contested (%1 east, %2 west inside)", _east, _west]] call DMS_fnc_log;
				};
			};
		};
	};
	default {};
};
