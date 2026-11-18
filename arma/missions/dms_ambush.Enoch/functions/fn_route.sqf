/*
	DMS_fnc_route - road trace and site layout (server only).
	["TRACE", [_road, _heading, _length]] -> [_points, _length]: walk the road network from road segment
	    _road in compass direction _heading, always taking the straightest connected segment (same road type
	    preferred), until _length metres; _points are [x, y, 0] in order, starting next to _road.
	["SITE", [_siteXY, _fromForward, _startDist]] -> HashMap or nil: snap to a road segment near _siteXY that
	    has enough road on both sides, then lay out the kill zone, convoy entry and exit traces, kill line,
	    ambush position (higher, better-sighted side of the road), squad start and rally point.
	    _fromForward picks which way the convoy travels (seeded by the caller).
*/
params [["_mode", "", [""]], ["_args", [], [[]]]];

switch (_mode) do {
	case "TRACE": {
		_args params ["_road", "_heading", "_length"];
		// getRoadInfo: [mapType, width, isPedestrian, texture, textureEnd, material, begPos, endPos, isBridge, ...];
		// mapType is compared upper-case ("ROAD", "MAIN ROAD", "TRACK").
		private _types = DMS_cfg get "roadTypes";
		private _type0 = (getRoadInfo _road) select 0;
		private _visited = [_road];
		private _pts = [];
		private _dist = 0;
		private _cur = _road;
		private _last = getPosATL _road;
		private _hdg = _heading;
		private _steps = 0;
		while {_dist < _length && {_steps < 800}} do {
			_steps = _steps + 1;
			private _cands = (roadsConnectedTo _cur) - _visited;
			if (_cands isEqualTo []) then {
				// Some junctions are not linked; look for road segments just ahead instead.
				_cands = ((_last nearRoads 45) - _visited) select {
					private _d = (((_last getDir _x) - _hdg) + 540) mod 360 - 180;
					abs _d < 70 && {(_x distance2D _last) > 2}
				};
			};
			private _best = objNull;
			private _bestCost = 1e9;
			{
				private _p = getPosATL _x;
				if ((_p distance2D _last) > 0.5) then {
					private _turn = abs ((((_last getDir _p) - _hdg) + 540) mod 360 - 180);
					private _info = getRoadInfo _x;
					private _cost = _turn + ([30, 0] select ((_info select 0) == _type0)) + ([60, 0] select ((toUpper (_info select 0)) in _types));
					if (_turn < 80 && {_cost < _bestCost}) then { _bestCost = _cost; _best = _x; };
				};
			} forEach _cands;
			if (isNull _best) exitWith {};
			private _p = getPosATL _best;
			_dist = _dist + (_p distance2D _last);
			_hdg = _last getDir _p;
			_last = _p;
			_cur = _best;
			_visited pushBack _best;
			_pts pushBack [_p select 0, _p select 1, 0];
		};
		[_pts, _dist]
	};

	case "SITE": {
		_args params ["_xy", ["_fromForward", true], ["_startDist", 800]];
		private _cfg = DMS_cfg;
		private _types = _cfg get "roadTypes";
		private _ws = worldSize;
		private _margin = _cfg get "mapMargin";
		private _inMap = {
			params ["_p"];
			(_p select 0) > _margin && {(_p select 0) < (_ws - _margin)} && {(_p select 1) > _margin} && {(_p select 1) < (_ws - _margin)}
				&& {!(surfaceIsWater _p)}
		};
		private _nVeh = count (_cfg get "convoy");
		private _needIn = (_cfg get "entryDistance") + (_nVeh + 1) * (_cfg get "convoyGap");
		private _needOut = _cfg get "exitDistance";
		private _center = [_xy select 0, _xy select 1, 0];

		// 1. a real road segment (road/main road, not a bridge) with enough road both ways
		private _roads = ((_center nearRoads (_cfg get "roadSnapRadius")) select {
			private _i = getRoadInfo _x;
			((toUpper (_i select 0)) in _types) && {!(_i select 8)}
		}) apply { [_x distance2D _center, _x] };
		_roads sort true;
		if (_roads isEqualTo []) exitWith {
			[format ["Route: no road of type %1 within %2 m of %3", _types, _cfg get "roadSnapRadius", _xy], "ERROR"] call DMS_fnc_log;
			nil
		};
		private _pick = [];
		private _bestScore = -1;
		{
			private _road = _x select 1;
			private _i = getRoadInfo _road;
			private _dir = (_i select 6) getDir (_i select 7);
			private _fw = ["TRACE", [_road, _dir, _needIn max _needOut]] call DMS_fnc_route;
			private _bw = ["TRACE", [_road, (_dir + 180) mod 360, _needIn max _needOut]] call DMS_fnc_route;
			private _inT = [_bw, _fw] select _fromForward;
			private _outT = [_fw, _bw] select _fromForward;
			private _score = (((_inT select 1) / _needIn) min 1) + (((_outT select 1) / _needOut) min 1);
			if (_score > _bestScore) then { _bestScore = _score; _pick = [_road, _dir, _inT, _outT]; };
			if (_score >= 2 || {_forEachIndex >= 11}) exitWith {};
		} forEach _roads;
		_pick params ["_road", "_dir", "_inT", "_outT"];
		if (count (_inT select 0) < 2 || {count (_outT select 0) < 2}) exitWith {
			[format ["Route: road near %1 is not connected (trace %2 / %3 points)", _xy, count (_inT select 0), count (_outT select 0)], "ERROR"] call DMS_fnc_log;
			nil
		};
		private _kz = getPosATL _road;
		_kz = [_kz select 0, _kz select 1, 0];
		if (_bestScore < 2) then {
			[format ["Route: best road near %1 has only %2 m in / %3 m out (wanted %4 / %5)",
				_xy, round (_inT select 1), round (_outT select 1), round _needIn, round _needOut], "WARN"] call DMS_fnc_log;
		};
		private _inPts = _inT select 0; // from the kill zone back towards the convoy's start
		private _outPts = _outT select 0; // from the kill zone onwards to the exit

		// cumulative distances; kill line and travel direction through the kill zone
		private _cum = {
			params ["_pts"];
			private _acc = 0;
			private _prev = _kz;
			_pts apply { _acc = _acc + (_x distance2D _prev); _prev = _x; _acc }
		};
		private _inCum = [_inPts] call _cum;
		private _outCum = [_outPts] call _cum;
		private _killIdx = _outCum findIf {_x >= (_cfg get "killLineDistance")};
		if (_killIdx < 0) then { _killIdx = (count _outPts - 1) max 0; };
		private _beyond = _outPts select [_killIdx, 9999];
		private _aIn = _inPts select ((_inCum findIf {_x >= 50}) max 0);
		private _aOut = _outPts select ((_outCum findIf {_x >= 50}) max 0);
		private _travel = _aIn getDir _aOut;

		// convoy spawn points (lead first), each facing the kill zone
		private _spawns = [];
		for "_v" from 0 to (_nVeh - 1) do {
			private _want = (_cfg get "entryDistance") + _v * (_cfg get "convoyGap");
			private _k = _inCum findIf {_x >= _want};
			if (_k < 0) then { _k = (count _inPts - 1) - ((_nVeh - 1 - _v) * 3); };
			_k = (_k max 1) min (count _inPts - 1);
			private _sp = _inPts select _k;
			_spawns pushBack [_sp, _sp getDir (_inPts select (_k - 1))];
		};

		// waypoints: along the entry trace towards the kill zone, the kill zone, then out to the exit
		private _wps = [];
		private _spacing = _cfg get "waypointSpacing";
		private _next = (_cfg get "entryDistance") - _spacing;
		for "_k" from (count _inPts - 1) to 0 step -1 do {
			if ((_inCum select _k) <= _next && {(_inCum select _k) > 60}) then { _wps pushBack (_inPts select _k); _next = (_inCum select _k) - _spacing; };
		};
		_wps pushBack _kz;
		_next = _spacing;
		{ if ((_outCum select _forEachIndex) >= _next) then { _wps pushBack _x; _next = _next + _spacing; }; } forEach _outPts;
		if (_outPts isNotEqualTo [] && {(_wps select (count _wps - 1)) isNotEqualTo (_outPts select (count _outPts - 1))}) then { _wps pushBack (_outPts select (count _outPts - 1)); };

		// 2. ambush position: the side of the road with the better view of the kill zone, then height
		private _amDist = ["RANGE", _cfg get "ambushDistance"] call DMS_fnc_rng;
		private _kzPts = ((_inPts select {(_x distance2D _kz) < 150}) + (_outPts select {(_x distance2D _kz) < 150}) + [_kz]);
		private _best = [];
		private _bestS = -1e9;
		{
			private _side = _x;
			private _brg = (_travel + 90 * _side + 360) mod 360;
			private _p = ["FLAT", [_kz getPos [_amDist, _brg], 0, 35, 6]] call DMS_fnc_findPos;
			private _st = ["FLAT", [_p getPos [_startDist, _brg], 0, 120, 8]] call DMS_fnc_findPos;
			private _rp = _p getPos [_cfg get "rpDistance", _brg];
			private _eye = AGLToASL [_p select 0, _p select 1, 1.2];
			private _vis = { !(terrainIntersectASL [_eye, AGLToASL [_x select 0, _x select 1, 2]]) } count _kzPts;
			private _h = (getTerrainHeightASL _p) - (getTerrainHeightASL _kz);
			private _ok = ([_p] call _inMap) && {[_st] call _inMap} && {[_rp] call _inMap};
			private _s = (_vis * 10) + (_h min 30) + ([-1000, 0] select _ok);
			[format ["Route: side %1 (bearing %2) ambush %3 visible %4/%5 height %6 m in-map %7 score %8",
				_side, round _brg, _p, _vis, count _kzPts, round _h, _ok, round _s]] call DMS_fnc_log;
			if (_s > _bestS) then { _bestS = _s; _best = [_side, _brg, _p]; };
		} forEach [1, -1];
		_best params ["_side", "_away", "_ambush"];

		// 3. squad start and rally point, away from the road, off-axis so they don't share a line
		private _stOff = ["RANGE", [-35, 35]] call DMS_fnc_rng;
		private _start = ["FLAT", [_ambush getPos [_startDist, _away + _stOff], 0, (_startDist * 0.15) min 120, 8]] call DMS_fnc_findPos;
		private _rpOff = ["RANGE", [40, 75]] call DMS_fnc_rng;
		if (_stOff > 0) then { _rpOff = -_rpOff; };
		private _rpNominal = _ambush getPos [_cfg get "rpDistance", _away + _rpOff];
		if (!([_rpNominal] call _inMap)) then { _rpNominal = _ambush getPos [_cfg get "rpDistance", _away]; };
		private _route = _inPts + _outPts;
		private _farFromRoute = {
			params ["_p"];
			(_route findIf {(_x distance2D _p) < (DMS_cfg get "rpMinRouteDistance")}) < 0
		};
		// Prefer a nearby track or road for the pickup vehicles, if one is clear of the convoy's road.
		private _rp = [];
		private _rpRoads = ((_rpNominal nearRoads 250) apply { [_x distance2D _rpNominal, _x] });
		_rpRoads sort true;
		{
			private _q = getPosATL (_x select 1);
			if ([_q] call _farFromRoute && {[_q] call _inMap}) exitWith { _rp = [_q select 0, _q select 1, 0]; };
		} forEach _rpRoads;
		private _rpOnRoad = _rp isNotEqualTo [];
		if (!_rpOnRoad) then { _rp = ["FLAT", [_rpNominal, 0, 150, 12]] call DMS_fnc_findPos; };
		if (!([_rp] call _farFromRoute)) then {
			[format ["Route: rally point %1 is closer than %2 m to the convoy road", _rp, _cfg get "rpMinRouteDistance"], "WARN"] call DMS_fnc_log;
		};

		createHashMapFromArray [
			["killZone", _kz],
			["road", _road],
			["travelDir", _travel],
			["inPts", _inPts],
			["outPts", _outPts],
			["inLength", _inT select 1],
			["outLength", _outT select 1],
			["killLine", _outPts select (_killIdx min ((count _outPts - 1) max 0))],
			["beyond", _beyond],
			["spawns", _spawns],
			["waypoints", _wps],
			["ambush", _ambush],
			["awayDir", _away],
			["start", _start],
			["rp", _rp],
			["rpOnRoad", _rpOnRoad]
		]
	};
	default {};
};
