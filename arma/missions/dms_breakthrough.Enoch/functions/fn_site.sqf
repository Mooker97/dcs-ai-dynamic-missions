/*
	DMS_fnc_site - site layout from the configured approach route (server only).
	["LAYOUT", [_site, _startDist]] -> HashMap: route points, distance to go, crossroads, start, phase line,
	    treeline tank spots, ATGM spot, BMP spot, counter-attack spawn, rear bearing (all seeded and logged).
	    _startDist > 0 (test only) drops route points further than that from the crossroads.
	["SPOTS", [_route, _toGo, _band, _offsets, _ringMin]] -> [[side, pos, roadPt], ...]: firing positions beside
	    the road: no tree within 9 m, at least _ringMin trees within 35 m (a treeline), flat, dry, and line of
	    sight from 2.5 m to 2.5 m above the road point. side 1 = right of the direction of advance, -1 = left.
	["INDEX", [_pos]] -> index of the route point nearest _pos (DMS_layout must exist).
*/
params [["_mode", "", [""]], ["_args", [], [[]]]];

switch (_mode) do {
	case "SPOTS": {
		_args params ["_route", "_toGo", "_band", "_offsets", ["_ringMin", 4]];
		_band params ["_bMin", "_bMax"];
		_offsets params ["_oMin", "_oMax"];
		private _out = [];
		{
			private _d = _toGo select _forEachIndex;
			if (_d >= _bMin && {_d <= _bMax} && {_forEachIndex < (count _route - 1)}) then {
				private _p = _x;
				private _dir = _p getDir (_route select (_forEachIndex + 1));
				{
					private _side = _x;
					for "_o" from _oMin to _oMax step 50 do {
						private _q = _p getPos [_o, _dir + 90 * _side];
						_q = [_q select 0, _q select 1, 0];
						if (!(surfaceIsWater _q) && {((surfaceNormal _q) select 2) > 0.96}
							&& {(nearestTerrainObjects [_q, ["TREE", "SMALL TREE", "HOUSE", "BUILDING", "ROCK", "ROCKS"], 9, false, true]) isEqualTo []}
							&& {(count (nearestTerrainObjects [_q, ["TREE", "SMALL TREE"], 35, false, true])) >= _ringMin}
							&& {!(terrainIntersectASL [AGLToASL [_q select 0, _q select 1, 2.5], AGLToASL [_p select 0, _p select 1, 2.5]])}) then {
							_out pushBack [_side, _q, _p];
						};
					};
				} forEach [1, -1];
			};
		} forEach _route;
		_out
	};

	case "INDEX": {
		_args params ["_pos"];
		private _route = DMS_layout get "route";
		private _best = 0;
		private _bd = 1e9;
		{ private _d = _x distance2D _pos; if (_d < _bd) then { _bd = _d; _best = _forEachIndex; }; } forEach _route;
		_best
	};

	case "LAYOUT": {
		_args params ["_site", ["_startDist", 0]];
		_site params ["_name", "_vxy", "_pts"];
		private _cfg = DMS_cfg;
		private _route = _pts apply { [_x select 0, _x select 1, 0] };
		// distance to go along the route from each point to the last one
		private _toGo = [];
		private _acc = 0;
		for "_i" from (count _route - 1) to 0 step -1 do {
			if (_i < (count _route - 1)) then { _acc = _acc + ((_route select _i) distance2D (_route select (_i + 1))); };
			_toGo set [_i, _acc];
		};
		if (_startDist > 0) then {
			private _keep = _toGo findIf {_x <= _startDist};
			if (_keep > 0) then {
				_route = _route select [_keep, 999];
				_toGo = _toGo select [_keep, 999];
			};
		};

		// crossroads: a road segment with 3+ connections near the village point, else the nearest road
		private _v = [_vxy select 0, _vxy select 1, 0];
		private _junctions = ((_v nearRoads (_cfg get "crossroadsSnap")) select {(count (roadsConnectedTo _x)) >= 3}) apply { [_x distance2D _v, _x] };
		_junctions sort true;
		private _xr = if (_junctions isNotEqualTo []) then {
			private _q = getPosATL ((_junctions select 0) select 1);
			[_q select 0, _q select 1, 0]
		} else {
			["ROAD", [_v, 200]] call DMS_fnc_findPos
		};

		private _si = (_cfg get "tankStartIndex") min (count _route - 4);
		private _start = _route select _si;
		private _startDir = _start getDir (_route select (_si + 1));
		private _plIdx = (_toGo findIf {_x <= (_cfg get "phaseLineDistance")}) max 0;
		private _rear = _xr getDir _start;

		// treeline ambush: seeded side among the sides that have spots, then a seeded spot and its pair
		private _spots = ["SPOTS", [_route, _toGo, _cfg get "treelineBand", _cfg get "treelineOffset", 4]] call DMS_fnc_site;
		private _order = [[1, -1], [-1, 1]] select (["CHANCE", 0.5] call DMS_fnc_rng);
		private _sides = _order select { private _s = _x; (_spots findIf {(_x select 0) == _s}) > -1 };
		private _tl = [];
		private _tlSide = 1;
		if (_sides isNotEqualTo []) then {
			_tlSide = _sides select 0;
			private _mine = _spots select {(_x select 0) == _tlSide};
			private _first = ["PICK", _mine] call DMS_fnc_rng;
			_tl pushBack [_first select 1, (_first select 1) getDir (_first select 2)];
			(_cfg get "treelinePair") params ["_pMin", "_pMax"];
			private _pairs = _mine select {private _d = (_x select 1) distance2D (_first select 1); _d >= _pMin && {_d <= _pMax}};
			if (_pairs isNotEqualTo []) then {
				private _second = ["PICK", _pairs] call DMS_fnc_rng;
				_tl pushBack [_second select 1, (_second select 1) getDir (_second select 2)];
			} else {
				private _q = ["CLEAR", [_first select 1, _pMin, _pMax, 6, [_first select 1]]] call DMS_fnc_findPos;
				if (_q isEqualTo []) then { _q = (_first select 1) getPos [_pMin, ((_first select 1) getDir (_first select 2)) + 90]; };
				_tl pushBack [_q, _q getDir (_first select 2)];
			};
			[format ["Site: %1 treeline spots (%2 right, %3 left); tanks on the %4 at %5",
				count _spots, {(_x select 0) == 1} count _spots, {(_x select 0) == -1} count _spots, ["left", "right"] select (_tlSide == 1), _tl apply {(_x select 0) apply {round _x}}]] call DMS_fnc_log;
		} else {
			_tlSide = [1, -1] select (["CHANCE", 0.5] call DMS_fnc_rng);
			private _mid = _toGo findIf {_x <= 1300};
			private _p = _route select (_mid max 0);
			private _dir = _p getDir _xr;
			private _q1 = ["FLAT", [_p getPos [450, _dir + 90 * _tlSide], 0, 100, 6]] call DMS_fnc_findPos;
			private _q2 = ["FLAT", [_q1, 50, 120, 6]] call DMS_fnc_findPos;
			_tl = [[_q1, _q1 getDir _p], [_q2, _q2 getDir _p]];
			[format ["Site: no treeline spot with line of sight to the road; tanks placed in the open at %1", _tl apply {(_x select 0) apply {round _x}}], "WARN"] call DMS_fnc_log;
		};
		_tl resize ((_cfg get "treelineTanks") min (count _tl));

		// ATGM team: usually the other flank, closer to the village
		private _atSide = if (["CHANCE", _cfg get "atgmOppositeChance"] call DMS_fnc_rng) then { -_tlSide } else { _tlSide };
		private _atSpots = ["SPOTS", [_route, _toGo, _cfg get "atgmBand", _cfg get "atgmOffset", 3]] call DMS_fnc_site;
		private _atMine = _atSpots select {(_x select 0) == _atSide};
		if (_atMine isEqualTo []) then { _atMine = _atSpots; };
		private _atgm = [];
		if (_atMine isNotEqualTo []) then {
			private _a = ["PICK", _atMine] call DMS_fnc_rng;
			_atgm = [_a select 1, (_a select 1) getDir (_a select 2)];
			_atSide = _a select 0;
		} else {
			private _mid = _toGo findIf {_x <= 800};
			private _p = _route select (_mid max 0);
			private _q = ["FLAT", [_p getPos [400, (_p getDir _xr) + 90 * _atSide], 0, 100, 4]] call DMS_fnc_findPos;
			_atgm = [_q, _q getDir _p];
			[format ["Site: no ATGM spot with line of sight to the road; using %1", _q apply {round _x}], "WARN"] call DMS_fnc_log;
		};

		// BMP at the village edge, beside the road, facing the approach
		private _bd = ["RANGE", _cfg get "villageIfvDistance"] call DMS_fnc_rng;
		private _bi = (_toGo findIf {_x <= _bd}) max 1;
		private _bp = _route select _bi;
		private _bSide = [1, -1] select (["CHANCE", 0.5] call DMS_fnc_rng);
		private _bDir = (_route select (_bi - 1)) getDir _bp;
		private _bNom = _bp getPos [["RANGE", _cfg get "villageIfvOffset"] call DMS_fnc_rng, _bDir + 90 * _bSide];
		private _bPos = ["CLEAR", [_bNom, 0, 30, 5, []]] call DMS_fnc_findPos;
		if (_bPos isEqualTo []) then { _bPos = ["CLEAR", [_bNom, 0, 70, 4, []]] call DMS_fnc_findPos; };
		if (_bPos isEqualTo []) then { _bPos = [_bNom select 0, _bNom select 1, 0]; };
		private _bmp = [_bPos, _bDir + 180];

		// counter-attack: far side of the village, on a road
		private _ws = worldSize;
		private _m = _cfg get "mapMargin";
		private _cNom = _xr getPos [_cfg get "counterDistance", _rear + 180];
		_cNom = [((_cNom select 0) max _m) min (_ws - _m), ((_cNom select 1) max _m) min (_ws - _m), 0];
		private _counter = ["ROAD", [_cNom, 400]] call DMS_fnc_findPos;
		if (surfaceIsWater _counter) then { _counter = _xr getPos [600, _rear + 180]; };

		// fuzzed objective area
		private _fz = _xr getPos [["RANGE", _cfg get "objMarkerFuzz"] call DMS_fnc_rng, ["RANGE", [0, 360]] call DMS_fnc_rng];

		createHashMapFromArray [
			["name", _name],
			["village", _v],
			["route", _route],
			["toGo", _toGo],
			["crossroads", _xr],
			["startIndex", _si],
			["start", _start],
			["startDir", _startDir],
			["phaseLine", _route select _plIdx],
			["rear", _rear],
			["treeline", _tl],
			["treelineSide", _tlSide],
			["atgm", _atgm],
			["atgmSide", _atSide],
			["bmp", _bmp],
			["counter", _counter],
			["objFuzz", [_fz select 0, _fz select 1, 0]]
		]
	};
	default {};
};
