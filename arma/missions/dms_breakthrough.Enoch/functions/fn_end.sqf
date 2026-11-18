/*
	DMS_fnc_end - end the mission once (server only; safe to call from event handlers).
	[_endClass, _isWin, _reason, _result] call DMS_fnc_end;   _endClass is a CfgDebriefing class
	_result defaults to "WIN"/"FAIL" from _isWin; the immobilised-tank ending passes "DRAW".
	Writes one "[DMS.OUTCOME]" line for log parsers (same format as the other DMS missions).
*/
params [["_end", "DMS_Win", [""]], ["_win", true, [true]], ["_reason", "", [""]], ["_result", "", [""]]];
if (missionNamespace getVariable ["DMS_over", false]) exitWith {};
DMS_over = true;
publicVariable "DMS_over";
if (_result == "") then { _result = ["FAIL", "WIN"] select _win; };

if (_win) then {
	{ if ([_x] call BIS_fnc_taskExists && {!([_x] call BIS_fnc_taskCompleted)}) then { [_x, "SUCCEEDED"] call BIS_fnc_taskSetState; }; } forEach ["DMS_t_village"];
} else {
	{ if ([_x] call BIS_fnc_taskExists && {!([_x] call BIS_fnc_taskCompleted)}) then { [_x, ["FAILED", "CANCELED"] select (_result == "DRAW")] call BIS_fnc_taskSetState; }; } forEach ["DMS_t_village"];
};
diag_log text format ["[DMS.OUTCOME] result=%1 end=%2 reason=%3 seed=%4 site=%5 t=%6",
	_result, _end, _reason, DMS_seed, DMS_siteName, round time];
if (DMS_testMode) then {
	if (DMS_testForce == 0) then {
		["CHECK", ["outcome_win", _win, _reason]] call DMS_fnc_testMode;
	} else {
		private _want = "DMS_FailTank";
		["CHECK", ["outcome_forced", !_win && {_end == _want}, format ["%1 (%2, wanted %3)", _reason, _end, _want]]] call DMS_fnc_testMode;
	};
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
