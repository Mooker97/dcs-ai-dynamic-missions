/*
	DMS_fnc_strike - target reports and the virtual 155 mm battery that answers them (server only).
	["INIT"] call DMS_fnc_strike;                          counters, comm-menu items for the player
	["MENU", [_unit, _item]] call DMS_fnc_strike;          (re)add a CfgCommunicationMenu item on the unit's machine
	["REPORT", [_caller, _pos, "LASER"|"CURSOR"|"TEST"]]  sent by the comm menu (remoteExecCall to the server)
	The rounds fall where the REPORT says, not where the battery really is: a bad report misses.
	Realism: processing delay + time of flight, Rayleigh dispersion from a CEP, danger-close refusal,
	limited fire missions. Every landed strike alerts the enemy.
*/
params [["_mode", "", [""]], ["_args", [], [[]]]];
private _cfg = DMS_cfg;

switch (_mode) do {
	case "INIT": {
		DMS_strikesLeft = _cfg get "strikeMissions";
		DMS_strikeBusy = false;
		DMS_strikesLanded = 0;
		DMS_strikeImpacts = [];
		DMS_strikeShells = 0;
		["MENU", [DMS_player, "DMS_ReportLaser"]] call DMS_fnc_strike;
		["MENU", [DMS_player, "DMS_ReportCursor"]] call DMS_fnc_strike;
	};

	case "MENU": {
		_args params [["_unit", objNull], ["_item", ""]];
		if (isNull _unit || {!isPlayer _unit}) exitWith {};
		[_unit, _item] remoteExecCall ["BIS_fnc_addCommMenuItem", _unit];
	};

	case "REPORT": {
		_args params [["_caller", objNull], ["_pos", [], [[]]], ["_kind", "CURSOR", [""]]];
		private _item = ["DMS_ReportCursor", "DMS_ReportLaser"] select (_kind == "LASER");
		private _tell = {
			params ["_text"];
			if (isPlayer _caller) then { _text remoteExecCall ["hintSilent", _caller]; };
			[_text] call DMS_fnc_log;
		};
		if (DMS_over) exitWith {};
		// The comm-menu cursor gives [0, 0, 0] when it points at nothing (sky); treat that as no position.
		if (_pos isNotEqualTo [] && {((_pos select 0) == 0) && {(_pos select 1) == 0}}) then { _pos = []; };
		if (_pos isEqualTo []) exitWith {
			[["Fire mission: no target position. Point at the ground or click the map and report again.",
				"Fire mission: no laser spot. Lase the target (designator on, fire) and report again."] select (_kind == "LASER")] call _tell;
			["MENU", [_caller, _item]] call DMS_fnc_strike;
		};
		if (DMS_strikesLeft <= 0) exitWith { ["Fire mission: the battery has no missions left for you."] call _tell; };
		if (DMS_strikeBusy) exitWith {
			["Fire mission: battery busy with the previous mission. Report again shortly."] call _tell;
			["MENU", [_caller, _item]] call DMS_fnc_strike;
		};
		_pos = [_pos select 0, _pos select 1, 0];
		private _dc = _cfg get "strikeDangerClose";
		if (((units DMS_team) findIf {alive _x && {_x distance2D _pos < _dc}}) > -1) exitWith {
			[format ["Fire mission: DANGER CLOSE, your team is within %1 m of grid %2. Mission denied, pull back and report again.", _dc, mapGridPosition _pos]] call _tell;
			["MENU", [_caller, _item]] call DMS_fnc_strike;
		};

		DMS_strikesLeft = DMS_strikesLeft - 1;
		DMS_strikeBusy = true;
		private _n = (_cfg get "strikeMissions") - DMS_strikesLeft;
		private _miss = round (_pos distance2D DMS_siteCenter);
		private _nearTube = round (selectMin (DMS_tubes apply {_x distance2D _pos}));
		[format ["Report %1 #%2 by %3: grid %4, %5 m from the battery centre, %6 m from the nearest tube, observer %7 m away",
			_kind, _n, [name _caller, "script"] select (isNull _caller), mapGridPosition _pos, _miss, _nearTube,
			[round (_caller distance2D _pos), -1] select (isNull _caller)]] call DMS_fnc_log;
		private _eta = [(["RANGE", _cfg get "strikeProcessTime"] call DMS_fnc_rng) + (_cfg get "strikeTimeOfFlight")] call DMS_fnc_t;
		[format ["Fire mission at grid %1 received. %2 rounds HE, splash in about %3 s.", mapGridPosition _pos, _cfg get "strikeRounds", round _eta]] call _tell;

		[_caller, _pos, _item, _eta, _n] spawn {
			params ["_caller", "_pos", "_item", "_eta", "_n"];
			private _cfg = DMS_cfg;
			sleep _eta;
			if (DMS_over) exitWith { DMS_strikeBusy = false; };
			private _wasOut = DMS_siteNeutralized;
			if (isPlayer _caller) then { "Splash." remoteExecCall ["hintSilent", _caller]; };
			private _rounds = _cfg get "strikeRounds";
			private _sigma = (_cfg get "strikeCEP") / 1.1774;
			private _imp0 = count DMS_strikeImpacts;
			for "_r" from 1 to _rounds do {
				private _u = ["RANGE", [0.0001, 0.9999]] call DMS_fnc_rng;
				private _dist = _sigma * sqrt (-2 * ln _u);
				private _impact = _pos getPos [_dist, ["RANGE", [0, 360]] call DMS_fnc_rng];
				private _shell = createVehicle [_cfg get "strikeAmmo", [_impact select 0, _impact select 1, 300], [], 0, "CAN_COLLIDE"];
				_shell setPosATL [_impact select 0, _impact select 1, 300];
				_shell setVectorDirAndUp [[0, 0, -1], [0, 1, 0]];
				_shell setVelocity [0, 0, -200];
				// Track where the round actually goes off (the shell object is deleted on detonation).
				[_shell] spawn {
					params ["_shell"];
					private _last = getPosATL _shell;
					private _t = time;
					waitUntil {
						if (!isNull _shell) then { _last = getPosATL _shell; };
						isNull _shell || {time - _t > 30}
					};
					if (isNull _shell) then { DMS_strikeImpacts pushBack _last; };
				};
				DMS_strikeShells = DMS_strikeShells + 1;
				[format ["Strike %1 round %2/%3 aimed %4 m from the reported point", _n, _r, _rounds, round _dist], "DEBUG"] call DMS_fnc_log;
				sleep ([["RANGE", _cfg get "strikeInterval"] call DMS_fnc_rng, 1] call DMS_fnc_t);
			};
			// Let the last rounds land, then assess.
			private _tw = time;
			waitUntil { sleep 1; DMS_over || {(count DMS_strikeImpacts) - _imp0 >= _rounds} || {time - _tw > 20} };
			private _hits = DMS_strikeImpacts select [_imp0, _rounds];
			private _mean = -1;
			if (_hits isNotEqualTo []) then {
				private _sx = 0;
				private _sy = 0;
				{ _sx = _sx + (_x select 0); _sy = _sy + (_x select 1); } forEach _hits;
				_mean = round ([_sx / (count _hits), _sy / (count _hits), 0] distance2D DMS_siteCenter);
			};
			private _out = ["STATUS"] call DMS_fnc_site;
			DMS_strikesLanded = DMS_strikesLanded + 1;
			DMS_strikeBusy = false;
			[format ["Strike %1 complete: %2/%3 detonations, mean impact %4 m from the battery, tubes out %5/%6",
				_n, count _hits, _rounds, _mean, _out, count DMS_tubes]] call DMS_fnc_log;
			if (DMS_testMode) then {
				["CHECK", ["strike", (count _hits) >= 1, format ["%1/%2 detonations, mean %3 m from the battery", count _hits, _rounds, _mean]]] call DMS_fnc_testMode;
			};
			private _text = format ["Rounds complete. Fire missions left: %1.", DMS_strikesLeft];
			if (isPlayer _caller) then { _text remoteExecCall ["hintSilent", _caller]; };
			[_text] call DMS_fnc_log;
			// The battery and its guard know they were targeted.
			if (_mean >= 0 && {_mean < 400}) then { ["ALARM", ["strike"]] call DMS_fnc_alarm; };
			// A re-attack on a battery that was already out confirms it without an observer.
			if (_wasOut && {_mean >= 0} && {_mean < (_cfg get "strikeReattackRadius")}) then { DMS_bdaByStrike = true; };
			if (DMS_strikesLeft > 0) then {
				["MENU", [_caller, _item]] call DMS_fnc_strike;
			} else {
				sleep ([30, 10] call DMS_fnc_t);
				["STATUS"] call DMS_fnc_site;
				["CHECK"] call DMS_fnc_bda;
				if (!DMS_over && {!DMS_siteNeutralized}) then {
					["DMS_FailAmmo", false, "no fire missions left and the battery is still active"] call DMS_fnc_end;
				};
			};
		};
	};
	default {};
};
