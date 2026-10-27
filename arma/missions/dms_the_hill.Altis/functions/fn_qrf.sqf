/*
	DMS_fnc_qrf - alarm detection and quick reaction force (server only).
	["MONITOR"] spawn DMS_fnc_qrf;           watch for detection (group knowsAbout >= threshold)
	["ALARM", [_reason]] call DMS_fnc_qrf;   raise the alarm once; schedules wave 1 and maybe wave 2
	["WAVE", [_n]] call DMS_fnc_qrf;         spawn wave _n (1 or 2) on a road and send it in
	Wave 1 comes 5-8 min after the alarm. Wave 2 comes only if the fight drags or wave 1 dies quickly.
	Vehicles stop 350-600 m short; infantry dismount, flank, then search and destroy.
*/
params [["_mode", "MONITOR", [""]], ["_args", [], [[]]]];
private _cfg = DMS_cfg;

switch (_mode) do {
	case "MONITOR": {
		private _thr = _cfg get "alarmKnowsAbout";
		while {!DMS_alarm && {!DMS_over}} do {
			sleep 2;
			private _targets = (units DMS_squad) select {alive _x};
			private _detected = DMS_enemyGroups findIf {
				private _g = _x;
				!isNull _g && {_targets findIf {(_g knowsAbout _x) >= _thr} > -1}
			} > -1;
			if (_detected) exitWith { ["ALARM", ["detected"]] call DMS_fnc_qrf; };
		};
	};

	case "ALARM": {
		_args params [["_reason", "unknown", [""]]];
		if (DMS_alarm || {DMS_over}) exitWith {};
		DMS_alarm = true;
		DMS_alarmTime = time;
		[format ["ALARM raised (%1) at t=%2", _reason, round time]] call DMS_fnc_log;
		if (DMS_testMode) then { ["CHECK", ["alarm", true, _reason]] call DMS_fnc_testMode; };

		{ _x setBehaviour "COMBAT"; _x setCombatMode "YELLOW"; } forEach (DMS_enemyGroups select {!isNull _x});

		// The patrol falls back into the compound instead of charging.
		private _pg = DMS_patrolGroup;
		if (!isNull _pg) then {
			for "_i" from (count (waypoints _pg) - 1) to 0 step -1 do { deleteWaypoint [_pg, _i]; };
			private _wpMove = _pg addWaypoint [DMS_compoundCenter, 10];
			_wpMove setWaypointType "MOVE";
			_wpMove setWaypointSpeed "FULL";
			private _wpHold = _pg addWaypoint [DMS_compoundCenter, 10];
			_wpHold setWaypointType "HOLD";
			_pg setCurrentWaypoint _wpMove;
		};

		[] spawn {
			private _cfg = DMS_cfg;
			private _d1 = [DMS_rolls get "wave1Delay"] call DMS_fnc_t;
			[format ["QRF wave 1 from %1 due in %2 s", DMS_rolls get "wave1SpawnName", round _d1]] call DMS_fnc_log;
			sleep _d1;
			if (DMS_over) exitWith {};
			["WAVE", [1]] call DMS_fnc_qrf;

			private _drag = DMS_alarmTime + ([_cfg get "wave2DragTime", 120] call DMS_fnc_t);
			private _quick = [_cfg get "wave2QuickKill", 60] call DMS_fnc_t;
			waitUntil {
				sleep 5;
				DMS_over || {time > _drag} || {
					(missionNamespace getVariable ["DMS_wave1Down", -1]) > 0
					&& {((missionNamespace getVariable ["DMS_wave1Down", -1]) - (missionNamespace getVariable ["DMS_wave1Spawned", 0])) < _quick}
				}
			};
			if (DMS_over) exitWith {};
			private _d2 = [DMS_rolls get "wave2Delay"] call DMS_fnc_t;
			[format ["QRF wave 2 from %1 due in %2 s", DMS_rolls get "wave2SpawnName", round _d2]] call DMS_fnc_log;
			sleep _d2;
			if (DMS_over) exitWith {};
			["WAVE", [2]] call DMS_fnc_qrf;
		};
	};

	case "WAVE": {
		_args params ["_n"];
		(_cfg get (["wave1", "wave2"] select (_n - 1))) params ["_vehClasses", "_infClasses", "_infCount", "_dismount"];
		private _spawnPos = DMS_rolls get (["wave1Spawn", "wave2Spawn"] select (_n - 1));
		private _idx = _vehClasses findIf {isClass (configFile >> "CfgVehicles" >> _x)};
		if (_idx < 0) exitWith { [format ["QRF wave %1: no vehicle class exists in %2", _n, _vehClasses], "WARN"] call DMS_fnc_log; };

		private _veh = createVehicle [_vehClasses select _idx, _spawnPos, [], 0, "NONE"];
		_veh setDir (_spawnPos getDir DMS_compoundCenter);
		createVehicleCrew _veh;
		private _crewGrp = group (effectiveCommander _veh);
		private _inf = createGroup [east, true];
		for "_i" from 1 to _infCount do {
			private _u = _inf createUnit [["PICK", _infClasses] call DMS_fnc_rng, _spawnPos, [], 20, "NONE"];
			{ _u setSkill _x } forEach (_cfg get "enemySkill");
			_u moveInCargo _veh;
			_u addEventHandler ["Killed", {
				params ["_unit", "_killer"];
				[format ["QRF unit killed by %1 (%2) at %3 m", typeOf _killer, side (group _killer), round (_unit distance2D _killer)], "DEBUG"] call DMS_fnc_log;
			}];
			if (vehicle _u == _u) then { deleteVehicle _u; };
		};
		{
			private _c = _x;
			{ _c setSkill _x } forEach (_cfg get "enemySkill");
		} forEach (units _crewGrp);

		private _dmDist = ["RANGE", _dismount] call DMS_fnc_rng;
		private _dm = ["ROAD", [DMS_compoundCenter getPos [_dmDist, DMS_compoundCenter getDir _spawnPos], 150]] call DMS_fnc_findPos;
		private _wp = _crewGrp addWaypoint [_dm, 0];
		_wp setWaypointType "MOVE";
		_wp setWaypointBehaviour "AWARE";
		_wp setWaypointSpeed "NORMAL";

		missionNamespace setVariable [format ["DMS_wave%1Spawned", _n], time];
		DMS_enemyGroups pushBack _inf;
		[format ["QRF wave %1 spawned: %2 with %3 infantry, dismount at %4 m", _n, typeOf _veh, count (units _inf), round _dmDist]] call DMS_fnc_log;
		if (DMS_testMode) then { ["CHECK", [format ["qrf_wave%1", _n], true, typeOf _veh]] call DMS_fnc_testMode; };

		[_n, _veh, _inf, _dm] spawn {
			params ["_n", "_veh", "_inf", "_dm"];
			private _cfg = DMS_cfg;
			private _t0 = time;
			private _slowSince = -1;
			waitUntil {
				sleep 2;
				if (alive _veh && {speed _veh < 2}) then {
					if (_slowSince < 0) then { _slowSince = time; };
				} else {
					_slowSince = -1;
				};
				DMS_over || {!alive _veh} || {!canMove _veh} || {_veh distance2D _dm < 40}
					|| {_slowSince > 0 && {time - _slowSince > 45}} || {time - _t0 > 600}
			};
			if (DMS_over) exitWith {};

			_inf leaveVehicle _veh;
			{ unassignVehicle _x; } forEach (units _inf);

			// Flank: approach from the side, then search and destroy around the target.
			private _target = DMS_compoundCenter;
			private _ldr = leader DMS_squad;
			if (alive _ldr && {_ldr distance2D DMS_compoundCenter > 400}) then { _target = getPosATL _ldr; };
			private _side = [-1, 1] select (["CHANCE", 0.5] call DMS_fnc_rng);
			private _flank = _target getPos [_cfg get "qrfFlankOffset", (_target getDir _dm) + (_side * (_cfg get "qrfFlankAngle"))];
			private _w1 = _inf addWaypoint [_flank, 30];
			_w1 setWaypointType "MOVE";
			_w1 setWaypointBehaviour "AWARE";
			_w1 setWaypointFormation "WEDGE";
			_w1 setWaypointSpeed "NORMAL";
			private _w2 = _inf addWaypoint [_target, 30];
			_w2 setWaypointType "SAD";
			_w2 setWaypointBehaviour "COMBAT";
			[format ["QRF wave %1 dismounted (%2 alive), flanking", _n, {alive _x} count (units _inf)]] call DMS_fnc_log;

			waitUntil { sleep 5; DMS_over || {({alive _x} count (units _inf)) <= 1} };
			if (!DMS_over) then {
				missionNamespace setVariable [format ["DMS_wave%1Down", _n], time];
				[format ["QRF wave %1 combat ineffective at t=%2", _n, round time]] call DMS_fnc_log;
			};
		};
	};
	default {};
};
