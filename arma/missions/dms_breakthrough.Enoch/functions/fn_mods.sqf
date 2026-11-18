/*
	DMS_fnc_mods - check the required mods (server only).
	[] call DMS_fnc_mods -> array of missing required mod labels ([] = all present)
	Logs "Mods: <loaded>" and, if anything required is missing, "Missing required mods: ..." as an ERROR.
	Each mod is detected by its CfgPatches class (see "mods" in fn_config).
*/
private _loaded = [];
private _missing = [];
{
	_x params ["_label", "_patch", "_required"];
	if (isClass (configFile >> "CfgPatches" >> _patch)) then {
		_loaded pushBack _label;
	} else {
		if (_required) then { _missing pushBack _label; };
	};
} forEach (DMS_cfg get "mods");
// LAMBS waypoint functions are compiled by CBA at preInit; check the ones this mission calls.
if ("LAMBS Waypoints" in _loaded) then {
	if (isNil "lambs_wp_fnc_taskGarrison") then { ["lambs_wp_fnc_taskGarrison is not defined although lambs_wp is loaded; the village garrison just holds its ground", "WARN"] call DMS_fnc_log; };
	if (isNil "lambs_wp_fnc_taskCQB") then { ["lambs_wp_fnc_taskCQB is not defined although lambs_wp is loaded; the dismounts fall back to a SAD waypoint", "WARN"] call DMS_fnc_log; };
};
[format ["Mods: %1", [_loaded joinString ", ", "none"] select (_loaded isEqualTo [])]] call DMS_fnc_log;
if (_missing isNotEqualTo []) then {
	[format ["Missing required mods: %1", _missing joinString ", "], "ERROR"] call DMS_fnc_log;
};
_missing
