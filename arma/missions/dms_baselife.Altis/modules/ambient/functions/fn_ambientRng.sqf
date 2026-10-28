/*
	DMSA_fnc_ambientRng - seeded Wichmann-Hill generator for the ambient module (server only).
	Separate state (DMSA_rngState) so the module never shifts a mission's own DMS_fnc_rng draws.
	["SEED", n] -> seed used      ["FLOAT"] -> [0, 1)
	["RANGE", [min, max]] -> float ["INT", [min, max]] -> integer, inclusive
	["PICK", array] -> element     ["SHUFFLE", array] -> shuffled copy
*/
params [["_mode", "FLOAT", [""]], ["_arg", 0]];

private _next = {
	private _s = missionNamespace getVariable ["DMSA_rngState", [11, 22, 33]];
	_s params ["_a", "_b", "_c"];
	_a = (171 * _a) mod 30269;
	_b = (172 * _b) mod 30307;
	_c = (170 * _c) mod 30323;
	DMSA_rngState = [_a, _b, _c];
	((_a / 30269) + (_b / 30307) + (_c / 30323)) mod 1
};

switch (_mode) do {
	case "SEED": {
		private _seed = (floor abs _arg) mod 1000000;
		DMSA_rngState = [(_seed mod 30268) + 1, ((_seed * 5) mod 30306) + 1, ((_seed * 11) mod 30322) + 1];
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
	default { call _next };
};
