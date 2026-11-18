// DMS ambient "base life" module - CfgFunctions entries (tag DMSA).
// Copy arma/modules/ambient/ to <mission>/modules/ambient/ and include this file INSIDE the
// mission's class CfgFunctions:
//     class CfgFunctions
//     {
//         class DMS { ... };                               // the mission's own functions
//         #include "modules\ambient\cfgFunctions.hpp"
//     };
class DMSA
{
	tag = "DMSA";
	class ambient
	{
		file = "modules\ambient\functions";
		class ambientAdd {};
		class ambientRemove {};
		class ambientCount {};
		class ambientMonitor {};
		class ambientSpawn {};
		class ambientDespawn {};
		class ambientHeli {};
		class ambientPresets {};
		class ambientLog {};
		class ambientRng {};
	};
};
