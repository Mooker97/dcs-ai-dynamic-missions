/*
	DMS_fnc_section - the friendly section behind the tank: two M2A3 Bradleys carrying a rifle squad (server only).
	["INIT"] call DMS_fnc_section;      spawn the Bradleys on the route points behind the tank, squad in the back
	["FOLLOW"] spawn DMS_fnc_section;   keep Bradley 1 followDistance behind the tank along the route (Bradley 2 a
	                                    further followGap), stop when the tank stops, never overtake it; once the
	                                    village armour is down and they are close, stop short and dismount the squad
	["DISMOUNT"] call DMS_fnc_section;  the squad gets out and clears the village (LAMBS taskCQB, else SAD)
	["LOSSES"] spawn DMS_fnc_section;   log (and hint) each Bradley lost and the squad wiped out; losing them does not fail
	The crews fight on their own (combat mode YELLOW); LAMBS is told to leave the crews alone so they keep station.
*/
params [["_mode", "", [""]], ["_args", [], [[]]]];
private _cfg = DMS_cfg;

switch (_mode) do {
	case "INIT": {
		DMS_ifvs = [];
		DMS_inf = grpNull;
		DMS_dismounted = false;
		DMS_followSamples = [];
		private _cls = (_cfg get "ifvClasses") select {isClass (configFile >> "CfgVehicles" >> _x)};
		if (_cls isEqualTo []) exitWith { ["Section: no Bradley class exists, no section", "WARN"] call DMS_fnc_log; };
		private _route = DMS_layout get "route";
		private _si = DMS_layout get "startIndex";
		for "_i" from 0 to ((_cfg get "ifvCount") - 1) do {
			private _k = (_si - 2 - _i) max 0;
			private _p = _route select _k;
			private _veh = createVehicle [_cls select 0, _p, [], 0, "NONE"];
			_veh setDir (_p getDir (_route select (_k + 1)));
			createVehicleCrew _veh;
			private _grp = group (driver _veh);
			{ _x setSkill (_cfg get "ifvSkill"); _x setVariable ["lambs_danger_disableAI", true, true]; } forEach (crew _veh);
			_grp setVariable ["lambs_danger_disableGroupAI", true, true];
			_grp setBehaviour "AWARE";
			_grp setCombatMode "YELLOW";
			_grp setSpeedMode "NORMAL";
			_veh setVariable ["DMS_lastTarget", []];
			_veh setVariable ["DMS_lastOrder", -100];
			DMS_ifvs pushBack _veh;
		};
		// rifle squad split across the Bradleys
		private _inf = createGroup [west, true];
		private _infCls = [_cfg get "infLeaderClass"] + (_cfg get "infClasses");
		{
			private _u = _inf createUnit [_x, [0, 0, 0], [], 0, "CAN_COLLIDE"];
			_u setSkill (_cfg get "infSkill");
			private _veh = DMS_ifvs select (_forEachIndex mod (count DMS_ifvs));
			if ((_veh emptyPositions "cargo") == 0) then { _veh = DMS_ifvs select ((_forEachIndex + 1) mod (count DMS_ifvs)); };
			_u assignAsCargo _veh;
			_u moveInCargo _veh;
		} forEach _infCls;
		_inf setBehaviour "AWARE";
		_inf setCombatMode "YELLOW";
		DMS_inf = _inf;
		[format ["Section: %1 x %2 at route points %3, squad %4 men (%5 in the back)", count DMS_ifvs, _cls select 0,
			DMS_ifvs apply {["INDEX", [getPosATL _x]] call DMS_fnc_site}, count (units _inf), {vehicle _x != _x} count (units _inf)]] call DMS_fnc_log;
	};

	case "FOLLOW": {
		private _route = DMS_layout get "route";
		private _toGo = DMS_layout get "toGo";
		private _xr = DMS_layout get "crossroads";
		(_cfg get "followDistance") params ["_fMin", "_fMax"];
		private _gap = _cfg get "followGap";
		private _lastTankPos = getPosATL DMS_tank;
		private _tankStill = 0;
		while {!DMS_over && {!DMS_dismounted}} do {
			sleep (_cfg get "followUpdate");
			if (DMS_over) exitWith {};
			private _tank = DMS_tank;
			private _live = DMS_ifvs select {alive _x && {alive (driver _x)}};
			if (_live isEqualTo []) exitWith { ["Section: no Bradley left to follow the tank"] call DMS_fnc_log; };
			private _tp = getPosATL _tank;
			_tankStill = if ((_tp distance2D _lastTankPos) < 8) then { _tankStill + (_cfg get "followUpdate") } else { 0 };
			_lastTankPos = _tp;
			private _ti = ["INDEX", [_tp]] call DMS_fnc_site;

			// dismount once the village armour is down and the section or the tank is close
			private _armour = (DMS_villageArmour select {["THREAT", [_x]] call DMS_fnc_enemy}) isEqualTo [];
			private _close = ((_tank distance2D _xr) < (_cfg get "dismountTrigger")) || {(_live findIf {(_x distance2D _xr) < (_cfg get "dismountTrigger")}) > -1};
			if (_armour && {_close} && {alive (leader DMS_inf)}) exitWith { ["DISMOUNT"] spawn DMS_fnc_section; };

			{
				private _veh = _x;
				private _want = _fMin + _forEachIndex * _gap;
				private _max = _fMax + _forEachIndex * _gap;
				private _d = _veh distance2D _tank;
				private _vi = ["INDEX", [getPosATL _veh]] call DMS_fnc_site;
				if (_forEachIndex == 0 && {(speed _tank) > 5}) then { DMS_followSamples pushBack _d; };
				// the route point about _want metres (along the road) behind the tank
				private _k = _ti;
				while {_k > 0 && {((_toGo select _k) - (_toGo select _ti)) < _want}} do { _k = _k - 1; };
				private _tgt = _route select _k;
				private _stop = (_d < _want) || {_vi > _ti} || {_tankStill >= 10 && {_d < _max}};
				if (_stop) then {
					if ((speed _veh) > 2) then { doStop _veh; _veh setVariable ["DMS_lastTarget", []]; };
				} else {
					private _last = _veh getVariable ["DMS_lastTarget", []];
					if (_d > _max || {(speed _veh) < 2}) then {
						if (_last isEqualTo [] || {(_last distance2D _tgt) > 40} || {time - (_veh getVariable ["DMS_lastOrder", -100]) > 30}) then {
							_veh doMove _tgt;
							_veh setVariable ["DMS_lastTarget", _tgt];
							_veh setVariable ["DMS_lastOrder", time];
						};
					};
				};
			} forEach _live;
		};
	};

	case "DISMOUNT": {
		if (DMS_dismounted) exitWith {};
		DMS_dismounted = true;
		private _route = DMS_layout get "route";
		private _toGo = DMS_layout get "toGo";
		private _xr = DMS_layout get "crossroads";
		private _k = (_toGo findIf {_x <= (_cfg get "dismountDistance")}) max 0;
		private _dp = _route select _k;
		private _live = DMS_ifvs select {alive _x && {alive (driver _x)}};
		["Section: village armour down, Bradleys moving up to dismount the squad"] call DMS_fnc_log;
		if (!isNull DMS_player) then { "Village armour down. Bradleys moving up to dismount the infantry." remoteExecCall ["hintSilent", DMS_player]; };
		{
			private _p = _dp getPos [_forEachIndex * 40, (_dp getDir _xr) + 180];
			// only move up if the Bradley is still short of the dismount point
			if ((_x distance2D _xr) > ((_p distance2D _xr) + 20)) then { _x doMove _p; } else { doStop _x; };
		} forEach _live;
		private _t = time;
		waitUntil { sleep 2; DMS_over || {(_live findIf {alive _x && {(_x distance2D _dp) > 60} && {(_x distance2D _xr) > ((_dp distance2D _xr) + 20)}}) < 0} || {time - _t > 150} };
		if (DMS_over) exitWith {};
		{ if (alive _x) then { doStop _x; }; } forEach _live;
		sleep 3;
		private _inf = DMS_inf;
		{ unassignVehicle _x; } forEach (units _inf);
		{ _inf leaveVehicle _x; } forEach DMS_ifvs;
		sleep 6;
		{ if (alive _x && {vehicle _x != _x}) then { moveOut _x; }; } forEach (units _inf);
		_inf setBehaviour "COMBAT";
		_inf setCombatMode "RED";
		private _out = {alive _x && {vehicle _x == _x}} count (units _inf);
		[format ["Section: squad dismounted, %1 men out, %2 m from the crossroads", _out, round ((leader _inf) distance2D _xr)]] call DMS_fnc_log;
		if (DMS_testMode) then { ["CHECK", ["section_dismount", _out >= 2, format ["%1 men out %2 m from the crossroads", _out, round ((leader _inf) distance2D _xr)]]] call DMS_fnc_testMode; };
		sleep 4;
		if (DMS_over || {_out == 0}) exitWith {};
		if (!isNil "lambs_wp_fnc_taskCQB") then {
			// [group, position, radius, cycle, area, isWaypoint]
			[_inf, _xr, _cfg get "clearSearchRadius", 21] spawn lambs_wp_fnc_taskCQB;
			[format ["Section: squad clearing the village (LAMBS taskCQB, %1 m)", _cfg get "clearSearchRadius"]] call DMS_fnc_log;
		} else {
			private _wp = _inf addWaypoint [_xr, 30];
			_wp setWaypointType "SAD";
			_wp setWaypointBehaviour "COMBAT";
			["Section: no LAMBS, squad SAD on the crossroads", "WARN"] call DMS_fnc_log;
		};
	};

	case "LOSSES": {
		private _lost = [];
		private _infLost = false;
		while {!DMS_over} do {
			sleep 3;
			{
				private _veh = _x;
				if (!(_veh in _lost)) then {
					private _why = if (!alive _veh) then { "destroyed" } else {
						if (({alive _x} count ((crew _veh) select {!(_x in (units DMS_inf))})) == 0) then { "crew out or dead" } else { "" }
					};
					if (_why != "") then {
						_lost pushBack _veh;
						[format ["Section: Bradley %1 lost (%2) at t=%3, %4 m from the crossroads", _forEachIndex + 1, _why, round time, round (_veh distance2D (DMS_layout get "crossroads"))], "WARN"] call DMS_fnc_log;
						if (!isNull DMS_player) then { (format ["Bradley %1 is out of the fight.", _forEachIndex + 1]) remoteExecCall ["hintSilent", DMS_player]; };
					};
				};
			} forEach DMS_ifvs;
			if (!_infLost && {!isNull DMS_inf} && {({alive _x} count (units DMS_inf)) == 0}) then {
				_infLost = true;
				[format ["Section: rifle squad wiped out at t=%1", round time], "WARN"] call DMS_fnc_log;
			};
		};
	};
	default {};
};
