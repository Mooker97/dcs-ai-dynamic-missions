/*
	DMSA_fnc_ambientCount - count ambient objects in the world by their "DMSA_ambient" tag.
	[_siteId, _deep] call DMSA_fnc_ambientCount -> [units, vehicles, groups, objects]
	_siteId "" = every site. Units include the dead, vehicles include wrecks.
	objects is -1 unless _deep is true (scans allMissionObjects; slow, meant for tests).
*/
params [["_id", "", [""]], ["_deep", false, [false]]];
private _is = {
	private _t = _this getVariable ["DMSA_ambient", ""];
	_t != "" && {_id == "" || {_t == _id}}
};
private _men = (allUnits + allDeadMen) arrayIntersect (allUnits + allDeadMen);
private _vehs = (vehicles + (allDead select {!(_x isKindOf "CAManBase")})) arrayIntersect (vehicles + (allDead select {!(_x isKindOf "CAManBase")}));
private _objs = -1;
if (_deep) then { _objs = {_x call _is} count (allMissionObjects "All"); };
[
	{_x call _is} count _men,
	{_x call _is} count (_vehs select {!(_x isKindOf "CAManBase")}),
	{_x call _is} count allGroups,
	_objs
]
