/*
	DMSA_fnc_ambientMonitor - activation loop for one site (spawned by DMSA_fnc_ambientAdd).
	[_siteId] spawn DMSA_fnc_ambientMonitor;
	Inactive: a watcher within activeRadius -> DMSA_fnc_ambientSpawn.
	Active: every watcher beyond despawnRadius for despawnDelay s -> DMSA_fnc_ambientDespawn.
	Watchers: players (unless watchPlayers is false), the global DMSA_watchers and opts "watchers".
*/
params [["_id", "", [""]]];
if (isNil "DMSA_sites" || {!(_id in DMSA_sites)}) exitWith {};
private _st = DMSA_sites get _id;
private _o = _st get "opts";
private _center = _st get "center";
private _absentSince = -1;

while {!(_st get "removed")} do {
	sleep (_o get "pollInterval");
	private _w = [];
	if (_o get "watchPlayers") then { _w = allPlayers - (entities "HeadlessClient_F"); };
	_w append (missionNamespace getVariable ["DMSA_watchers", []]);
	_w append (_o get "watchers");
	_w = _w select {!isNull _x && {alive _x}};
	private _nearest = 1e9;
	private _who = objNull;
	{
		private _d = _x distance2D _center;
		if (_d < _nearest) then { _nearest = _d; _who = _x; };
	} forEach _w;

	if (!(_st get "removed")) then {
		if (!(_st get "active")) then {
			if (_nearest <= (_o get "activeRadius")) then {
				_st set ["active", true];
				_st set ["gen", (_st get "gen") + 1];
				_st set ["activations", (_st get "activations") + 1];
				_absentSince = -1;
				private _whoName = "watcher";
				if (!isNull _who) then { _whoName = name _who; };
				[format ["[%1] activate #%2: %3 at %4 m", _id, _st get "activations", _whoName, round _nearest]] call DMSA_fnc_ambientLog;
				[_id] call DMSA_fnc_ambientSpawn;
			};
		} else {
			if (_nearest > (_o get "despawnRadius")) then {
				if (_absentSince < 0) then {
					_absentSince = time;
					[format ["[%1] no watcher within %2 m (nearest %3 m), despawn in %4 s", _id, _o get "despawnRadius", [round _nearest, "none"] select (_nearest > 1e8), _o get "despawnDelay"], "DEBUG"] call DMSA_fnc_ambientLog;
				};
				if ((time - _absentSince) >= (_o get "despawnDelay")) then {
					[_id, format ["no watcher within %1 m for %2 s", _o get "despawnRadius", round (time - _absentSince)]] call DMSA_fnc_ambientDespawn;
					_absentSince = -1;
				};
			} else {
				if (_absentSince >= 0) then { [format ["[%1] watcher back within %2 m, despawn cancelled", _id, _o get "despawnRadius"], "DEBUG"] call DMSA_fnc_ambientLog; };
				_absentSince = -1;
			};
		};
	};
};
[format ["[%1] monitor stopped", _id]] call DMSA_fnc_ambientLog;
