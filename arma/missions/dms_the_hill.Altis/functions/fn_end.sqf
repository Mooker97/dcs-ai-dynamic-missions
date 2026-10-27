/*
	DMS_fnc_end - end the mission once (server only; safe to call from event handlers).
	[_endClass, _isWin, _reason] call DMS_fnc_end;   _endClass is a CfgDebriefing class
	Writes one "[DMS.OUTCOME]" line for log parsers.
*/
params [["_end", "DMS_Win", [""]], ["_win", true, [true]], ["_reason", "", [""]]];
if (missionNamespace getVariable ["DMS_over", false]) exitWith {};
DMS_over = true;
publicVariable "DMS_over";

diag_log text format ["[DMS.OUTCOME] result=%1 end=%2 reason=%3 seed=%4 site=%5 t=%6",
	["FAIL", "WIN"] select _win, _end, _reason, DMS_seed, DMS_siteName, round time];
if (DMS_testMode) then {
	["CHECK", ["outcome_win", _win, _reason]] call DMS_fnc_testMode;
	["SUMMARY"] call DMS_fnc_testMode;
};

[_end, _win] spawn {
	params ["_end", "_win"];
	sleep 3;
	if (isMultiplayer) then {
		[_end, _win] remoteExecCall ["BIS_fnc_endMission", 0];
		if (isDedicated) then {
			sleep 15;
			if (_win) then { endMission _end; } else { failMission _end; };
		};
	} else {
		[_end, _win] call BIS_fnc_endMission;
	};
};
