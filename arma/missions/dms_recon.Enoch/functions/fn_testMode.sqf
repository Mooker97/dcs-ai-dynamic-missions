/*
	DMS_fnc_testMode - unattended run with an AI team standing in for the player (server only).
	["CHECK", [_name, _pass, _detail]] call DMS_fnc_testMode;   log "[DMS.TEST] PASS|FAIL <name> <detail>" (first verdict wins)
	["SUMMARY"] call DMS_fnc_testMode;                         FAIL every expected check not reached, then a summary line
	["RUN"] spawn DMS_fnc_testMode;                            drive the team: find, report, BDA, exfil
	AI cannot use the comm menu, so the driver calls the same server function (REPORT) the menu calls,
	with the battery position plus a seeded error. Every wait is bounded.
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
		private _expected = +(DMS_cfg get "testExpected");
		if (DMS_testForce == 1) then {
			_expected = (_expected - ["strike", "alarm", "site_neutralized", "bda", "exfil", "outcome_win"]) + ["outcome_forced"];
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
		private _grp = DMS_team;

		["spawn_site", ({alive _x} count DMS_tubes) == (_cfg get "batteryTubes"), format ["%1 tubes at grid %2", count DMS_tubes, mapGridPosition DMS_siteCenter]] call _check;
		["spawn_enemy", (count DMS_garrison) >= 8, format ["%1 defenders", count DMS_garrison]] call _check;
		["spawn_team", ({alive _x} count (units _grp)) == 4, format ["%1 units, leader binocular %2", count (units _grp), binocular (leader _grp)]] call _check;

		// Hard stop after DMS_testMinutes.
		[_t0 + (DMS_testMinutes * 60)] spawn {
			params ["_deadline"];
			waitUntil { sleep 5; DMS_over || {time > _deadline} };
			if (!DMS_over) then { ["DMS_TestEnd", false, "test timeout"] call DMS_fnc_end; };
		};

		// Progress line for the log reader.
		[_t0] spawn {
			params ["_t0"];
			while {!DMS_over} do {
				sleep ([60, 20] call DMS_fnc_t);
				private _ldr = leader DMS_team;
				[format ["STATUS t=%1 team=%2 leaderToSite=%3 leaderToPickup=%4 tubesOut=%5 neutralized=%6 bda=%7 alarm=%8 strikesLeft=%9 eastAlive=%10 qrf=%11",
					round (time - _t0), {alive _x} count (units DMS_team), round (_ldr distance2D DMS_siteCenter),
					round (_ldr distance2D DMS_pickup), {(_x getVariable ["DMS_out", ""]) != ""} count DMS_tubes,
					DMS_siteNeutralized, DMS_bdaDone, DMS_alarm, DMS_strikesLeft,
					{alive _x && {side (group _x) == east}} count allUnits,
					[-1, {alive _x} count (units DMS_qrfGroup)] select (!isNull DMS_qrfGroup)]] call DMS_fnc_log;
			};
		};

		private _move = {
			params ["_pos", ["_speed", "NORMAL"]];
			for "_i" from (count (waypoints DMS_team) - 1) to 0 step -1 do { deleteWaypoint [DMS_team, _i]; };
			private _wp = DMS_team addWaypoint [_pos, 5];
			_wp setWaypointType "MOVE";
			_wp setWaypointSpeed _speed;
			DMS_team setCurrentWaypoint _wp;
		};
		private _found = {
			private _r = _cfg get "testFindRange";
			private _how = "";
			private _seenBy = (units DMS_team) findIf {
				private _o = _x;
				alive _o && {_o distance2D DMS_siteCenter < _r} && {DMS_tubes findIf {
					([_o, "VIEW", _x] checkVisibility [eyePos _o, (getPosASL _x) vectorAdd [0, 0, 0.8]]) >= 0.25
				} > -1}
			};
			if (_seenBy > -1) then {
				_how = format ["line of sight from %1 m", round (((units DMS_team) select _seenBy) distance2D DMS_siteCenter)];
			} else {
				private _known = DMS_garrison findIf {alive _x && {(DMS_team knowsAbout _x) >= 1.5} && {_x distance2D DMS_siteCenter < 120}};
				if (_known > -1) then { _how = format ["knowsAbout %1 on a defender", DMS_team knowsAbout (DMS_garrison select _known)]; };
			};
			_how
		};
		private _minTeamDist = {
			private _d = 1e6;
			{ if (alive _x) then { _d = _d min (_x distance2D DMS_siteCenter); }; } forEach (units DMS_team);
			_d
		};

		_grp setBehaviour "AWARE";
		_grp setCombatMode "GREEN";
		_grp setFormation "WEDGE";

		// 1. Find: observation posts on the approach bearing, closer each time.
		private _how = "";
		{
			private _d = _x;
			if (_how == "" && {!DMS_over} && {((leader _grp) distance2D DMS_siteCenter) > (_d + 30)}) then {
				private _op = DMS_siteCenter getPos [_d, DMS_startBearing];
				[_op] call _move;
				private _tm = time;
				waitUntil { sleep 3; _how = call _found; DMS_over || {_how != ""} || {(leader _grp) distance2D _op < 30} || {time - _tm > 600} };
				private _th = time;
				waitUntil { sleep 3; _how = call _found; DMS_over || {_how != ""} || {time - _th > ([_cfg get "testOpHold", 45] call DMS_fnc_t)} };
				[format ["Test: OP at %1 m reached=%2 found='%3'", _d, (leader _grp) distance2D _op < 40, _how]] call DMS_fnc_log;
			};
		} forEach (_cfg get "testOpDistances");
		if (DMS_over) exitWith {};
		if (_how == "") then {
			if (DMS_testAssist > 0) then {
				{ _grp reveal [_x, 4]; } forEach DMS_tubes;
				["found", true, "assisted: not seen from the last OP, battery revealed"] call _check;
			} else {
				["found", false, "not seen from any OP, reporting anyway"] call _check;
			};
		} else {
			["found", true, format ["%1 at t=%2", _how, round (time - _t0)]] call _check;
		};

		// 2. Pull back out of danger-close range, then report (repeat while the battery is not out).
		private _reportFrom = DMS_siteCenter getPos [_cfg get "testReportDistance", DMS_startBearing];
		while {!DMS_over && {!DMS_siteNeutralized} && {DMS_strikesLeft > 0}} do {
			[_reportFrom, "FULL"] call _move;
			private _tw = time;
			waitUntil { sleep 3; DMS_over || {(call _minTeamDist) > ((_cfg get "strikeDangerClose") + 25)} || {time - _tw > 240} };
			if (DMS_over) exitWith {};
			private _err = DMS_siteCenter getPos [["RANGE", _cfg get "testReportError"] call DMS_fnc_rng, ["RANGE", [0, 360]] call DMS_fnc_rng];
			private _left0 = DMS_strikesLeft;
			["REPORT", [leader _grp, _err, "TEST"]] call DMS_fnc_strike;
			["report", DMS_strikesLeft < _left0, format ["%1 m from the battery, team %2 m away", round (_err distance2D DMS_siteCenter), round (call _minTeamDist)]] call _check;
			if (DMS_strikesLeft == _left0) exitWith {};
			if (DMS_testForce == 1) exitWith {
				["Test: forcing failure, killing the team after the report"] call DMS_fnc_log;
				{ _x setDamage 1; } forEach (units _grp);
			};
			private _ts = time;
			waitUntil { sleep 3; DMS_over || {!DMS_strikeBusy} || {time - _ts > 400} };
			sleep 5;
		};
		if (DMS_over || {DMS_testForce == 1}) exitWith {};

		// 3. BDA: close in to observe; if that fails and missions remain, re-attack to confirm.
		if (DMS_siteNeutralized) then {
			[DMS_siteCenter getPos [_cfg get "testBdaDistance", DMS_startBearing]] call _move;
			private _tb = time;
			waitUntil { sleep 3; DMS_over || {DMS_bdaDone} || {time - _tb > 420} };
			if (!DMS_over && {!DMS_bdaDone} && {DMS_strikesLeft > 0}) then {
				["Test: BDA not observed, re-attacking to confirm"] call DMS_fnc_log;
				[_reportFrom, "FULL"] call _move;
				private _tw = time;
				waitUntil { sleep 3; DMS_over || {(call _minTeamDist) > ((_cfg get "strikeDangerClose") + 25)} || {time - _tw > 240} };
				["REPORT", [leader _grp, DMS_siteCenter, "TEST"]] call DMS_fnc_strike;
				private _ts = time;
				waitUntil { sleep 3; DMS_over || {DMS_bdaDone} || {time - _ts > 400} };
			};
		};
		if (DMS_over) exitWith {};

		// 4. Exfil on foot to the pickup.
		_grp setCombatMode "YELLOW";
		[DMS_pickup, "FULL"] call _move;
		private _te = time;
		waitUntil { sleep 5; DMS_over || {time - _te > 1500} };
	};
	default {};
};
