/*
	DMS_fnc_testMode - unattended run with an AI squad standing in for the player (server only).
	["CHECK", [_name, _pass, _detail]] call DMS_fnc_testMode;   log "[DMS.TEST] PASS|FAIL <name> <detail>" (first verdict wins)
	["SUMMARY"] call DMS_fnc_testMode;                         FAIL every expected check not reached, then a summary line
	["RUN"] spawn DMS_fnc_testMode;                            drive the squad: artillery, assault, intel, extraction
	AI cannot use hold actions or the comm menu, so the harness calls the same server functions directly.
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
		// A forced failure replaces the win and skips the steps it cuts short.
		private _expected = +(DMS_cfg get "testExpected");
		switch (DMS_testForce) do {
			case 1: { _expected = (_expected - ["exfil_boarded", "outcome_win"]) + ["outcome_forced"]; };
			case 2: { _expected = (_expected - ["exfil_requested", "exfil_landed", "exfil_boarded", "outcome_win"]) + ["outcome_forced"]; };
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

		["spawn_compound", (count DMS_compoundObjects) >= 4 && {(count DMS_compoundBuildings) >= 2},
			format ["%1 objects, %2 buildings (%3)", count DMS_compoundObjects, count DMS_compoundBuildings, DMS_siteMode]] call _check;
		["spawn_garrison", (count DMS_garrison) >= 8, format ["%1 defenders", count DMS_garrison]] call _check;
		["spawn_intel", !isNull DMS_intel, typeOf DMS_intel] call _check;
		["spawn_squad", ({alive _x} count (units DMS_squad)) >= 5, format ["%1 units", count (units DMS_squad)]] call _check;

		// Hard stop after DMS_testMinutes.
		[_t0 + (DMS_testMinutes * 60)] spawn {
			params ["_deadline"];
			waitUntil { sleep 5; DMS_over || {time > _deadline} };
			if (!DMS_over) then { ["DMS_TestEnd", false, "test timeout"] call DMS_fnc_end; };
		};

		// Progress line every 60 s for the log reader.
		[_t0] spawn {
			params ["_t0"];
			while {!DMS_over} do {
				sleep ([60, 20] call DMS_fnc_t);
				private _ldr = leader DMS_squad;
				[format ["STATUS t=%1 squad=%2 leaderToCompound=%3 garrison=%4 eastAlive=%5 alarm=%6 intel=%7 exfil=%8/%9 heliToLz=%10",
					round (time - _t0), {alive _x} count (units DMS_squad), round (_ldr distance2D DMS_compoundCenter),
					{alive _x} count DMS_garrison, {alive _x && {side (group _x) == east}} count allUnits,
					DMS_alarm, DMS_intelTaken, DMS_exfilActive, DMS_exfilLanded,
					[-1, round (DMS_exfilHeli distance2D DMS_lz)] select (alive DMS_exfilHeli)]] call DMS_fnc_log;
			};
		};

		// Advance: stage short of the compound, then search and destroy.
		private _grp = DMS_squad;
		_grp setBehaviour "AWARE";
		_grp setCombatMode "YELLOW";
		_grp setFormation "WEDGE";
		if ((DMS_start distance2D DMS_compoundCenter) > 500) then {
			private _stage = DMS_compoundCenter getPos [350, DMS_startBearing];
			private _wpStage = _grp addWaypoint [_stage, 20];
			_wpStage setWaypointType "MOVE";
			_wpStage setWaypointSpeed "NORMAL";
		};
		private _wpSad = _grp addWaypoint [DMS_compoundCenter, 10];
		_wpSad setWaypointType "SAD";
		_wpSad setWaypointBehaviour "COMBAT";

		// Artillery on the compound while the squad is still ~1 km out.
		sleep ([_cfg get "testArtyAt", 5] call DMS_fnc_t);
		private _shells0 = DMS_artyShellsFired;
		["REQUEST", [leader _grp, DMS_compoundCenter, "FFE"]] call DMS_fnc_support;
		private _imp0 = count DMS_artyImpacts;
		private _want = _cfg get "artyRoundsFFE";
		waitUntil { sleep 5; DMS_over || {(count DMS_artyImpacts) - _imp0 >= _want} || {(time - _t0) > (([400, 120] call DMS_fnc_t) + ([_cfg get "testArtyAt", 5] call DMS_fnc_t))} };
		private _hits = DMS_artyImpacts select [_imp0, 99];
		private _near = { (_x select 1) < 3 * (_cfg get "artyCEP") } count _hits;
		["artillery", (count _hits) >= 1 && {_near * 2 >= count _hits},
			format ["%1 rounds fired, %2 detonations, %3 within %4 m", DMS_artyShellsFired - _shells0, count _hits, _near, 3 * (_cfg get "artyCEP")]] call _check;

		// Alarm (detection, casualties) - forced if it never happens.
		waitUntil { sleep 5; DMS_over || {DMS_alarm} || {(time - _t0) > ([_cfg get "testAlarmTimeout", 240] call DMS_fnc_t)} };
		if (DMS_over) exitWith {};
		if (!DMS_alarm) then {
			["alarm", false, "no detection before timeout, forcing"] call _check;
			["ALARM", ["test forced"]] call DMS_fnc_qrf;
		};

		// Optional assault assist: the AI-vs-AI fight for the buildings can take very long. Once the
		// squad has been within 200 m for DMS_testAssist seconds, the remaining defenders are removed
		// so the rest of the flow (intel, extraction) still gets exercised. Logged, never in normal play.
		DMS_testAssisted = 0;
		if (DMS_testAssist > 0) then {
			[_grp] spawn {
				params ["_grp"];
				waitUntil { sleep 5; DMS_over || {DMS_intelTaken} || {((units _grp) findIf {alive _x && {_x distance2D DMS_compoundCenter < 200}}) > -1} };
				private _tc = time;
				waitUntil { sleep 5; DMS_over || {DMS_intelTaken} || {time - _tc > DMS_testAssist} };
				if (DMS_over || {DMS_intelTaken}) exitWith {};
				private _left = DMS_garrison select {alive _x && {_x distance2D DMS_compoundCenter < 100}};
				DMS_testAssisted = count _left;
				[format ["Test: assault assist after %1 s near the compound, removing %2 defenders", DMS_testAssist, count _left]] call DMS_fnc_log;
				{ _x setDamage 1; } forEach _left;
				private _wp = _grp addWaypoint [DMS_compoundCenter, 5];
				_wp setWaypointType "MOVE";
				_grp setCurrentWaypoint _wp;
			};
		};

		// Intel: once a squad member is inside the compound and the defenders are nearly gone.
		waitUntil {
			sleep 5;
			DMS_over || {(time - _t0) > ([_cfg get "testIntelTimeout", 600] call DMS_fnc_t)} || {
				((units _grp) findIf {alive _x && {_x distance2D DMS_compoundCenter < 40}}) > -1
				&& {({alive _x && {_x distance2D DMS_compoundCenter < 100}} count DMS_garrison) <= 2}
			}
		};
		if (DMS_over) exitWith {};
		["compound_cleared", (time - _t0) <= ([_cfg get "testIntelTimeout", 600] call DMS_fnc_t), format ["t=%1 assisted=%2", round (time - _t0), DMS_testAssisted]] call _check;
		["TAKEN", [leader _grp]] call DMS_fnc_intel;
		if (DMS_testForce == 2) exitWith {
			["Test: forcing failure, killing the squad"] call DMS_fnc_log;
			{ _x setDamage 1; } forEach (units _grp);
		};
		if (DMS_testForce == 1) then {
			[] spawn {
				waitUntil { sleep 2; DMS_over || {DMS_exfilLanded} };
				if (!DMS_over && {alive DMS_exfilHeli}) then {
					["Test: forcing failure, destroying the extraction helicopter"] call DMS_fnc_log;
					DMS_exfilHeli setDamage 1;
				};
			};
		};

		// Optional exfil assist (test only): if the heli has held off a hot LZ for DMS_testAssist s,
		// remove the enemies near the LZ so the run can reach the boarding and win checks.
		if (DMS_testAssist > 0) then {
			[] spawn {
				while {!DMS_over} do {
					sleep 5;
					if (DMS_exfilHoldSince >= 0 && {time - DMS_exfilHoldSince > DMS_testAssist}) then {
						private _r = DMS_cfg get "exfilHotRadius";
						private _near = allUnits select {alive _x && {side (group _x) == east} && {_x distance2D DMS_lz < _r}};
						private _rv = DMS_cfg get "exfilHotVehicleRadius";
						{ _near pushBackUnique _x; } forEach (vehicles select {alive _x && {side (effectiveCommander _x) == east} && {_x distance2D DMS_lz < _rv}});
						{ _x setDamage 1; } forEach _near;
						[format ["Test: exfil assist after %1 s holding, removing %2 enemies near the LZ", DMS_testAssist, count _near]] call DMS_fnc_log;
						DMS_exfilHoldSince = time;
					};
				};
			};
		};

		// Extraction: stop the assault, request the heli, re-request if it leaves without us.
		for "_i" from (count (waypoints _grp) - 1) to 0 step -1 do { deleteWaypoint [_grp, _i]; };
		private _tries = 0;
		while {!DMS_over && {_tries < 3}} do {
			if (!DMS_exfilActive) then {
				_tries = _tries + 1;
				["REQUEST", [leader _grp]] call DMS_fnc_exfil;
				if (_tries > 1) then { ["exfil_retry", true, format ["attempt %1", _tries]] call _check; };
			};
			if (DMS_exfilActive) then {
				private _lzMove = _grp addWaypoint [DMS_lz, 15];
				_lzMove setWaypointType "MOVE";
				_lzMove setWaypointBehaviour "AWARE";
				_lzMove setWaypointSpeed "FULL";
				_grp setBehaviour "AWARE";
				_grp setSpeedMode "FULL";
				_grp setCurrentWaypoint _lzMove;
				waitUntil { sleep 5; DMS_over || {!DMS_exfilActive} };
			};
		};
	};
	default {};
};
