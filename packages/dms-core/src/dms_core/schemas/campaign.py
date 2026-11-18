# ruff: noqa: E501
"""Campaign arc (arc.yaml) and persistent campaign state (state/qualities.yaml)."""

from __future__ import annotations

from typing import Literal

from pydantic import Field, model_validator

from ._common import DMSModel, Ident, MissionType, OutcomeValue, Requires


class QualityDef(DMSModel):
    """Declares a campaign quality: a named integer that persists and steers later missions."""

    id: Ident = Field(description="Quality id, e.g. 'trust', 'civilian_goodwill', 'enemy_morale'.")
    description: str = Field(description="What the number means narratively.")
    initial: int = Field(default=0, description="Starting value.")
    min: int = Field(default=-5, description="Lowest allowed value (clamped).")
    max: int = Field(default=5, description="Highest allowed value (clamped).")


class Qualities(DMSModel):
    """Current campaign state, updated by the debriefer after each flown mission."""

    values: dict[str, int] = Field(default_factory=dict, description="Quality id -> current value.")
    flags: dict[str, bool] = Field(
        default_factory=dict,
        description="Campaign-wide flags carried between missions, e.g. {'kirk_bridge_down': true}.",
    )
    outcomes: dict[str, dict[str, OutcomeValue]] = Field(
        default_factory=dict,
        description="Mission id -> outcome dict recorded from [DMS.OUTCOME] lines.",
    )
    updated_after: Ident | None = Field(
        default=None, description="Id of the last mission folded into this state."
    )
    next_mission: Ident | None = Field(
        default=None,
        description="Arc mission id chosen by the debriefer (first matching branch, else next in order).",
    )


class Branch(DMSModel):
    """A conditional jump to another arc mission, evaluated after the mission is flown."""

    when: Requires = Field(
        default_factory=Requires,
        description="Conditions on campaign flags/qualities; first matching branch wins.",
    )
    goto: Ident = Field(description="Arc mission id to play next if the condition holds.")
    description: str | None = Field(default=None, description="Narrative reason for this branch.")


class ArcMission(DMSModel):
    """One mission slot in the arc. Detail is filled in later by the mission-designer."""

    id: Ident = Field(description="Mission id 'mNN-slug', e.g. 'm01-first-light'.")
    title: str = Field(description="Mission title.")
    mission_type: MissionType = Field(description="Primary mission type.")
    dramatic_question: str = Field(
        description="The question this mission answers for the player, e.g. 'Can we trust the militia guides?'"
    )
    synopsis: str = Field(description="Two to five sentence plan of what happens.")
    player_aircraft: str | None = Field(
        default=None, description="DCS aircraft type id the player flies, e.g. 'AH-64D_BLK_II'."
    )
    characters: list[Ident] = Field(
        default_factory=list, description="Bible character ids that appear in this mission."
    )
    key_beats: list[str] = Field(
        default_factory=list,
        description="Guaranteed story moments, as short phrases; become beats later.",
    )
    quality_effects: dict[str, str] = Field(
        default_factory=dict,
        description="Quality id -> how this mission can move it, e.g. {'trust': '+1 if convoy survives'}.",
    )
    branches: list[Branch] = Field(
        default_factory=list, description="Conditional next missions; empty means 'next in order'."
    )
    optional: bool = Field(
        default=False, description="True if this mission only appears via a branch."
    )
    status: Literal["planned", "designed", "built", "flown"] = Field(
        default="planned", description="Pipeline status of this mission."
    )


class Act(DMSModel):
    """A group of missions with a shared dramatic purpose."""

    id: Ident = Field(description="Act id, e.g. 'act1'.")
    title: str = Field(description="Act title.")
    summary: str = Field(description="What this act is about.")
    missions: list[ArcMission] = Field(min_length=1, description="Missions in play order.")


class CampaignArc(DMSModel):
    """The campaign plan (arc.yaml), typically 5-8 missions over 2-3 acts."""

    schema_version: Literal[1] = Field(default=1, description="Schema version; always 1.")
    title: str = Field(description="Campaign title (should match the bible).")
    logline: str = Field(description="One sentence pitch.")
    acts: list[Act] = Field(min_length=1, description="Acts in order.")
    qualities: list[QualityDef] = Field(
        default_factory=list, description="Qualities tracked across the campaign."
    )
    ending_notes: str | None = Field(default=None, description="How endings depend on qualities.")

    def all_missions(self) -> list[ArcMission]:
        """All missions across acts, in order."""
        return [m for a in self.acts for m in a.missions]

    @model_validator(mode="after")
    def _check_refs(self) -> CampaignArc:
        ids = [m.id for m in self.all_missions()]
        dupes = {i for i in ids if ids.count(i) > 1}
        if dupes:
            raise ValueError(f"duplicate mission ids: {sorted(dupes)}")
        quality_ids = {q.id for q in self.qualities}
        for m in self.all_missions():
            for b in m.branches:
                if b.goto not in ids:
                    raise ValueError(f"mission '{m.id}' branches to unknown mission '{b.goto}'")
                for qc in b.when.qualities:
                    if qc.quality not in quality_ids:
                        raise ValueError(
                            f"mission '{m.id}' branch uses undeclared quality '{qc.quality}'"
                        )
        return self
