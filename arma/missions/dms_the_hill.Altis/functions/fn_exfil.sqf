/*
	DMS_fnc_exfil - extraction Ghost Hawk (server only).
	["REQUEST", [_caller]] call DMS_fnc_exfil;   from the comm menu; needs the intel
	["RUN", [_caller]] spawn DMS_fnc_exfil;      internal: one extraction attempt
	The heli approaches from the safe side (the squad's start bearing), holds off while the LZ is hot
	(known enemies near it) for a bounded time, lands, waits a limited time, then lifts off when the
	player and every living squad member nearby are aboard. If the window runs out with the player
	aboard it lifts off with whoever is in; otherwise it unloads, leaves and can be requested again.
	A disabled heli (cannot move, pilot dead) fails the mission like a destroyed one.
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
		// Only enemies the friendly side knows about make the LZ hot (the pilot can't see the rest).
		// Infantry counts within exfilHotRadius; any armed vehicle within exfilHotVehicleRadius.
		private _hot = {
			(({alive _x && {side (group _x) == east} && {_x distance2D DMS_lz < (DMS_cfg get "exfilHotRadius")}
				&& {(west knowsAbout _x) >= 1}} count allUnits) >= (DMS_cfg get "exfilHotCount"))
			|| {(vehicles findIf {alive _x && {canFire _x} && {side (effectiveCommander _x) == east}
				&& {_x distance2D DMS_lz < (DMS_cfg get "exfilHotVehicleRadius")} && {(west knowsAbout _x) >= 1}}) != -1}
		};
		// Like a real pickup, the heli only comes in once the ground team is at the LZ.
		private _ready = {
			(isNull DMS_player && {((units DMS_squad) findIf {alive _x && {_x distance2D DMS_lz < (DMS_cfg get "exfilReadyRadius")}}) != -1})
			|| {!isNull DMS_player && {alive DMS_player} && {DMS_player distance2D DMS_lz < (DMS_cfg get "exfilReadyRadius")}}
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
		// Disabled = pilot dead, hull nearly gone, or main rotor/engine destroyed. Not canMove: it
		// reported false for a healthy Ghost Hawk on touchdown and lift-off (test batch 2026-10-28).
		private _disabledWhy = {
			params ["_h"];
			if (!alive (driver _h)) exitWith { "pilot dead" };
			if (damage _h > 0.8) exitWith { format ["damage %1", (round ((damage _h) * 100)) / 100] };
			if ((_h getHitPointDamage "HitHRotor") >= 0.9) exitWith { "main rotor destroyed" };
			if ((_h getHitPointDamage "HitEngine") >= 0.9) exitWith { "engine destroyed" };
			""
		};
		private _lost = { !alive _heli || {([_heli] call _disabledWhy) != ""} };
		// A heli that is shot up but not destroyed would otherwise hang the extraction forever.
		[_heli, _disabledWhy] spawn {
			params ["_h", "_disabledWhy"];
			private _why = "";
			waitUntil {
				sleep 2;
				if (alive _h) then { _why = [_h] call _disabledWhy; };
				DMS_over || {!alive _h} || {_why != ""} || {DMS_exfilHeli != _h}
			};
			if (!DMS_over && {DMS_exfilHeli == _h} && {alive _h}) then {
				["DMS_FailHeli", false, format ["extraction helicopter disabled (%1)", _why]] call DMS_fnc_end;
			};
		};

		// 1. holding point, wait (bounded) for a cold LZ
		_grp move _hold;
		private _t = time;
		waitUntil { sleep 2; (call _lost) || {DMS_over} || {_heli distance2D _hold < 400} || {time - _t > 300} };
		private _warned = false;
		private _abort = false;
		private _hotSince = time;
		private _waitedMsg = false;
		private _readySince = time;
		while {!_abort && {!(call _lost)} && {!DMS_over} && {(call _hot) || {!(call _ready)}}} do {
			if (call _hot) then {
				if (!_warned) then {
					_warned = true;
					_hotSince = time;
					DMS_exfilHoldSince = time;
					["Extraction: LZ is hot, holding off until it is clear."] call _tell;
				};
				if ((time - _hotSince) > ([_cfg get "exfilHotMaxHold", 120] call DMS_fnc_t)) then {
					_abort = true;
					["Extraction: LZ still hot, Ghost Hawk returning to base. Request again when the LZ is clear."] call _tell;
				};
			} else {
				_warned = false;
				DMS_exfilHoldSince = -1;
				if (!_waitedMsg) then { _waitedMsg = true; ["Extraction: holding off, call us in when you are at the LZ."] call _tell; };
				if ((time - _readySince) > ([_cfg get "exfilReadyMaxWait", 300] call DMS_fnc_t)) then {
					_abort = true;
					["Extraction: nobody at the LZ, Ghost Hawk returning to base. Request again from the LZ."] call _tell;
				};
			};
			if (!_abort) then { sleep ([15, 3] call DMS_fnc_t); };
		};
		DMS_exfilHoldSince = -1;

		// 2. approach and land
		private _landed = false;
		if (!(call _lost) && {!DMS_over} && {!_abort}) then {
			_grp move _lz;
			_t = time;
			waitUntil { sleep 1; (call _lost) || {DMS_over} || {_heli distance2D _lz < 250} || {time - _t > 300} };
			_heli land "GET IN";
			private _down = { isTouchingGround _heli || {((getPosATL _heli) select 2) < 1.5 && {speed _heli < 3}} };
			_t = time;
			waitUntil { sleep 1; (call _lost) || {DMS_over} || {call _down} || {time - _t > 120} };
			_landed = !(call _lost) && {call _down};
		};

		// 3. boarding window
		private _boarded = false;
		if (_landed && {!DMS_over}) then {
			DMS_exfilLanded = true;
			if (DMS_testMode) then { ["CHECK", ["exfil_landed", true]] call DMS_fnc_testMode; };
			private _wait = round ([_cfg get "exfilWaitOnGround", 120] call DMS_fnc_t);
			[format ["Extraction: on the ground. Board now, departing in %1 s.", _wait]] call _tell;
			private _tOn = time;
			private _lastOrder = -100;
			while {!(call _lost) && {!DMS_over} && {!_boarded} && {(time - _tOn) < _wait}} do {
				private _need = (units DMS_squad) select {alive _x && {_x distance2D _heli < (_cfg get "exfilBoardRadius")}};
				if ((time - _lastOrder) > ([30, 15] call DMS_fnc_t)) then {
					_lastOrder = time;
					{
						if (!isPlayer _x && {vehicle _x != _heli}) then {
							[_x, _heli] remoteExecCall ["assignAsCargo", _x];
							[[_x], true] remoteExecCall ["orderGetIn", _x];
						};
					} forEach _need;
				};
				if ((time - _tOn) > ([60, 30] call DMS_fnc_t)) then {
					{
						if (!isPlayer _x && {vehicle _x != _heli} && {_x distance2D _heli < 75}) then {
							[_x, _heli] remoteExecCall ["moveInCargo", _x];
						};
					} forEach _need;
				};
				private _playerOk = isNull DMS_player || {vehicle DMS_player == _heli};
				_boarded = _playerOk && {_need isNotEqualTo []} && {_need findIf {vehicle _x != _heli} == -1};
				if (!_boarded) then { sleep 2; };
			};
			// Window over: with the player aboard, leave with whoever made it; otherwise unload the squad.
			if (!_boarded && {!(call _lost)} && {!DMS_over}) then {
				private _aboard = (units DMS_squad) select {alive _x && {vehicle _x == _heli}};
				private _pOk = isNull DMS_player || {vehicle DMS_player == _heli};
				if (_pOk && {_aboard isNotEqualTo []}) then {
					_boarded = true;
					private _left = ({alive _x} count (units DMS_squad)) - count _aboard;
					[format ["Extraction: lifting off, %1 left behind.", _left]] call _tell;
				} else {
					{
						if (_x in (units DMS_squad)) then {
							[_x] remoteExecCall ["unassignVehicle", _x];
							[_x] remoteExecCall ["moveOut", _x];
						};
					} forEach (crew _heli);
					sleep 3;
				};
			};
		};

		if ((call _lost) || {DMS_over}) exitWith {};

		if (_boarded) then {
			DMS_exfilBoarded = true;
			if (DMS_testMode) then { ["CHECK", ["exfil_boarded", true]] call DMS_fnc_testMode; };
			["Extraction: squad aboard, lifting off."] call DMS_fnc_log;
			_heli land "NONE";
			_heli flyInHeight 100;
			_grp move (_lz getPos [6000, _brg]);
			waitUntil { sleep 2; (call _lost) || {DMS_over} || {_heli distance2D _lz > (_cfg get "exfilDepartDistance")} };
			if (!(call _lost) && {!DMS_over}) then {
				["DMS_t_exfil", "SUCCEEDED"] call BIS_fnc_taskSetState;
				["DMS_Win", true, "extracted"] call DMS_fnc_end;
			};
		} else {
			if (!_abort) then { ["Extraction: cannot wait any longer, departing. Request again when ready."] call _tell; };
			_heli removeEventHandler ["Killed", _ehKilled];
			DMS_exfilHeli = objNull; // stops the disabled-heli monitor
			_heli land "NONE";
			_grp move _spawn;
			DMS_exfilActive = false;
			DMS_exfilLanded = false;
			["MENU", [_caller, "DMS_Extract"]] call DMS_fnc_support;
			_t = time;
			waitUntil { sleep 5; !alive _heli || {_heli distance2D _lz > 2500} || {time - _t > 600} };
			{ deleteVehicle _x } forEach ((crew _heli) select {group _x == _grp});
			deleteVehicle _heli;
		};
	};
	default {};
};
