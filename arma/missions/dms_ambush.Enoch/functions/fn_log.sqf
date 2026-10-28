/*
	DMS_fnc_log
	[_msg, _level] call DMS_fnc_log;
	_level: "INFO" (default), "WARN", "DEBUG" (only when DMS_debug), "TEST" (prints "[DMS.TEST] <msg>").
*/
params [["_msg", "", [""]], ["_level", "INFO", [""]]];

private _debug = missionNamespace getVariable ["DMS_debug", false];
if (_level == "DEBUG" && {!_debug}) exitWith {};

private _line = if (_level == "TEST") then {
	format ["[DMS.TEST] %1", _msg]
} else {
	format ["[DMS] %1: %2", _level, _msg]
};
diag_log text _line;
if (_debug && {hasInterface}) then { systemChat _line; };
