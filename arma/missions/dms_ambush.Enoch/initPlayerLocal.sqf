/*
	initPlayerLocal.sqf - briefing and the "player opened fire" trigger. Everything else is server-side;
	comm-menu items reach this client through remoteExec.
*/
params ["_player", "_didJIP"];
if (!hasInterface) exitWith {};

// Springing the ambush: the player's first shot once the convoy is on the road releases the squad.
_player addEventHandler ["Fired", {
	params ["_unit"];
	if (missionNamespace getVariable ["DMS_contact", false]) exitWith { _unit removeEventHandler ["Fired", _thisEventHandler]; };
	if (!(missionNamespace getVariable ["DMS_convoySpawned", false])) exitWith {};
	["CONTACT", ["player opened fire"]] remoteExecCall ["DMS_fnc_convoy", 2];
	_unit removeEventHandler ["Fired", _thisEventHandler];
}];

private _t0 = diag_tickTime;
waitUntil { uiSleep 0.5; !isNil "DMS_brief" || {diag_tickTime - _t0 > 60} };
if (isNil "DMS_brief") exitWith { ["initPlayerLocal: no briefing data from the server after 60 s", "WARN"] call DMS_fnc_log; };
DMS_brief params ["_site", "_from", "_w0", "_w1", "_ffe", "_spots", "_rounds"];

_player createDiaryRecord ["Diary", ["Support",
	format ["81 mm mortar section on call (comm menu 0-8).<br/>- Spotting round: one HE round to check the fall of shot (%1 available).<br/>- Fire for effect: %3 HE rounds, roughly 50 m CEP; within 150 m of a recent spotting round the CEP tightens to about 25 m (%2 missions).<br/>Expect about 85 s from request to splash, so it will not catch a moving convoy. Use it on dismounts and halted vehicles. Requests within 150 m of friendlies are refused (danger close).", _spots, _ffe, _rounds]]];
_player createDiaryRecord ["Diary", ["Mission",
	format ["%1, Livonia.<br/><br/>A Russian motor-rifle convoy (a Tigr, a BTR-80 and one or two Ural trucks carrying a dismount squad each) is expected through the marked kill zone from the %2, between %3 and %4. An observation post will call it when it is about 2 km out.<br/><br/>1. Move on foot to the marked ambush position. The squad holds fire until the ambush is sprung.<br/>2. Spring it when the convoy is in the kill zone: your first shot, or the first hit on the convoy, releases the squad. Use the AT weapons on the BTR first.<br/>3. Destroy the convoy before it gets past the kill line. Expect the dismounts to fight back and come after you.<br/>4. Break contact and move to the RP, where two HMMWVs are waiting.<br/><br/>Fail if you are killed, the squad is wiped out, or two vehicles get past the kill line.", _site, _from, _w0, _w1]]];

["initPlayerLocal done"] call DMS_fnc_log;
