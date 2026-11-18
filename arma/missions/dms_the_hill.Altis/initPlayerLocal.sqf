/*
	initPlayerLocal.sqf - briefing only. Everything else is server-side; comm-menu items and the
	intel hold action reach this client through remoteExec.
*/
params ["_player", "_didJIP"];
if (!hasInterface) exitWith {};

_player createDiaryRecord ["Diary", ["Support",
	"82 mm mortar section on call (comm menu 0-8).<br/>- Spotting round: one HE round to check the fall of shot (3 available).<br/>- Fire for effect: 5 HE rounds, roughly 50 m CEP; within 150 m of a recent spotting round the CEP tightens to about 25 m (3 missions).<br/>Expect about 85 s from request to splash. Requests within 150 m of friendlies are refused (danger close)."]];
_player createDiaryRecord ["Diary", ["Mission",
	"Your squad is on foot about 1 km from a small CSAT compound inside the marked area.<br/>1. Clear the compound and retrieve the intel (laptop).<br/>2. Expect a motorised reaction force about 5-8 minutes after they know you are there, or once the intel goes missing.<br/>3. Call the extraction helicopter (comm menu 0-8) and get everyone aboard at the LZ. It will not land on a hot LZ and will only wait a few minutes on the ground.<br/>Fail if you are killed or the helicopter is lost."]];

["initPlayerLocal done"] call DMS_fnc_log;
