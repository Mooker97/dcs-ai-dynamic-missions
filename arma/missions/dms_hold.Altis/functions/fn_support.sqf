/*
	DMS_fnc_support - virtual 81 mm M252 mortar section plus the comm-menu helper (server only).
	["INIT"] call DMS_fnc_support;                        set counters, give the menu items to the player
	["MENU", [_unit, _item]] call DMS_fnc_support;        (re)add a CfgCommunicationMenu item on the unit's machine
	["REQUEST", [_caller, _pos, "FFE" | "SPOT"]]           sent by the comm menu (remoteExecCall to the server)
	Realism: processing delay + time of flight, Rayleigh dispersion from a CEP, adjust-fire (a fire for
	effect within artyAdjustWindow of a recent spotting round uses the tighter CEP), danger-close refusal.
*/
params [["_mode", "", [""]], ["_args", [], [[]]]];
private _cfg = DMS_cfg;

switch (_mode) do {
	case "INIT": {
		DMS_artyMissions = _cfg get "artyMissions";
		DMS_artySpots = _cfg get "artySpotRounds";
		DMS_artyBusy = false;
		DMS_artyLastSpot = [];
		DMS_artyShellsFired = 0;
		DMS_artyImpacts = [];
		DMS_artyRefused = 0;
		["MENU", [DMS_player, "DMS_ArtyFire"]] call DMS_fnc_support;
		["MENU", [DMS_player, "DMS_ArtySpot"]] call DMS_fnc_support;
		["Mortars: section ready"] call DMS_fnc_log;
	};

	case "MENU": {
		_args params [["_unit", objNull], ["_item", ""]];
		if (isNull _unit || {!isPlayer _unit}) exitWith {};
		[_unit, _item] remoteExecCall ["BIS_fnc_addCommMenuItem", _unit];
	};

	case "REQUEST": {
		_args params [["_caller", objNull], ["_pos", [0, 0, 0]], ["_kind", "FFE", [""]]];
		private _isSpot = _kind == "SPOT";
		private _item = ["DMS_ArtyFire", "DMS_ArtySpot"] select _isSpot;
		private _tell = {
			params ["_text"];
			if (isPlayer _caller) then { _text remoteExecCall ["hintSilent", _caller]; };
			[_text] call DMS_fnc_log;
		};
		private _left = [DMS_artyMissions, DMS_artySpots] select _isSpot;
		if (_left <= 0) exitWith { ["Mortars: none of those rounds left."] call _tell; };
		if (DMS_artyBusy) exitWith {
			["Mortars: busy with the previous mission. Request again shortly."] call _tell;
			["MENU", [_caller, _item]] call DMS_fnc_support;
		};
		_pos = [_pos select 0, _pos select 1, 0];
		private _dc = _cfg get "artyDangerClose";
		private _friendly = allUnits findIf {alive _x && {side (group _x) == west} && {_x distance2D _pos < _dc}};
		if (_friendly > -1) exitWith {
			[format ["Mortars: DANGER CLOSE, friendlies within %1 m of %2. Mission denied.", _dc, mapGridPosition _pos]] call _tell;
			DMS_artyRefused = DMS_artyRefused + 1;
			["MENU", [_caller, _item]] call DMS_fnc_support;
		};

		if (_isSpot) then { DMS_artySpots = DMS_artySpots - 1; } else { DMS_artyMissions = DMS_artyMissions - 1; };
		DMS_artyBusy = true;
		private _eta = [(_cfg get "artyProcessTime") + (_cfg get "artyTimeOfFlight")] call DMS_fnc_t;
		[format ["Mortars: %1 at grid %2 received. Splash in about %3 s.",
			["fire for effect", "spotting round"] select _isSpot, mapGridPosition _pos, round _eta]] call _tell;

		[_caller, _pos, _isSpot, _item, _eta] spawn {
			params ["_caller", "_pos", "_isSpot", "_item", "_eta"];
			private _cfg = DMS_cfg;
			sleep _eta;
			private _rounds = [_cfg get "artyRoundsFFE", 1] select _isSpot;
			private _cep = _cfg get "artyCEP";
			if (!_isSpot && {DMS_artyLastSpot isNotEqualTo []}
				&& {((DMS_artyLastSpot select 0) distance2D _pos) < (_cfg get "artyAdjustWindow")}
				&& {(time - (DMS_artyLastSpot select 1)) < ([600] call DMS_fnc_t)}) then {
				_cep = _cfg get "artyAdjustedCEP";
			};
			private _sigma = _cep / 1.1774;
			for "_r" from 1 to _rounds do {
				private _u = ["RANGE", [0.0001, 0.9999]] call DMS_fnc_rng;
				private _dist = _sigma * sqrt (-2 * ln _u);
				private _brg = ["RANGE", [0, 360]] call DMS_fnc_rng;
				private _impact = _pos getPos [_dist, _brg];
				private _shell = createVehicle [_cfg get "artyAmmo", [_impact select 0, _impact select 1, 250], [], 0, "CAN_COLLIDE"];
				_shell setPosATL [_impact select 0, _impact select 1, 250];
				_shell setVectorDirAndUp [[0, 0, -1], [0, 1, 0]];
				_shell setVelocity [0, 0, -150];
				// Track where the round actually goes off (the shell object is deleted on detonation).
				[_shell, _pos] spawn {
					params ["_shell", "_aim"];
					private _last = getPosATL _shell;
					private _t = time;
					waitUntil {
						if (!isNull _shell) then { _last = getPosATL _shell; };
						isNull _shell || {time - _t > 30}
					};
					if (isNull _shell) then {
						DMS_artyImpacts pushBack [_last, _last distance2D _aim];
						[format ["Mortar round detonated %1 m from the target, %2 m AGL", round (_last distance2D _aim), round (_last select 2)], "DEBUG"] call DMS_fnc_log;
					};
				};
				if (_isSpot) then { DMS_artyLastSpot = [_impact, time]; };
				DMS_artyShellsFired = DMS_artyShellsFired + 1;
				[format ["Mortar round %1/%2 aimed %3 m from target (CEP %4)", _r, _rounds, round _dist, _cep], "DEBUG"] call DMS_fnc_log;
				sleep ([["RANGE", _cfg get "artyInterval"] call DMS_fnc_rng, 1] call DMS_fnc_t);
			};
			DMS_artyBusy = false;
			private _text = format ["Mortars: rounds complete. Fire missions left: %1. Spotting rounds left: %2.", DMS_artyMissions, DMS_artySpots];
			if (isPlayer _caller) then { _text remoteExecCall ["hintSilent", _caller]; };
			[_text] call DMS_fnc_log;
			if (([DMS_artyMissions, DMS_artySpots] select _isSpot) > 0) then { ["MENU", [_caller, _item]] call DMS_fnc_support; };
		};
	};
	default {};
};
