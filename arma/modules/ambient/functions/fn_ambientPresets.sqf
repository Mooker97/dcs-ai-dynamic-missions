/*
	DMSA_fnc_ambientPresets - faction class lists for the ambient module.
	[_name] call DMSA_fnc_ambientPresets -> hashmap
	  "name", "side", "infantry", "sentry", "worker", "driver", "traffic", "parked", "heli"
	_name: "auto" (rhs_usarmy when RHS USAF is loaded, else vanilla_nato), "vanilla_nato",
	       "rhs_usarmy", "rhs_usmc". Unknown names fall back to vanilla_nato with a WARN.
	Classes are verified in arma/modules/ambient/CLASSES.md. DMSA_fnc_ambientAdd still drops any
	class that is missing at runtime (isClass) and logs it.
	The RHS vehicle lists use the desert (_d) variants, which suit Altis/Malden; override them with
	the "classes" option for woodland maps.
*/
params [["_name", "auto", [""]]];

if (_name == "auto") then {
	_name = ["vanilla_nato", "rhs_usarmy"] select (isClass (configFile >> "CfgVehicles" >> "rhsusf_army_ocp_rifleman"));
};

private _p = switch (_name) do {
	case "rhs_usarmy": {
		createHashMapFromArray [
			["side", west],
			["infantry", ["rhsusf_army_ocp_rifleman", "rhsusf_army_ocp_rifleman_m4", "rhsusf_army_ocp_autorifleman", "rhsusf_army_ocp_grenadier", "rhsusf_army_ocp_teamleader", "rhsusf_army_ocp_machinegunner", "rhsusf_army_ocp_medic", "rhsusf_army_ocp_squadleader"]],
			["sentry", ["rhsusf_army_ocp_rifleman", "rhsusf_army_ocp_rifleman_m4"]],
			["worker", ["rhsusf_army_ocp_engineer", "rhsusf_army_ocp_driver"]],
			["driver", ["rhsusf_army_ocp_driver"]],
			["traffic", ["rhsusf_m1025_d", "rhsusf_m998_d_2dr_halftop", "rhsusf_M1078A1P2_D_fmtv_usarmy", "rhsusf_m1151_usarmy_d"]],
			["parked", ["rhsusf_M1078A1P2_D_fmtv_usarmy", "rhsusf_m998_d_4dr"]],
			["heli", ["RHS_UH60M_d", "RHS_UH60M"]]
		]
	};
	case "rhs_usmc": {
		createHashMapFromArray [
			["side", west],
			["infantry", ["rhsusf_usmc_marpat_wd_rifleman", "rhsusf_usmc_marpat_wd_rifleman_m4", "rhsusf_usmc_marpat_wd_autorifleman", "rhsusf_usmc_marpat_wd_grenadier", "rhsusf_usmc_marpat_wd_teamleader", "rhsusf_usmc_marpat_wd_machinegunner", "rhsusf_usmc_marpat_wd_squadleader", "rhsusf_usmc_marpat_wd_rifleman_light"]],
			["sentry", ["rhsusf_usmc_marpat_wd_rifleman", "rhsusf_usmc_marpat_wd_rifleman_m4"]],
			["worker", ["rhsusf_usmc_marpat_wd_engineer", "rhsusf_usmc_marpat_wd_driver"]],
			["driver", ["rhsusf_usmc_marpat_wd_driver"]],
			["traffic", ["rhsusf_m1025_d_s", "rhsusf_m998_d_s_2dr_halftop", "rhsusf_m1043_d_s", "rhsusf_m1151_usmc_d"]],
			["parked", ["rhsusf_m998_d_s_4dr", "rhsusf_m1043_d_s"]],
			["heli", ["RHS_UH1Y_UNARMED_d", "RHS_UH1Y_UNARMED"]]
		]
	};
	case "vanilla_nato": {
		createHashMapFromArray [
			["side", west],
			["infantry", ["B_Soldier_F", "B_Soldier_GL_F", "B_soldier_AR_F", "B_Soldier_TL_F", "B_medic_F", "B_soldier_M_F"]],
			["sentry", ["B_Soldier_F", "B_Soldier_GL_F"]],
			["worker", ["B_engineer_F", "B_Soldier_F"]],
			["driver", ["B_Soldier_F"]],
			["traffic", ["B_Truck_01_transport_F", "B_Truck_01_covered_F", "B_MRAP_01_F"]],
			["parked", ["B_Truck_01_transport_F", "B_MRAP_01_F"]],
			["heli", ["B_Heli_Transport_01_F", "B_Heli_Transport_03_unarmed_F"]]
		]
	};
	default {
		[format ["preset '%1' unknown, using vanilla_nato", _name], "WARN"] call DMSA_fnc_ambientLog;
		_name = "vanilla_nato";
		["vanilla_nato"] call DMSA_fnc_ambientPresets
	};
};
_p set ["name", _name];
_p
