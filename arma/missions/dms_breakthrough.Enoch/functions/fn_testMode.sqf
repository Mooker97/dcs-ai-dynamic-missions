/*
	DMS_fnc_testMode - unattended run with an AI-crewed M1A2 standing in for the player (server only).
	["CHECK", [_name, _pass, _detail]] call DMS_fnc_testMode;   log "[DMS.TEST] PASS|FAIL <name> <detail>" (first verdict wins)
	["SUMMARY"] call DMS_fnc_testMode;                         FAIL every expected check not reached, then a summary line
	["RUN"] spawn DMS_fnc_testMode;                            drive the tank: halt short of the treeline and fight it (CAS 1
	                                                           on the treeline), advance to a halt point short of the village
	                                                           (CAS 2 on the ATGM or the BMP), then onto the crossroads once
	                                                           the squad is out. The section, phase line, pre-planned strike,
	                                                           counter-attack and win logic are the normal mission code.
	AI cannot use the comm menu, so the harness calls the same server function (DMS_fnc_air REQUEST) directly, and the
	AI commander is told about enemies within testRevealDistance (it stands in for the player's eyes).
	DMS_testForce 1: the tank is destroyed right after first contact (expects DMS_FailTank).
	DMS_testAssist N: N s after a stage starts (treeline fight, village armour, village clearing) its remaining enemies
	are removed and counted (DMS_testAssisted).
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
			_expected = (_expected - ["cas_strike", "treeline_killed", "section_follow", "preplanned_strike", "section_dismount", "village_cleared", "outcome_win"]) + ["outcome_forced"];
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
		private _tank = DMS_tank;
		private _grp = DMS_tankGroup;
		private _route = DMS_layout get "route";
		private _toGo = DMS_layout get "toGo";
		private _xr = DMS_layout get "crossroads";
		private _threat = { (["THREAT", [_this]] call DMS_fnc_enemy) };

		["spawn_tank", alive _tank && {(count (crew _tank)) >= 3}, format ["%1 crew %2", typeOf _tank, (crew _tank) apply {typeOf _x}]] call _check;
		["spawn_section", (count DMS_ifvs) == (_cfg get "ifvCount") && {({vehicle _x != _x} count (units DMS_inf)) >= 6},
			format ["%1 Bradleys, squad %2 (%3 in the back)", count DMS_ifvs, count (units DMS_inf), {vehicle _x != _x} count (units DMS_inf)]] call _check;
		private _vMen = {alive _x && {side (group _x) == east} && {(_x distance2D _xr) < 400}} count allUnits;
		["spawn_enemy", (count DMS_treeline) == (_cfg get "treelineTanks") && {alive DMS_atgm} && {(count DMS_villageArmour) >= 1} && {_vMen >= 6},
			format ["treeline %1, ATGM %2, village armour %3, men near the crossroads %4", count DMS_treeline, typeOf DMS_atgm, count DMS_villageArmour, _vMen]] call _check;

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
				private _xr = DMS_layout get "crossroads";
				[format ["STATUS t=%1 tank=%2 pos=%14 routeIdx=%15 dmg=%3 canMove=%4 toCrossroads=%5 ifvGaps=%6 treeline=%7 atgm=%8 villageArmour=%9 contact=%10 pl=%11 dismounted=%12 cas=%13",
					round (time - _t0), alive DMS_tank, (round ((damage DMS_tank) * 100)) / 100, canMove DMS_tank, round (DMS_tank distance2D _xr),
					DMS_ifvs apply {[-1, round (_x distance2D DMS_tank)] select (alive _x)},
					{["THREAT", [_x]] call DMS_fnc_enemy} count DMS_treeline, alive DMS_atgm, {["THREAT", [_x]] call DMS_fnc_enemy} count DMS_villageArmour,
					DMS_contact, DMS_plCrossed, DMS_dismounted, DMS_casLeft, (getPosATL DMS_tank) apply {round _x}, ["INDEX", [getPosATL DMS_tank]] call DMS_fnc_site]] call DMS_fnc_log;
			};
		};

		// The AI commander's eyes: reveal what is within testRevealDistance.
		[_grp] spawn {
			params ["_grp"];
			private _r = DMS_cfg get "testRevealDistance";
			while {!DMS_over && {alive DMS_tank}} do {
				{
					if (alive _x && {side (group _x) == east} && {(_x distance2D DMS_tank) < _r}) then { _grp reveal [vehicle _x, 4]; };
				} forEach allUnits;
				sleep 10;
			};
		};

		// Forced failure: kill the tank at first contact.
		if (DMS_testForce == 1) exitWith {
			waitUntil { sleep 2; DMS_over || {DMS_contact} };
			if (DMS_over) exitWith {};
			["Test: forcing failure, destroying the tank"] call DMS_fnc_log;
			DMS_tank setDamage 1;
		};

		private _goTo = {
			params ["_grp", "_fromIdx", "_toIdx"];
			{ _x doFollow (leader _grp); } forEach (units _grp);
			for "_i" from (count (waypoints _grp) - 1) to 0 step -1 do { deleteWaypoint [_grp, _i]; };
			for "_k" from (_fromIdx + 1) to _toIdx do {
				if ((_k - _fromIdx) mod 2 == 0 || {_k == _toIdx}) then {
					private _wp = _grp addWaypoint [_route select _k, 0];
					_wp setWaypointType "MOVE";
					_wp setWaypointSpeed "LIMITED";
					_wp setWaypointBehaviour "AWARE";
					_wp setWaypointCombatMode "YELLOW";
				};
			};
		};
		private _assist = {
			params ["_label", "_units"];
			private _left = _units select {alive _x};
			if (_left isEqualTo []) exitWith {};
			DMS_testAssisted = DMS_testAssisted + count _left;
			[format ["Test: fight assist (%1) after %2 s, removing %3", _label, DMS_testAssist, _left apply {typeOf _x}]] call DMS_fnc_log;
			{ _x setDamage 1; } forEach _left;
		};
		_grp setBehaviour "AWARE";
		_grp setCombatMode "YELLOW";

		// 1. Advance to the road abeam the treeline, halt and fight it.
		private _ti = ["INDEX", [getPosATL _tank]] call DMS_fnc_site;
		// halt on the road abeam the first treeline tank (its spot was chosen for line of sight to that stretch)
		private _h1 = (_toGo findIf {_x <= 2200}) max (_ti + 1);
		if (DMS_treeline isNotEqualTo []) then { _h1 = ((["INDEX", [getPosATL (DMS_treeline select 0)]] call DMS_fnc_site) - 1) max (_ti + 1); };
		[_grp, _ti, _h1] call _goTo;
		waitUntil { sleep 3; DMS_over || {!alive _tank} || {(_tank distance2D (_route select _h1)) < 40} || {time - _t0 > 400} };
		if (DMS_over || {!alive _tank}) exitWith {};
		[format ["Test: tank halted %1 m from the crossroads to engage the treeline", round (_tank distance2D _xr)]] call DMS_fnc_log;
		private _tl = DMS_treeline select {_x call _threat};
		if (_tl isNotEqualTo []) then {
			private _aim = getPosATL (_tl select 0);
			waitUntil { sleep 3; DMS_over || {!alive _tank} || {(_tank distance2D _aim) < (_cfg get "testCasDistance")} || {(DMS_treeline select {_x call _threat}) isEqualTo []} };
			if (!DMS_over && {(DMS_treeline select {_x call _threat}) isNotEqualTo []}) then {
				["REQUEST", [effectiveCommander _tank, _aim]] call DMS_fnc_air;
			};
		};
		private _ts = time;
		waitUntil {
			sleep 3;
			if (DMS_testAssist > 0 && {time - _ts > DMS_testAssist}) then { ["treeline", DMS_treeline select {_x call _threat}] call _assist; };
			DMS_over || {!alive _tank} || {(DMS_treeline select {_x call _threat}) isEqualTo []} || {time - _ts > ([_cfg get "testTreelineTimeout", 300] call DMS_fnc_t)}
		};
		if (DMS_over || {!alive _tank}) exitWith {};
		private _tlLeft = DMS_treeline select {_x call _threat};
		["treeline_killed", _tlLeft isEqualTo [], format ["t=%1, %2 left, assisted %3, tank damage %4", round (time - _t0), count _tlLeft, DMS_testAssisted, (round ((damage _tank) * 100)) / 100]] call _check;

		// 2. Advance to the halt point short of the village; CAS 2 on the ATGM (or the BMP) on the way.
		[_tank] spawn {
			params ["_tank"];
			waitUntil {
				sleep 3;
				DMS_over || {!alive _tank} || {DMS_casLeft <= 0}
					|| {alive DMS_atgm && {(_tank distance2D DMS_atgm) < 1300}}
					|| {(DMS_villageArmour findIf {(["THREAT", [_x]] call DMS_fnc_enemy) && {(_x distance2D _tank) < 1400}}) > -1}
			};
			if (DMS_over || {!alive _tank} || {DMS_casLeft <= 0}) exitWith {};
			waitUntil { sleep 3; DMS_over || {!DMS_casBusy} };
			if (DMS_over) exitWith {};
			private _aim = if (alive DMS_atgm) then { getPosATL DMS_atgm } else { getPosATL ((DMS_villageArmour select {["THREAT", [_x]] call DMS_fnc_enemy}) param [0, objNull]) };
			if ((_aim select 0) != 0) then { ["REQUEST", [effectiveCommander _tank, _aim]] call DMS_fnc_air; };
		};
		_ti = ["INDEX", [getPosATL _tank]] call DMS_fnc_site;
		private _h2 = (_toGo findIf {_x <= (_cfg get "testHaltDistance")}) max (_ti + 1);
		[_grp, _ti, _h2] call _goTo;
		waitUntil { sleep 3; DMS_over || {!alive _tank} || {(_tank distance2D (_route select _h2)) < 40} || {(_tank distance2D _xr) < (_cfg get "testHaltDistance")} || {time - _t0 > 1500} };
		if (DMS_over || {!alive _tank}) exitWith {};
		[format ["Test: tank halted %1 m from the crossroads, village armour %2", round (_tank distance2D _xr), {_x call _threat} count DMS_villageArmour]] call DMS_fnc_log;

		// 3. Village armour; the section dismounts by itself once it is down.
		_ts = time;
		waitUntil {
			sleep 3;
			if (DMS_testAssist > 0 && {time - _ts > DMS_testAssist}) then { ["village armour", DMS_villageArmour select {_x call _threat}] call _assist; };
			DMS_over || {!alive _tank} || {DMS_dismounted} || {((DMS_villageArmour select {_x call _threat}) isEqualTo []) && {time - _ts > 60}}
				|| {time - _ts > ([_cfg get "testVillageTimeout", 300] call DMS_fnc_t)}
		};
		if (DMS_over || {!alive _tank}) exitWith {};

		// 4. Up to the village once the squad is out: 150 m short of the crossroads, inside clearFriendlyRadius but
		//    outside holdRadius, so the run tests the "cleared" win (the hold win is the player's shortcut).
		_ts = time;
		waitUntil { sleep 3; DMS_over || {!alive _tank} || {!isNil {DMS_testResults get "section_dismount"}} || {time - _ts > 240} };
		if (DMS_over || {!alive _tank}) exitWith {};
		for "_i" from (count (waypoints _grp) - 1) to 0 step -1 do { deleteWaypoint [_grp, _i]; };
		private _wp = _grp addWaypoint [_xr getPos [150, _xr getDir _tank], 0];
		_wp setWaypointType "MOVE";
		_wp setWaypointSpeed "LIMITED";
		_grp setCurrentWaypoint _wp;
		["Test: tank moving up to 150 m from the crossroads"] call DMS_fnc_log;
		_ts = time;
		waitUntil {
			sleep 5;
			if (DMS_testAssist > 0 && {time - _ts > DMS_testAssist}) then {
				["village clearance", (allUnits select {alive _x && {side (group _x) == east} && {(_x distance2D _xr) < (_cfg get "clearRadius")}})
					+ (DMS_villageArmour select {_x call _threat})] call _assist;
			};
			DMS_over || {!alive _tank} || {time - _ts > ([_cfg get "testVillageTimeout", 300] call DMS_fnc_t)}
		};
		if (!DMS_over) then { ["village_cleared", false, format ["not cleared %1 s after the move onto the crossroads", round (time - _ts)]] call _check; };
	};
	default {};
};
