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
		{
			if (!(_x in DMS_testResults)) then { ["CHECK", [_x, false, "not reached"]] call DMS_fnc_testMode; };
		} forEach (DMS_cfg get "testExpected");
		private _pass = 0;
		private _fail = 0;
		{ if (_y) then { _pass = _pass + 1; } else { _fail = _fail + 1; }; } forEach DMS_testResults;
		[format ["SUMMARY pass=%1 fail=%2 seed=%3 site=%4", _pass, _fail, DMS_seed, DMS_siteName], "TEST"] call DMS_fnc_log;
	};

	case "RUN": {
		private _cfg = DMS_cfg;
		private _check = { ["CHECK", _this] call DMS_fnc_testMode; };
		private _t0 = time;

		["spawn_compound", (count DMS_compoundObjects) >= 10, format ["%1 objects", count DMS_compoundObjects]] call _check;
		["spawn_garrison", (count DMS_garrison) >= 8, format ["%1 defenders", count DMS_garrison]] call _check;
		["spawn_intel", !isNull DMS_intel, typeOf DMS_intel] call _check;
		["spawn_squad", ({alive _x} count (units DMS_squad)) >= 5, format ["%1 units", count (units DMS_squad)]] call _check;

		// Hard stop after DMS_testMinutes.
		[_t0 + (DMS_testMinutes * 60)] spawn {
			params ["_deadline"];
			waitUntil { sleep 5; DMS_over || {time > _deadline} };
			if (!DMS_over) then { ["DMS_TestEnd", false, "test timeout"] call DMS_fnc_end; };
		};

		// Advance: stage short of the compound, then search and destroy.
		private _grp = DMS_squad;
		_grp setBehaviour "AWARE";
		_grp setCombatMode "YELLOW";
		_grp setFormation "WEDGE";
		private _stage = DMS_compoundCenter getPos [350, DMS_startBearing];
		private _wpStage = _grp addWaypoint [_stage, 20];
		_wpStage setWaypointType "MOVE";
		_wpStage setWaypointSpeed "NORMAL";
		private _wpSad = _grp addWaypoint [DMS_compoundCenter, 10];
		_wpSad setWaypointType "SAD";
		_wpSad setWaypointBehaviour "COMBAT";

		// Artillery on the compound while the squad is still ~1 km out.
		sleep (_cfg get "testArtyAt");
		private _shells0 = DMS_artyShellsFired;
		["REQUEST", [leader _grp, DMS_compoundCenter, "FFE"]] call DMS_fnc_support;
		waitUntil { sleep 5; DMS_over || {DMS_artyShellsFired > _shells0} || {(time - _t0) > 400} };
		["artillery", DMS_artyShellsFired > _shells0, format ["%1 rounds", DMS_artyShellsFired - _shells0]] call _check;

		// Alarm (detection, casualties) - forced if it never happens.
		waitUntil { sleep 5; DMS_over || {DMS_alarm} || {(time - _t0) > (_cfg get "testAlarmTimeout")} };
		if (DMS_over) exitWith {};
		if (!DMS_alarm) then {
			["alarm", false, "no detection before timeout, forcing"] call _check;
			["ALARM", ["test forced"]] call DMS_fnc_qrf;
		};

		// Intel: once a squad member is inside the compound and the defenders are nearly gone.
		waitUntil {
			sleep 5;
			DMS_over || {(time - _t0) > (_cfg get "testIntelTimeout")} || {
				((units _grp) findIf {alive _x && {_x distance2D DMS_compoundCenter < 40}}) > -1
				&& {({alive _x && {_x distance2D DMS_compoundCenter < 100}} count DMS_garrison) <= 2}
			}
		};
		if (DMS_over) exitWith {};
		["compound_cleared", (time - _t0) <= (_cfg get "testIntelTimeout"), format ["t=%1", round (time - _t0)]] call _check;
		["TAKEN", [leader _grp]] call DMS_fnc_intel;

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
				_grp setCurrentWaypoint _lzMove;
				waitUntil { sleep 5; DMS_over || {!DMS_exfilActive} };
			};
		};
	};
	default {};
};
