/*
	DMS_fnc_t - scale a mission-logic delay for test mode.
	[_seconds, _min] call DMS_fnc_t -> _seconds * DMS_timeScale, but at least _min (default 0).
	DMS_timeScale is 1 in normal play; in test mode it is DMS_testTimeScale / 100. AI, physics and
	spawning are not scaled, so waits that the AI needs to act in (boarding, fighting) pass a _min.
*/
params [["_s", 0, [0]], ["_min", 0, [0]]];
((_s * (missionNamespace getVariable ["DMS_timeScale", 1])) max (_min min _s))
