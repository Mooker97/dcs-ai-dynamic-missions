/*
	DMSA_fnc_ambientRemove - stop a site for good: despawn everything and unregister it (scheduled, server).
	[_siteId] call DMSA_fnc_ambientRemove;   (use spawn from unscheduled code)
*/
params [["_id", "", [""]]];
if (isNil "DMSA_sites" || {!(_id in DMSA_sites)}) exitWith { [format ["[%1] remove: no such site", _id], "WARN"] call DMSA_fnc_ambientLog; };
private _st = DMSA_sites get _id;
_st set ["removed", true];
[_id, "site removed"] call DMSA_fnc_ambientDespawn;
DMSA_sites deleteAt _id;
[format ["[%1] site removed", _id]] call DMSA_fnc_ambientLog;
