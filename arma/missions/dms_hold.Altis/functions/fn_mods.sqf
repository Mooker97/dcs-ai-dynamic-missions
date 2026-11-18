/*
	DMS_fnc_mods - required-mod check (server only).
	call DMS_fnc_mods -> [] when everything is present, otherwise a list of human-readable problems.
	Logs "Mods: ..." (loaded CfgPatches) and every missing patch, class and function. The gate is the
	classes and LAMBS functions the mission actually uses, not just the patch names.
*/
private _cfg = DMS_cfg;
private _problems = [];

private _loaded = [];
{
	_x params ["_label", "_patch"];
	if (isClass (configFile >> "CfgPatches" >> _patch)) then {
		_loaded pushBack _label;
	} else {
		_problems pushBack format ["mod %1 (CfgPatches %2) not loaded", _label, _patch];
	};
} forEach (_cfg get "modPatches");
[format ["Mods: %1", [_loaded joinString ", ", "none (vanilla)"] select (_loaded isEqualTo [])]] call DMS_fnc_log;

private _classes = [_cfg get "squadLeaderClass", _cfg get "playerLoadoutClass", _cfg get "enemyLeaderClass"]
	+ (_cfg get "squadClasses") + (_cfg get "enemyClasses");
{
	if (!isClass (configFile >> "CfgVehicles" >> _x)) then { _problems pushBack format ["class %1 missing", _x]; };
} forEach (_classes arrayIntersect _classes);
// lists where the first existing class is used: at least one must exist
{
	private _list = _cfg get _x;
	if ((_list findIf {isClass (configFile >> "CfgVehicles" >> _x)}) < 0) then {
		_problems pushBack format ["none of %1 exists (%2)", _list, _x];
	};
} forEach ["staticClasses", "sbfClasses", "airClasses"];
{
	if (isNil _x) then { _problems pushBack format ["function %1 missing", _x]; };
} forEach (_cfg get "modFunctions");

{ [format ["Mod check: %1", _x], "WARN"] call DMS_fnc_log; } forEach _problems;
_problems
