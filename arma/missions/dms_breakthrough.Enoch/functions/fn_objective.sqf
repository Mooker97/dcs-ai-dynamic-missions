/*
	DMS_fnc_objective - phase line and win conditions (server only).
	["WATCH"] spawn DMS_fnc_objective;
	Phase line: the tank within phaseLineDistance of the crossroads -> hint + pre-planned strike + counter-attack clock.
	Win (either):
	  A. cleared: no village armour left (the BMP, plus the counter-attack if it came), at most clearMax enemy men
	     alive within clearRadius of the crossroads, and the tank or a dismount within clearFriendlyRadius;
	  B. held: the tank within holdRadius of the crossroads for holdSeconds with no enemy armour alive anywhere
	     within armourCheckRadius.
	Fails (tank destroyed, player killed) and the draw (tank immobilised) are in DMS_fnc_tank "MONITOR".
*/
private _cfg = DMS_cfg;
private _xr = DMS_layout get "crossroads";
private _holdSince = -1;
private _lastLog = -100;
while {!DMS_over} do {
	sleep 3;
	if (DMS_over) exitWith {};
	private _tank = DMS_tank;

	if (!DMS_plCrossed && {alive _tank} && {(_tank distance2D _xr) < (_cfg get "phaseLineDistance")}) then {
		DMS_plCrossed = true;
		DMS_plTime = time;
		[format ["Phase line crossed at t=%1, tank %2 m from the crossroads", round time, round (_tank distance2D _xr)]] call DMS_fnc_log;
		["PREPLANNED"] spawn DMS_fnc_air;
		if (DMS_testMode) then {
			private _d = (DMS_ifvs select {alive _x}) apply {round (_x distance2D _tank)};
			private _ok = _d isNotEqualTo [] && {(_d select 0) < 450};
			private _s = +DMS_followSamples;
			_s sort true;
			private _med = if (_s isEqualTo []) then { -1 } else { round (_s select (floor ((count _s) / 2))) };
			["CHECK", ["section_follow", _ok, format ["Bradleys %1 m behind the tank at the phase line, median gap on the move %2 m (%3 samples)", _d, _med, count _s]]] call DMS_fnc_testMode;
		};
	};

	private _vArm = DMS_villageArmour select {["THREAT", [_x]] call DMS_fnc_enemy};
	private _allArm = (DMS_treeline + DMS_villageArmour) select {(["THREAT", [_x]] call DMS_fnc_enemy) && {(_x distance2D _xr) < (_cfg get "armourCheckRadius")}};
	private _men = allUnits select {alive _x && {side (group _x) == east} && {(_x distance2D _xr) < (_cfg get "clearRadius")}};
	private _dismounts = if (isNull DMS_inf) then { [] } else { (units DMS_inf) select {alive _x && {vehicle _x == _x}} };
	private _near = ((alive _tank) && {(_tank distance2D _xr) < (_cfg get "clearFriendlyRadius")}) || {(_dismounts findIf {(_x distance2D _xr) < (_cfg get "clearFriendlyRadius")}) > -1};
	if (time - _lastLog > ([60, 20] call DMS_fnc_t)) then {
		_lastLog = time;
		[format ["Objective: villageArmour=%1 allArmour=%2 menInRadius=%3 friendlyNear=%4 tankToCrossroads=%5 dismounts=%6 plCrossed=%7 counter=%8",
			count _vArm, count _allArm, count _men, _near, round (_tank distance2D _xr), count _dismounts, DMS_plCrossed, DMS_counterSpawned]] call DMS_fnc_log;
	};

	// A. cleared
	if (_vArm isEqualTo [] && {(count _men) <= (_cfg get "clearMax")} && {_near}) exitWith {
		private _why = format ["village cleared: no village armour, %1 enemy men within %2 m", count _men, _cfg get "clearRadius"];
		if (DMS_testMode) then { ["CHECK", ["village_cleared", true, format ["%1, dismounts %2, assisted %3", _why, count _dismounts, DMS_testAssisted]]] call DMS_fnc_testMode; };
		["DMS_Win", true, _why] call DMS_fnc_end;
	};

	// B. held
	if (alive _tank && {(_tank distance2D _xr) < (_cfg get "holdRadius")} && {_allArm isEqualTo []}) then {
		if (_holdSince < 0) then {
			_holdSince = time;
			["Holding the crossroads"] call DMS_fnc_log;
			if (!isNull DMS_player) then { "On the crossroads. Hold here." remoteExecCall ["hintSilent", DMS_player]; };
		};
	} else {
		if (_holdSince >= 0) then { ["Left the crossroads or enemy armour reappeared; hold timer reset"] call DMS_fnc_log; };
		_holdSince = -1;
	};
	if (_holdSince >= 0 && {time - _holdSince >= ([_cfg get "holdSeconds", 120] call DMS_fnc_t)}) exitWith {
		private _why = format ["crossroads held for %1 s with no enemy armour, %2 enemy men within %3 m", round (time - _holdSince), count _men, _cfg get "clearRadius"];
		if (DMS_testMode) then { ["CHECK", ["village_cleared", (count _men) <= (_cfg get "clearMax"), _why]] call DMS_fnc_testMode; };
		["DMS_Win", true, _why] call DMS_fnc_end;
	};
};
