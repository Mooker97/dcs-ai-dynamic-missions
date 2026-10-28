/*
	DMS_fnc_testMode - unattended run with an AI squad standing in for the player (server only).
	["CHECK", [_name, _pass, _detail]] call DMS_fnc_testMode;   log "[DMS.TEST] PASS|FAIL <name> <detail>" (first verdict wins)
	["SUMMARY"] call DMS_fnc_testMode;                         FAIL every expected check not reached, then a summary line
	["RUN"] spawn DMS_fnc_testMode;                            drive the squad: ambush position, spring the ambush, RP
	AI cannot use the comm menu, so the harness calls the same server functions directly.
	DMS_testForce 1: the squad holds fire and is ignored by the enemy (captive), so the convoy drives through.
	DMS_testForce 2: the squad is killed right after contact.
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
			case 1: { _expected = (_expected - ["contact", "artillery", "convoy_ineffective", "rp_reached", "outcome_win"]) + ["outcome_forced"]; };
			case 2: { _expected = (_expected - ["artillery", "convoy_ineffective", "rp_reached", "outcome_win"]) + ["outcome_forced"]; };
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
		private _kz = DMS_route get "killZone";
		private _ambush = DMS_route get "ambush";

		["spawn_route", (DMS_route get "inLength") >= (_cfg get "entryDistance") && {(DMS_route get "outLength") >= (_cfg get "killLineDistance")},
			format ["in %1 m, out %2 m, %3 waypoints, ambush %4 m from the road", round (DMS_route get "inLength"), round (DMS_route get "outLength"),
				count (DMS_route get "waypoints"), round (_ambush distance2D _kz)]] call _check;
		["spawn_squad", ({alive _x} count (units _grp)) >= 6, format ["%1 units", count (units _grp)]] call _check;

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
				private _ldr = leader DMS_squad;
				private _lead = if (DMS_convoySpawned) then { (DMS_convoy select 0) select 0 } else { objNull };
				[format ["STATUS t=%1 squad=%2 leaderToAmbush=%3 convoy=%4 leadToKillZone=%5 vehiclesAlive=%6 menAlive=%7 contact=%8 ineffective=%9 leaderToRp=%10",
					round (time - _t0), {alive _x} count (units DMS_squad), round (_ldr distance2D (DMS_route get "ambush")),
					DMS_convoySpawned, [-1, round (_lead distance2D (DMS_route get "killZone"))] select (alive _lead),
					{alive (_x select 0)} count DMS_convoy, {alive _x} count DMS_convoyMen,
					DMS_contact, DMS_convoyIneffective, round (_ldr distance2D (DMS_route get "rp"))]] call DMS_fnc_log;
			};
		};

		// 1. Move to the ambush position on hold fire.
		if (DMS_testForce == 1) then {
			{ _x setCaptive true; } forEach (units _grp);
			_grp setCombatMode "BLUE";
		} else {
			_grp setCombatMode "GREEN";
		};
		_grp setBehaviour "AWARE";
		_grp setFormation "WEDGE";
		private _wpAm = _grp addWaypoint [_ambush, 10];
		_wpAm setWaypointType "MOVE";
		_wpAm setWaypointSpeed "NORMAL";
		waitUntil {
			sleep 5;
			DMS_over || {DMS_contact} || {((leader _grp) distance2D _ambush) < 40}
				|| {(time - _t0) > ([_cfg get "testSetupTimeout", 300] call DMS_fnc_t)}
		};
		if (DMS_over) exitWith {};
		private _leadD = if (DMS_convoySpawned) then { round ((((DMS_convoy select 0) select 0)) distance2D _kz) } else { -1 };
		["squad_in_position", ((leader _grp) distance2D _ambush) < 40 && {!DMS_contact},
			format ["t=%1 leaderToAmbush=%2 convoyLeadToKillZone=%3", round (time - _t0), round ((leader _grp) distance2D _ambush), _leadD]] call _check;
		{ _x setUnitPos "MIDDLE"; doStop _x; } forEach (units _grp);

		// 2. Wait for the convoy and spring the ambush when the lead vehicle is close to the kill zone.
		waitUntil { sleep 2; DMS_over || {DMS_convoySpawned} || {(time - _t0) > (_cfg get "testConvoyTimeout")} };
		if (DMS_over) exitWith {};
		if (!DMS_convoySpawned) exitWith { ["convoy_spawned", false, "convoy never spawned"] call _check; };
		if (DMS_testForce == 1) exitWith { ["Test: forced failure, the squad holds fire and lets the convoy pass"] call DMS_fnc_log; };
		private _tc = time;
		waitUntil {
			sleep 1;
			private _lead = (DMS_convoy select 0) select 0;
			DMS_over || {DMS_contact} || {!alive _lead} || {(_lead distance2D _kz) < (_cfg get "testInitiateDistance")} || {time - _tc > 600}
		};
		if (DMS_over) exitWith {};
		if (!DMS_contact) then { ["CONTACT", ["test squad initiated"]] call DMS_fnc_convoy; };
		{ _x setUnitPos "AUTO"; } forEach (units _grp);
		_grp setCombatMode "YELLOW";
		_grp setBehaviour "COMBAT";
		if (DMS_testForce == 2) exitWith {
			["Test: forcing failure, killing the squad"] call DMS_fnc_log;
			{ _x setDamage 1; } forEach (units _grp);
		};

		// Mortars on the kill zone (danger close is checked by the support function itself).
		private _shells0 = DMS_artyShellsFired;
		private _imp0 = count DMS_artyImpacts;
		["REQUEST", [leader _grp, _kz, "FFE"]] call DMS_fnc_support;
		[_imp0, _shells0, _t0] spawn {
			params ["_imp0", "_shells0", "_t0"];
			private _cfg = DMS_cfg;
			private _tq = time;
			waitUntil { sleep 5; DMS_over || {(count DMS_artyImpacts) - _imp0 >= (_cfg get "artyRoundsFFE")} || {time - _tq > ([300, 90] call DMS_fnc_t)} };
			if (DMS_over) exitWith {};
			private _hits = DMS_artyImpacts select [_imp0, 99];
			private _near = { (_x select 1) < 3 * (_cfg get "artyCEP") } count _hits;
			["CHECK", ["artillery", (count _hits) >= 1 && {_near * 2 >= count _hits},
				format ["%1 rounds fired, %2 detonations, %3 within %4 m", DMS_artyShellsFired - _shells0, count _hits, _near, 3 * (_cfg get "artyCEP")]]] call DMS_fnc_testMode;
		};

		// Keep the launchers on the vehicles: reveal them and point the AT men at the nearest working one.
		[_grp] spawn {
			params ["_grp"];
			while {!DMS_over && {!DMS_convoyIneffective}} do {
				private _vehs = (DMS_convoy apply {_x select 0}) select {alive _x && {!(_x getVariable ["DMS_escaped", false])}};
				{ _grp reveal [_x, 4]; } forEach _vehs;
				{ _grp reveal [_x, 2.5]; } forEach (DMS_convoyMen select {alive _x && {(_x distance2D (leader _grp)) < 600}});
				{
					private _u = _x;
					if (alive _u && {secondaryWeapon _u != ""} && {_vehs isNotEqualTo []}) then {
						private _tgt = _vehs select 0;
						{ if ((_x distance2D _u) < (_tgt distance2D _u)) then { _tgt = _x; }; } forEach _vehs;
						_u doTarget _tgt;
						_u doFire _tgt;
					};
				} forEach (units _grp);
				sleep 15;
			};
		};

		// Optional fight assist (test only): AI-vs-AI fights in the trees can take very long.
		DMS_testAssisted = 0;
		if (DMS_testAssist > 0) then {
			[] spawn {
				private _tc = time;
				waitUntil { sleep 5; DMS_over || {DMS_convoyIneffective} || {time - _tc > DMS_testAssist} };
				if (DMS_over || {DMS_convoyIneffective}) exitWith {};
				private _kz = DMS_route get "killZone";
				private _left = DMS_convoyMen select {alive _x && {(_x distance2D _kz) < 900}};
				private _vehs = (DMS_convoy apply {_x select 0}) select {alive _x && {!(_x getVariable ["DMS_escaped", false])}};
				DMS_testAssisted = count _left;
				[format ["Test: fight assist after %1 s, removing %2 men and %3 vehicles", DMS_testAssist, count _left, count _vehs]] call DMS_fnc_log;
				{ _x setDamage 1; } forEach (_left + _vehs);
			};
		};

		// 3. Wait for the convoy to be finished, then walk to the RP.
		waitUntil { sleep 5; DMS_over || {DMS_convoyIneffective} || {(time - _tc) > ([_cfg get "testFightTimeout", 600] call DMS_fnc_t)} };
		if (DMS_over) exitWith {};
		if (!DMS_convoyIneffective) exitWith {
			["convoy_ineffective", false, format ["not finished after %1 s (assisted=%2)", round (time - _tc), DMS_testAssisted]] call _check;
		};
		{ _x doFollow (leader _grp); } forEach (units _grp);
		for "_i" from (count (waypoints _grp) - 1) to 0 step -1 do { deleteWaypoint [_grp, _i]; };
		private _wpRp = _grp addWaypoint [DMS_route get "rp", 10];
		_wpRp setWaypointType "MOVE";
		_wpRp setWaypointBehaviour "AWARE";
		_wpRp setWaypointSpeed "FULL";
		_grp setCurrentWaypoint _wpRp;
		private _tr = time;
		waitUntil { sleep 5; DMS_over || {(time - _tr) > ([_cfg get "testRpTimeout", 600] call DMS_fnc_t)} };
		if (!DMS_over) then { ["rp_reached", false, format ["not at the RP after %1 s", round (time - _tr)]] call _check; };
	};
	default {};
};
