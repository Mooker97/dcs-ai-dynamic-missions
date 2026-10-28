"""Voice data models and duck-typed accessors.

The canonical schemas live in ``dms_core.schemas`` (``voice.VoiceLine``/``VoiceLineSet`` and
``story.VoiceProfile``) and are re-exported here. The render pipeline reads lines through
:func:`line_fields`/:func:`line_turns`, so plain mappings (tests, ad hoc scripts) work too.
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from dms_core.schemas.story import StoryBible, VoiceProfile
from dms_core.schemas.voice import DialogueTurn, VoiceLine, VoiceLineSet


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
    """Return ``(line_id, speaker, text, radio_fx_or_None)`` from a model or mapping."""
    line_id = _get(line, "id", "line_id")
    speaker = _get(line, "speaker")
    text = _get(line, "text")
    if not line_id or not speaker or not text:
        raise ValueError(f"voice line needs id, speaker and text: {line!r}")
    fx = _get(line, "radio_fx")
    return str(line_id), str(speaker), str(text), (str(fx) if fx else None)


def line_turns(line: Any) -> list[tuple[str, str]] | None:
    """Return ``[(speaker, text), ...]`` for a multi-speaker line, or None for a single voice."""
    turns = _get(line, "turns")
    if not turns:
        return None
    out: list[tuple[str, str]] = []
    for turn in turns:
        speaker = _get(turn, "speaker")
        text = _get(turn, "text")
        if not speaker or not text:
            raise ValueError(f"dialogue turn needs speaker and text: {turn!r}")
        out.append((str(speaker), str(text)))
    return out


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


def bible_voices(bible: StoryBible) -> dict[str, VoiceProfile]:
    """Map character id -> VoiceProfile for every bible character that has a voice."""
    return {c.id: c.voice for c in bible.characters if c.voice is not None}


__all__ = [
    "DialogueTurn",
    "StoryBible",
    "VoiceLine",
    "VoiceLineSet",
    "VoiceProfile",
    "bible_voices",
    "line_fields",
    "line_turns",
    "voice_fx_of",
    "voice_id_of",
]
