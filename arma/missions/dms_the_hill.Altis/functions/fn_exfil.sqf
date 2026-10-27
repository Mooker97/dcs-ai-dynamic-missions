/*
	DMS_fnc_exfil - extraction Ghost Hawk (server only).
	["REQUEST", [_caller]] call DMS_fnc_exfil;   from the comm menu; needs the intel
	["RUN", [_caller]] spawn DMS_fnc_exfil;      internal: one extraction attempt
	The heli approaches from the safe side (the squad's start bearing), holds off while the LZ is hot,
	lands, waits a limited time, then lifts off when the player and every living squad member nearby
	are aboard. If nobody boards in time it leaves and can be requested again.
*/
params [["_mode", "", [""]], ["_args", [], [[]]]];

switch (_mode) do {
	case "REQUEST": {
		_args params [["_caller", objNull]];
		if (DMS_over) exitWith {};
		private _tell = {
			params ["_text"];
			if (isPlayer _caller) then { _text remoteExecCall ["hintSilent", _caller]; };
			[_text] call DMS_fnc_log;
		};
		if (!DMS_intelTaken) exitWith {
			["Extraction: not authorised until the intel is secured."] call _tell;
			["MENU", [_caller, "DMS_Extract"]] call DMS_fnc_support;
		};
		if (DMS_exfilActive) exitWith { ["Extraction: already inbound."] call _tell; };
		DMS_exfilActive = true;
		if (DMS_testMode) then { ["CHECK", ["exfil_requested", true]] call DMS_fnc_testMode; };
		["Extraction: Ghost Hawk inbound to the marked LZ."] call _tell;
		["RUN", [_caller]] spawn DMS_fnc_exfil;
	};

	case "RUN": {
		_args params [["_caller", objNull]];
		private _cfg = DMS_cfg;
		private _lz = DMS_lz;
		private _brg = DMS_startBearing;
		private _tell = {
			params ["_text"];
			if (isPlayer _caller) then { _text remoteExecCall ["hintSilent", _caller]; };
			[_text] call DMS_fnc_log;
		};
		private _hot = {
			({alive _x && {side (group _x) == east} && {_x distance2D DMS_lz < (DMS_cfg get "exfilHotRadius")}} count allUnits)
				>= (DMS_cfg get "exfilHotCount")
		};

		private _spawn = _lz getPos [_cfg get "exfilSpawnDistance", _brg];
		private _hold = _lz getPos [_cfg get "exfilHoldDistance", _brg];
		private _heli = createVehicle [_cfg get "exfilHeliClass", [_spawn select 0, _spawn select 1, 150], [], 0, "FLY"];
		_heli setDir (_spawn getDir _lz);
		_heli setPosATL [_spawn select 0, _spawn select 1, 150];
		createVehicleCrew _heli;
		_heli lockDriver true;
		private _grp = group (driver _heli);
		_grp setBehaviour "CARELESS";
		_grp setCombatMode "BLUE";
		_heli flyInHeight (_cfg get "exfilFlyHeight");
		_heli setVelocityModelSpace [0, 50, 0];
		DMS_exfilHeli = _heli;
		private _ehKilled = _heli addEventHandler ["Killed", { ["DMS_FailHeli", false, "extraction helicopter destroyed"] call DMS_fnc_end; }];
		["Exfil heli spawned"] call DMS_fnc_log;

		// 1. holding point, wait for a cold LZ
		_grp move _hold;
		waitUntil { sleep 2; !alive _heli || {_heli distance2D _hold < 400} };
		private _warned = false;
		while {alive _heli && {!DMS_over} && {call _hot}} do {
			if (!_warned) then { _warned = true; ["Extraction: LZ is hot, holding off until it is clear."] call _tell; };
			sleep 15;
		};

		// 2. approach and land
		private _landed = false;
		if (alive _heli && {!DMS_over}) then {
			_grp move _lz;
			waitUntil { sleep 1; !alive _heli || {_heli distance2D _lz < 250} };
			_heli land "GET IN";
			private _tl = time;
			waitUntil { sleep 1; !alive _heli || {isTouchingGround _heli} || {time - _tl > 120} };
			_landed = alive _heli && {isTouchingGround _heli};
		};

		// 3. boarding window
		private _boarded = false;
		if (_landed && {!DMS_over}) then {
			DMS_exfilLanded = true;
			if (DMS_testMode) then { ["CHECK", ["exfil_landed", true]] call DMS_fnc_testMode; };
			private _wait = _cfg get "exfilWaitOnGround";
			[format ["Extraction: on the ground. Board now, departing in %1 s.", _wait]] call _tell;
			private _tOn = time;
			private _lastOrder = -100;
			while {alive _heli && {!DMS_over} && {!_boarded} && {(time - _tOn) < _wait}} do {
				private _need = (units DMS_squad) select {alive _x && {_x distance2D _heli < (_cfg get "exfilBoardRadius")}};
				if ((time - _lastOrder) > 30) then {
					_lastOrder = time;
					{
						if (!isPlayer _x && {vehicle _x != _heli}) then {
							[_x, _heli] remoteExecCall ["assignAsCargo", _x];
							[[_x], true] remoteExecCall ["orderGetIn", _x];
						};
					} forEach _need;
				};
				if ((time - _tOn) > 60) then {
					{
						if (!isPlayer _x && {vehicle _x != _heli} && {_x distance2D _heli < 30}) then {
							[_x, _heli] remoteExecCall ["moveInCargo", _x];
						};
					} forEach _need;
				};
				private _playerOk = isNull DMS_player || {vehicle DMS_player == _heli};
				_boarded = _playerOk && {_need isNotEqualTo []} && {_need findIf {vehicle _x != _heli} == -1};
				if (!_boarded) then { sleep 2; };
			};
		};

		if (!alive _heli || {DMS_over}) exitWith {};

		if (_boarded) then {
			DMS_exfilBoarded = true;
			if (DMS_testMode) then { ["CHECK", ["exfil_boarded", true]] call DMS_fnc_testMode; };
			["Extraction: squad aboard, lifting off."] call DMS_fnc_log;
			_heli land "NONE";
			_heli flyInHeight 100;
			_grp move (_lz getPos [6000, _brg]);
			waitUntil { sleep 2; !alive _heli || {DMS_over} || {_heli distance2D _lz > (_cfg get "exfilDepartDistance")} };
			if (alive _heli && {!DMS_over}) then {
				["DMS_t_exfil", "SUCCEEDED"] call BIS_fnc_taskSetState;
				["DMS_Win", true, "extracted"] call DMS_fnc_end;
			};
		} else {
			["Extraction: cannot wait any longer, departing. Request again when ready."] call _tell;
			_heli removeEventHandler ["Killed", _ehKilled];
			_heli land "NONE";
			_grp move _spawn;
			DMS_exfilActive = false;
			DMS_exfilLanded = false;
			["MENU", [_caller, "DMS_Extract"]] call DMS_fnc_support;
			waitUntil { sleep 5; !alive _heli || {_heli distance2D _lz > 2500} };
			{ deleteVehicle _x } forEach (crew _heli);
			deleteVehicle _heli;
		};
	};
	default {};
};
