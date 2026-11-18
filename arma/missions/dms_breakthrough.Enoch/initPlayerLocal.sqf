/*
	initPlayerLocal.sqf - briefing. Everything else is server-side; comm-menu items reach this client through remoteExec.
*/
params ["_player", "_didJIP"];
if (!hasInterface) exitWith {};

private _t0 = diag_tickTime;
waitUntil { uiSleep 0.5; !isNil "DMS_brief" || {diag_tickTime - _t0 > 60} };
if (isNil "DMS_brief") exitWith { ["initPlayerLocal: no briefing data from the server after 60 s", "WARN"] call DMS_fnc_log; };
DMS_brief params ["_site", "_from", "_dist", "_cas", "_pl"];

_player createDiaryRecord ["Diary", ["Support",
	format ["A-10A on call (comm menu 0-8), %1 strikes. Each strike is 2 x Mk82 on the position you mark with the cursor or on the map, roughly 25 m CEP, about 2 minutes from request to impact. Requests within 200 m of friendlies are refused (danger close).<br/><br/>A pre-planned strike of 4 x Mk82 hits the village defences when you cross PL BLUE, %2 m short of the crossroads.", _cas, _pl]]];
_player createDiaryRecord ["Diary", ["Tank",
	"You command an M1A2 SEP (woodland) with an AI driver and gunner. You start in the commander's seat. Give the driver and gunner orders as you would any AI in your group, or switch seats from the action menu.<br/><br/>Two M2A3 Bradleys with a rifle squad follow 150-250 m behind you along the road. They stop when you stop. When the village armour is down they move up, stop about 300 m short of the crossroads and dismount the squad to clear the village. Losing them does not end the mission.<br/><br/>If your tank is immobilised you can keep fighting from the hull or bail out and fall back to the Bradleys. If it stays immobilised for 10 minutes without the objective taken, the attack is called off."]];
_player createDiaryRecord ["Diary", ["Mission",
	format ["%1, Livonia.<br/><br/>Your tank leads a small combined-arms team from the line of departure, about %2 m (straight line) from the objective, coming in from the %3 along the farm road.<br/><br/>Intelligence expects a Russian armour screen in the treelines on the approach (at least two tanks), anti-tank teams on the flanks and a dug-in BMP with infantry at the village edge. Reinforcements from the far side are possible if the attack stalls. No exact positions are known: the objective area is approximate.<br/><br/>1. Advance on the axis, find and destroy the armour screen. Use the terrain and the A-10.<br/>2. Cross PL BLUE: the pre-planned strike goes in on the village defences.<br/>3. Destroy the armour in the village. The Bradleys then dismount the squad to clear it.<br/><br/>Win: the village armour destroyed and the village cleared, or your tank holding the crossroads for 2 minutes with no enemy armour left.<br/>Fail: your tank is destroyed or you are killed.", _site, _dist, _from]]];

["initPlayerLocal done"] call DMS_fnc_log;
