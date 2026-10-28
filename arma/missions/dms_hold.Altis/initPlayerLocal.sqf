/*
	initPlayerLocal.sqf - briefing only. Everything else is server-side; comm-menu items reach this
	client through remoteExec.
*/
params ["_player", "_didJIP"];
if (!hasInterface) exitWith {};

_player createDiaryRecord ["Diary", ["Support",
	"<font size='14'>Mortars</font><br/>81 mm M252 section on call (comm menu 0-8), firing from behind the OP.<br/>- Spotting round: one HE round to check the fall of shot (2 available).<br/>- Fire for effect: 6 HE rounds, roughly 50 m CEP; within 150 m of a recent spotting round the CEP tightens to about 25 m (3 missions).<br/>Expect about 85 s from request to splash. Requests within 200 m of friendlies are refused (danger close).<br/><br/><font size='14'>Attack helicopter</font><br/>One AH-64D sortie. Mark the target on the map through the comm menu. Tasking and launch take about 2 minutes, then it flies in from the rear, works the area round the mark for about 3 minutes and returns to base. It only engages what is near the mark. Marks within 150 m of friendlies are refused. It can be shot down."]];
_player createDiaryRecord ["Diary", ["Mission",
	"Your squad holds a small observation post on the high ground (blue circle). A Russian motor-rifle company is expected to attack it in several waves over the next 20 minutes or so, probably with an armoured vehicle in support from stand-off range.<br/><br/>1. Hold the OP. The squad starts in position with an M2 on a tripod.<br/>2. Break each attack. Use the mortars on troops forming up at range and save the helicopter for the armour.<br/>3. A relief element arrives a couple of minutes after the last attack is broken.<br/><br/>You fail if you are killed, the squad is wiped out, or the enemy holds the OP with none of you inside it for a minute."]];

["initPlayerLocal done"] call DMS_fnc_log;
