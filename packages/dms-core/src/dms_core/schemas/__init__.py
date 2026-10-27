"""Pydantic v2 schemas for every DMS file format, plus JSON Schema export."""

from __future__ import annotations

import json
from pathlib import Path

from pydantic import BaseModel

from ._common import (
    MISSION_TYPES,
    THEATERS,
    Coalition,
    ContentMode,
    DMSModel,
    LatLon,
    MissionType,
    QualityCheck,
    RadioFxPreset,
    Requires,
    Theater,
)
from .beats import Beat, BeatEffects, BeatMark, BeatSheet, BeatTrigger
from .campaign import Act, ArcMission, Branch, CampaignArc, Qualities, QualityDef
from .mission import (
    Area,
    DirectorIntent,
    DynamicIntent,
    EncounterIntent,
    EncounterTriggerIntent,
    FogOfWarIntent,
    LatLonArea,
    MissionSpec,
    NearAirbase,
    NearNamedPlace,
    Objective,
    PlayerFlight,
    PolygonArea,
    PoolIntent,
    Support,
    Threat,
)
from .outcome import MissionOutcome, parse_dcs_log, summarize_outcomes
from .plan import (
    BuildPlan,
    Payload,
    PlanBriefing,
    PlanGroup,
    PlanOptions,
    PlanResource,
    PlanTask,
    PlanTrigger,
    PlanTriggerItem,
    PlanUnit,
    PlanWaypoint,
    PlanWeather,
    PlanZone,
    Pylon,
)
from .runtime import (
    Budgets,
    CircleZone,
    Director,
    DirectorGain,
    Encounter,
    EncounterTrigger,
    Intel,
    NarrativeSettings,
    Players,
    PolygonZone,
    Pool,
    PoolMember,
    RuntimeConfig,
    Speaker,
    Template,
    TemplateUnit,
    VoiceEntry,
    VoiceTurn,
)
from .story import (
    Character,
    Faction,
    FactionDCS,
    Setting,
    Source,
    StoryBible,
    TimelineEvent,
    Tone,
    VoiceProfile,
)
from .validation import Issue, validate_mission_bundle
from .voice import DialogueTurn, VoiceLine, VoiceLineSet

#: Top-level document models -> JSON Schema file stem (written as <stem>.schema.json).
DOCUMENT_MODELS: dict[str, type[BaseModel]] = {
    "story-bible": StoryBible,
    "campaign-arc": CampaignArc,
    "qualities": Qualities,
    "mission-spec": MissionSpec,
    "beats": BeatSheet,
    "voice-lines": VoiceLineSet,
    "build-plan": BuildPlan,
    "runtime-config": RuntimeConfig,
    "mission-outcome": MissionOutcome,
}


def export_json_schemas(out_dir: str | Path) -> list[Path]:
    """Write one JSON Schema file per document model into `out_dir`; return written paths."""
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    for stem, model in DOCUMENT_MODELS.items():
        schema = model.model_json_schema()
        schema["$schema"] = "https://json-schema.org/draft/2020-12/schema"
        schema["$id"] = f"https://dms.local/schemas/{stem}.schema.json"
        path = out / f"{stem}.schema.json"
        text = json.dumps(schema, indent=2, ensure_ascii=False) + "\n"
        path.write_text(text, encoding="utf-8", newline="\n")
        written.append(path)
    return written


__all__ = [
    "DOCUMENT_MODELS",
    "MISSION_TYPES",
    "THEATERS",
    "Act",
    "ArcMission",
    "Area",
    "Beat",
    "BeatEffects",
    "BeatMark",
    "BeatSheet",
    "BeatTrigger",
    "Branch",
    "Budgets",
    "BuildPlan",
    "CampaignArc",
    "Character",
    "CircleZone",
    "Coalition",
    "ContentMode",
    "DMSModel",
    "DialogueTurn",
    "Director",
    "DirectorGain",
    "DirectorIntent",
    "DynamicIntent",
    "Encounter",
    "EncounterIntent",
    "EncounterTrigger",
    "EncounterTriggerIntent",
    "Faction",
    "FactionDCS",
    "FogOfWarIntent",
    "Intel",
    "Issue",
    "LatLon",
    "LatLonArea",
    "MissionOutcome",
    "MissionSpec",
    "MissionType",
    "NarrativeSettings",
    "NearAirbase",
    "NearNamedPlace",
    "Objective",
    "Payload",
    "PlanBriefing",
    "PlanGroup",
    "PlanOptions",
    "PlanResource",
    "PlanTask",
    "PlanTrigger",
    "PlanTriggerItem",
    "PlanUnit",
    "PlanWaypoint",
    "PlanWeather",
    "PlanZone",
    "PlayerFlight",
    "Players",
    "PolygonArea",
    "PolygonZone",
    "Pool",
    "PoolIntent",
    "PoolMember",
    "Pylon",
    "Qualities",
    "QualityCheck",
    "QualityDef",
    "RadioFxPreset",
    "Requires",
    "RuntimeConfig",
    "Setting",
    "Source",
    "Speaker",
    "StoryBible",
    "Support",
    "Template",
    "TemplateUnit",
    "Theater",
    "Threat",
    "TimelineEvent",
    "Tone",
    "VoiceEntry",
    "VoiceLine",
    "VoiceLineSet",
    "VoiceProfile",
    "VoiceTurn",
    "export_json_schemas",
    "parse_dcs_log",
    "summarize_outcomes",
    "validate_mission_bundle",
]
