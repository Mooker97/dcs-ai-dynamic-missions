/*
	DMS_fnc_counter - insurgent counterattack and the hold phase (server only).
	["SCHEDULE"] spawn DMS_fnc_counter;   after the village is cleared: seeded delay, then SPAWN and HOLD
	["SPAWN"] call DMS_fnc_counter;       truck (+ optional technical) on a road 1.3-1.7 km out, away from the
	                                      squad's approach; infantry dismount 300-450 m short and clear the
	                                      village house by house (lambs_wp_fnc_taskCQB). Vehicles hold at the
	                                      dismount point (a vehicle sent hunting the squad wiped it in The Hill).
	["HOLD"] spawn DMS_fnc_counter;       counterattack beaten + village secure -> win (partial if the Bradley is lost)
*/
params [["_mode", "", [""]], ["_args", [], [[]]]];
private _cfg = DMS_cfg;

switch (_mode) do {
	case "SCHEDULE": {
		private _d = [DMS_rolls get "counterDelay"] call DMS_fnc_t;
		[format ["Counterattack from %1 due in %2 s", DMS_rolls get "counterOrigin", round _d]] call DMS_fnc_log;
		private _t = time;
		waitUntil { sleep 2; DMS_over || {time - _t > _d} };
		if (DMS_over) exitWith {};
		["SPAWN"] call DMS_fnc_counter;
		["HOLD"] spawn DMS_fnc_counter;
	};

	case "SPAWN": {
		private _spawnPos = DMS_rolls get "counterSpawn";
		private _center = DMS_villageCenter;
		private _skills = _cfg get "enemySkill";
		private _trucks = (_cfg get "counterTruckClasses") select {isClass (configFile >> "CfgVehicles" >> _x)};
		DMS_counterUnits = [];
		DMS_counterVehicles = [];
		DMS_counterSpawned = time;
		if (_trucks isEqualTo []) exitWith { [format ["Counterattack: no truck class exists in %1", _cfg get "counterTruckClasses"], "WARN"] call DMS_fnc_log; };

		private _veh = createVehicle [_trucks select 0, _spawnPos, [], 0, "NONE"];
		_veh setDir (_spawnPos getDir _center);
		createVehicleCrew _veh;
		private _crewGrp = group (effectiveCommander _veh);
		{ private _c = _x; { _c setSkill _x } forEach _skills; } forEach (crew _veh);
		DMS_counterVehicles pushBack _veh;

		private _inf = createGroup [DMS_enemySide, true];
		{
			if (isClass (configFile >> "CfgVehicles" >> _x)) then {
				private _u = _inf createUnit [_x, _spawnPos, [], 20, "NONE"];
				{ _u setSkill _x } forEach _skills;
				_u moveInCargo _veh;
				if (vehicle _u == _u) then { deleteVehicle _u; };
			};
		} forEach (_cfg get "counterInfantry");
		DMS_counterUnits = units _inf;

		// Optional DShKM technical 40 m behind the truck. It stops short with the truck and gives fire support.
		private _tech = objNull;
		private _techCls = _cfg get "technicalClass";
		if ((DMS_rolls get "counterTechnical") && {isClass (configFile >> "CfgVehicles" >> _techCls)}) then {
			private _tp = ["ROAD", [_spawnPos getPos [40, _center getDir _spawnPos], 60]] call DMS_fnc_findPos;
			_tech = createVehicle [_techCls, _tp, [], 0, "NONE"];
			_tech setDir (_tp getDir _center);
			createVehicleCrew _tech;
			{ private _c = _x; { _c setSkill _x } forEach _skills; } forEach (crew _tech);
			DMS_counterVehicles pushBack _tech;
		};

		private _dmDist = DMS_rolls get "counterDismountDist";
		private _dm = ["ROAD", [_center getPos [_dmDist, _center getDir _spawnPos], 150]] call DMS_fnc_findPos;
		{
			private _g = group (effectiveCommander _x);
			private _wp = _g addWaypoint [[_dm, _dm getPos [30, _center getDir _spawnPos]] select (_x != _veh), 0];
			_wp setWaypointType "MOVE";
			_wp setWaypointBehaviour "AWARE";
			_wp setWaypointSpeed "NORMAL";
			_g setBehaviour "AWARE";
			_g setCombatMode "YELLOW";
		} forEach DMS_counterVehicles;
		DMS_enemyGroups pushBack _inf;
		[format ["Counterattack spawned at %1: %2 with %3 infantry%4, dismount %5 m out",
			_spawnPos apply {round _x}, typeOf _veh, count (units _inf), [" (no technical)", format [" and %1", typeOf _tech]] select (!isNull _tech), round _dmDist]] call DMS_fnc_log;
		if (DMS_testMode) then { ["CHECK", ["counterattack", (count (units _inf)) > 0, format ["%1 infantry, %2 vehicles", count (units _inf), count DMS_counterVehicles]]] call DMS_fnc_testMode; };

		[_veh, _inf, _dm, _crewGrp] spawn {
			params ["_veh", "_inf", "_dm", "_crewGrp"];
			private _t0 = time;
			private _slowSince = -1;
			waitUntil {
				sleep 2;
				if (alive _veh && {speed _veh < 2}) then {
					if (_slowSince < 0) then { _slowSince = time; };
				} else {
					_slowSince = -1;
				};
				DMS_over || {!alive _veh} || {!alive (driver _veh)} || {_veh distance2D _dm < 40}
					|| {_slowSince > 0 && {time - _slowSince > 45}} || {time - _t0 > 600}
			};
			if (DMS_over) exitWith {};
			_inf leaveVehicle _veh;
			{ unassignVehicle _x; } forEach (units _inf);
			doStop (crew _veh);
			{ if (_x != _veh && {alive _x}) then { doStop (crew _x); }; } forEach DMS_counterVehicles;
			DMS_counterDismounted = time;
			[format ["Counterattack dismounted %1 m from the village (%2 alive), clearing house by house",
				round (_veh distance2D DMS_villageCenter), {alive _x} count (units _inf)]] call DMS_fnc_log;
			sleep 5;
			if (DMS_over) exitWith {};
			// [group, position, radius, cycle delay, area, called by waypoint]
			[_inf, DMS_villageCenter, DMS_cfg get "counterCqbRadius"] spawn lambs_wp_fnc_taskCQB;
		};
	};

	case "HOLD": {
		private _t0 = time;
		private _n = count DMS_counterUnits;
		private _thr = floor (_n * (_cfg get "counterBeatenFraction"));
		private _beaten = {
			({alive _x} count DMS_counterUnits) <= _thr
			&& {(DMS_counterVehicles findIf {alive _x && {canFire _x} && {alive (gunner _x)} && {!isNull (gunner _x)}}) < 0}
		};
		private _secure = {
			private _r = DMS_cfg get "holdRadius";
			((allUnits findIf {alive _x && {side (group _x) == DMS_enemySide} && {_x distance2D DMS_villageCenter < _r} && {(west knowsAbout _x) >= 1}}) < 0)
			&& {((units DMS_squad) findIf {alive _x && {_x distance2D DMS_villageCenter < _r}}) > -1}
		};
		private _stall = [_cfg get "holdStallTime", 300] call DMS_fnc_t;
		waitUntil { sleep 5; DMS_over || {call _beaten} || {time - _t0 > _stall} };
		if (DMS_over) exitWith {};
		[format ["Counterattack %1 at t=%2: %3 of %4 infantry alive",
			["stalled", "beaten"] select (call _beaten), round time, {alive _x} count DMS_counterUnits, _n]] call DMS_fnc_log;

		// Consolidate: the village must stay secure for holdConsolidate s: no KNOWN insurgent inside holdRadius
		// (a last hidden defender does not block the win forever) and a squad member inside it.
		private _need = [_cfg get "holdConsolidate", 20] call DMS_fnc_t;
		private _since = -1;
		waitUntil {
			sleep 5;
			if (call _secure) then {
				if (_since < 0) then { _since = time; };
			} else {
				_since = -1;
			};
			DMS_over || {_since > 0 && {time - _since >= _need}}
		};
		if (DMS_over) exitWith {};
		["DMS_t_hold", "SUCCEEDED"] call BIS_fnc_taskSetState;
		if (DMS_testMode) then { ["CHECK", ["village_held", true, format ["t=%1", round time]]] call DMS_fnc_testMode; };
		if (DMS_ifvLost) then {
			["DMS_WinPartial", true, "village held, Bradley lost", "PARTIAL"] call DMS_fnc_end;
		} else {
			if (["DMS_t_ifv"] call BIS_fnc_taskExists) then { ["DMS_t_ifv", "SUCCEEDED"] call BIS_fnc_taskSetState; };
			["DMS_Win", true, "village held"] call DMS_fnc_end;
		};
	};
	default {};
};
