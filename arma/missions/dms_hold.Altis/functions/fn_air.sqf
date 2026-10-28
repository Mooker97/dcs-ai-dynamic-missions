/*
	DMS_fnc_air - one AH-64D attack run on a marked position (server only).
	["INIT"] call DMS_fnc_air;                        one sortie available, give the menu item to the player
	["REQUEST", [_caller, _pos]] call DMS_fnc_air;    from the comm menu (remoteExecCall to the server)
	["RUN", [_caller, _pos]] spawn DMS_fnc_air;       internal: tasking delay, transit, time on station, RTB
	Realism: tasking/launch delay plus a real flight in from the rear, refuses danger close, the crew only
	gets the targets the ground team can talk them onto (enemies near the mark), a fixed time on station,
	and it can be shot down. A refused request does not use the sortie.
*/
params [["_mode", "", [""]], ["_args", [], [[]]]];
private _cfg = DMS_cfg;

switch (_mode) do {
	case "INIT": {
		DMS_airLeft = 1;
		DMS_airBusy = false;
		DMS_airHeli = objNull;
		DMS_airOnStation = false;
		["MENU", [DMS_player, "DMS_AirSupport"]] call DMS_fnc_support;
		["Air: one AH-64D sortie available"] call DMS_fnc_log;
	};

	case "REQUEST": {
		_args params [["_caller", objNull], ["_pos", [0, 0, 0]]];
		if (DMS_over) exitWith {};
		private _tell = {
			params ["_text"];
			if (isPlayer _caller) then { _text remoteExecCall ["hintSilent", _caller]; };
			[_text] call DMS_fnc_log;
		};
		if (DMS_airLeft <= 0) exitWith { ["Air: no sorties left."] call _tell; };
		if (DMS_airBusy) exitWith { ["Air: already tasked."] call _tell; };
		_pos = [_pos select 0, _pos select 1, 0];
		private _dc = _cfg get "airDangerClose";
		private _friendly = allUnits findIf {alive _x && {side (group _x) == west} && {!(_x in (crew DMS_airHeli))} && {_x distance2D _pos < _dc}};
		if (_friendly > -1) exitWith {
			[format ["Air: DANGER CLOSE, friendlies within %1 m of %2. Request denied, mark a target further out.", _dc, mapGridPosition _pos]] call _tell;
			["MENU", [_caller, "DMS_AirSupport"]] call DMS_fnc_support;
		};
		DMS_airLeft = DMS_airLeft - 1;
		DMS_airBusy = true;
		private _eta = ([_cfg get "airProcessTime", 10] call DMS_fnc_t) + ((_cfg get "airSpawnDistance") / 60);
		[format ["Air: AH-64D tasked to grid %1, %2 m from the OP. Expect it in about %3 min.",
			mapGridPosition _pos, round (_pos distance2D DMS_opCenter), ceil (_eta / 60)]] call _tell;
		if (DMS_testMode) then { ["CHECK", ["air_requested", true, mapGridPosition _pos]] call DMS_fnc_testMode; };
		["RUN", [_caller, _pos]] spawn DMS_fnc_air;
	};

	case "RUN": {
		_args params [["_caller", objNull], ["_pos", [0, 0, 0]]];
		private _tell = {
			params ["_text"];
			if (isPlayer _caller) then { _text remoteExecCall ["hintSilent", _caller]; };
			[_text] call DMS_fnc_log;
		};
		sleep ([_cfg get "airProcessTime", 10] call DMS_fnc_t);
		if (DMS_over) exitWith {};
		private _list = _cfg get "airClasses";
		private _idx = _list findIf {isClass (configFile >> "CfgVehicles" >> _x)};
		if (_idx < 0) exitWith { ["Air: no helicopter class exists, sortie cancelled.", "WARN"] call DMS_fnc_log; DMS_airBusy = false; };

		private _home = DMS_opCenter getPos [_cfg get "airSpawnDistance", DMS_rearBearing];
		private _heli = createVehicle [_list select _idx, [_home select 0, _home select 1, 150], [], 0, "FLY"];
		_heli setDir (_home getDir _pos);
		_heli setPosATL [_home select 0, _home select 1, 150];
		createVehicleCrew _heli;
		private _grp = group (driver _heli);
		_grp setBehaviour "AWARE";
		_grp setCombatMode "YELLOW";
		_heli flyInHeight (_cfg get "airFlyHeight");
		_heli setVelocityModelSpace [0, 50, 0];
		DMS_airHeli = _heli;
		_heli addEventHandler ["Killed", {
			params ["_unit", "_killer"];
			[format ["Air: AH-64D shot down by %1", typeOf _killer]] call DMS_fnc_log;
		}];
		[format ["Air: %1 airborne %2 m out, crew %3", typeOf _heli, round (_heli distance2D _pos), count (crew _heli)]] call DMS_fnc_log;
		// Lost = destroyed, pilot dead or badly damaged (not canMove: unreliable for helicopters).
		private _lost = { !alive _heli || {!alive (driver _heli)} || {damage _heli > 0.7} };

		// Transit (AI flight time is real, never scaled).
		_grp move _pos;
		private _t = time;
		waitUntil { sleep 2; DMS_over || {call _lost} || {_heli distance2D _pos < 1500} || {time - _t > (_cfg get "airTransitTimeout")} };
		if (DMS_over) exitWith {};
		if (call _lost) exitWith { ["Air: the AH-64D was lost on the way in."] call _tell; DMS_airBusy = false; };

		// The JTAC talks the crew onto what is near the mark.
		private _r = _cfg get "airSearchRadius";
		private _reveal = {
			private _n = 0;
			{
				if (alive _x && {side (group _x) == east} && {_x distance2D _pos < _r}) then { _grp reveal [vehicle _x, 4]; _n = _n + 1; };
			} forEach allUnits;
			_n
		};
		private _seen = call _reveal;
		for "_i" from (count (waypoints _grp) - 1) to 0 step -1 do { deleteWaypoint [_grp, _i]; };
		private _wp = _grp addWaypoint [_pos, 0];
		_wp setWaypointType "SAD";
		_wp setWaypointBehaviour "COMBAT";
		_wp setWaypointCombatMode "RED";
		_grp setCurrentWaypoint _wp;
		[format ["Air: AH-64D inbound to the mark, %1 targets passed to the crew.", _seen]] call _tell;

		waitUntil { sleep 2; DMS_over || {call _lost} || {_heli distance2D _pos < 800} || {time - _t > (_cfg get "airTransitTimeout") + 120} };
		if (DMS_over) exitWith {};
		if (call _lost) exitWith { ["Air: the AH-64D was lost before reaching the target area."] call _tell; DMS_airBusy = false; };
		DMS_airOnStation = true;
		["Air: AH-64D on station, engaging."] call _tell;
		if (DMS_testMode) then { ["CHECK", ["air_on_station", true, format ["%1 m from the mark, %2 targets", round (_heli distance2D _pos), _seen]]] call DMS_fnc_testMode; };

		private _on = [_cfg get "airOnStation", 90] call DMS_fnc_t;
		private _tOn = time;
		while {!DMS_over && {!(call _lost)} && {time - _tOn < _on}} do {
			sleep 10;
			call _reveal;
		};
		DMS_airOnStation = false;
		if (DMS_over) exitWith {};
		if (call _lost) exitWith { ["Air: the AH-64D was lost on station."] call _tell; DMS_airBusy = false; };

		// RTB
		["Air: AH-64D off station, returning to base. No more air support."] call _tell;
		for "_i" from (count (waypoints _grp) - 1) to 0 step -1 do { deleteWaypoint [_grp, _i]; };
		_grp setBehaviour "CARELESS";
		_grp setCombatMode "BLUE";
		_grp move _home;
		private _tr = time;
		waitUntil { sleep 5; DMS_over || {!alive _heli} || {_heli distance2D _pos > 3000} || {time - _tr > 300} };
		DMS_airBusy = false;
		if (alive _heli) then {
			{ deleteVehicle _x; } forEach (crew _heli);
			deleteVehicle _heli;
			["Air: AH-64D gone"] call DMS_fnc_log;
		};
	};
	default {};
};
