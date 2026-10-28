/*
	DMS_fnc_testMode - unattended run with an AI squad standing in for the player (server only).
	["CHECK", [_name, _pass, _detail]] call DMS_fnc_testMode;   log "[DMS.TEST] PASS|FAIL <name> <detail>" (first verdict wins)
	["SUMMARY"] call DMS_fnc_testMode;                         FAIL every expected check not reached, then a summary line
	["RUN"] spawn DMS_fnc_testMode;                            danger-close checks, mortar and air calls, forced failures
	["ASSIST", [_n]] spawn DMS_fnc_testMode;                   with DMS_testAssist > 0: remove what is left of wave _n
	                                                           DMS_testAssist s after it first closes to 300 m (logged)
	The squad holds the OP on its own (it is placed and stopped at start). AI cannot use the comm menu,
	so the harness calls the same server functions directly.
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
		if (DMS_testForce > 0) then {
			// A forced failure replaces the win and cuts the run short after wave 1.
			_expected = ["mods", "spawn_squad", "spawn_static", "mortar_danger_close", "air_danger_close", "wave1", "outcome_forced"];
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

	case "ASSIST": {
		_args params ["_n"];
		if (DMS_testAssist <= 0) exitWith {};
		private _w = DMS_waves select {(_x select 0) == _n};
		if (_w isEqualTo []) exitWith {};
		private _grps = (_w select 0) select 1;
		private _t0 = time;
		private _close = {
			private _hit = false;
			{ if ((units _x) findIf {alive _x && {_x distance2D DMS_opCenter < 300}} > -1) then { _hit = true; }; } forEach _grps;
			_hit
		};
		waitUntil { sleep 5; DMS_over || {["BROKEN", [_n]] call DMS_fnc_waves} || {call _close} || {time - _t0 > 900} };
		if (DMS_over || {["BROKEN", [_n]] call DMS_fnc_waves}) exitWith {};
		private _tc = time;
		waitUntil { sleep 5; DMS_over || {["BROKEN", [_n]] call DMS_fnc_waves} || {time - _tc > DMS_testAssist} };
		if (DMS_over || {["BROKEN", [_n]] call DMS_fnc_waves}) exitWith {};
		private _left = [];
		{ _left append ((units _x) select {alive _x}); } forEach _grps;
		[format ["Test: assist after %1 s in contact, removing the %2 men left of wave %3", DMS_testAssist, count _left, _n]] call DMS_fnc_log;
		{ _x setDamage 1; } forEach _left;
	};

	case "RUN": {
		private _cfg = DMS_cfg;
		private _check = { ["CHECK", _this] call DMS_fnc_testMode; };
		private _t0 = time;
		private _grp = DMS_squad;

		["spawn_squad", ({alive _x} count (units _grp)) >= 6, format ["%1 units", count (units _grp)]] call _check;
		["spawn_static", !isNull DMS_static && {!isNull (gunner DMS_static)},
			format ["%1, gunner %2", typeOf DMS_static, typeOf (gunner DMS_static)]] call _check;

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
				private _r = DMS_cfg get "opRadius";
				[format ["STATUS t=%1 squad=%2 inOP=%3 waves=%4 alive=%5 eastAlive=%6 eastInOP=%7 sbf=%8 mortarLeft=%9 air=%10",
					round (time - _t0), {alive _x} count (units DMS_squad),
					{alive _x && {_x distance2D DMS_opCenter < _r}} count (units DMS_squad),
					count DMS_waves, DMS_waves apply {["ALIVE", [_x select 0]] call DMS_fnc_waves},
					{alive _x && {side (group _x) == east}} count allUnits,
					{alive _x && {side (group _x) == east} && {_x distance2D DMS_opCenter < _r}} count allUnits,
					[-1, round (DMS_sbfVeh distance2D DMS_opCenter)] select (alive DMS_sbfVeh),
					DMS_artyMissions, [DMS_airLeft, "on station"] select DMS_airOnStation]] call DMS_fnc_log;
			};
		};

		// Danger close: both requests on the OP itself must be refused without using a mission.
		sleep 5;
		private _m0 = DMS_artyMissions;
		private _r0 = DMS_artyRefused;
		["REQUEST", [leader _grp, DMS_opCenter, "FFE"]] call DMS_fnc_support;
		["mortar_danger_close", DMS_artyMissions == _m0 && {DMS_artyRefused == _r0 + 1} && {!DMS_artyBusy},
			format ["missions %1 -> %2", _m0, DMS_artyMissions]] call _check;
		private _a0 = DMS_airLeft;
		["REQUEST", [leader _grp, DMS_opCenter getPos [50, DMS_threatBearing]]] call DMS_fnc_air;
		["air_danger_close", DMS_airLeft == _a0 && {!DMS_airBusy}, format ["sorties %1 -> %2", _a0, DMS_airLeft]] call _check;

		// Forced failures (after wave 1 is in).
		if (DMS_testForce > 0) exitWith {
			waitUntil { sleep 5; DMS_over || {(count DMS_waves) >= 1} || {time - _t0 > 900} };
			if (DMS_over) exitWith {};
			sleep ([60, 20] call DMS_fnc_t);
			if (DMS_over) exitWith {};
			if (DMS_testForce == 1) then {
				["Test: forcing failure, killing the squad"] call DMS_fnc_log;
				{ _x setDamage 1; } forEach (units _grp);
			} else {
				["Test: forcing an overrun, the squad leaves the OP and wave 1 moves in"] call DMS_fnc_log;
				private _away = DMS_opCenter getPos [350, DMS_rearBearing];
				{
					if (vehicle _x != _x) then { moveOut _x; };
					_x setCaptive true;
					_x disableAI "PATH";
					_x setPosATL (_away getPos [3 * _forEachIndex, 90]);
				} forEach (units _grp);
				private _w1 = (DMS_waves select 0) select 1;
				private _i = 0;
				{
					{
						if (alive _x) then {
							_x setPosATL (DMS_opCenter getPos [5 + 2 * _i, 40 * _i]);
							_x disableAI "PATH";
							_i = _i + 1;
						};
					} forEach (units _x);
				} forEach _w1;
			};
		};

		// Air (in parallel with the mortar): on the support-by-fire vehicle once it holds, else on whatever
		// of wave 2 is outside danger close.
		[_grp] spawn {
			params ["_grp"];
			private _cfg = DMS_cfg;
			private _t0 = time;
			waitUntil { sleep 5; DMS_over || {(count DMS_waves) >= 2} || {time - _t0 > 1200} };
			if (DMS_over || {(count DMS_waves) < 2}) exitWith {};
			private _w2 = (DMS_waves select 1) select 1;
			private _ta = time;
			waitUntil { sleep 5; DMS_over || {alive DMS_sbfVeh && {(DMS_sbfVeh distance2D DMS_sbfPos) < 150} && {speed DMS_sbfVeh < 2}} || {time - _ta > 150} };
			if (DMS_over) exitWith {};
			private _airTgt = [];
			if (alive DMS_sbfVeh && {(DMS_sbfVeh distance2D DMS_opCenter) > (_cfg get "airDangerClose") + 50}) then {
				_airTgt = getPosATL DMS_sbfVeh;
			} else {
				{
					private _l = leader _x;
					if (alive _l && {(_l distance2D DMS_opCenter) > (_cfg get "airDangerClose") + 50}) exitWith { _airTgt = getPosATL _l; };
				} forEach _w2;
			};
			if (_airTgt isEqualTo []) exitWith { ["CHECK", ["air_requested", false, "no target outside danger close"]] call DMS_fnc_testMode; };
			["REQUEST", [leader _grp, _airTgt]] call DMS_fnc_air;
		};

		// Mortar: fire for effect on the second wave once it is past danger close and inside 800 m.
		private _dc = (_cfg get "artyDangerClose") + 50;
		waitUntil { sleep 5; DMS_over || {(count DMS_waves) >= 2} || {time - _t0 > 1200} };
		if (DMS_over || {(count DMS_waves) < 2}) exitWith {};
		private _w2 = (DMS_waves select 1) select 1;
		private _target = [];
		private _tw = time;
		waitUntil {
			sleep 5;
			{
				private _l = leader _x;
				if (alive _l && {(_l distance2D DMS_opCenter) > _dc} && {(_l distance2D DMS_opCenter) < 800}) exitWith { _target = getPosATL _l; };
			} forEach _w2;
			DMS_over || {_target isNotEqualTo []} || {time - _tw > 400}
		};
		if (DMS_over) exitWith {};
		if (_target isEqualTo []) exitWith {
			["mortar", false, "wave 2 never came inside 800 m while outside danger close"] call _check;
		};
		private _shells0 = DMS_artyShellsFired;
		private _imp0 = count DMS_artyImpacts;
		["REQUEST", [leader _grp, _target, "FFE"]] call DMS_fnc_support;
		private _want = _cfg get "artyRoundsFFE";
		private _tm = time;
		waitUntil { sleep 5; DMS_over || {(count DMS_artyImpacts) - _imp0 >= _want} || {time - _tm > 300} };
		private _hits = DMS_artyImpacts select [_imp0, 99];
		private _near = { (_x select 1) < 3 * (_cfg get "artyCEP") } count _hits;
		["mortar", (count _hits) >= 1 && {_near * 2 >= count _hits},
			format ["%1 rounds fired, %2 detonations, %3 within %4 m, target %5 m from the OP", DMS_artyShellsFired - _shells0,
				count _hits, _near, 3 * (_cfg get "artyCEP"), round (_target distance2D DMS_opCenter)]] call _check;
	};
	default {};
};
