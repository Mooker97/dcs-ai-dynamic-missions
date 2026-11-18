/*
	DMS_fnc_air - A-10A bomb runs (server only).
	["INIT"] call DMS_fnc_air;                       casUses strikes available, give the menu item to the player
	["MENU", [_unit, _item]] call DMS_fnc_air;       (re)add a CfgCommunicationMenu item on the unit's machine
	["REQUEST", [_caller, _pos]] call DMS_fnc_air;   from the comm menu (remoteExecCall to the server)
	["PREPLANNED"] spawn DMS_fnc_air;                the scripted strike on the village defences at the phase line
	["RUN", [_caller, _pos, _bombs, _cep, _tag, _process]] spawn DMS_fnc_air;   internal
	Reliability over AI behaviour: the jet flies a real pass from the friendly rear (for the visuals and the
	sound), but the bombs are spawned above the aim point with a seeded Rayleigh CEP when the jet is within
	casReleaseDistance (or when its transit times out), like the virtual mortars of the other DMS missions. The jet
	crew is captive so the AI air defence never decides whether the strike happens. Refused requests (danger
	close, busy) do not use a strike.
*/
params [["_mode", "", [""]], ["_args", [], [[]]]];
private _cfg = DMS_cfg;

switch (_mode) do {
	case "INIT": {
		DMS_casLeft = _cfg get "casUses";
		DMS_casBusy = false;
		DMS_casImpacts = [];
		DMS_casDropped = 0;
		["MENU", [DMS_player, "DMS_AirSupport"]] call DMS_fnc_air;
		[format ["Air: %1 A-10 strikes available", DMS_casLeft]] call DMS_fnc_log;
	};

	case "MENU": {
		_args params [["_unit", objNull], ["_item", ""]];
		if (isNull _unit || {!isPlayer _unit}) exitWith {};
		[_unit, _item] remoteExecCall ["BIS_fnc_addCommMenuItem", _unit];
	};

	case "REQUEST": {
		_args params [["_caller", objNull], ["_pos", [0, 0, 0]]];
		if (DMS_over) exitWith {};
		private _tell = {
			params ["_text"];
			if (isPlayer _caller) then { _text remoteExecCall ["hintSilent", _caller]; };
			[_text] call DMS_fnc_log;
		};
		if (DMS_casLeft <= 0) exitWith { ["CAS: no strikes left."] call _tell; };
		if (DMS_casBusy) exitWith {
			["CAS: aircraft already tasked. Request again after the drop."] call _tell;
			["MENU", [_caller, "DMS_AirSupport"]] call DMS_fnc_air;
		};
		_pos = [_pos select 0, _pos select 1, 0];
		private _dc = _cfg get "casDangerClose";
		private _friendly = allUnits findIf {alive _x && {side (group _x) == west} && {!captive _x} && {_x distance2D _pos < _dc}};
		if (_friendly > -1) exitWith {
			[format ["CAS: DANGER CLOSE, friendlies within %1 m of %2. Request denied.", _dc, mapGridPosition _pos]] call _tell;
			["MENU", [_caller, "DMS_AirSupport"]] call DMS_fnc_air;
		};
		DMS_casLeft = DMS_casLeft - 1;
		DMS_casBusy = true;
		private _proc = [_cfg get "casProcessTime", 10] call DMS_fnc_t;
		[format ["CAS: A-10 tasked, %1 x Mk82 on grid %2. Bombs in about %3 s.", _cfg get "casBombs", mapGridPosition _pos, round (_proc + 50)]] call _tell;
		["RUN", [_caller, _pos, _cfg get "casBombs", _cfg get "casCEP", "CAS", _proc]] spawn DMS_fnc_air;
	};

	case "PREPLANNED": {
		private _aim = (DMS_layout get "bmp") select 0;
		if (!isNull DMS_player) then { "Phase line crossed. Pre-planned strike inbound on the village defences." remoteExecCall ["hintSilent", DMS_player]; };
		[format ["Air: pre-planned strike on the village defences at grid %1", mapGridPosition _aim]] call DMS_fnc_log;
		["RUN", [DMS_player, _aim, _cfg get "ppBombs", _cfg get "ppCEP", "PP", [_cfg get "ppProcessTime", 5] call DMS_fnc_t]] call DMS_fnc_air;
	};

	case "RUN": {
		_args params ["_caller", "_pos", "_bombs", "_cep", "_tag", "_proc"];
		private _tell = {
			params ["_text"];
			if (!isNull _caller && {isPlayer _caller}) then { _text remoteExecCall ["hintSilent", _caller]; };
			[_text] call DMS_fnc_log;
		};
		sleep _proc;
		if (DMS_over) exitWith { if (_tag == "CAS") then { DMS_casBusy = false; }; };
		private _ammo = (_cfg get "casAmmo") select {isClass (configFile >> "CfgAmmo" >> _x)};
		if (_ammo isEqualTo []) exitWith { ["Air: no bomb ammo class exists, strike cancelled", "WARN"] call DMS_fnc_log; if (_tag == "CAS") then { DMS_casBusy = false; }; };
		private _rear = DMS_layout get "rear";
		private _home = _pos getPos [_cfg get "casSpawnDistance", _rear];
		private _hdg = _home getDir _pos;
		private _h = _cfg get "casFlyHeight";

		// the pass (visuals); a missing class or a lost jet still gets the scripted drop
		private _jet = objNull;
		private _jets = (_cfg get "casClasses") select {isClass (configFile >> "CfgVehicles" >> _x)};
		if (_jets isNotEqualTo []) then {
			_jet = createVehicle [_jets select 0, [_home select 0, _home select 1, _h], [], 0, "FLY"];
			_jet setDir _hdg;
			_jet setPosATL [_home select 0, _home select 1, _h];
			createVehicleCrew _jet;
			{ _x setCaptive true; } forEach (crew _jet);
			private _grp = group (driver _jet);
			_grp setBehaviour "CARELESS";
			_grp setCombatMode "BLUE";
			_jet flyInHeight _h;
			_jet setVelocityModelSpace [0, 120, 0];
			_grp move (_pos getPos [3000, _hdg]);
			[format ["Air: %1 airborne %2 m out at %3 m, run-in heading %4", typeOf _jet, round (_jet distance2D _pos), _h, round _hdg]] call DMS_fnc_log;
		} else {
			["Air: no jet class exists, bombs only", "WARN"] call DMS_fnc_log;
		};
		private _t = time;
		private _rel = _cfg get "casReleaseDistance";
		waitUntil { sleep 0.5; DMS_over || {isNull _jet} || {!alive _jet} || {(_jet distance2D _pos) < _rel} || {time - _t > (_cfg get "casTransitTimeout")} };
		if (DMS_over) exitWith { if (_tag == "CAS") then { DMS_casBusy = false; }; };
		private _how = if (isNull _jet) then { "no jet" } else { if (!alive _jet) then { "jet lost" } else { if ((_jet distance2D _pos) < _rel) then { "on the pass" } else { "transit timed out" } } };
		if (_how != "on the pass") then { [format ["Air: scripted drop without the pass (%1, jet %2 m out)", _how, [-1, round (_jet distance2D _pos)] select (alive _jet)], "WARN"] call DMS_fnc_log; };
		if (alive _jet) then { _hdg = _jet getDir _pos; };

		// the drop: each bomb falls from casDropHeight along the run-in heading onto a seeded impact point
		private _imp0 = count DMS_casImpacts;
		private _sigma = _cep / 1.1774;
		private _dh = _cfg get "casDropHeight";
		for "_b" from 1 to _bombs do {
			private _u = ["RANGE", [0.0001, 0.9999]] call DMS_fnc_rng;
			private _dist = _sigma * sqrt (-2 * ln _u);
			private _impact = _pos getPos [_dist, ["RANGE", [0, 360]] call DMS_fnc_rng];
			// fall time from _dh with 80 m/s down: _dh = 80 t + 4.9 t^2
			private _tf = ((sqrt (6400 + 19.6 * _dh)) - 80) / 9.8;
			private _from = _impact getPos [60 * _tf, _hdg + 180];
			private _bomb = createVehicle [_ammo select 0, [_from select 0, _from select 1, _dh], [], 0, "CAN_COLLIDE"];
			_bomb setPosATL [_from select 0, _from select 1, _dh];
			_bomb setVectorDirAndUp [[sin _hdg * 0.6, cos _hdg * 0.6, -0.8], [0, 0, 1]];
			_bomb setVelocity [60 * sin _hdg, 60 * cos _hdg, -80];
			DMS_casDropped = DMS_casDropped + 1;
			[_bomb, _pos] spawn {
				params ["_bomb", "_aim"];
				private _last = getPosATL _bomb;
				private _t = time;
				waitUntil {
					if (!isNull _bomb) then { _last = getPosATL _bomb; };
					isNull _bomb || {time - _t > 30}
				};
				if (isNull _bomb) then {
					DMS_casImpacts pushBack [_last, _last distance2D _aim];
					[format ["Bomb detonated %1 m from the aim point, %2 m AGL", round (_last distance2D _aim), round (_last select 2)], "DEBUG"] call DMS_fnc_log;
				} else {
					[format ["Bomb did not detonate within 30 s at %1", (getPosATL _bomb) apply {round _x}], "WARN"] call DMS_fnc_log;
				};
			};
			sleep 0.35;
		};
		[format ["%1: %2 bombs away on grid %3.", ["CAS", "Pre-planned strike"] select (_tag == "PP"), _bombs, mapGridPosition _pos]] call _tell;

		// the jet egresses and is removed out of sight
		if (alive _jet) then {
			[_jet] spawn {
				params ["_jet"];
				private _t = time;
				waitUntil { sleep 5; isNull _jet || {!alive _jet} || {(_jet distance2D (DMS_layout get "crossroads")) > 5000} || {time - _t > 180} };
				if (alive _jet) then { { deleteVehicle _x; } forEach (crew _jet); deleteVehicle _jet; };
			};
		};

		sleep 12;
		private _hits = DMS_casImpacts select [_imp0, 99];
		private _near = { (_x select 1) < 3 * _cep } count _hits;
		[format ["Air: %1 detonations, %2 within %3 m of the aim point", count _hits, _near, 3 * _cep]] call DMS_fnc_log;
		if (DMS_testMode) then {
			["CHECK", [["cas_strike", "preplanned_strike"] select (_tag == "PP"), (count _hits) >= 1 && {_near * 2 >= count _hits},
				format ["%1 bombs, %2 detonations, %3 within %4 m (%5)", _bombs, count _hits, _near, 3 * _cep, _how]]] call DMS_fnc_testMode;
		};
		if (_tag == "CAS") then {
			DMS_casBusy = false;
			if (DMS_casLeft > 0) then {
				["MENU", [_caller, "DMS_AirSupport"]] call DMS_fnc_air;
				[format ["CAS: aircraft available, %1 strike(s) left.", DMS_casLeft]] call _tell;
			};
		};
	};
	default {};
};
