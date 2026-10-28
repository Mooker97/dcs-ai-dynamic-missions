/*
	DMS_fnc_convoy - the Russian motor-rifle convoy (server only).
	["SCHEDULE"] spawn DMS_fnc_convoy;               wait the seeded delay, then SPAWN
	["SPAWN"] call DMS_fnc_convoy;                   vehicles in march order on the entry road, crews in one column group,
	                                                 dismount squads in the trucks, waypoints through the kill zone
	["CONTACT", [_reason]] call DMS_fnc_convoy;      once: the ambush is sprung (or compromised); the convoy reacts
	["DISMOUNT", [_veh, _cargoGrp]] spawn DMS_fnc_convoy; stop the truck, dismount, then LAMBS taskHunt
	["MONITOR"] spawn DMS_fnc_convoy;                detection, escapes past the kill line, combat-ineffective check
	Escaped vehicles drive on and are removed; escapeFailCount escapes fail the mission.
*/
params [["_mode", "", [""]], ["_args", [], [[]]]];
private _cfg = DMS_cfg;

switch (_mode) do {
	case "SCHEDULE": {
		private _d = [DMS_rolls get "convoyDelay", 240] call DMS_fnc_t;
		[format ["Convoy sets off in %1 s", round _d]] call DMS_fnc_log;
		private _tEnd = time + _d;
		waitUntil { sleep 2; DMS_over || {time >= _tEnd} };
		if (DMS_over) exitWith {};
		["SPAWN"] call DMS_fnc_convoy;
	};

	case "SPAWN": {
		if (DMS_convoySpawned) exitWith {};
		private _rows = _cfg get "convoy";
		private _trucks = DMS_rolls get "convoyTrucks";
		private _spawns = DMS_route get "spawns";
		private _skills = _cfg get "enemySkill";
		private _grp = createGroup [east, true];
		private _entries = [];
		private _men = [];
		private _truckN = 0;
		// Hits from BLUFOR, or from nothing (scripted mortar rounds), spring the ambush. Collisions inside the
		// convoy (an east source) do not.
		private _onHit = {
			params ["_unit", "_source", "_damage", ["_instigator", objNull]];
			if (missionNamespace getVariable ["DMS_contact", false]) exitWith {};
			private _west = (!isNull _instigator && {side (group _instigator) == west}) || {!isNull _source && {side (group _source) == west}};
			if (_west || {isNull _source && {isNull _instigator} && {_damage > 0.1}}) then { ["CONTACT", ["convoy hit"]] call DMS_fnc_convoy; };
		};
		{
			_x params ["_role", "_cls", "_cargoN"];
			private _use = true;
			if (_role == "TRUCK") then { _truckN = _truckN + 1; _use = _truckN <= _trucks; };
			if (_use) then {
				if (!(isClass (configFile >> "CfgVehicles" >> _cls))) then {
					[format ["Convoy: missing class %1 (skipped)", _cls], "WARN"] call DMS_fnc_log;
				} else {
					(_spawns select (count _entries)) params ["_pos", "_dir"];
					private _veh = createVehicle [_cls, _pos, [], 0, "CAN_COLLIDE"];
					_veh setDir _dir;
					_veh setPosATL [_pos select 0, _pos select 1, 0.3];
					createVehicleCrew _veh;
					private _cg0 = group (effectiveCommander _veh);
					(crew _veh) joinSilent _grp;
					if (!isNull _cg0 && {_cg0 != _grp}) then { deleteGroup _cg0; };
					{ private _u = _x; { _u setSkill _x } forEach _skills; _men pushBack _u; } forEach (crew _veh);
					_veh forceFollowRoad true;
					_veh addEventHandler ["Hit", _onHit];
					_veh addEventHandler ["Killed", { [format ["Convoy vehicle destroyed: %1", typeOf (_this select 0)]] call DMS_fnc_log; }];

					private _cargo = grpNull;
					if (_cargoN > 0) then {
						_cargo = createGroup [east, true];
						for "_i" from 1 to _cargoN do {
							private _ucls = if (_i == 1) then { _cfg get "dismountLeaderClass" } else { ["PICK", _cfg get "dismountClasses"] call DMS_fnc_rng };
							private _u = _cargo createUnit [_ucls, _pos getPos [25, _dir + 180], [], 5, "NONE"];
							{ _u setSkill _x } forEach _skills;
							_u moveInCargo _veh;
							if (vehicle _u == _u) then { deleteVehicle _u; } else { _men pushBack _u; };
						};
						_cargo setBehaviour "SAFE";
						_cargo setCombatMode "YELLOW";
					};
					_entries pushBack [_veh, _role, _cargo];
				};
			};
		} forEach _rows;

		if (_entries isEqualTo []) exitWith { ["Convoy: no vehicle could be created", "ERROR"] call DMS_fnc_log; };
		{
			_x addEventHandler ["Hit", _onHit];
			_x addEventHandler ["Killed", {
				if (!(missionNamespace getVariable ["DMS_contact", false])) then { ["CONTACT", ["convoy casualty"]] call DMS_fnc_convoy; };
			}];
		} forEach _men;
		_grp selectLeader (effectiveCommander ((_entries select 0) select 0));
		_grp setFormation "COLUMN";
		_grp setBehaviour "SAFE";
		_grp setSpeedMode "LIMITED";
		_grp setCombatMode "YELLOW";
		{
			private _wp = _grp addWaypoint [_x, 0];
			_wp setWaypointType "MOVE";
			_wp setWaypointCompletionRadius 25;
		} forEach (DMS_route get "waypoints");

		DMS_convoy = _entries;
		DMS_convoyGroup = _grp;
		DMS_convoyMen = _men;
		DMS_convoyStartMen = count _men;
		DMS_convoySpawned = true;
		publicVariable "DMS_convoySpawned";
		[format ["Convoy spawned: %1, %2 men (%3 dismounts), lead %4 m by road from the kill zone, %5 waypoints",
			_entries apply {typeOf (_x select 0)}, count _men, {!isNull (_x select 2)} count _entries,
			_cfg get "entryDistance", count (DMS_route get "waypoints")]] call DMS_fnc_log;
		if (DMS_testMode) then { ["CHECK", ["convoy_spawned", (count _entries) >= 3, format ["%1 vehicles, %2 men", count _entries, count _men]]] call DMS_fnc_testMode; };
		private _km = (round ((_cfg get "entryDistance") / 100)) / 10;
		[format ["Observation post: convoy moving towards the kill zone, %1 km out. %2 vehicles.", _km, count _entries]] remoteExecCall ["hintSilent", 0];

		if (DMS_debug) then {
			{
				private _vm = createMarker [format ["DMS_dbg_veh_%1", _forEachIndex], getPosATL (_x select 0)];
				_vm setMarkerType "mil_dot";
				_vm setMarkerColor "ColorRed";
				_vm setMarkerText typeOf (_x select 0);
			} forEach _entries;
		};
		["MONITOR"] spawn DMS_fnc_convoy;
	};

	case "CONTACT": {
		_args params [["_reason", "unknown", [""]]];
		if (DMS_contact || {DMS_over} || {!DMS_convoySpawned}) exitWith {};
		DMS_contact = true;
		DMS_contactTime = time;
		publicVariable "DMS_contact";
		private _lead = (DMS_convoy select 0) select 0;
		private _kz = DMS_route get "killZone";
		[format ["CONTACT (%1) at t=%2, lead vehicle %3 m from the kill zone", _reason, round time, round (_lead distance2D _kz)]] call DMS_fnc_log;
		if (DMS_testMode) then { ["CHECK", ["contact", true, _reason]] call DMS_fnc_testMode; };

		// The squad is released to fire at will (it starts on hold fire).
		[DMS_squad, "YELLOW"] remoteExecCall ["setCombatMode", leader DMS_squad];

		private _grp = DMS_convoyGroup;
		_grp setBehaviour "COMBAT";
		_grp setCombatMode "RED";
		_grp setSpeedMode "NORMAL";
		{
			_x params ["_veh", "_role", "_cargo"];
			if (alive _veh) then { _veh forceFollowRoad false; };
			if (!isNull _cargo) then { ["DISMOUNT", [_veh, _cargo]] spawn DMS_fnc_convoy; };
		} forEach DMS_convoy;
	};

	case "DISMOUNT": {
		_args params ["_veh", "_cg"];
		if (alive _veh) then {
			private _drv = driver _veh;
			if (alive _drv) then { doStop _drv; };
			_veh forceSpeed 0;
			private _t = time;
			waitUntil { sleep 1; DMS_over || {!alive _veh} || {speed _veh < 3} || {time - _t > (DMS_cfg get "dismountStopTimeout")} };
		};
		if (DMS_over) exitWith {};
		{ unassignVehicle _x; } forEach (units _cg);
		_cg leaveVehicle _veh;
		sleep 4;
		{ if (alive _x && {vehicle _x != _x}) then { moveOut _x; }; } forEach (units _cg);
		_cg setBehaviour "COMBAT";
		_cg setCombatMode "RED";
		[format ["Dismounts out of %1: %2 men", typeOf _veh, {alive _x} count (units _cg)]] call DMS_fnc_log;

		// LAMBS Danger drives the immediate reaction; after a short delay the squad hunts the ambushers.
		sleep (DMS_cfg get "huntDelay");
		if (DMS_over || {({alive _x} count (units _cg)) == 0}) exitWith {};
		if (!isNil "lambs_wp_fnc_taskHunt") then {
			// [group, radius, cycle, area, centre, onlyPlayers, enableReinforcement, flares]
			[_cg, DMS_cfg get "huntRadius", 15, [], DMS_route get "killZone", false, false, 0] spawn lambs_wp_fnc_taskHunt;
			[format ["Dismount group %1: LAMBS taskHunt, radius %2 m", groupId _cg, DMS_cfg get "huntRadius"]] call DMS_fnc_log;
		} else {
			private _wp = _cg addWaypoint [DMS_route get "ambush", 50];
			_wp setWaypointType "SAD";
			_wp setWaypointBehaviour "COMBAT";
			[format ["Dismount group %1: no LAMBS, SAD on the ambush position", groupId _cg], "WARN"] call DMS_fnc_log;
		};
	};

	case "MONITOR": {
		private _thr = _cfg get "detectKnowsAbout";
		private _beyond = DMS_route get "beyond";
		private _exitPt = (DMS_route get "outPts") select (count (DMS_route get "outPts") - 1);
		private _kz = DMS_route get "killZone";
		private _escaped = 0;
		private _closeLogged = false;
		private _slowSince = -1;
		private _stuckLogged = false;
		while {!DMS_over && {!DMS_convoyIneffective}} do {
			sleep 2;
			private _lead = (DMS_convoy select 0) select 0;
			// detection before the ambush is sprung
			if (!DMS_contact) then {
				private _targets = (units DMS_squad) select {alive _x};
				private _groups = [DMS_convoyGroup] + ((DMS_convoy apply {_x select 2}) select {!isNull _x});
				if (_groups findIf { private _g = _x; _targets findIf {(_g knowsAbout _x) >= _thr} > -1 } > -1) then {
					["CONTACT", ["ambush compromised (convoy spotted the squad)"]] call DMS_fnc_convoy;
				};
				if (!_closeLogged && {alive _lead} && {(_lead distance2D _kz) < 400}) then {
					_closeLogged = true;
					[format ["Convoy lead 400 m from the kill zone at t=%1", round time]] call DMS_fnc_log;
				};
				if (alive _lead && {speed _lead < 1}) then {
					if (_slowSince < 0) then { _slowSince = time; };
					if (!_stuckLogged && {time - _slowSince > (DMS_cfg get "stuckWarn")}) then {
						_stuckLogged = true;
						[format ["Convoy lead has not moved for %1 s at %2 (%3 m from the kill zone)", DMS_cfg get "stuckWarn", mapGridPosition _lead, round (_lead distance2D _kz)], "WARN"] call DMS_fnc_log;
					};
				} else {
					_slowSince = -1;
				};
			};
			// escapes past the kill line
			{
				_x params ["_veh"];
				if (alive _veh && {!(_veh getVariable ["DMS_escaped", false])} && {canMove _veh} && {alive (driver _veh)}
					&& {(_beyond findIf {(_x distance2D _veh) < 40}) > -1}) then {
					_veh setVariable ["DMS_escaped", true];
					_escaped = _escaped + 1;
					[format ["Convoy vehicle %1 escaped past the kill line (%2 of %3 allowed)", typeOf _veh, _escaped, (DMS_cfg get "escapeFailCount") - 1]] call DMS_fnc_log;
					[_veh, _exitPt] spawn {
						params ["_veh", "_exitPt"];
						private _t = time;
						waitUntil { sleep 3; DMS_over || {!alive _veh} || {(_veh distance2D _exitPt) < 80} || {time - _t > 150} };
						if (DMS_over) exitWith {};
						{ deleteVehicle _x; } forEach (crew _veh);
						deleteVehicle _veh;
					};
				};
			} forEach DMS_convoy;
			if (_escaped >= (DMS_cfg get "escapeFailCount")) exitWith {
				["DMS_FailEscape", false, format ["%1 convoy vehicles escaped past the kill line", _escaped]] call DMS_fnc_end;
			};
			// combat ineffective: no working vehicle and almost nobody left near the kill zone
			if (DMS_contact || {(DMS_convoy findIf {!alive (_x select 0)}) > -1}) then {
				private _working = DMS_convoy select {
					private _v = _x select 0;
					alive _v && {!(_v getVariable ["DMS_escaped", false])} && {({alive _x} count (crew _v)) > 0}
						&& {canMove _v || {canFire _v && {alive (gunner _v)}}}
				};
				private _men = DMS_convoyMen select {
					alive _x && {!((vehicle _x) getVariable ["DMS_escaped", false])} && {(_x distance2D _kz) < (DMS_cfg get "fledDistance")}
				};
				if (_working isEqualTo [] && {(count _men) <= (DMS_cfg get "ineffectiveMaxAlive")}) then {
					DMS_convoyIneffective = true;
					[format ["Convoy combat ineffective at t=%1: %2 vehicles destroyed or disabled, %3 escaped, %4 of %5 men left",
						round time, ({!((_x select 0) getVariable ["DMS_escaped", false])} count DMS_convoy), _escaped, count _men, DMS_convoyStartMen]] call DMS_fnc_log;
					if (DMS_testMode) then { ["CHECK", ["convoy_ineffective", true, format ["%1 escaped, %2 men left", _escaped, count _men]]] call DMS_fnc_testMode; };
					["START"] call DMS_fnc_rp;
				};
			};
		};
	};
	default {};
};
