/*
	DMS_fnc_enemy - the Russian defence (RHS AFRF, server only).
	["INIT"] call DMS_fnc_enemy;            treeline tanks (hull-down, no driving), ATGM team on a flank, dug-in BMP
	                                        plus an RPG team and a garrisoned rifle squad at the village (LAMBS taskGarrison)
	["THREAT", [_veh]] call -> bool         armour that still matters: alive, crew alive inside, can move or fire
	["CONTACT", [_why]] call                first contact (an enemy shot, a hit on the tank, or the tank within
	                                        contactDistance of the treeline); logged once
	["WATCH"] spawn                         contact by distance
	["SCHEDULE"] spawn                      after the phase line, maybe (counterChance) a late counter-attack of one tank
	                                        and one BMP from the far side once counterDelay has passed without a win
	["COUNTER"] call                        spawn that counter-attack now
*/
params [["_mode", "", [""]], ["_args", [], [[]]]];
private _cfg = DMS_cfg;
private _skill = {
	params ["_u"];
	{ _u setSkill [_x select 0, _x select 1]; } forEach (DMS_cfg get "enemySkill");
};
private _crewed = {
	params ["_list", "_pos", "_dir", ["_static", false]];
	private _cls = _list select {isClass (configFile >> "CfgVehicles" >> _x)};
	if (_cls isEqualTo []) exitWith { [objNull, grpNull] };
	private _veh = createVehicle [_cls select 0, _pos, [], 0, ["NONE", "CAN_COLLIDE"] select _static];
	_veh setDir _dir;
	if (_static) then { _veh setPosATL [_pos select 0, _pos select 1, 0]; };
	createVehicleCrew _veh;
	private _grp = group ((crew _veh) select 0);
	{ [_x] call _skill; } forEach (crew _veh);
	_veh addEventHandler ["Fired", { if (!(missionNamespace getVariable ["DMS_contact", false])) then { ["CONTACT", [format ["%1 opened fire", typeOf (_this select 0)]]] call DMS_fnc_enemy; }; }];
	[_veh, _grp]
};
private _debugMark = {
	params ["_name", "_pos", "_text"];
	if (!DMS_debug) exitWith {};
	private _m = createMarker [_name, _pos];
	_m setMarkerType "mil_dot";
	_m setMarkerColor "ColorRed";
	_m setMarkerText _text;
};

switch (_mode) do {
	case "THREAT": {
		_args params [["_veh", objNull]];
		alive _veh && {({alive _x} count (crew _veh)) > 0} && {canFire _veh || {canMove _veh}}
	};

	case "INIT": {
		DMS_treeline = [];
		DMS_villageArmour = [];
		DMS_counterArmour = [];
		DMS_enemyGroups = [];
		DMS_atgm = objNull;
		DMS_counterSpawned = false;
		DMS_counterRolled = false;

		// 1. treeline tanks: dug in (no pathing), turret free
		{
			_x params ["_pos", "_dir"];
			([_cfg get "treelineTankClasses", _pos, _dir, true] call _crewed) params ["_veh", "_grp"];
			if (!isNull _veh) then {
				(driver _veh) disableAI "PATH";
				_grp setBehaviour "AWARE";
				_grp setCombatMode "YELLOW";
				DMS_treeline pushBack _veh;
				DMS_enemyGroups pushBack _grp;
				[format ["DMS_dbg_tl_%1", _forEachIndex], _pos, typeOf _veh] call _debugMark;
			};
		} forEach (DMS_layout get "treeline");

		// 2. ATGM team on a flank
		(DMS_layout get "atgm") params ["_aPos", "_aDir"];
		([_cfg get "atgmClasses", _aPos, _aDir, true] call _crewed) params ["_at", "_atGrp"];
		if (!isNull _at) then {
			DMS_atgm = _at;
			{
				private _u = _atGrp createUnit [_x, _aPos getPos [6 + 3 * _forEachIndex, _aDir + 160 + 40 * _forEachIndex], [], 0, "NONE"];
				[_u] call _skill;
				_u setUnitPos "MIDDLE";
				doStop _u;
			} forEach (_cfg get "atgmTeam");
			_atGrp setBehaviour "AWARE";
			_atGrp setCombatMode "YELLOW";
			DMS_enemyGroups pushBack _atGrp;
			["DMS_dbg_atgm", _aPos, typeOf _at] call _debugMark;
		};

		// 3. village: dug-in BMP, RPG team beside it, rifle squad garrisoned round the crossroads
		(DMS_layout get "bmp") params ["_bPos", "_bDir"];
		([_cfg get "villageIfvClasses", _bPos, _bDir, true] call _crewed) params ["_bmp", "_bGrp"];
		if (!isNull _bmp) then {
			(driver _bmp) disableAI "PATH";
			_bGrp setBehaviour "AWARE";
			_bGrp setCombatMode "YELLOW";
			DMS_villageArmour pushBack _bmp;
			DMS_enemyGroups pushBack _bGrp;
			["DMS_dbg_bmp", _bPos, typeOf _bmp] call _debugMark;
		};
		private _rpg = createGroup [east, true];
		{
			private _u = _rpg createUnit [_x, _bPos getPos [12 + 4 * _forEachIndex, _bDir + 90 + 180 * _forEachIndex], [], 2, "NONE"];
			[_u] call _skill;
			_u setUnitPos "MIDDLE";
			doStop _u;
		} forEach (_cfg get "villageAtTeam");
		_rpg setBehaviour "AWARE";
		_rpg setCombatMode "YELLOW";
		DMS_enemyGroups pushBack _rpg;

		private _xr = DMS_layout get "crossroads";
		private _gar = createGroup [east, true];
		{
			private _u = _gar createUnit [_x, _xr, [], 25, "NONE"];
			[_u] call _skill;
		} forEach ([_cfg get "villageLeaderClass"] + (_cfg get "villageInfClasses"));
		_gar setBehaviour "AWARE";
		_gar setCombatMode "YELLOW";
		DMS_enemyGroups pushBack _gar;
		if (!isNil "lambs_wp_fnc_taskGarrison") then {
			// [group, position, range, area, teleport, sortByHeight, exitCondition (-2 random), patrol]
			[_gar, _xr, _cfg get "garrisonRange", [], true, true, -2, false] call lambs_wp_fnc_taskGarrison;
		} else {
			{ doStop _x; } forEach (units _gar);
		};
		{ _x addEventHandler ["Fired", { if (!(missionNamespace getVariable ["DMS_contact", false])) then { ["CONTACT", [format ["%1 opened fire", typeOf (_this select 0)]]] call DMS_fnc_enemy; }; }]; } forEach ((units _gar) + (units _rpg) + (units _atGrp));

		[format ["Enemy: treeline %1, ATGM %2 at %3, village BMP %4 at %5, RPG team %6, garrison %7 men",
			DMS_treeline apply {typeOf _x}, typeOf DMS_atgm, _aPos apply {round _x}, typeOf _bmp, _bPos apply {round _x},
			count (units _rpg), count (units _gar)]] call DMS_fnc_log;
	};

	case "CONTACT": {
		_args params [["_why", ""]];
		if (DMS_contact || {DMS_over}) exitWith {};
		DMS_contact = true;
		DMS_contactTime = time;
		publicVariable "DMS_contact";
		[format ["Contact: %1 at t=%2, tank %3 m from the crossroads", _why, round time, round (DMS_tank distance2D (DMS_layout get "crossroads"))]] call DMS_fnc_log;
		if (DMS_testMode) then { ["CHECK", ["contact", true, _why]] call DMS_fnc_testMode; };
	};

	case "WATCH": {
		DMS_tank addEventHandler ["Hit", {
			params ["_unit", "_source"];
			if (!(missionNamespace getVariable ["DMS_contact", false]) && {side (group _source) == east}) then { ["CONTACT", [format ["tank hit by %1", typeOf _source]]] call DMS_fnc_enemy; };
		}];
		waitUntil {
			sleep 3;
			DMS_over || {DMS_contact} || {(DMS_treeline findIf {alive _x && {(_x distance2D DMS_tank) < (_cfg get "contactDistance")}}) > -1}
		};
		if (!DMS_over && {!DMS_contact}) then { ["CONTACT", [format ["tank within %1 m of the treeline", _cfg get "contactDistance"]]] call DMS_fnc_enemy; };
	};

	case "SCHEDULE": {
		waitUntil { sleep 5; DMS_over || {DMS_plCrossed} };
		if (DMS_over) exitWith {};
		DMS_counterRolled = ["CHANCE", _cfg get "counterChance"] call DMS_fnc_rng;
		[format ["Counter-attack %1", ["not coming", format ["rolled, sets off in %1 s unless the village falls", round ([_cfg get "counterDelay", 60] call DMS_fnc_t)]] select DMS_counterRolled]] call DMS_fnc_log;
		if (!DMS_counterRolled) exitWith {};
		private _t = time;
		waitUntil { sleep 5; DMS_over || {time - _t > ([_cfg get "counterDelay", 60] call DMS_fnc_t)} };
		if (DMS_over) exitWith {};
		["COUNTER"] call DMS_fnc_enemy;
	};

	case "COUNTER": {
		if (DMS_counterSpawned) exitWith {};
		DMS_counterSpawned = true;
		private _c = DMS_layout get "counter";
		private _xr = DMS_layout get "crossroads";
		private _dir = _c getDir _xr;
		([_cfg get "counterTankClasses", _c, _dir] call _crewed) params ["_t", "_tg"];
		([_cfg get "counterIfvClasses", _c getPos [40, _dir + 180], _dir] call _crewed) params ["_b", "_bg"];
		private _grp = createGroup [east, true];
		{ if (!isNull _x) then { (crew _x) joinSilent _grp; DMS_counterArmour pushBack _x; DMS_villageArmour pushBack _x; }; } forEach [_t, _b];
		{ if (!isNull _x && {(units _x) isEqualTo []}) then { deleteGroup _x; }; } forEach [_tg, _bg];
		_grp setBehaviour "AWARE";
		_grp setCombatMode "YELLOW";
		_grp setFormation "COLUMN";
		private _wp1 = _grp addWaypoint [_xr getPos [150, _dir + 180], 0];
		_wp1 setWaypointType "MOVE";
		_wp1 setWaypointSpeed "NORMAL";
		private _wp2 = _grp addWaypoint [_xr, 50];
		_wp2 setWaypointType "SAD";
		_wp2 setWaypointBehaviour "COMBAT";
		DMS_enemyGroups pushBack _grp;
		[format ["Counter-attack: %1 from %2, %3 m from the crossroads", DMS_counterArmour apply {typeOf _x}, _c apply {round _x}, round (_c distance2D _xr)]] call DMS_fnc_log;
		if (!isNull DMS_player) then { "Spot report: enemy armour moving on the village from the far side." remoteExecCall ["hintSilent", DMS_player]; };
	};
	default {};
};
