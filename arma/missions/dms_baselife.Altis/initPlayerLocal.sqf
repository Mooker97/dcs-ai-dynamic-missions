/*
	initPlayerLocal.sqf - briefing only. The ambient site runs on the server.
*/
params ["_player", "_didJIP"];
if (!hasInterface) exitWith {};

_player createDiaryRecord ["Diary", ["Base life",
	"You start on a working NATO base: sentries at the entrances, soldiers idling by the buildings, a work party on a parked vehicle, vehicles driving round the base roads and a transport helicopter coming and going.<br/>The activity appears within about 600 m of the base and is removed once you have been more than 900 m away for 30 s. Come back and it starts again."]];

["initPlayerLocal done"] call DMS_fnc_log;
