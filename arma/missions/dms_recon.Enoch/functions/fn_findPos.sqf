/*
	DMS_fnc_findPos - seeded placement helpers (server only).
	["CLAMP", [_pos]]                            -> [x, y, 0] kept mapMargin inside the map
	["FLAT", [_center, _minR, _maxR, _clear, _avoidTrees]] -> [x, y, 0]: dry, flattest spot in the ring with no
	                                                building or rock within _clear; with _avoidTrees, fewer trees score better
	["FOREST", [_center, _maxR]]                 -> [[x, y, 0], score]: dry, gentle slope, no building within 150 m,
	                                                no road within 60 m, densest tree cover within 60 m (a battery hide)
	["ROAD", [_pos, _radius]]                    -> [x, y, 0]: nearest road segment, or _pos if none
*/
params [["_mode", "FLAT", [""]], ["_args", [], [[]]]];

switch (_mode) do {
	case "CLAMP": {
		_args params ["_pos"];
		private _m = DMS_cfg get "mapMargin";
		[((_pos select 0) max _m) min (worldSize - _m), ((_pos select 1) max _m) min (worldSize - _m), 0]
	};
	case "FLAT": {
		_args params ["_center", ["_minR", 0], ["_maxR", 200], ["_clear", 15], ["_avoidTrees", false]];
		private _blockers = ["HOUSE", "BUILDING", "CHURCH", "CHAPEL", "RUIN", "FUELSTATION", "HOSPITAL", "ROCK", "ROCKS", "POWER LINES", "TRANSMITTER"];
		private _best = ["CLAMP", [_center]] call DMS_fnc_findPos;
		private _bestScore = -1;
		for "_i" from 1 to 80 do {
			private _p = _center getPos [["RANGE", [_minR, _maxR]] call DMS_fnc_rng, ["RANGE", [0, 360]] call DMS_fnc_rng];
			_p = ["CLAMP", [_p]] call DMS_fnc_findPos;
			private _ok = !(surfaceIsWater _p) && {!(isOnRoad _p)}
				&& {(nearestTerrainObjects [_p, _blockers, _clear, false, true]) isEqualTo []};
			if (_ok) then {
				private _flat = (surfaceNormal _p) select 2;
				if (_avoidTrees) then {
					_flat = _flat - 0.01 * count (nearestTerrainObjects [_p, ["TREE", "SMALL TREE", "BUSH"], _clear, false, true]);
				};
				if (_flat > _bestScore) then { _bestScore = _flat; _best = _p; };
			};
			if (_bestScore > 0.97 && {!_avoidTrees || {_bestScore > 0.99}}) exitWith {};
		};
		if (_bestScore < 0) then {
			[format ["findPos FLAT: no clear spot near %1, using it unchanged", _center], "WARN"] call DMS_fnc_log;
		};
		_best
	};
	case "FOREST": {
		_args params ["_center", ["_maxR", 500]];
		private _blockers = ["HOUSE", "BUILDING", "CHURCH", "CHAPEL", "RUIN", "FUELSTATION", "HOSPITAL", "POWER LINES", "TRANSMITTER"];
		private _best = ["CLAMP", [_center]] call DMS_fnc_findPos;
		private _bestScore = -1;
		for "_i" from 1 to 60 do {
			private _p = _center getPos [["RANGE", [0, _maxR]] call DMS_fnc_rng, ["RANGE", [0, 360]] call DMS_fnc_rng];
			_p = ["CLAMP", [_p]] call DMS_fnc_findPos;
			if (!(surfaceIsWater _p) && {((surfaceNormal _p) select 2) > 0.96}
				&& {(_p nearRoads 60) isEqualTo []}
				&& {(nearestTerrainObjects [_p, _blockers, 150, false, true]) isEqualTo []}) then {
				private _trees = count (nearestTerrainObjects [_p, ["TREE"], 60, false, true]);
				// Cover matters most; a very steep or wet spot never gets here.
				private _score = _trees * ((surfaceNormal _p) select 2);
				if (_score > _bestScore) then { _bestScore = _score; _best = _p; };
			};
		};
		if (_bestScore < 0) then {
			[format ["findPos FOREST: no usable spot near %1, using the anchor", _center], "WARN"] call DMS_fnc_log;
		};
		[_best, _bestScore]
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
