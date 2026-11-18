/*
	DMS_fnc_alarm - detection and the hunting QRF (server only).
	["MONITOR"] spawn DMS_fnc_alarm;          watch for detection (an enemy group knowsAbout a team member >= threshold)
	["ALARM", [_reason]] call DMS_fnc_alarm;  raise the alarm once (detected, casualty, strike); schedules the QRF
	["QRF"] call DMS_fnc_alarm;               spawn the QRF on foot on the battery's far side and start a LAMBS hunt
	The QRF is infantry only (an armed vehicle hunting a 4-man team on foot is a guaranteed wipe).
*/
params [["_mode", "", [""]], ["_args", [], [[]]]];

switch (_mode) do {
	case "MONITOR": {
		private _thr = DMS_cfg get "alarmKnowsAbout";
		while {!DMS_alarm && {!DMS_over}} do {
			sleep 2;
			private _targets = (units DMS_team) select {alive _x};
			private _detected = DMS_enemyGroups findIf {
				private _g = _x;
				!isNull _g && {_targets findIf {(_g knowsAbout _x) >= _thr} > -1}
			} > -1;
			if (_detected) exitWith { ["ALARM", ["detected"]] call DMS_fnc_alarm; };
		};
	};

	case "ALARM": {
		_args params [["_reason", "unknown", [""]]];
		if (DMS_alarm || {DMS_over}) exitWith {};
		DMS_alarm = true;
		DMS_alarmTime = time;
		[format ["ALARM raised (%1) at t=%2", _reason, round time]] call DMS_fnc_log;
		if (DMS_testMode) then { ["CHECK", ["alarm", true, _reason]] call DMS_fnc_testMode; };
		{ _x setBehaviour "COMBAT"; _x setCombatMode "YELLOW"; } forEach ((DMS_enemyGroups - [DMS_batteryGroup]) select {!isNull _x});
		[] spawn {
			private _d = [["RANGE", DMS_cfg get "qrfDelay"] call DMS_fnc_rng, 30] call DMS_fnc_t;
			[format ["QRF due in %1 s", round _d]] call DMS_fnc_log;
			sleep _d;
			if (DMS_over) exitWith {};
			["QRF"] call DMS_fnc_alarm;
		};
	};

	case "QRF": {
		private _cfg = DMS_cfg;
		// Spawn point: the rolled road spot, or the mirror one if the team is too close to it.
		private _minD = _cfg get "qrfMinTeamDistance";
		private _far = {
			params ["_p"];
			((units DMS_team) findIf {alive _x && {_x distance2D _p < _minD}}) < 0
		};
		private _pos = DMS_qrfSpawn;
		if (!([_pos] call _far)) then { _pos = DMS_qrfSpawnAlt; };
		if (!([_pos] call _far)) then {
			[format ["QRF: both spawn points within %1 m of the team, using the farther one", _minD], "WARN"] call DMS_fnc_log;
			private _ldr = leader DMS_team;
			if ((_ldr distance2D DMS_qrfSpawn) > (_ldr distance2D DMS_qrfSpawnAlt)) then { _pos = DMS_qrfSpawn; };
		};
		private _grp = createGroup [east, true];
		{
			private _u = _grp createUnit [_x, _pos, [], 15, "NONE"];
			{ _u setSkill _x } forEach (_cfg get "enemySkill");
		} forEach (_cfg get "qrfClasses");
		DMS_qrfGroup = _grp;
		DMS_enemyGroups pushBack _grp;
		// LAMBS hunt: radius, cycle, no camp area, moving centre, not only players (the AI team counts), no reinforcement, no flares.
		[_grp, _cfg get "qrfHuntRadius", _cfg get "qrfHuntCycle", [], [], false, false, 0] spawn lambs_wp_fnc_taskHunt;
		[format ["QRF spawned: %1 infantry at grid %2, %3 m from the team leader, hunting (LAMBS taskHunt r=%4)",
			count (units _grp), mapGridPosition _pos, round ((leader DMS_team) distance2D _pos), _cfg get "qrfHuntRadius"]] call DMS_fnc_log;
		if (DMS_testMode) then { ["CHECK", ["qrf", true, format ["%1 units", count (units _grp)]]] call DMS_fnc_testMode; };
	};
	default {};
};
