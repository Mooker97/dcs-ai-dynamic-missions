/*
	DMS_fnc_waves - the attack (server only).
	["PLAN"] call DMS_fnc_waves;          seeded plan at init (fixed draw order): bearings, spawn points,
	                                      gaps, the support-by-fire position -> DMS_wavePlan, DMS_sbfPos
	["RUN"] spawn DMS_fnc_waves;          director: prep time, waves 1..n, relief, win
	["SPAWN", [_n]] call DMS_fnc_waves;   spawn wave _n and give its groups their LAMBS task
	["ALIVE", [_n]] call DMS_fnc_waves;   -> men of wave _n still alive
	["BROKEN", [_n]] call DMS_fnc_waves;  -> true when wave _n is down to waveBrokenFraction or less
	["SBF"] spawn DMS_fnc_waves;          the support-by-fire vehicle: drive in, hold at stand-off, withdraw
	["SPOT", [_bearing, [_min, _max], _wantLOS]] -> [x, y, 0]: dry, gentle spot on that bearing from the
	                                      OP, hidden from the OP (or, with _wantLOS, in sight of it)
	All waits are bounded and end on DMS_over.
*/
params [["_mode", "", [""]], ["_args", [], [[]]]];
private _cfg = DMS_cfg;

switch (_mode) do {
	case "SPOT": {
		_args params ["_brg", "_range", ["_wantLOS", false]];
		_range params ["_dMin", "_dMax"];
		private _eye = AGLToASL [DMS_opCenter select 0, DMS_opCenter select 1, 3];
		private _best = [];
		private _bestScore = -99;
		for "_i" from 1 to 16 do {
			private _b = _brg + (["RANGE", [-20, 20]] call DMS_fnc_rng);
			private _p = DMS_opCenter getPos [["RANGE", [_dMin, _dMax]] call DMS_fnc_rng, _b];
			_p = [_p select 0, _p select 1, 0];
			if (!(surfaceIsWater _p)) then {
				private _flat = (surfaceNormal _p) select 2;
				private _seen = !(terrainIntersectASL [_eye, AGLToASL [_p select 0, _p select 1, 2]]);
				private _score = _flat + ([0, 1] select (_seen isEqualTo _wantLOS)) - ([0, 0.5] select (isOnRoad _p && {!_wantLOS}));
				if (_flat > 0.9 && {_score > _bestScore}) then { _bestScore = _score; _best = _p; };
			};
			if (_bestScore > 1.95) exitWith {};
		};
		if (_best isEqualTo []) then {
			_best = DMS_opCenter getPos [(_dMin + _dMax) / 2, _brg];
			_best = [_best select 0, _best select 1, 0];
			[format ["Wave spot: nothing dry and gentle on bearing %1, using %2 unchanged (TO VERIFY)", round _brg, _best], "WARN"] call DMS_fnc_log;
		};
		_best
	};

	case "PLAN": {
		private _brgs = ["SHUFFLE", DMS_enemyBearings] call DMS_fnc_rng;
		private _waves = _cfg get "waves";
		private _dist = _cfg get "waveSpawnDistance";
		if (DMS_testMode && {DMS_testStartDist > 0}) then {
			private _d = DMS_testStartDist max (_cfg get "testWaveSpawnDistance");
			_dist = [_d, _d + 150];
		};
		DMS_wavePlan = [];
		{
			private _brg = _brgs select (_forEachIndex mod (count _brgs));
			private _groups = [];
			{
				_x params ["_tactic", "_size", ["_off", 0]];
				private _side = [-1, 1] select (["CHANCE", 0.5] call DMS_fnc_rng);
				private _gb = _brg + (_side * _off);
				private _spawn = ["SPOT", [_gb, _dist, false]] call DMS_fnc_waves;
				_groups pushBack [_tactic, _size, _gb, _spawn];
			} forEach _x;
			private _gap = ["RANGE", _cfg get "waveGapMax"] call DMS_fnc_rng;
			DMS_wavePlan pushBack [_brg, _groups, _gap];
			[format ["Plan: wave %1 from bearing %2, %3 group(s): %4, next wave after at most %5 s",
				_forEachIndex + 1, round _brg, count _groups,
				(_groups apply {format ["%1x%2 brg %3 at %4 m (seen from OP: %5)", _x select 0, _x select 1, round (_x select 2),
					round ((_x select 3) distance2D DMS_opCenter),
					!(terrainIntersectASL [AGLToASL [DMS_opCenter select 0, DMS_opCenter select 1, 3], AGLToASL [(_x select 3) select 0, (_x select 3) select 1, 2]])]}) joinString "; ",
				round _gap]] call DMS_fnc_log;
		} forEach _waves;
		private _sbfIdx = ((_cfg get "sbfWave") - 1) min ((count DMS_wavePlan) - 1);
		private _sbfBrg = (DMS_wavePlan select _sbfIdx) select 0;
		private _sbfDist = _cfg get "sbfDistance";
		if (DMS_testMode && {DMS_testStartDist > 0}) then { _sbfDist = [_sbfDist select 0, _sbfDist select 1] apply {_x min 900}; };
		DMS_sbfPos = ["SPOT", [_sbfBrg, _sbfDist, true]] call DMS_fnc_waves;
		private _sp = DMS_sbfPos getPos [_cfg get "sbfApproach", DMS_opCenter getDir DMS_sbfPos];
		DMS_sbfSpawn = ["FLAT", [_sp, 0, 150, 8]] call DMS_fnc_findPos;
		[format ["Plan: support-by-fire position %1 m out on bearing %2 (line of sight %3), vehicle spawns at %4 m",
			round (DMS_sbfPos distance2D DMS_opCenter), round (DMS_opCenter getDir DMS_sbfPos),
			!(terrainIntersectASL [AGLToASL [DMS_opCenter select 0, DMS_opCenter select 1, 3], AGLToASL [DMS_sbfPos select 0, DMS_sbfPos select 1, 2.5]]),
			round (DMS_sbfSpawn distance2D DMS_opCenter)]] call DMS_fnc_log;
	};

	case "SPAWN": {
		_args params ["_n"];
		(DMS_wavePlan select (_n - 1)) params ["_brg", "_groups"];
		private _grps = [];
		private _count = 0;
		{
			_x params ["_tactic", "_size", "_gb", "_spawn"];
			private _grp = createGroup [east, true];
			for "_i" from 1 to _size do {
				private _cls = if (_i == 1) then { _cfg get "enemyLeaderClass" } else { ["PICK", _cfg get "enemyClasses"] call DMS_fnc_rng };
				private _u = _grp createUnit [_cls, _spawn, [], 15, "FORM"];
				{ _u setSkill _x } forEach (_cfg get "enemySkill");
			};
			_grp setBehaviour "AWARE";
			_grp setFormation "WEDGE";
			_count = _count + count (units _grp);
			_grps pushBack _grp;
			DMS_enemyGroups pushBack _grp;
			private _track = _cfg get "waveTrackRadius";
			if (_tactic == "ASSAULT") then {
				private _ap = DMS_opCenter getPos [_cfg get "waveAssaultDistance", _gb];
				_ap = [_ap select 0, _ap select 1, 0];
				[_grp, _ap, false, 15, 2, false] spawn lambs_wp_fnc_taskAssault;
				[_n, _grp, _ap, _track] spawn {
					params ["_n", "_grp", "_ap", "_track"];
					private _t0 = time;
					sleep 5;
					// Bounded: until the LAMBS assault members have all arrived (or died), or 7 min.
					waitUntil {
						sleep 5;
						DMS_over || {({alive _x} count (units _grp)) == 0}
							|| {(_grp getVariable ["lambs_wp_taskAssaultMembers", []]) isEqualTo []}
							|| {time - _t0 > 420}
					};
					if (DMS_over || {({alive _x} count (units _grp)) == 0}) exitWith {};
					[_grp, _track, 15, [], DMS_opCenter, false] spawn lambs_wp_fnc_taskRush;
					[format ["Wave %1 group %2 at its assault position after %3 s (%4 alive, leader %5 m from OP), rushing the OP",
						_n, groupId _grp, round (time - _t0), {alive _x} count (units _grp), round ((leader _grp) distance2D DMS_opCenter)]] call DMS_fnc_log;
				};
			} else {
				[_grp, _track, 20, [], DMS_opCenter, false] spawn lambs_wp_fnc_taskCreep;
			};
			[format ["Wave %1: %2 group of %3 (%4) at %5 m bearing %6", _n, _tactic, count (units _grp), groupId _grp,
				round (_spawn distance2D DMS_opCenter), round _gb]] call DMS_fnc_log;
		} forEach _groups;
		DMS_waves pushBack [_n, _grps, _count, time];
		if (DMS_debug) then {
			private _mk = createMarker [format ["DMS_dbg_wave%1", _n], (_groups select 0) select 3];
			_mk setMarkerType "mil_start";
			_mk setMarkerColor "ColorOPFOR";
			_mk setMarkerText format ["wave %1", _n];
		};
		if (DMS_testMode) then {
			["CHECK", [format ["wave%1", _n], _count > 0, format ["%1 men in %2 group(s) from bearing %3", _count, count _grps, round _brg]]] call DMS_fnc_testMode;
			["ASSIST", [_n]] spawn DMS_fnc_testMode;
		};
	};

	case "ALIVE": {
		_args params ["_n"];
		private _w = DMS_waves select {(_x select 0) == _n};
		if (_w isEqualTo []) exitWith { 0 };
		private _alive = 0;
		{ _alive = _alive + ({alive _x} count (units _x)); } forEach ((_w select 0) select 1);
		_alive
	};

	case "BROKEN": {
		_args params ["_n"];
		private _w = DMS_waves select {(_x select 0) == _n};
		if (_w isEqualTo []) exitWith { false };
		(["ALIVE", [_n]] call DMS_fnc_waves) <= (((_w select 0) select 2) * (_cfg get "waveBrokenFraction"))
	};

	case "SBF": {
		private _list = _cfg get "sbfClasses";
		private _idx = _list findIf {isClass (configFile >> "CfgVehicles" >> _x)};
		if (_idx < 0) exitWith { ["SBF: no vehicle class exists", "WARN"] call DMS_fnc_log; };
		private _veh = createVehicle [_list select _idx, DMS_sbfSpawn, [], 0, "NONE"];
		_veh setDir (DMS_sbfSpawn getDir DMS_opCenter);
		createVehicleCrew _veh;
		private _grp = group (effectiveCommander _veh);
		{ private _c = _x; { _c setSkill _x } forEach (_cfg get "sbfSkill"); } forEach (units _grp);
		_grp setBehaviour "AWARE";
		_grp setCombatMode "YELLOW";
		DMS_sbfVeh = _veh;
		DMS_enemyGroups pushBack _grp;
		private _wp = _grp addWaypoint [DMS_sbfPos, 0];
		_wp setWaypointType "MOVE";
		_wp setWaypointSpeed "LIMITED";
		[format ["SBF: %1 spawned %2 m out, moving to its position %3 m from the OP", typeOf _veh,
			round (_veh distance2D DMS_opCenter), round (DMS_sbfPos distance2D DMS_opCenter)]] call DMS_fnc_log;

		private _t0 = time;
		private _slowSince = -1;
		waitUntil {
			sleep 3;
			if (alive _veh && {speed _veh < 2} && {time - _t0 > 30}) then {
				if (_slowSince < 0) then { _slowSince = time; };
			} else {
				_slowSince = -1;
			};
			DMS_over || {!alive _veh} || {_veh distance2D DMS_sbfPos < 30}
				|| {_slowSince > 0 && {time - _slowSince > 45}} || {time - _t0 > (_cfg get "sbfMoveTimeout")}
		};
		if (DMS_over) exitWith {};
		if (!alive _veh) exitWith { ["SBF: vehicle destroyed before reaching its position"] call DMS_fnc_log; };
		// Hold here: the driver may no longer path, so the vehicle never closes on the OP.
		for "_i" from (count (waypoints _grp) - 1) to 0 step -1 do { deleteWaypoint [_grp, _i]; };
		if (!isNull (driver _veh)) then { (driver _veh) disableAI "PATH"; };
		_grp setCombatMode "YELLOW";
		private _off = _veh distance2D DMS_sbfPos;
		[format ["SBF: holding %1 m from the OP (%2 m from the planned spot) after %3 s", round (_veh distance2D DMS_opCenter), round _off, round (time - _t0)]] call DMS_fnc_log;
		if (DMS_testMode) then { ["CHECK", ["sbf_in_position", _off < 300 || {(_veh distance2D DMS_opCenter) > 600}, format ["%1 m from the planned spot, %2 m from the OP", round _off, round (_veh distance2D DMS_opCenter)]]] call DMS_fnc_testMode; };

		private _w = _cfg get "sbfWave";
		waitUntil { sleep 5; DMS_over || {!alive _veh} || {({alive _x} count (crew _veh)) == 0} || {["BROKEN", [_w]] call DMS_fnc_waves} };
		if (DMS_over) exitWith {};
		if (!alive _veh || {({alive _x} count (crew _veh)) == 0}) exitWith { ["SBF: vehicle knocked out"] call DMS_fnc_log; };
		["SBF: wave broken, vehicle withdrawing"] call DMS_fnc_log;
		if (!isNull (driver _veh)) then { (driver _veh) enableAI "PATH"; };
		_grp setCombatMode "GREEN";
		_grp move DMS_sbfSpawn;
		private _tw = time;
		waitUntil { sleep 5; DMS_over || {!alive _veh} || {_veh distance2D DMS_sbfSpawn < 60} || {time - _tw > 240} };
		if (DMS_over || {!alive _veh}) exitWith {};
		{ deleteVehicle _x; } forEach (crew _veh);
		deleteVehicle _veh;
		["SBF: vehicle gone"] call DMS_fnc_log;
	};

	case "RUN": {
		private _prep = [["RANGE", _cfg get "prepTime"] call DMS_fnc_rng, 20] call DMS_fnc_t;
		[format ["Director: wave 1 in %1 s", round _prep]] call DMS_fnc_log;
		sleep _prep;
		private _n = count DMS_wavePlan;
		private _lastSpawn = time;
		for "_i" from 1 to _n do {
			if (DMS_over) exitWith {};
			["SPAWN", [_i]] call DMS_fnc_waves;
			_lastSpawn = time;
			if (_i == (_cfg get "sbfWave")) then { ["SBF"] spawn DMS_fnc_waves; };
			if (_i < _n) then {
				private _gapMax = [(DMS_wavePlan select (_i - 1)) select 2, 120] call DMS_fnc_t;
				private _gapMin = [_cfg get "waveGapMin", 30] call DMS_fnc_t;
				waitUntil {
					sleep 5;
					DMS_over || {time - _lastSpawn > _gapMax}
						|| {time - _lastSpawn > _gapMin && {["BROKEN", [_i]] call DMS_fnc_waves}}
				};
				[format ["Director: wave %1 %2 after %3 s (%4 alive)", _i,
					["still fighting, next wave due", "broken"] select (["BROKEN", [_i]] call DMS_fnc_waves),
					round (time - _lastSpawn), ["ALIVE", [_i]] call DMS_fnc_waves]] call DMS_fnc_log;
			};
		};
		if (DMS_over) exitWith {};

		private _maxLast = [_cfg get "reliefMaxAfterLast", 360] call DMS_fnc_t;
		waitUntil { sleep 5; DMS_over || {time - _lastSpawn > _maxLast} || {["BROKEN", [_n]] call DMS_fnc_waves} };
		if (DMS_over) exitWith {};
		private _why = ["time", "last wave broken"] select (["BROKEN", [_n]] call DMS_fnc_waves);
		private _delay = [_cfg get "reliefDelay", 60] call DMS_fnc_t;
		[format ["Director: relief on the way (%1), arriving in %2 s", _why, round _delay]] call DMS_fnc_log;
		if (!isNull DMS_player) then {
			(format ["Relief element is %1 minutes out. Hold the OP.", (ceil (_delay / 60)) max 1]) remoteExecCall ["hintSilent", DMS_player];
		};
		private _tr = time;
		waitUntil { sleep 2; DMS_over || {time - _tr > _delay} };
		if (DMS_over) exitWith {};
		private _east = {alive _x && {side (group _x) == east}} count allUnits;
		["DMS_Win", true, format ["OP held, relief arrived (%1, %2 enemy left in the area)", _why, _east]] call DMS_fnc_end;
	};
	default {};
};
