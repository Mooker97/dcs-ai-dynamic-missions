"""DMS voice: ElevenLabs rendering, radio FX, cache"""

from .cache import TTSCache, cache_key
from .client import MissingApiKeyError, VoiceApiError, VoiceClient, synthesize
from .fx import PRESETS, apply_fx, duration_seconds
from .render import render_lines

__all__ = [
    "PRESETS",
    "MissingApiKeyError",
    "TTSCache",
    "VoiceApiError",
    "VoiceClient",
    "apply_fx",
    "cache_key",
    "duration_seconds",
    "render_lines",
    "synthesize",
]
