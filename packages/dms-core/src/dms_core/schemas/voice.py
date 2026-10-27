"""Voice lines (lines.yaml): the text each speaker says, keyed by line id."""

from __future__ import annotations

from typing import Any, Literal

from pydantic import Field, model_validator

from ._common import DMSModel, Ident, RadioFxPreset


class VoiceLine(DMSModel):
    """One spoken radio line. Write 3-5 variants per beat (ids like 'convoy_hit_v1'..'_v3')."""

    id: Ident = Field(description="Line id referenced by beats, e.g. 'convoy_hit_v1'.")
    speaker: Ident = Field(description="Character id (bible) who speaks it.")
    text: str = Field(
        min_length=1,
        max_length=600,
        description=(
            "Exactly what is said. Terse radio style. Eleven v3 audio tags allowed, e.g. "
            "'[shouts] Troops in contact!'. Never put invented quotes in real people's mouths."
        ),
    )
    subtitle: str | None = Field(
        default=None,
        description="On-screen text if different from `text` (tags stripped otherwise).",
    )
    beat: Ident | None = Field(
        default=None, description="Beat this line belongs to (informational)."
    )
    delivery: str | None = Field(
        default=None, description="Direction for the voice actor/TTS, e.g. 'out of breath, urgent'."
    )
    radio_fx: RadioFxPreset | None = Field(
        default=None, description="Override the speaker's radio FX preset for this line."
    )
    file: str | None = Field(
        default=None, description="Rendered .ogg file name; filled in by `dms voice`."
    )
    dur_sec: float | None = Field(
        default=None, gt=0, description="Audio duration; filled by `dms voice`."
    )


class VoiceLineSet(DMSModel):
    """Contents of lines.yaml. A bare YAML list of lines is also accepted."""

    mission_id: Ident | None = Field(default=None, description="Mission these lines belong to.")
    model: Literal["eleven_v3", "eleven_flash_v2_5", "eleven_multilingual_v2"] = Field(
        default="eleven_v3", description="TTS model; flash for cheap drafts."
    )
    lines: list[VoiceLine] = Field(default_factory=list, description="All voice lines.")

    @model_validator(mode="before")
    @classmethod
    def _accept_bare_list(cls, data: Any) -> Any:
        if isinstance(data, list):
            return {"lines": data}
        return data

    @model_validator(mode="after")
    def _unique_ids(self) -> VoiceLineSet:
        ids = [ln.id for ln in self.lines]
        dupes = {i for i in ids if ids.count(i) > 1}
        if dupes:
            raise ValueError(f"duplicate line ids: {sorted(dupes)}")
        return self

    def by_id(self) -> dict[str, VoiceLine]:
        """Map line id -> line."""
        return {ln.id: ln for ln in self.lines}
