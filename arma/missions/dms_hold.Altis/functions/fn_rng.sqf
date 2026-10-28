/*
	DMS_fnc_rng - seeded Wichmann-Hill generator (server only).
	All intermediate values stay below 2^24, so it is exact in SQF's 32-bit floats.
	["SEED", n] -> seed actually used      ["FLOAT"] -> [0, 1)
	["RANGE", [min, max]] -> float          ["INT", [min, max]] -> integer, inclusive
	["PICK", array] -> element              ["SHUFFLE", array] -> shuffled copy
	["CHANCE", p] -> bool
*/
params [["_mode", "FLOAT", [""]], ["_arg", 0]];

private _next = {
	private _s = missionNamespace getVariable ["DMS_rngState", [1, 2, 3]];
	_s params ["_a", "_b", "_c"];
	_a = (171 * _a) mod 30269;
	_b = (172 * _b) mod 30307;
	_c = (170 * _c) mod 30323;
	DMS_rngState = [_a, _b, _c];
	((_a / 30269) + (_b / 30307) + (_c / 30323)) mod 1
};

switch (_mode) do {
	case "SEED": {
		private _seed = (floor abs _arg) mod 1000000;
		DMS_rngState = [(_seed mod 30268) + 1, ((_seed * 3) mod 30306) + 1, ((_seed * 7) mod 30322) + 1];
		for "_i" from 1 to 10 do { call _next; };
		_seed
	};
	case "RANGE": {
		_arg params ["_min", "_max"];
		_min + ((call _next) * (_max - _min))
	};
	case "INT": {
		_arg params ["_min", "_max"];
		(_min + floor ((call _next) * (_max - _min + 1))) min _max
	};
	case "PICK": {
		private _n = count _arg;
		_arg select ((floor ((call _next) * _n)) min (_n - 1))
	};
	case "SHUFFLE": {
		private _arr = +_arg;
		for "_i" from (count _arr - 1) to 1 step -1 do {
			private _j = (floor ((call _next) * (_i + 1))) min _i;
			private _tmp = _arr select _i;
			_arr set [_i, _arr select _j];
			_arr set [_j, _tmp];
		};
		_arr
	};
	case "CHANCE": { (call _next) < _arg };
	default { call _next };
};
