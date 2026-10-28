/*
	DMS_fnc_bda - battery status, battle damage assessment, exfil and the time limit (server only).
	["MONITOR"] spawn DMS_fnc_bda;   loop every 3 s until the mission ends
	["CHECK"] call DMS_fnc_bda;      one pass (also called by the strike module)
	Neutralized = siteKillNeeded tubes out (ground truth, never told to the player directly).
	BDA confirmed = an observer sees the battery after it is neutralized: within bdaCloseRange, or within
	bdaRange with a line of sight to a tube; or a later strike lands on it (DMS_bdaByStrike).
	The observer is the player; with no player (test mode) any team member.
	Exfil = the observer at the pickup, the rest of the team close, no known enemy near, held pickupHold s.
*/
params [["_mode", "", [""]], ["_args", [], [[]]]];

switch (_mode) do {
	case "MONITOR": {
		while {!DMS_over} do {
			sleep 3;
			["CHECK"] call DMS_fnc_bda;
		};
	};

	case "CHECK": {
		if (DMS_over) exitWith {};
		private _cfg = DMS_cfg;
		private _out = ["STATUS"] call DMS_fnc_site;

		// ground truth
		if (!DMS_siteNeutralized && {_out >= (_cfg get "siteKillNeeded")}) then {
			DMS_siteNeutralized = true;
			DMS_neutralizedTime = time;
			[format ["Battery NEUTRALIZED at t=%1: %2", round time, (DMS_tubes apply {_x getVariable ["DMS_out", ""]}) joinString ", "]] call DMS_fnc_log;
			if (DMS_testMode) then { ["CHECK", ["site_neutralized", true, format ["%1/%2 tubes out", _out, count DMS_tubes]]] call DMS_fnc_testMode; };
		};

		// time limit for the battery
		if (!DMS_siteNeutralized && {time > (_cfg get "timeLimit")}) exitWith {
			["DMS_FailTime", false, "battery not destroyed within the time limit"] call DMS_fnc_end;
		};

		private _observers = if (isNull DMS_player) then { (units DMS_team) select {alive _x} } else { [DMS_player] select {alive _x} };

		// BDA
		if (!DMS_bdaDone && {DMS_strikesLanded > 0}) then {
			private _how = "";
			if (DMS_siteNeutralized && {DMS_bdaByStrike}) then { _how = "re-attack"; };
			if (_how == "") then {
				private _seen = _observers findIf {
					private _o = _x;
					private _d = _o distance2D DMS_siteCenter;
					_d < (_cfg get "bdaCloseRange") || {_d < (_cfg get "bdaRange") && {DMS_tubes findIf {
						([_o, "VIEW", _x] checkVisibility [eyePos _o, (getPosASL _x) vectorAdd [0, 0, 0.8]]) >= (_cfg get "bdaVisibility")
					} > -1}}
				};
				if (_seen > -1) then {
					private _o = _observers select _seen;
					if (DMS_siteNeutralized) then {
						_how = format ["observed by %1 at %2 m", name _o, round (_o distance2D DMS_siteCenter)];
					} else {
						// One report per landed strike: the battery is still working.
						if (DMS_bdaReportedStrike < DMS_strikesLanded) then {
							DMS_bdaReportedStrike = DMS_strikesLanded;
							private _text = format ["BDA: battery still active, %1 of %2 tubes out. Re-attack.", _out, count DMS_tubes];
							if (isPlayer _o) then { _text remoteExecCall ["hintSilent", _o]; };
							[_text] call DMS_fnc_log;
						};
					};
				};
			};
			if (_how != "") then {
				DMS_bdaDone = true;
				[format ["BDA confirmed (%1) at t=%2", _how, round time]] call DMS_fnc_log;
				if (DMS_testMode) then { ["CHECK", ["bda", true, _how]] call DMS_fnc_testMode; };
				if (!isNull DMS_player) then { "BDA: battery destroyed. Exfil to the pickup point." remoteExecCall ["hintSilent", DMS_player]; };
				["DMS_t_find", "SUCCEEDED"] call BIS_fnc_taskSetState;
				[true, "DMS_t_exfil",
					["The battery is out. Move on foot to the pickup point (marked) with the team. Transport waits there for a cold pickup.", "Exfil", ""],
					DMS_pickup, "ASSIGNED", 1, true, "move"] call BIS_fnc_taskCreate;
				private _mk = createMarker ["DMS_mk_pickup", DMS_pickup];
				_mk setMarkerType "hd_pickup";
				_mk setMarkerColor "ColorBLUFOR";
				_mk setMarkerText "Pickup";
			};
		};

		// Exfil
		if (DMS_bdaDone) then {
			private _lead = _observers select {_x distance2D DMS_pickup < (_cfg get "pickupRadius")};
			private _ok = _lead isNotEqualTo []
				&& {((units DMS_team) findIf {alive _x && {_x distance2D DMS_pickup > (_cfg get "pickupTeamRadius")}}) < 0}
				&& {(allUnits findIf {alive _x && {side (group _x) == east} && {_x distance2D DMS_pickup < (_cfg get "pickupClearRadius")}
					&& {(west knowsAbout _x) >= 1}}) < 0};
			if (_ok) then {
				if (DMS_pickupSince < 0) then {
					DMS_pickupSince = time;
					["Exfil: team at the pickup, transport coming in"] call DMS_fnc_log;
					if (!isNull DMS_player) then { "Pickup: hold here, transport inbound." remoteExecCall ["hintSilent", DMS_player]; };
				};
				if ((time - DMS_pickupSince) >= ([_cfg get "pickupHold", 5] call DMS_fnc_t)) then {
					if (DMS_testMode) then { ["CHECK", ["exfil", true, format ["t=%1", round time]]] call DMS_fnc_testMode; };
					["DMS_t_exfil", "SUCCEEDED"] call BIS_fnc_taskSetState;
					["DMS_Win", true, "battery destroyed, team exfiltrated"] call DMS_fnc_end;
				};
			} else {
				if (DMS_pickupSince >= 0) then { ["Exfil: pickup interrupted (team spread out or enemy near)"] call DMS_fnc_log; };
				DMS_pickupSince = -1;
			};
		};
	};
	default {};
};
