"""Voice data models.

Prefers the canonical schemas from ``dms_core.schemas`` (``voice.VoiceLine``/``VoiceLineSet`` and
``story.VoiceProfile``). Until those exist, minimal compatible local fallbacks are defined here.
The render pipeline itself is duck-typed (see :func:`line_fields`), so either works.
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

try:  # pragma: no cover - depends on dms-core progress
    from dms_core.schemas.voice import VoiceLine, VoiceLineSet  # type: ignore[import-not-found,import-untyped,unused-ignore]
except ImportError:

    class VoiceLine(BaseModel):  # type: ignore[no-redef]
        """One spoken radio line (local fallback for dms_core.schemas.voice.VoiceLine)."""

        model_config = ConfigDict(extra="forbid")

        id: str = Field(
            description="Stable line id; becomes <id>.ogg and the DMS_CONFIG.voice key."
        )
        speaker: str = Field(description="Character id resolved to an ElevenLabs voice id.")
        text: str = Field(description="Text to speak. Eleven v3 audio tags like [shouts] allowed.")
        fx: str | None = Field(default=None, description="Radio FX preset override.")

    class VoiceLineSet(BaseModel):  # type: ignore[no-redef]
        """A lines.yaml document (local fallback for dms_core.schemas.voice.VoiceLineSet)."""

        model_config = ConfigDict(extra="forbid")

        lines: list[VoiceLine] = Field(default_factory=list, description="All lines.")


try:  # pragma: no cover - depends on dms-core progress
    from dms_core.schemas.story import VoiceProfile  # type: ignore[import-not-found,import-untyped,unused-ignore]
except ImportError:

    class VoiceProfile(BaseModel):  # type: ignore[no-redef]
        """Character voice (local fallback for dms_core.schemas.story.VoiceProfile)."""

        model_config = ConfigDict(extra="forbid")

        eleven_voice_id: str | None = Field(default=None, description="ElevenLabs voice id.")
        design_prompt: str | None = Field(default=None, description="Voice Design prompt.")


def _get(obj: Any, *names: str) -> Any:
    for name in names:
        if isinstance(obj, Mapping):
            if name in obj and obj[name] is not None:
                return obj[name]
        else:
            val = getattr(obj, name, None)
            if val is not None:
                return val
    return None


def line_fields(line: Any) -> tuple[str, str, str, str | None]:
    """Return ``(line_id, speaker, text, fx_preset_or_None)`` from a model or mapping."""
    line_id = _get(line, "id", "line_id")
    speaker = _get(line, "speaker")
    text = _get(line, "text")
    if not line_id or not speaker or not text:
        raise ValueError(f"voice line needs id, speaker and text: {line!r}")
    fx = _get(line, "fx", "fx_preset")
    return str(line_id), str(speaker), str(text), (str(fx) if fx else None)


def voice_id_of(entry: Any) -> str | None:
    """Extract an ElevenLabs voice id from a str, VoiceProfile-like object or mapping."""
    if isinstance(entry, str):
        return entry
    vid = _get(entry, "eleven_voice_id", "voice_id")
    if vid is None:
        nested = _get(entry, "voice")
        if nested is not None and nested is not entry:
            return voice_id_of(nested)
    return str(vid) if vid else None


def voice_fx_of(entry: Any) -> str | None:
    """Preferred radio FX preset of a voice entry (VoiceProfile.radio_fx), if any."""
    if entry is None or isinstance(entry, str):
        return None
    fx = _get(entry, "radio_fx", "fx")
    return str(fx) if fx else None


__all__ = ["VoiceLine", "VoiceLineSet", "VoiceProfile", "line_fields", "voice_fx_of", "voice_id_of"]
