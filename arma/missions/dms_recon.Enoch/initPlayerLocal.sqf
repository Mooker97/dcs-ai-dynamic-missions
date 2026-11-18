/*
	initPlayerLocal.sqf - player loadout (RHS recon team leader + laser designator) and the briefing.
	The mission.sqm unit is a vanilla class so the mission loads without mods and the server can
	report missing mods by name. Everything else is server-side.
*/
params ["_player", "_didJIP"];
if (!hasInterface) exitWith {};

private _cfg = call DMS_fnc_config;
private _cls = _cfg get "teamLeaderClass";
if ((["DMS_testMode", 0] call BIS_fnc_getParamValue) == 0 && {isClass (configFile >> "CfgVehicles" >> _cls)}) then {
	_player setUnitLoadout (configFile >> "CfgVehicles" >> _cls);
	private _old = binocular _player;
	if (_old != "") then { _player removeWeapon _old; };
	_player addMagazine (_cfg get "leaderDesignatorBattery");
	_player addWeapon (_cfg get "leaderDesignator");
	[format ["Player loadout: %1, binocular %2", _cls, binocular _player]] call DMS_fnc_log;
};

_player createDiaryRecord ["Diary", ["Fire support",
	"155 mm battery on call (comm menu 0-8), 3 fire missions of 6 rounds HE, about 30 m CEP around the point you report.<br/>- <b>Fire mission: target at my laser spot</b>: lase the target with your designator first (the rounds go where the laser hits, including a tree in front of the target).<br/>- <b>Fire mission: target at cursor / map position</b>: point at the target, or open the map and click it.<br/>Expect 2-3 minutes from report to splash. Reports within 200 m of your team are refused (danger close)."]];
_player createDiaryRecord ["Diary", ["Mission",
	"You lead a 4-man Force Recon team, inserted on foot about 2 km from the search area.<br/>1. Find the Russian 82 mm mortar battery (3 tubes) hidden in the forest inside the search area. You can hear it fire now and then. It is guarded and patrolled.<br/>2. Stay unseen. If they spot you, a reaction force comes hunting.<br/>3. Report it for a fire mission. The rounds land where you report, so a bad report misses.<br/>4. Confirm the kill: observe the battery (line of sight within about 400 m, or walk in) or re-attack it. If it is still working, call another mission.<br/>5. Exfil on foot to the pickup point that is marked after the kill.<br/>Fail if you are killed, the team is wiped out, or the battery is still active after 90 minutes or when the fire missions run out."]];

["initPlayerLocal done"] call DMS_fnc_log;
