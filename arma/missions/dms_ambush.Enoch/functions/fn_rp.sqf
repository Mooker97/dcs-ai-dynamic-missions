/*
	DMS_fnc_rp - rally point and pickup (server only).
	["INIT"] call DMS_fnc_rp;    park the crewed pickup vehicles at the rally point, mark it
	["START"] call DMS_fnc_rp;   the convoy is combat ineffective: break-contact task, then win when the player
	                             (or, with no player, any squad member) reaches the rally point
*/
params [["_mode", "", [""]], ["_args", [], [[]]]];

switch (_mode) do {
	case "INIT": {
		private _rp = DMS_route get "rp";
		private _away = DMS_route get "awayDir";
		private _grp = createGroup [west, true];
		private _made = [];
		{
			if (isClass (configFile >> "CfgVehicles" >> _x)) then {
				private _p = _rp getPos [12 * _forEachIndex, _away + 90];
				private _veh = createVehicle [_x, _p, [], 0, "NONE"];
				_veh setDir (_away + 180);
				createVehicleCrew _veh;
				private _g0 = group (effectiveCommander _veh);
				(crew _veh) joinSilent _grp;
				if (!isNull _g0 && {_g0 != _grp}) then { deleteGroup _g0; };
				_veh lock 0;
				_made pushBack _veh;
			} else {
				[format ["Rally point: missing class %1 (skipped)", _x], "WARN"] call DMS_fnc_log;
			};
		} forEach (DMS_cfg get "rpVehicles");
		_grp setBehaviour "AWARE";
		_grp setCombatMode "YELLOW";
		{ doStop _x; } forEach (units _grp);
		DMS_rpVehicles = _made;

		private _mk = createMarker ["DMS_mk_rp", _rp];
		_mk setMarkerType "hd_pickup";
		_mk setMarkerColor "ColorBLUFOR";
		_mk setMarkerText "RP";
		[format ["Rally point at %1 (%2): %3", _rp, ["open ground", "track/road"] select (DMS_route get "rpOnRoad"), _made apply {typeOf _x}]] call DMS_fnc_log;
		if (DMS_testMode) then { ["CHECK", ["spawn_rp", (count _made) >= 1, format ["%1 vehicles", count _made]]] call DMS_fnc_testMode; };
	};

	case "START": {
		if (DMS_over || {DMS_rpActive}) exitWith {};
		DMS_rpActive = true;
		["DMS_t_ambush", "SUCCEEDED"] call BIS_fnc_taskSetState;
		[true, "DMS_t_rp",
			["The convoy is finished. Break contact and get the squad to the rally point (RP), where the vehicles are waiting.", "Move to the RP", ""],
			DMS_route get "rp", "ASSIGNED", 1, true, "move"] call BIS_fnc_taskCreate;
		"Convoy combat ineffective. Break contact and move to the RP." remoteExecCall ["hintSilent", 0];
		["Rally point phase started"] call DMS_fnc_log;
		[] spawn {
			private _rp = DMS_route get "rp";
			private _r = DMS_cfg get "rpRadius";
			waitUntil {
				sleep 2;
				DMS_over
				|| {!isNull DMS_player && {alive DMS_player} && {(DMS_player distance2D _rp) < _r}}
				|| {isNull DMS_player && {((units DMS_squad) findIf {alive _x && {(_x distance2D _rp) < _r}}) > -1}}
			};
			if (DMS_over) exitWith {};
			private _with = {alive _x && {(_x distance2D _rp) < 150}} count (units DMS_squad);
			[format ["Rally point reached at t=%1, %2 of %3 squad members there", round time, _with, {alive _x} count (units DMS_squad)]] call DMS_fnc_log;
			if (DMS_testMode) then { ["CHECK", ["rp_reached", true, format ["%1 at the RP", _with]]] call DMS_fnc_testMode; };
			["DMS_t_rp", "SUCCEEDED"] call BIS_fnc_taskSetState;
			["DMS_Win", true, "convoy destroyed, squad at the rally point"] call DMS_fnc_end;
		};
	};
	default {};
};
