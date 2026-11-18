/*
	DMS_fnc_testMode - unattended run of the ambient module (server only).
	["CHECK", [_name, _pass, _detail]] call DMS_fnc_testMode;   log "[DMS.TEST] PASS|FAIL <name> <detail>" (first verdict wins)
	["SUMMARY"] call DMS_fnc_testMode;                         FAIL every expected check not reached, then SUMMARY and DONE
	["RUN"] spawn DMS_fnc_testMode;                            activate -> layers -> traffic/heli -> hysteresis -> despawn -> reactivate
	An AI test squad is the only watcher (DMSA_watchers); it is teleported with setPosATL between phases.
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
		[format ["SUMMARY pass=%1 fail=%2 seed=%3 site=%4 faction=%5", _pass, _fail, DMS_seed, DMS_siteName, DMS_faction], "TEST"] call DMS_fnc_log;
		["DONE", "TEST"] call DMS_fnc_log;
	};

	case "RUN": {
		private _cfg = DMS_cfg;
		private _check = { ["CHECK", _this] call DMS_fnc_testMode; };
		private _t0 = time;
		private _id = DMS_siteId;
		private _center = DMS_baseCenter;

		// Hard stop after DMS_testMinutes.
		[_t0 + (DMS_testMinutes * 60)] spawn {
			params ["_deadline"];
			waitUntil { sleep 5; DMS_over || {time > _deadline} };
			if (!DMS_over) then { ["DMS_TestEnd", false, "test timeout"] call DMS_fnc_end; };
		};

		// Test squad: the only watcher.
		private _grp = createGroup [west, true];
		{
			private _u = _grp createUnit [_x, DMS_baseStart, [], 3, "NONE"];
			_u allowDamage false;
		} forEach (_cfg get "squadClasses");
		_grp setBehaviour "CARELESS";
		_grp setCombatMode "BLUE";
		{ _x disableAI "PATH"; } forEach (units _grp);
		DMSA_watchers = units _grp;
		["spawn_squad", (count (units _grp)) >= 4, format ["%1 units at %2", count (units _grp), DMS_baseStart apply {round _x}]] call _check;

		private _site = DMSA_sites get _id;
		private _o = _site get "opts";
		private _moveSquad = {
			params ["_pos"];
			{
				private _p = _pos getPos [3 * _forEachIndex, 90];
				_x setPosATL [_p select 0, _p select 1, 0];
			} forEach (units _grp);
		};
		// First dry point at distance _d from the centre, trying bearings every 15 deg.
		private _dryAt = {
			params ["_d"];
			private _res = [];
			for "_i" from 0 to 23 do {
				private _p = _center getPos [_d, _i * 15];
				if (_res isEqualTo [] && {!surfaceIsWater _p}) then { _res = [_p select 0, _p select 1, 0]; };
			};
			_res
		};
		private _countStr = {
			private _c = [_id, true] call DMSA_fnc_ambientCount;
			format ["units=%1 vehicles=%2 groups=%3 objects=%4", _c select 0, _c select 1, _c select 2, _c select 3]
		};

		// Progress line every 60 s for the log reader.
		[_t0, _id] spawn {
			params ["_t0", "_id"];
			while {!DMS_over} do {
				sleep 60;
				private _s = DMSA_sites get _id;
				private _c = [_id] call DMSA_fnc_ambientCount;
				[format ["STATUS t=%1 active=%2 activations=%3 units=%4 vehicles=%5 groups=%6 heli=%7/%8 squadToBase=%9",
					round (time - _t0), _s get "active", _s get "activations", _c select 0, _c select 1, _c select 2,
					_s get "heliSpawned", _s get "heliLanded", round ((leader (DMSA_watchers select 0)) distance2D DMS_baseCenter)]] call DMS_fnc_log;
			};
		};

		// ------------------------------------------------ 1. activation
		waitUntil { sleep 2; DMS_over || {_site get "active"} || {(time - _t0) > (_cfg get "testActivateTimeout")} };
		if (DMS_over) exitWith {};
		["ambient_activated", _site get "active", format ["t=%1 activations=%2", round (time - _t0), _site get "activations"]] call _check;
		private _t1 = time;
		waitUntil { sleep 1; !(_site get "spawning") || {(time - _t1) > 120} };
		sleep 2;
		private _c = [_id] call DMSA_fnc_ambientCount;
		private _n = _site get "lastSpawn";
		["ambient_spawned", (_c select 0) > 0 && {(_c select 1) > 0} && {(_c select 2) > 0}, call _countStr] call _check;
		["ambient_layers", (_n getOrDefault ["idle", 0]) > 0 && {(_n getOrDefault ["sentries", 0]) > 0} && {(_n getOrDefault ["traffic", 0]) > 0},
			format ["sentries=%1 idle=%2 work=%3 traffic=%4", _n getOrDefault ["sentries", 0], _n getOrDefault ["idle", 0], _n getOrDefault ["work", 0], _n getOrDefault ["traffic", 0]]] call _check;
		["ambient_caps", (_c select 0) <= (_o get "maxUnits") && {(_c select 1) <= (_o get "maxVehicles")},
			format ["units %1/%2 vehicles %3/%4", _c select 0, _o get "maxUnits", _c select 1, _o get "maxVehicles"]] call _check;
		private _tracked = ((_site get "units") + (_site get "vehicles")) select {!isNull _x};
		["ambient_tagged", (_tracked isNotEqualTo []) && {(_tracked findIf {(_x getVariable ["DMSA_ambient", ""]) != _id}) < 0}
			&& {(((_site get "units") select {!isNull _x}) findIf {(side (group _x)) != (_site get "side")}) < 0},
			format ["%1 tracked objects, side %2", count _tracked, _site get "side"]] call _check;
		private _grps = (_site get "groups") select {!isNull _x};
		private _men = (_site get "units") select {!isNull _x};
		["ambient_lambs_off", (_grps isNotEqualTo []) && {(_grps findIf {!(_x getVariable ["lambs_danger_disableGroupAI", false])}) < 0}
			&& {(_men findIf {!(_x getVariable ["lambs_danger_disableAI", false])}) < 0},
			format ["%1 groups, %2 men", count _grps, count _men]] call _check;

		// ------------------------------------------------ 2. traffic moves, helicopter lands
		private _t2 = time;
		private _moved = 0;
		waitUntil {
			sleep 5;
			_moved = 0;
			{ _x params ["_veh", "_p0"]; if (alive _veh) then { _moved = _moved max (_veh distance2D _p0); }; } forEach (_site get "trafficStart");
			DMS_over || {_moved > 40} || {(time - _t2) > (_cfg get "testTrafficWait")}
		};
		if (DMS_over) exitWith {};
		["ambient_traffic_moving", _moved > 40, format ["max %1 m from start after %2 s (%3 vehicles)", round _moved, round (time - _t2), count (_site get "trafficStart")]] call _check;

		waitUntil { sleep 5; DMS_over || {(_site get "heliLanded") > 0} || {(time - _t1) > (_cfg get "testHeliTimeout")} };
		if (DMS_over) exitWith {};
		["ambient_heli_landed", (_site get "heliLanded") > 0,
			format ["spawned=%1 landed=%2 pad=%3 t=%4", _site get "heliSpawned", _site get "heliLanded", (_site get "pad") apply {round _x}, round (time - _t1)]] call _check;

		// ------------------------------------------------ 3. hysteresis: between activeRadius and despawnRadius nothing despawns
		private _mid = [((_o get "activeRadius") + (_o get "despawnRadius")) / 2] call _dryAt;
		if (_mid isEqualTo []) then { _mid = _center getPos [((_o get "activeRadius") + (_o get "despawnRadius")) / 2, 0]; };
		[_mid] call _moveSquad;
		[format ["Test: squad moved to %1 m from the base (hysteresis band)", round ((leader _grp) distance2D _center)]] call DMS_fnc_log;
		sleep ((_o get "despawnDelay") + 3 * (_o get "pollInterval"));
		private _c2 = [_id] call DMSA_fnc_ambientCount;
		["ambient_hysteresis", (_site get "active") && {(_c2 select 0) > 0},
			format ["still active at %1 m after %2 s: %3", round ((leader _grp) distance2D _center), (_o get "despawnDelay") + 3 * (_o get "pollInterval"), _c2 select 0]] call _check;

		// ------------------------------------------------ 4. despawn when the squad is far away
		private _far = [_cfg get "testFarDist"] call _dryAt;
		if (_far isEqualTo []) then { _far = [(_o get "despawnRadius") + 200] call _dryAt; };
		[_far] call _moveSquad;
		[format ["Test: squad moved to %1 m from the base", round ((leader _grp) distance2D _center)]] call DMS_fnc_log;
		private _t4 = time;
		waitUntil { sleep 2; DMS_over || {!(_site get "active")} || {(time - _t4) > ((_o get "despawnDelay") + 60)} };
		if (DMS_over) exitWith {};
		sleep 4;
		private _c4 = [_id, true] call DMSA_fnc_ambientCount;
		private _left = ((_site get "units") + (_site get "vehicles") + (_site get "groups")) select {!isNull _x};
		["ambient_despawned", !(_site get "active") && {(_c4 select 0) == 0} && {(_c4 select 1) == 0} && {(_c4 select 2) == 0} && {(_c4 select 3) == 0} && {_left isEqualTo []},
			format ["after %1 s: %2 tracked=%3", round (time - _t4), call _countStr, count _left]] call _check;

		// ------------------------------------------------ 5. back to base: reactivation
		[DMS_baseStart] call _moveSquad;
		["Test: squad moved back to the base"] call DMS_fnc_log;
		private _t5 = time;
		private _act0 = _site get "activations";
		waitUntil { sleep 2; DMS_over || {(_site get "activations") > _act0} || {(time - _t5) > (_cfg get "testActivateTimeout")} };
		if (DMS_over) exitWith {};
		_t5 = time;
		waitUntil { sleep 1; !(_site get "spawning") || {(time - _t5) > 120} };
		sleep 2;
		private _c5 = [_id] call DMSA_fnc_ambientCount;
		["ambient_reactivated", (_site get "active") && {(_c5 select 0) > 0} && {(_site get "activations") == (_act0 + 1)},
			format ["activations=%1 %2", _site get "activations", call _countStr]] call _check;

		["DMS_Win", true, "test complete"] call DMS_fnc_end;
	};
	default {};
};
