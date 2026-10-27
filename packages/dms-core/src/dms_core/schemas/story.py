# ruff: noqa: E501
"""Story bible: setting, factions (mapped to DCS), characters with voices, timeline, sources.

Written by the story-writer skill as ``bible.yaml``. It is canonical memory for every later step.
"""

from __future__ import annotations

from typing import Literal

from pydantic import Field, model_validator

from ._common import (
    Coalition,
    Confidence,
    ContentMode,
    DMSModel,
    Ident,
    RadioFxPreset,
    Theater,
)


class Source(DMSModel):
    """A factual claim with its citation. Required for anything presented as real history."""

    claim: str = Field(description="One factual sentence, e.g. 'Route X linked A and B in 2004'.")
    source_url: str | None = Field(
        default=None, description="URL backing the claim. Omit only for fictional/adapted canon."
    )
    confidence: Confidence = Field(
        default="medium",
        description="How well the source supports the claim: high (primary/official), medium, low.",
    )
    note: str | None = Field(default=None, description="Caveats, conflicting sources, etc.")


class VoiceProfile(DMSModel):
    """How a character sounds on the radio. Drives TTS rendering and line writing style."""

    eleven_voice_id: str | None = Field(
        default=None,
        description="Existing ElevenLabs voice id. Leave null to have one designed from design_prompt.",
    )
    design_prompt: str = Field(
        description=(
            "Voice Design prompt describing the voice, e.g. 'Gravelly American male, 40s, calm "
            "under pressure, slight Texas drawl, clipped military radio delivery'."
        )
    )
    accent: str | None = Field(default=None, description="Accent, e.g. 'General American'.")
    age: int | None = Field(default=None, ge=10, le=100, description="Apparent age in years.")
    gender: str | None = Field(default=None, description="Voice gender presentation, free text.")
    cadence: Literal["slow", "measured", "brisk", "rapid"] = Field(
        default="measured", description="Speaking pace on the radio."
    )
    brevity: Literal["terse", "normal", "chatty"] = Field(
        default="terse",
        description="How many words they use. Real military radio is terse; keep most characters terse.",
    )
    radio_fx: RadioFxPreset = Field(
        default="uhf_clean",
        description=(
            "Post-processing preset: uhf_clean (aircraft/ATC UHF), vhf_noisy (ground units, FM "
            "squad nets), intercom (cockpit crew), none (narrator/briefing)."
        ),
    )
    notes: str | None = Field(default=None, description="Extra delivery notes for line writers.")


class Character(DMSModel):
    """A recurring person in the story. Real people must have real_person=true and no invented quotes."""

    id: Ident = Field(description="Stable id used as beat/line speaker, e.g. 'ops_mustang'.")
    name: str = Field(description="Full name, or a role name like 'Battalion TOC watch officer'.")
    callsign: str | None = Field(default=None, description="Radio callsign, e.g. 'Mustang'.")
    role: str = Field(description="Function in the story and on the radio, e.g. 'JTAC', 'wingman'.")
    faction: Ident | None = Field(default=None, description="Faction id this character belongs to.")
    real_person: bool = Field(
        default=False,
        description="True for real historical people. Never write invented dialogue for them.",
    )
    description: str | None = Field(default=None, description="Personality, background, look.")
    arc: str | None = Field(
        default=None, description="How this character changes over the campaign."
    )
    voice: VoiceProfile | None = Field(
        default=None, description="Voice profile. Required if the character speaks on the radio."
    )


class FactionDCS(DMSModel):
    """How a story faction maps onto what DCS can actually spawn."""

    country: str = Field(
        description="DCS country name used for this faction's units, e.g. 'USA', 'Insurgents', 'Syria'."
    )
    coalition: Coalition = Field(description="DCS coalition side.")
    units: list[str] = Field(
        default_factory=list,
        description="Representative DCS unit type ids this faction fields, e.g. ['BTR-80', 'ZU-23 Emplacement'].",
    )
    tech_veneer: str | None = Field(
        default=None,
        description="For fictional factions: which real equipment stands in for their gear and why.",
    )


class Faction(DMSModel):
    """A side or group in the story."""

    id: Ident = Field(description="Stable id, e.g. 'red_militia'.")
    name: str = Field(description="In-story name, e.g. 'Free Valley Front'.")
    description: str | None = Field(default=None, description="Who they are and what they want.")
    doctrine: str | None = Field(
        default=None, description="How they fight: ambushes, IADS-heavy, massed armor, etc."
    )
    dcs: FactionDCS = Field(description="Mapping to DCS country/coalition/unit types.")


class TimelineEvent(DMSModel):
    """An event on the story timeline, real or invented."""

    date: str = Field(description="ISO date or partial date ('2004-03', '2004-03-14').")
    event: str = Field(description="What happened, one or two sentences.")
    fictional: bool = Field(default=False, description="True if invented for this story.")
    source: Source | None = Field(
        default=None, description="Citation; required when fictional=false and mode is historical."
    )


class Setting(DMSModel):
    """Where and when the story takes place."""

    era: int = Field(
        ge=1900, le=2100, description="Year the story is set in; constrains equipment."
    )
    theater: Theater = Field(description="DCS map the campaign plays on.")
    region: str | None = Field(
        default=None, description="Area within the map, e.g. 'Orontes valley'."
    )
    premise_summary: str = Field(description="Two to four sentence summary of the premise.")


class Tone(DMSModel):
    """Narrative voice of the campaign."""

    style: str = Field(
        default="professional-terse",
        description="Overall narrative register, e.g. 'professional-terse', 'gritty', 'pulp adventure'.",
    )
    themes: list[str] = Field(
        default_factory=list, description="Themes, e.g. ['attrition', 'trust']."
    )


class StoryBible(DMSModel):
    """Canonical story bible (bible.yaml). Later agents read this instead of remembering."""

    schema_version: Literal[1] = Field(default=1, description="Schema version; always 1.")
    title: str = Field(description="Campaign title.")
    mode: ContentMode = Field(
        description=(
            "historical: real events, every claim cited; adapted: real setting with invented "
            "characters/events; fictional: invented world mapped onto DCS hardware."
        )
    )
    setting: Setting = Field(description="Era, theater, region and premise summary.")
    tone: Tone = Field(default_factory=Tone, description="Narrative register and themes.")
    player_role: str | None = Field(
        default=None, description="Who the player is, e.g. 'AH-64D crew, 1-227 ARB'."
    )
    factions: list[Faction] = Field(min_length=1, description="All sides; at least the player's.")
    characters: list[Character] = Field(default_factory=list, description="Recurring characters.")
    timeline: list[TimelineEvent] = Field(default_factory=list, description="Story chronology.")
    sources: list[Source] = Field(default_factory=list, description="General citations.")
    canon_rules: list[str] = Field(
        default_factory=list,
        description="Hard rules later writers must respect, e.g. 'Mustang never swears on the net'.",
    )

    @model_validator(mode="after")
    def _check_refs(self) -> StoryBible:
        faction_ids = [f.id for f in self.factions]
        char_ids = [c.id for c in self.characters]
        for label, ids in (("faction", faction_ids), ("character", char_ids)):
            dupes = {i for i in ids if ids.count(i) > 1}
            if dupes:
                raise ValueError(f"duplicate {label} ids: {sorted(dupes)}")
        for c in self.characters:
            if c.faction is not None and c.faction not in faction_ids:
                raise ValueError(
                    f"character '{c.id}' references unknown faction '{c.faction}' "
                    f"(known: {faction_ids})"
                )
        return self

    def character(self, char_id: str) -> Character | None:
        """Return the character with this id, or None."""
        return next((c for c in self.characters if c.id == char_id), None)
