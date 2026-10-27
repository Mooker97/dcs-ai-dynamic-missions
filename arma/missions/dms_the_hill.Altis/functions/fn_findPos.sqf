/*
	DMS_fnc_findPos - seeded placement helpers (server only).
	["FLAT", [_center, _minR, _maxR, _clear]] -> [x, y, 0]: dry, flattest clear spot found in the ring
	["ROAD", [_pos, _radius]]                 -> [x, y, 0]: nearest road segment, or _pos if none
*/
params [["_mode", "FLAT", [""]], ["_args", [], [[]]]];

switch (_mode) do {
	case "FLAT": {
		_args params ["_center", ["_minR", 0], ["_maxR", 200], ["_clear", 15]];
		private _blockers = ["HOUSE", "BUILDING", "CHURCH", "CHAPEL", "RUIN", "FUELSTATION", "HOSPITAL", "ROCK", "ROCKS", "POWER LINES", "TRANSMITTER"];
		private _best = [_center select 0, _center select 1, 0];
		private _bestScore = -1;
		for "_i" from 1 to 80 do {
			private _p = _center getPos [["RANGE", [_minR, _maxR]] call DMS_fnc_rng, ["RANGE", [0, 360]] call DMS_fnc_rng];
			_p = [_p select 0, _p select 1, 0];
			private _ok = !(surfaceIsWater _p) && {!(isOnRoad _p)}
				&& {(nearestTerrainObjects [_p, _blockers, _clear, false, true]) isEqualTo []};
			if (_ok) then {
				private _flat = (surfaceNormal _p) select 2;
				if (_flat > _bestScore) then { _bestScore = _flat; _best = _p; };
			};
			if (_bestScore > 0.97) exitWith {};
		};
		if (_bestScore < 0) then {
			[format ["findPos FLAT: no clear spot near %1, using it unchanged", _center], "WARN"] call DMS_fnc_log;
		};
		_best
	};
	case "ROAD": {
		_args params ["_pos", ["_radius", 300]];
		private _roads = (_pos nearRoads _radius) apply { [_x distance2D _pos, _x] };
		if (_roads isEqualTo []) then {
			[_pos select 0, _pos select 1, 0]
		} else {
			_roads sort true;
			private _rp = getPosATL ((_roads select 0) select 1);
			[_rp select 0, _rp select 1, 0]
		};
	};
	default { [0, 0, 0] };
};
