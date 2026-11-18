/*
	DMS_fnc_intel - intel item hold action and pickup (server only).
	["INIT", [_obj]] call DMS_fnc_intel;      add the "Retrieve intel" hold action on every client (JIP-safe)
	["TAKEN", [_caller]] call DMS_fnc_intel;  intel recovered: task update, extraction unlocked, alarm raised
*/
params [["_mode", "", [""]], ["_args", [], [[]]]];

switch (_mode) do {
	case "INIT": {
		_args params ["_obj"];
		private _icon = "\a3\ui_f\data\IGUI\Cfg\holdactions\holdAction_search_ca.paa";
		[
			_obj, "Retrieve intel", _icon, _icon,
			"_this distance _target < 3", "_caller distance _target < 3",
			{}, {},
			{ params ["_target", "_caller"]; ["TAKEN", [_caller]] remoteExecCall ["DMS_fnc_intel", 2]; },
			{},
			[], DMS_cfg get "intelHoldSeconds", 10, true, false
		] remoteExec ["BIS_fnc_holdActionAdd", [0, -2] select isDedicated, _obj];
	};

	case "TAKEN": {
		_args params [["_caller", objNull]];
		if (DMS_intelTaken || {DMS_over}) exitWith {};
		DMS_intelTaken = true;
		publicVariable "DMS_intelTaken";
		[format ["Intel retrieved by %1 at t=%2", [name _caller, "script"] select (isNull _caller), round time]] call DMS_fnc_log;
		if (!isNull DMS_intel) then { deleteVehicle DMS_intel; };
		if (DMS_testMode) then { ["CHECK", ["intel", true]] call DMS_fnc_testMode; };

		["DMS_t_intel", "SUCCEEDED"] call BIS_fnc_taskSetState;
		[true, "DMS_t_exfil",
			["Call the extraction helicopter (comm menu 0-8, Request extraction) and get the squad aboard at the LZ.", "Extract", ""],
			objNull, "ASSIGNED", 1, true, "takeoff"] call BIS_fnc_taskCreate;

		private _mk = createMarker ["DMS_mk_lz", DMS_lz];
		_mk setMarkerShape "ELLIPSE";
		_mk setMarkerSize [60, 60];
		_mk setMarkerBrush "Border";
		_mk setMarkerColor "ColorBLUFOR";
		private _mkIcon = createMarker ["DMS_mk_lz_icon", DMS_lz];
		_mkIcon setMarkerType "hd_pickup";
		_mkIcon setMarkerColor "ColorBLUFOR";
		_mkIcon setMarkerText "LZ";

		["MENU", [DMS_player, "DMS_Extract"]] call DMS_fnc_support;
		["ALARM", ["intel taken"]] call DMS_fnc_qrf;
	};
	default {};
};
