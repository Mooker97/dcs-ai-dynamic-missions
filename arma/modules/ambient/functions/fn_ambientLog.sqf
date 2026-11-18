/*
	DMSA_fnc_ambientLog
	[_msg, _level] call DMSA_fnc_ambientLog;
	Same line format as the missions' DMS_fnc_log: "[DMS] <LEVEL>: Ambient <msg>".
	_level: "INFO" (default), "WARN", "ERROR", "DEBUG" (only when DMSA_debug or DMS_debug is true).
*/
params [["_msg", "", [""]], ["_level", "INFO", [""]]];

private _debug = (missionNamespace getVariable ["DMSA_debug", false]) || {missionNamespace getVariable ["DMS_debug", false]};
if (_level == "DEBUG" && {!_debug}) exitWith {};

private _line = format ["[DMS] %1: Ambient %2", _level, _msg];
diag_log text _line;
if (_debug && {hasInterface}) then { systemChat _line; };
