/*
	DMS_fnc_ifv - the attached M2A3 Bradley and its three comm-menu orders (server only).
	["INIT", [_pos, _dir]] call DMS_fnc_ifv;                 spawn it with an AI crew, start the loss monitor
	["MOVE", [_caller]]                                      "move up to my position": stops ifvStandoff m short of the caller
	["HOLD", [_caller]]                                      "hold here, overwatch": stop, engage what it sees
	["SUPPRESS", [_caller, _pos]]                            "suppress marked position": the comm-menu cursor position;
	                                                         refused when danger close, out of range or no line of sight
	The crew runs its own engagements (combat mode YELLOW). LAMBS is told to leave the crew alone so it does
	not wander off between orders. Lost = destroyed, or no living crew inside (bailed out or killed).
*/
params [["_mode", "", [""]], ["_args", [], [[]]]];
private _cfg = DMS_cfg;
private _tell = {
	params ["_caller", "_text"];
	if (!isNull _caller && {isPlayer _caller}) then { _text remoteExecCall ["hintSilent", _caller]; };
	[_text] call DMS_fnc_log;
};

switch (_mode) do {
	case "INIT": {
		_args params ["_pos", "_dir"];
		private _veh = createVehicle [_cfg get "ifvClass", _pos, [], 0, "NONE"];
		_veh setDir _dir;
		createVehicleCrew _veh;
		private _grp = group (effectiveCommander _veh);
		{ _x setSkill (_cfg get "ifvSkill"); _x setVariable ["lambs_danger_disableAI", true, true]; } forEach (crew _veh);
		_grp setVariable ["lambs_danger_disableGroupAI", true, true];
		_grp setBehaviour "AWARE";
		_grp setCombatMode "YELLOW";
		DMS_ifv = _veh;
		DMS_ifvLost = false;
		DMS_ifvBusy = false;
		DMS_ifvShots = 0;
		DMS_ifvLastSuppress = -1000;
		DMS_ifvOrder = 0;
		_veh addEventHandler ["Fired", { DMS_ifvShots = DMS_ifvShots + 1; }];
		doStop (effectiveCommander _veh);
		[format ["Bradley %1 spawned at %2, crew %3", typeOf _veh, _pos apply {round _x}, (crew _veh) apply {typeOf _x}]] call DMS_fnc_log;

		[_veh] spawn {
			params ["_veh"];
			private _why = "";
			waitUntil {
				sleep 3;
				_why = if (!alive _veh) then { "destroyed" } else {
					if (({alive _x} count (crew _veh)) == 0) then { "crew out or dead" } else { "" }
				};
				DMS_over || {_why != ""}
			};
			if (DMS_over) exitWith {};
			DMS_ifvLost = true;
			[format ["Bradley lost (%1) at t=%2", _why, round time], "WARN"] call DMS_fnc_log;
			if (!isNull DMS_player) then { "Bradley is out of the fight." remoteExecCall ["hintSilent", DMS_player]; };
			if (["DMS_t_ifv"] call BIS_fnc_taskExists) then { ["DMS_t_ifv", "FAILED"] call BIS_fnc_taskSetState; };
			if (DMS_testMode) then { ["CHECK", ["ifv_lost", DMS_testForce == 1, _why]] call DMS_fnc_testMode; };
		};
	};

	case "MOVE": {
		_args params [["_caller", objNull]];
		if (DMS_over || {isNull _caller}) exitWith {};
		if (DMS_ifvLost) exitWith { [_caller, "Bradley: no response."] call _tell; };
		private _veh = DMS_ifv;
		private _cp = getPosATL _caller;
		private _standoff = _cfg get "ifvStandoff";
		if ((_veh distance2D _cp) < _standoff + 10) exitWith { [_caller, "Bradley: already on your position."] call _tell; };
		private _dest = _cp getPos [_standoff, _cp getDir _veh];
		DMS_ifvOrder = DMS_ifvOrder + 1;
		private _order = DMS_ifvOrder;
		_veh doMove _dest;
		[_caller, format ["Bradley: moving up to your position, %1 m.", round (_veh distance2D _dest)]] call _tell;
		[_veh, _dest, _order, _caller, _tell] spawn {
			params ["_veh", "_dest", "_order", "_caller", "_tell"];
			private _t0 = time;
			private _limit = DMS_cfg get "ifvMoveTimeout";
			waitUntil { sleep 3; DMS_over || {DMS_ifvLost} || {DMS_ifvOrder != _order} || {(_veh distance2D _dest) < 20} || {time - _t0 > _limit} };
			if (DMS_over || {DMS_ifvLost} || {DMS_ifvOrder != _order}) exitWith {};
			private _ok = (_veh distance2D _dest) < 20;
			if (_ok) then {
				doStop (effectiveCommander _veh);
				[_caller, "Bradley: set at your position."] call _tell;
			} else {
				[_caller, format ["Bradley: can't get through, holding %1 m short.", round (_veh distance2D _dest)]] call _tell;
			};
			if (DMS_testMode) then { ["CHECK", ["ifv_move", _ok, format ["%1 m from the ordered spot after %2 s", round (_veh distance2D _dest), round (time - _t0)]]] call DMS_fnc_testMode; };
		};
	};

	case "HOLD": {
		_args params [["_caller", objNull]];
		if (DMS_over) exitWith {};
		if (DMS_ifvLost) exitWith { [_caller, "Bradley: no response."] call _tell; };
		private _veh = DMS_ifv;
		DMS_ifvOrder = DMS_ifvOrder + 1;
		doStop (effectiveCommander _veh);
		doStop (driver _veh);
		(group (effectiveCommander _veh)) setCombatMode "YELLOW";
		[_caller, "Bradley: holding here, overwatch."] call _tell;
		if (DMS_testMode) then {
			[_veh] spawn {
				params ["_veh"];
				sleep 20;
				if (!DMS_over && {alive _veh}) then { ["CHECK", ["ifv_hold", (speed _veh) < 2, format ["speed %1 km/h", round (speed _veh)]]] call DMS_fnc_testMode; };
			};
		};
	};

	case "SUPPRESS": {
		_args params [["_caller", objNull], ["_pos", []]];
		if (DMS_over) exitWith {};
		if (DMS_ifvLost) exitWith { [_caller, "Bradley: no response."] call _tell; };
		if ((count _pos) < 2) exitWith { [_caller, "Bradley: no position marked."] call _tell; };
		private _veh = DMS_ifv;
		private _gun = gunner _veh;
		if (isNull _gun || {!alive _gun}) exitWith { [_caller, "Bradley: gunner down, can't engage."] call _tell; };
		if (DMS_ifvBusy) exitWith { [_caller, "Bradley: still on the last target."] call _tell; };
		if ((time - DMS_ifvLastSuppress) < (_cfg get "ifvSuppressCooldown")) exitWith { [_caller, "Bradley: reloading and resetting, wait one."] call _tell; };
		private _tgt = AGLToASL [_pos select 0, _pos select 1, 1];
		private _grid = mapGridPosition _tgt;
		private _range = _veh distance2D _tgt;
		if (_range > (_cfg get "ifvSuppressMaxRange")) exitWith { [_caller, format ["Bradley: grid %1 is out of range (%2 m).", _grid, round _range]] call _tell; };
		private _dc = _cfg get "ifvDangerClose";
		private _crew = crew _veh;
		if ((allUnits findIf {alive _x && {side (group _x) == west} && {!(_x in _crew)} && {(_x distance2D _tgt) < _dc}}) > -1) exitWith {
			[_caller, format ["Bradley: friendlies within %1 m of grid %2, can't fire.", _dc, _grid]] call _tell;
		};
		if (terrainIntersectASL [eyePos _gun, _tgt]) exitWith { [_caller, format ["Bradley: no line of sight to grid %1 from here.", _grid]] call _tell; };

		DMS_ifvBusy = true;
		DMS_ifvLastSuppress = time;
		[_caller, format ["Bradley: suppressing grid %1, %2 m.", _grid, round _range]] call _tell;
		[_veh, _gun, _tgt, _caller, _tell] spawn {
			params ["_veh", "_gun", "_tgt", "_caller", "_tell"];
			private _secs = DMS_cfg get "ifvSuppressSeconds";
			private _shots0 = DMS_ifvShots;
			_gun doWatch (ASLToAGL _tgt);
			sleep 4;
			if (!DMS_over && {alive _gun}) then {
				_gun suppressFor _secs;
				_gun doSuppressiveFire _tgt;
			};
			sleep (_secs + 4);
			DMS_ifvBusy = false;
			if (DMS_over) exitWith {};
			private _n = DMS_ifvShots - _shots0;
			[_caller, format ["Bradley: suppression complete, %1 rounds.", _n]] call _tell;
			if (DMS_testMode) then { ["CHECK", ["ifv_suppress", _n > 0, format ["%1 rounds", _n]]] call DMS_fnc_testMode; };
		};
	};
	default {};
};
