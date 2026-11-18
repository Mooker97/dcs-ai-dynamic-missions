/*
	DMS_fnc_site - the hidden mortar battery, its guard and patrols (server only).
	["SPAWN", [_center, _fireDir]] call DMS_fnc_site;  tubes + crews, props, LAMBS camp guard, LAMBS patrols
	["HARASS"] spawn DMS_fnc_site;                     the battery fires a few rounds now and then (audible clue)
	["STATUS"] call DMS_fnc_site;                       -> number of tubes out (latched per tube)
	A tube is out once it is destroyed, damaged past tubeDamageOut, or its whole crew is dead.
	Sets: DMS_tubes, DMS_siteObjects, DMS_garrison, DMS_enemyGroups, DMS_batteryGroup
*/
params [["_mode", "", [""]], ["_args", [], [[]]]];

switch (_mode) do {
	case "SPAWN": {
		_args params ["_center", "_fireDir"];
		private _cfg = DMS_cfg;
		private _skills = _cfg get "enemySkill";
		private _applySkill = {
			params ["_unit"];
			{ _unit setSkill _x } forEach _skills;
		};
		private _toWorld = {
			params ["_off"];
			_off params ["_dx", "_dy"];
			[(_center select 0) + (_dx * cos _fireDir) + (_dy * sin _fireDir), (_center select 1) - (_dx * sin _fireDir) + (_dy * cos _fireDir), 0]
		};

		// Clear a small hide inside the trees so the tubes and the net fit.
		private _hidden = nearestTerrainObjects [_center, ["TREE", "SMALL TREE", "BUSH", "ROCK", "ROCKS", "FENCE", "WALL", "HIDE"], _cfg get "siteClearRadius", false, true];
		{ hideObjectGlobal _x } forEach _hidden;
		private _netPos = [(_cfg get "siteProps") select 0 select 1] call _toWorld;
		{ hideObjectGlobal _x } forEach (nearestTerrainObjects [_netPos, ["TREE", "SMALL TREE", "BUSH"], 8, false, true]);

		// Tubes in a line across the firing direction, each with its own crew.
		private _batGrp = createGroup [east, true];
		private _tubes = [];
		private _n = _cfg get "batteryTubes";
		private _sp = _cfg get "batterySpacing";
		for "_i" from 0 to (_n - 1) do {
			private _p = [[(_i - ((_n - 1) / 2)) * _sp, 0]] call _toWorld;
			private _m = createVehicle [_cfg get "batteryClass", _p, [], 0, "CAN_COLLIDE"];
			_m setDir _fireDir;
			_m setPosATL _p;
			_m setVectorUp (surfaceNormal _p);
			createVehicleCrew _m;
			private _crew = crew _m;
			_crew joinSilent _batGrp;
			{ [_x] call _applySkill; } forEach _crew;
			_m setVariable ["DMS_crew", _crew];
			_m setVariable ["DMS_out", ""];
			_tubes pushBack _m;
		};
		_batGrp setBehaviour "SAFE";
		_batGrp setCombatMode "YELLOW";

		private _objects = +_tubes;
		{
			_x params ["_cls", "_off", ["_rel", 0]];
			private _p = [_off] call _toWorld;
			private _o = createVehicle [_cls, _p, [], 0, "CAN_COLLIDE"];
			_o setDir ((_fireDir + _rel) mod 360);
			_o setPosATL _p;
			_o setVectorUp (surfaceNormal _p);
			_objects pushBack _o;
		} forEach (_cfg get "siteProps");

		// Guard: LAMBS camp behaviour around the battery.
		private _grpG = createGroup [east, true];
		{
			private _u = _grpG createUnit [_x, [_netPos select 0, _netPos select 1, 0], [], 6, "NONE"];
			[_u] call _applySkill;
		} forEach (_cfg get "garrisonClasses");
		[_grpG, _center, _cfg get "garrisonCampRange"] call lambs_wp_fnc_taskCamp;

		// Patrols: LAMBS taskPatrol rings around the battery.
		private _groups = [_batGrp, _grpG];
		private _patrolUnits = 0;
		{
			_x params ["_size", "_radius"];
			private _g = createGroup [east, true];
			private _sp0 = ["FLAT", [_center, _radius * 0.5, _radius * 0.8, 3]] call DMS_fnc_findPos;
			for "_k" from 1 to _size do {
				private _u = _g createUnit [["PICK", _cfg get "patrolClasses"] call DMS_fnc_rng, _sp0, [], 4, "NONE"];
				[_u] call _applySkill;
			};
			[_g, _center, _radius, 4] call lambs_wp_fnc_taskPatrol;
			_groups pushBack _g;
			_patrolUnits = _patrolUnits + _size;
		} forEach (_cfg get "patrols");

		private _garrison = [];
		{ _garrison append (units _x); } forEach _groups;
		// Any casualty tells the battery it has been found.
		{
			_x addEventHandler ["Killed", {
				if (!(missionNamespace getVariable ["DMS_alarm", false])) then { ["ALARM", ["casualty"]] call DMS_fnc_alarm; };
			}];
		} forEach _garrison;

		DMS_tubes = _tubes;
		DMS_siteObjects = _objects;
		DMS_garrison = _garrison;
		DMS_enemyGroups = _groups;
		DMS_batteryGroup = _batGrp;
		[format ["Battery placed: %1 x %2 facing %3, %4 props, %5 trees hidden, %6 defenders (%7 crew, %8 guard, %9 patrol)",
			count _tubes, _cfg get "batteryClass", round _fireDir, (count _objects) - (count _tubes), count _hidden,
			count _garrison, count (units _batGrp), count (units _grpG), _patrolUnits]] call DMS_fnc_log;
	};

	case "STATUS": {
		private _cfg = DMS_cfg;
		private _out = 0;
		{
			private _m = _x;
			private _why = _m getVariable ["DMS_out", ""];
			if (_why == "") then {
				_why = switch (true) do {
					case (!alive _m): { "destroyed" };
					case ((damage _m) >= (_cfg get "tubeDamageOut")): { format ["damage %1", (round ((damage _m) * 100)) / 100] };
					case (((_m getVariable ["DMS_crew", []]) findIf {alive _x}) < 0): { "crew dead" };
					default { "" };
				};
				if (_why != "") then {
					_m setVariable ["DMS_out", _why];
					[format ["Tube %1 out: %2 at t=%3", _forEachIndex + 1, _why, round time]] call DMS_fnc_log;
				};
			};
			if (_why != "") then { _out = _out + 1; };
		} forEach DMS_tubes;
		_out
	};

	case "HARASS": {
		private _cfg = DMS_cfg;
		if (!(_cfg get "harassFire")) exitWith {};
		while {!DMS_over && {!DMS_siteNeutralized}} do {
			sleep ([["RANGE", _cfg get "harassInterval"] call DMS_fnc_rng, 60] call DMS_fnc_t);
			if (DMS_over || {DMS_siteNeutralized}) exitWith {};
			private _ready = DMS_tubes select {alive _x && {alive (gunner _x)} && {(_x getVariable ["DMS_out", ""]) == ""}};
			private _fired = 0;
			{
				if (_fired < (_cfg get "harassTubes")) then {
					private _mags = getArtilleryAmmo [_x];
					private _tgt = DMS_harassTarget getPos [["RANGE", [0, 150]] call DMS_fnc_rng, ["RANGE", [0, 360]] call DMS_fnc_rng];
					if (_mags isEqualTo []) then {
						["Battery fire skipped: no artillery magazine on the tube", "DEBUG"] call DMS_fnc_log;
					} else {
						if (_tgt inRangeOfArtillery [[_x], _mags select 0]) then {
							_x setVehicleAmmo 1;
							_x doArtilleryFire [_tgt, _mags select 0, _cfg get "harassRounds"];
							_fired = _fired + 1;
						} else {
							[format ["Battery fire skipped: %1 out of range for %2", mapGridPosition _tgt, _mags select 0], "DEBUG"] call DMS_fnc_log;
						};
					};
				};
			} forEach _ready;
			[format ["Battery fired: %1 tubes x %2 rounds toward grid %3 at t=%4", _fired, _cfg get "harassRounds", mapGridPosition DMS_harassTarget, round time]] call DMS_fnc_log;
		};
	};
	default {};
};
