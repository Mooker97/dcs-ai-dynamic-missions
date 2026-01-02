"""
Intent Parser - Convert natural language to structured mission parameters

MVP Focus: SEAD missions only
"""

import re
from typing import Dict, Any, Optional, List


class MissionIntent:
    """Structured mission parameters"""

    def __init__(self, **kwargs):
        self.mission_type = kwargs.get("mission_type", "SEAD")
        self.theater = kwargs.get("theater", "PersianGulf")
        self.time_of_day = kwargs.get("time_of_day", "day")
        self.weather = kwargs.get("weather", "clear")
        self.player = kwargs.get("player", {})
        self.threats = kwargs.get("threats", {})
        self.objectives = kwargs.get("objectives", {})
        self.support = kwargs.get("support", {})

    def to_dict(self) -> Dict[str, Any]:
        return {
            "mission_type": self.mission_type,
            "theater": self.theater,
            "time_of_day": self.time_of_day,
            "weather": self.weather,
            "player": self.player,
            "threats": self.threats,
            "objectives": self.objectives,
            "support": self.support
        }


def parse(prompt: str) -> MissionIntent:
    """
    Parse natural language mission request into structured parameters.

    Args:
        prompt: Natural language mission description

    Returns:
        MissionIntent object with parsed parameters

    Example:
        >>> parse("Create a 4-ship F-16 SEAD mission in Persian Gulf at dawn with heavy SAM threats")
        MissionIntent(mission_type="SEAD", theater="PersianGulf", ...)
    """
    prompt_lower = prompt.lower()

    # Extract parameters
    theater = _parse_theater(prompt_lower)
    aircraft_type, aircraft_count = _parse_aircraft(prompt_lower)
    time_of_day = _parse_time(prompt_lower)
    weather = _parse_weather(prompt_lower)
    threat_level = _parse_threat_level(prompt_lower)
    support = _parse_support(prompt_lower)

    return MissionIntent(
        mission_type="SEAD",
        theater=theater,
        time_of_day=time_of_day,
        weather=weather,
        player={
            "aircraft": aircraft_type,
            "count": aircraft_count,
            "loadout": "SEAD_Standard",
            "skill": "Player",
            "airbase": "auto"
        },
        threats={
            "level": threat_level,
            "types": ["SAM"],
            "specific": []
        },
        objectives={
            "primary": "Suppress enemy air defenses",
            "secondary": [],
            "count": "auto"
        },
        support=support
    )


def _parse_theater(prompt: str) -> str:
    """Extract theater from prompt"""
    theaters = {
        "persian gulf": "PersianGulf",
        "pg": "PersianGulf",
        "gulf": "PersianGulf",
        "syria": "Syria",
        "caucasus": "Caucasus",
        "nevada": "Nevada",
        "nttr": "Nevada",
        "marianas": "Marianas"
    }

    for keyword, theater_name in theaters.items():
        if keyword in prompt:
            return theater_name

    return "PersianGulf"  # Default


def _parse_aircraft(prompt: str) -> tuple[str, int]:
    """
    Extract aircraft type and count from prompt.

    Returns:
        (aircraft_type, count)
    """
    # Aircraft type mapping
    aircraft_map = {
        "f-16": "F-16C_50",
        "f16": "F-16C_50",
        "viper": "F-16C_50",
        "f/a-18": "F/A-18C_hornet",
        "f-18": "F/A-18C_hornet",
        "fa-18": "F/A-18C_hornet",
        "hornet": "F/A-18C_hornet",
        "f-15e": "F-15E",
        "strike eagle": "F-15E"
    }

    aircraft_type = "F-16C_50"  # Default
    for keyword, ac_type in aircraft_map.items():
        if keyword in prompt:
            aircraft_type = ac_type
            break

    # Extract count
    count = 2  # Default

    # Look for patterns like "4-ship", "2 ship", "4 aircraft"
    ship_match = re.search(r'(\d+)[\s-]?ship', prompt)
    if ship_match:
        count = int(ship_match.group(1))
    else:
        # Look for number before aircraft type
        ac_match = re.search(r'(\d+)\s+(f-16|f16|f-18|hornet|viper)', prompt)
        if ac_match:
            count = int(ac_match.group(1))

    return aircraft_type, count


def _parse_time(prompt: str) -> str:
    """Extract time of day from prompt"""
    time_keywords = {
        "dawn": "dawn",
        "sunrise": "dawn",
        "dusk": "dusk",
        "sunset": "dusk",
        "night": "night",
        "midnight": "night",
        "noon": "day",
        "midday": "day",
        "morning": "day",
        "afternoon": "day"
    }

    for keyword, time in time_keywords.items():
        if keyword in prompt:
            return time

    return "day"  # Default


def _parse_weather(prompt: str) -> str:
    """Extract weather from prompt"""
    weather_keywords = {
        "clear": "clear",
        "cloudy": "cloudy",
        "overcast": "overcast",
        "rain": "rain",
        "storm": "storm",
        "fog": "fog"
    }

    for keyword, weather in weather_keywords.items():
        if keyword in prompt:
            return weather

    return "clear"  # Default


def _parse_threat_level(prompt: str) -> str:
    """Extract threat level from prompt"""
    if "overwhelming" in prompt or "extreme" in prompt:
        return "overwhelming"
    elif "heavy" in prompt or "high" in prompt or "intense" in prompt:
        return "heavy"
    elif "moderate" in prompt or "medium" in prompt:
        return "moderate"
    elif "light" in prompt or "low" in prompt:
        return "light"
    else:
        return "moderate"  # Default


def _parse_support(prompt: str) -> Dict[str, bool]:
    """Extract support assets from prompt"""
    return {
        "awacs": "awacs" in prompt or "magic" in prompt,
        "tanker": "tanker" in prompt or "refuel" in prompt,
        "jtac": "jtac" in prompt or "fac" in prompt,
        "escort": "escort" in prompt
    }


# Test function for development
if __name__ == "__main__":
    test_prompts = [
        "Create a 4-ship F-16 SEAD mission in the Persian Gulf at dawn with heavy SAM threats",
        "2 F/A-18s SEAD mission Syria at night, light threats",
        "SEAD mission with 2 Vipers in Caucasus, moderate SAMs, need tanker"
    ]

    for prompt in test_prompts:
        print(f"\nPrompt: {prompt}")
        intent = parse(prompt)
        print(f"Result: {intent.to_dict()}")
