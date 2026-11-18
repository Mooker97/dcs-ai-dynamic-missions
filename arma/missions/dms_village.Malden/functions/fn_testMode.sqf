/*
	DMS_fnc_testMode - unattended run with an AI squad standing in for the player (server only).
	["CHECK", [_name, _pass, _detail]] call DMS_fnc_testMode;   log "[DMS.TEST] PASS|FAIL <name> <detail>" (first verdict wins)
	["SUMMARY"] call DMS_fnc_testMode;                         FAIL every expected check not reached, then a summary line
	["RUN"] spawn DMS_fnc_testMode;                            drive the squad and the Bradley through the mission
	AI cannot use the comm menu, so the harness calls the same server functions the menu calls.
*/
params [["_mode", "", [""]], ["_args", [], [[]]]];

switch (_mode) do {
	case "CHECK": {
		_args params ["_name", "_pass", ["_detail", ""]];
		if (isNil "DMS_testResults") then { DMS_testResults = createHashMap; };
		if (_name in DMS_testResults) exitWith {};
		DMS_testResults set [_name, _pass];
		[format ["%1 %2 %3", ["FAIL", "PASS"] select _pass, _name, _detail], "TEST"] call DMS_fnc_log;
	};

	case "SUMMARY": {
		if (isNil "DMS_testResults") then { DMS_testResults = createHashMap; };
		// A forced run replaces the plain win and skips the steps it cuts short.
		private _expected = +(DMS_cfg get "testExpected");
		switch (DMS_testForce) do {
			case 1: { _expected = (_expected - ["outcome_win"]) + ["outcome_forced", "ifv_lost"]; };
			case 2: { _expected = (_expected - ["counterattack", "village_held", "outcome_win"]) + ["outcome_forced"]; };
			default {};
		};
		{
			if (!(_x in DMS_testResults)) then { ["CHECK", [_x, false, "not reached"]] call DMS_fnc_testMode; };
		} forEach _expected;
		private _pass = 0;
		private _fail = 0;
		{ if (_y) then { _pass = _pass + 1; } else { _fail = _fail + 1; }; } forEach DMS_testResults;
		[format ["SUMMARY pass=%1 fail=%2 seed=%3 site=%4", _pass, _fail, DMS_seed, DMS_siteName], "TEST"] call DMS_fnc_log;
		["DONE", "TEST"] call DMS_fnc_log;
	};

	case "RUN": {
		private _cfg = DMS_cfg;
		private _check = { ["CHECK", _this] call DMS_fnc_testMode; };
		private _t0 = time;
		private _grp = DMS_squad;

		["spawn_village", (count DMS_villageHouses) >= ((_cfg get "villageHouses") select 0),
			format ["%1, %2 enterable houses", DMS_siteName, count DMS_villageHouses]] call _check;
		["spawn_defenders", (count DMS_defenders) >= 8, format ["%1 defenders, technical=%2", count DMS_defenders, !isNull DMS_technical]] call _check;
		["spawn_squad", ({alive _x} count (units _grp)) >= 7, format ["%1 units", count (units _grp)]] call _check;
		["spawn_bradley", alive DMS_ifv && {({alive _x} count (crew DMS_ifv)) >= 2}, format ["%1 crew %2", typeOf DMS_ifv, count (crew DMS_ifv)]] call _check;

		// Hard stop after DMS_testMinutes.
		[_t0 + (DMS_testMinutes * 60)] spawn {
			params ["_deadline"];
			waitUntil { sleep 5; DMS_over || {time > _deadline} };
			if (!DMS_over) then { ["DMS_TestEnd", false, "test timeout"] call DMS_fnc_end; };
		};

		// Progress line for the log reader.
		[_t0, _grp] spawn {
			params ["_t0", "_grp"];
			while {!DMS_over} do {
				sleep ([60, 20] call DMS_fnc_t);
				private _ldr = leader _grp;
				[format ["STATUS t=%1 squad=%2 leaderToVillage=%3 defenders=%4 cleared=%5 counter=%6 eastAlive=%7 ifv=%8 ifvToLeader=%9",
					round (time - _t0), {alive _x} count (units _grp), round (_ldr distance2D DMS_villageCenter),
					{alive _x} count DMS_defenders, DMS_villageCleared, {alive _x} count DMS_counterUnits,
					{alive _x && {side (group _x) == DMS_enemySide}} count allUnits,
					["alive", "lost"] select DMS_ifvLost, round (DMS_ifv distance2D _ldr)]] call DMS_fnc_log;
			};
		};

		// Advance to a staging point short of the village.
		_grp setBehaviour "AWARE";
		_grp setCombatMode "YELLOW";
		_grp setFormation "WEDGE";
		private _stage = DMS_villageCenter getPos [_cfg get "testStage", DMS_startBearing];
		private _wpStage = _grp addWaypoint [_stage, 15];
		_wpStage setWaypointType "MOVE";
		_wpStage setWaypointSpeed "NORMAL";

		// Bradley order 1: once the squad has moved off, bring the Bradley up to the leader.
		waitUntil { sleep 5; DMS_over || {((leader _grp) distance2D DMS_start) > (_cfg get "testIfvAfter")} || {(time - _t0) > 300} };
		if (DMS_over) exitWith {};
		["MOVE", [leader _grp]] call DMS_fnc_ifv;

		// At the staging point: Bradley order 2 (suppress a defended house), then order 3 (hold, overwatch).
		waitUntil { sleep 5; DMS_over || {((leader _grp) distance2D _stage) < 40} || {(time - _t0) > 600} };
		if (DMS_over) exitWith {};
		["MOVE", [leader _grp]] call DMS_fnc_ifv;
		private _tm = time;
		waitUntil { sleep 5; DMS_over || {(DMS_ifv distance2D (leader _grp)) < 50} || {time - _tm > 180} };
		if (DMS_over) exitWith {};
		private _tries = 0;
		while {!DMS_over && {!DMS_ifvLost} && {_tries < 3} && {!("ifv_suppress" in DMS_testResults)}} do {
			_tries = _tries + 1;
			// Aim at a living defender the gunner has terrain line of sight to, else at the village centre.
			private _gun = gunner DMS_ifv;
			private _tgts = DMS_defenders select {alive _x && {!isNull _gun} && {!(terrainIntersectASL [eyePos _gun, eyePos _x])}};
			private _tp = if (_tgts isEqualTo []) then { DMS_villageCenter } else { getPosATL (_tgts select 0) };
			["SUPPRESS", [leader _grp, _tp]] call DMS_fnc_ifv;
			private _ts = time;
			waitUntil { sleep 3; DMS_over || {"ifv_suppress" in DMS_testResults} || {time - _ts > 60} };
			if (!("ifv_suppress" in DMS_testResults)) then { sleep (DMS_cfg get "ifvSuppressCooldown"); };
		};
		if (DMS_over) exitWith {};
		["HOLD", [leader _grp]] call DMS_fnc_ifv;

		// Assault: search and destroy through the village.
		for "_i" from (count (waypoints _grp) - 1) to 0 step -1 do { deleteWaypoint [_grp, _i]; };
		private _wpSad = _grp addWaypoint [DMS_villageCenter, 10];
		_wpSad setWaypointType "SAD";
		_wpSad setWaypointBehaviour "COMBAT";
		_grp setCurrentWaypoint _wpSad;

		// Optional assault assist: house fights between AI take very long. Once the squad has been within 200 m
		// for DMS_testAssist s, the remaining defenders are removed and the squad walks in. Logged, test only.
		if (DMS_testAssist > 0) then {
			[_grp] spawn {
				params ["_grp"];
				waitUntil { sleep 5; DMS_over || {DMS_villageCleared} || {((units _grp) findIf {alive _x && {_x distance2D DMS_villageCenter < 200}}) > -1} };
				private _tc = time;
				waitUntil { sleep 5; DMS_over || {DMS_villageCleared} || {time - _tc > DMS_testAssist} };
				if (DMS_over || {DMS_villageCleared}) exitWith {};
				private _left = DMS_defenders select {alive _x};
				DMS_testAssisted = count _left;
				[format ["Test: assault assist after %1 s near the village, removing %2 defenders", DMS_testAssist, count _left]] call DMS_fnc_log;
				{ _x setDamage 1; } forEach _left;
				private _wp = _grp addWaypoint [DMS_villageCenter, 5];
				_wp setWaypointType "MOVE";
				_grp setCurrentWaypoint _wp;
			};
		};

		waitUntil { sleep 5; DMS_over || {DMS_villageCleared} || {(time - _t0) > ([_cfg get "testClearTimeout", 600] call DMS_fnc_t)} };
		if (DMS_over) exitWith {};
		if (!DMS_villageCleared) exitWith { ["village_cleared", false, format ["not cleared after %1 s", round (time - _t0)]] call _check; };

		// Forced failures.
		if (DMS_testForce == 2) exitWith {
			["Test: forcing failure, killing the squad"] call DMS_fnc_log;
			{ _x setDamage 1; } forEach (units _grp);
		};
		if (DMS_testForce == 1) then {
			["Test: forcing the Bradley loss"] call DMS_fnc_log;
			DMS_ifv setDamage 1;
		};

		// Hold: the squad holds the village centre; the counterattack comes to it.
		for "_i" from (count (waypoints _grp) - 1) to 0 step -1 do { deleteWaypoint [_grp, _i]; };
		private _wpHold = _grp addWaypoint [DMS_villageCenter, 20];
		_wpHold setWaypointType "SAD";
		_wpHold setWaypointBehaviour "COMBAT";
		_grp setCurrentWaypoint _wpHold;

		// Optional hold assist: DMS_testAssist s after the counterattack dismounts, remove what is left of it.
		if (DMS_testAssist > 0) then {
			waitUntil { sleep 5; DMS_over || {DMS_counterDismounted > 0} || {DMS_counterSpawned > 0 && {time - DMS_counterSpawned > 600}} };
			if (DMS_over) exitWith {};
			private _td = time;
			waitUntil { sleep 5; DMS_over || {time - _td > DMS_testAssist} };
			if (DMS_over) exitWith {};
			private _left = (DMS_counterUnits select {alive _x}) + (DMS_counterVehicles select {alive _x});
			if (_left isNotEqualTo []) then {
				[format ["Test: hold assist after %1 s, removing %2 counterattack units/vehicles", DMS_testAssist, count _left]] call DMS_fnc_log;
				{ _x setDamage 1; } forEach _left;
			};
		};
	};
	default {};
};
