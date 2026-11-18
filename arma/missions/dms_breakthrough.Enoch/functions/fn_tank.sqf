/*
	DMS_fnc_tank - the player's M1A2 (server only).
	["INIT", [_pos, _dir]] call DMS_fnc_tank -> the tank (objNull if no class exists)
	    Normal play: AI driver and gunner join the player's group, the player gets the combat crewman loadout and
	    is moved into the commander's seat (turret [0, 0]); the player can switch seats with the action menu.
	    Test mode: a full AI crew in its own group commands the tank (DMS_tankGroup).
	["MONITOR"] spawn DMS_fnc_tank;   fail when the tank is destroyed or the player dies; an immobilised tank that
	    is still alive is not a fail: a hint says to bail out and fall back to the Bradleys, and after
	    immobileTimeout without a win the mission ends in a draw ("attack stalled").
*/
params [["_mode", "", [""]], ["_args", [], [[]]]];
private _cfg = DMS_cfg;

switch (_mode) do {
	case "INIT": {
		_args params ["_pos", "_dir"];
		private _cls = (_cfg get "tankClasses") select {isClass (configFile >> "CfgVehicles" >> _x)};
		if (_cls isEqualTo []) exitWith { objNull };
		private _tank = createVehicle [_cls select 0, _pos, [], 0, "NONE"];
		_tank setDir _dir;
		_tank setPosATL [_pos select 0, _pos select 1, 0];
		createVehicleCrew _tank;
		private _crewGrp = group (driver _tank);
		{ _x setSkill (_cfg get "tankSkill"); _x setVariable ["lambs_danger_disableAI", true, true]; } forEach (crew _tank);
		_crewGrp setVariable ["lambs_danger_disableGroupAI", true, true];
		DMS_tank = _tank;
		DMS_tankGroup = _crewGrp;
		publicVariable "DMS_tank";

		if (!DMS_testMode && {!isNull DMS_player}) then {
			// keep the driver and gunner, the player takes the commander's seat
			private _keep = [driver _tank, gunner _tank];
			{ if (!(_x in _keep)) then { _tank deleteVehicleCrew _x; }; } forEach (crew _tank);
			private _pg = group DMS_player;
			_keep joinSilent _pg;
			[_pg, DMS_player] remoteExecCall ["selectLeader", groupOwner _pg];
			[DMS_player, configFile >> "CfgVehicles" >> (_cfg get "playerLoadoutClass")] remoteExecCall ["setUnitLoadout", DMS_player];
			[DMS_player, [_tank, _cfg get "tankCommanderTurret"]] remoteExecCall ["moveInTurret", DMS_player];
			DMS_tankGroup = _pg;
			if (!isNull _crewGrp && {(units _crewGrp) isEqualTo []}) then { deleteGroup _crewGrp; };
		};
		_tank addEventHandler ["Killed", {
			params ["_unit", "_killer"];
			[format ["Tank destroyed by %1 (%2)", typeOf _killer, typeOf (vehicle _killer)], "WARN"] call DMS_fnc_log;
		}];
		[format ["Tank %1 at %2 dir %3, crew %4", typeOf _tank, _pos apply {round _x}, round _dir, (fullCrew _tank) apply {[typeOf (_x select 0), _x select 1]}]] call DMS_fnc_log;
		_tank
	};

	case "MONITOR": {
		private _immobileSince = -1;
		private _hinted = false;
		waitUntil {
			sleep 2;
			if (!DMS_over && {alive DMS_tank} && {!canMove DMS_tank}) then {
				if (_immobileSince < 0) then {
					_immobileSince = time;
					[format ["Tank immobilised at %1 (damage %2)", (getPosATL DMS_tank) apply {round _x}, (round ((damage DMS_tank) * 100)) / 100], "WARN"] call DMS_fnc_log;
				};
				if (!_hinted && {time - _immobileSince > (_cfg get "immobileHintDelay")}) then {
					_hinted = true;
					if (!isNull DMS_player) then { "Tank immobilised. Keep fighting from the hull, or bail out and fall back to the Bradleys." remoteExecCall ["hintSilent", DMS_player]; };
				};
			} else {
				if (_immobileSince >= 0 && {alive DMS_tank}) then { ["Tank mobile again"] call DMS_fnc_log; };
				_immobileSince = -1;
			};
			DMS_over || {!alive DMS_tank} || {!isNull DMS_player && {!alive DMS_player}}
				|| {_immobileSince >= 0 && {time - _immobileSince > ([_cfg get "immobileTimeout", 120] call DMS_fnc_t)}}
		};
		if (DMS_over) exitWith {};
		if (!isNull DMS_player && {!alive DMS_player}) exitWith { ["DMS_FailDead", false, "player killed"] call DMS_fnc_end; };
		if (!alive DMS_tank) exitWith { ["DMS_FailTank", false, "tank destroyed"] call DMS_fnc_end; };
		["DMS_Draw", false, format ["tank immobilised for %1 s", round (time - _immobileSince)], "DRAW"] call DMS_fnc_end;
	};
	default {};
};
