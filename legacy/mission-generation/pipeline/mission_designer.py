"""
Mission Designer - Transform intent into concrete mission structure

MVP Focus: SEAD missions only
"""

import yaml
import random
from pathlib import Path
from typing import Dict, Any, List
from .intent_parser import MissionIntent


def design(intent: MissionIntent) -> Dict[str, Any]:
    """
    Transform parsed intent into concrete mission structure.

    Args:
        intent: Parsed mission parameters

    Returns:
        Mission structure dictionary with all details for building
    """
    # Load SEAD mission definition
    mission_def = _load_mission_definition("sead.yaml")

    # Select player flight template
    player_flight_template = _select_player_template(
        intent.player["aircraft"],
        intent.player["count"]
    )

    # Select threats based on difficulty
    threats = _select_threats(
        intent.threats["level"],
        mission_def["threat_composition"]
    )

    # Select support assets
    support_assets = _select_support(intent.support, mission_def["support_assets"])

    # Generate briefing
    briefing = _generate_briefing(intent, mission_def, threats)

    # Build mission structure
    return {
        "template": _select_theater_template(intent.theater),
        "theater": intent.theater,
        "time": _time_to_seconds(intent.time_of_day),
        "weather": intent.weather,
        "blue_forces": {
            "player_flight": {
                "template": player_flight_template,
                "position": [0, 0],  # Will be resolved to airbase
                "customizations": {}
            },
            **support_assets
        },
        "red_forces": {
            "sam_sites": threats["sam_sites"],
            "cap_flights": threats["cap_flights"]
        },
        "objectives": {
            "primary": mission_def["objectives"]["primary"].format(
                count=len(threats["sam_sites"])
            ),
            "secondary": mission_def["objectives"]["secondary"]
        },
        "lua_scripts": mission_def["lua_scripts"],
        "briefing": briefing,
        "randomization": {
            "position_variance": 1000,  # meters
            "spawn_timing_variance": 60  # seconds
        }
    }


def _load_mission_definition(filename: str) -> Dict[str, Any]:
    """Load mission type definition from YAML"""
    mission_dir = Path(__file__).parent.parent / "templates" / "missions"
    mission_file = mission_dir / filename

    with open(mission_file, 'r') as f:
        return yaml.safe_load(f)


def _select_player_template(aircraft: str, count: int) -> str:
    """Select appropriate player flight template"""
    templates = {
        "F-16C_50": {
            2: "F16_SEAD_2ship",
            4: "F16_SEAD_4ship"
        },
        "F/A-18C_hornet": {
            2: "FA18_SEAD_2ship",
            4: "FA18_SEAD_2ship"  # No 4-ship Hornet template yet
        },
        "F-15E": {
            2: "F15E_Strike_2ship",
            4: "F15E_Strike_2ship"
        }
    }

    # Default to 2-ship if count not available
    if aircraft in templates:
        if count in templates[aircraft]:
            return templates[aircraft][count]
        else:
            return templates[aircraft][2]
    else:
        return "F16_SEAD_2ship"


def _select_theater_template(theater: str) -> str:
    """Select appropriate template mission for theater"""
    templates = {
        "PersianGulf": "pg_clean.miz",
        "Syria": "syria_clean.miz",
        "Caucasus": "caucasus_clean.miz",
        "Nevada": "nevada_clean.miz",
        "Marianas": "marianas_clean.miz"
    }
    return templates.get(theater, "pg_clean.miz")


def _select_threats(threat_level: str, threat_comp: Dict[str, Any]) -> Dict[str, List]:
    """
    Select SAM sites and CAP flights based on threat level.

    Returns:
        {
            "sam_sites": [{"template": "...", "position": (x, y)}, ...],
            "cap_flights": [...]
        }
    """
    level_config = threat_comp.get(threat_level, threat_comp["moderate"])

    # Generate SAM sites
    sam_count = level_config["sam_sites"]
    sam_types = level_config["types"]
    sam_sites = []

    for i in range(sam_count):
        # Randomly select SAM type from allowed types
        sam_template = random.choice(sam_types)

        # Generate position (rough placement, will be refined)
        # Place SAMs in a rough arc 50-100km from starting point
        angle = (i / sam_count) * 180  # Spread across 180 degrees
        distance = random.randint(50000, 100000)  # 50-100km
        x = distance * random.uniform(0.7, 1.3)
        y = distance * random.uniform(-0.3, 0.3)

        sam_sites.append({
            "template": sam_template,
            "position": (x, y)
        })

    # Generate CAP flights
    cap_count = level_config.get("cap_flights", 0)
    cap_flights = []

    for i in range(cap_count):
        cap_flights.append({
            "template": "MIG29_CAP_2ship",
            "position": (
                random.randint(60000, 90000),
                random.randint(-20000, 20000)
            )
        })

    return {
        "sam_sites": sam_sites,
        "cap_flights": cap_flights
    }


def _select_support(support_intent: Dict[str, bool], support_config: Dict[str, str]) -> Dict[str, Any]:
    """Select support assets based on intent and mission requirements"""
    support = {}

    # AWACS
    if support_intent.get("awacs") or support_config.get("awacs") == "recommended":
        support["awacs"] = {
            "template": "AWACS_E3A",
            "position": [80000, 40000]
        }

    # Tanker
    if support_intent.get("tanker") or support_config.get("tanker") == "recommended":
        support["tanker"] = {
            "template": "Tanker_KC135",
            "position": [60000, 30000]
        }

    return support


def _time_to_seconds(time_of_day: str) -> int:
    """Convert time of day to seconds since midnight"""
    times = {
        "dawn": 6 * 3600,      # 06:00
        "day": 12 * 3600,      # 12:00
        "dusk": 18 * 3600,     # 18:00
        "night": 22 * 3600     # 22:00
    }
    return times.get(time_of_day, 12 * 3600)


def _generate_briefing(intent: MissionIntent, mission_def: Dict[str, Any], threats: Dict[str, List]) -> str:
    """Generate mission briefing text"""
    template = mission_def["briefing_template"]

    # Extract threat types for briefing
    threat_types = ", ".join(set([
        sam["template"].replace("_", " ") for sam in threats["sam_sites"]
    ]))

    # Format briefing
    briefing = template.format(
        theater=intent.theater,
        time=intent.time_of_day.capitalize(),
        weather=intent.weather.capitalize(),
        threat_count=len(threats["sam_sites"]),
        threat_level=intent.threats["level"].capitalize(),
        threat_types=threat_types,
        primary_targets=threat_types,
        awacs_callsign="Magic",
        awacs_freq="251.0 MHz",
        tanker_callsign="Texaco 1-1",
        tanker_location="Refueling Track Alpha",
        weather_description=f"{intent.weather.capitalize()} skies",
        tower_freq="250.0 MHz",
        flight_freq="251.0 MHz"
    )

    return briefing


# Test function
if __name__ == "__main__":
    from intent_parser import parse

    prompt = "Create a 4-ship F-16 SEAD mission in Persian Gulf at dawn with heavy SAM threats"
    intent = parse(prompt)
    structure = design(intent)

    print("Mission Structure:")
    print(f"Theater: {structure['theater']}")
    print(f"Player Flight: {structure['blue_forces']['player_flight']['template']}")
    print(f"SAM Sites: {len(structure['red_forces']['sam_sites'])}")
    print(f"CAP Flights: {len(structure['red_forces']['cap_flights'])}")
    print(f"\nBriefing:\n{structure['briefing']}")
