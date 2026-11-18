"""DMS Tacview: parse ACMI 2.x recordings into flight summaries and debrief facts."""

from __future__ import annotations

from .acmi import (
    AcmiError,
    AcmiEvent,
    AcmiHeader,
    AcmiObject,
    Recording,
    TrackPoint,
    parse_acmi,
    parse_acmi_file,
    read_acmi_text,
)
from .debrief import default_tacview_dirs, find_newest_acmi, merge_acmi
from .facts import (
    TacviewFacts,
    attach_tacview,
    enrich_outcome,
    fact_key,
    outcome_facts,
    tacview_facts,
)
from .summary import FlightSummary, Heuristics, NamedPoint, summarize

__all__ = [
    "AcmiError",
    "AcmiEvent",
    "AcmiHeader",
    "AcmiObject",
    "FlightSummary",
    "Heuristics",
    "NamedPoint",
    "Recording",
    "TacviewFacts",
    "TrackPoint",
    "attach_tacview",
    "default_tacview_dirs",
    "enrich_outcome",
    "fact_key",
    "find_newest_acmi",
    "merge_acmi",
    "outcome_facts",
    "parse_acmi",
    "parse_acmi_file",
    "read_acmi_text",
    "summarize",
    "tacview_facts",
]
