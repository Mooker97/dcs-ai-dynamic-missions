/*
	initPlayerLocal.sqf - briefing and the Bradley comm-menu items. Everything else is server-side; the
	menu items call DMS_fnc_ifv on the server through remoteExecCall.
*/
params ["_player", "_didJIP"];
if (!hasInterface) exitWith {};

{ [_player, _x] call BIS_fnc_addCommMenuItem; } forEach ["DMS_IfvMove", "DMS_IfvHold", "DMS_IfvSuppress"];

_player createDiaryRecord ["Diary", ["Bradley",
	"An M2A3 Bradley with an AI crew is attached to your squad. It fights on its own (it engages what it sees) and takes three orders through the comm menu (0-8):<br/>- Move up to my position: it drives to about 25 m from you and stops.<br/>- Hold here, overwatch: it stops where it is and covers.<br/>- Suppress marked position: point at a spot (or click it on the map) and the gunner puts about 20 s of fire on it. Refused within 50 m of friendlies, beyond 1.5 km, or without line of sight from where it sits.<br/>Keep it out of RPG range of houses you have not cleared. If it is knocked out you can still win, but only a partial success."]];
_player createDiaryRecord ["Diary", ["Mission",
	"ChDKZ insurgents hold the village inside the marked area: two groups dug into the houses, an RPG team on the side facing you and possibly a DShKM technical.<br/>1. Clear the village. It counts as clear when almost all defenders are down and your squad is in the village.<br/>2. Expect a counterattack by truck a few minutes later from the far side. They will dismount short and come in house by house.<br/>3. Hold the village until the counterattack is beaten and you have had about a minute with no known enemy inside it.<br/>Fail if you are killed or the squad is wiped out. No respawn."]];

["initPlayerLocal done"] call DMS_fnc_log;
