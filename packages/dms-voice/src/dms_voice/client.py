"""Thin wrapper over the ElevenLabs SDK with retries and a clear missing-key error.

The API key is read from ``ELEVENLABS_API_KEY`` (a ``.env`` found from the cwd upward is loaded
first). The key is never logged or included in error messages.
"""

from __future__ import annotations

import os
import time
from collections.abc import Callable, Iterable
from typing import Any, TypeVar

T = TypeVar("T")

DEFAULT_MODEL = "eleven_v3"
DEFAULT_OUTPUT = "mp3_44100_128"
RETRY_STATUS = {408, 409, 425, 429, 500, 502, 503, 504}


class MissingApiKeyError(RuntimeError):
    pass


class VoiceApiError(RuntimeError):
    pass


def load_api_key() -> str:
    try:
        from dotenv import find_dotenv, load_dotenv

        load_dotenv(find_dotenv(usecwd=True), override=False)
    except Exception:  # pragma: no cover - dotenv is optional at runtime
        pass
    key = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    if not key:
        raise MissingApiKeyError(
            "ELEVENLABS_API_KEY is not set. Add it to DMS/.env or the environment, "
            "or use --dry-run to estimate cost without calling the API."
        )
    return key


def _status_of(exc: BaseException) -> int | None:
    status = getattr(exc, "status_code", None)
    return status if isinstance(status, int) else None


def _is_retryable(exc: BaseException) -> bool:
    status = _status_of(exc)
    if status is not None:
        return status in RETRY_STATUS
    name = type(exc).__name__
    return any(s in name for s in ("Timeout", "Connect", "Network", "RemoteProtocol"))


def with_retries(
    fn: Callable[[], T],
    *,
    attempts: int = 4,
    base_delay: float = 1.0,
    sleep: Callable[[float], None] = time.sleep,
) -> T:
    for attempt in range(1, attempts + 1):
        try:
            return fn()
        except Exception as exc:
            if attempt >= attempts or not _is_retryable(exc):
                status = _status_of(exc)
                detail = f"HTTP {status}" if status else type(exc).__name__
                body = getattr(exc, "body", None)
                raise VoiceApiError(f"ElevenLabs request failed ({detail}): {body or exc}") from exc
            sleep(base_delay * 2 ** (attempt - 1))
    raise AssertionError("unreachable")  # pragma: no cover


def _join(chunks: Iterable[bytes] | bytes) -> bytes:
    return chunks if isinstance(chunks, bytes) else b"".join(chunks)


class VoiceClient:
    def __init__(self, api_key: str | None = None, sdk: Any = None) -> None:
        self._api_key = api_key
        self._sdk = sdk

    @property
    def sdk(self) -> Any:
        if self._sdk is None:
            from elevenlabs.client import ElevenLabs

            self._sdk = ElevenLabs(api_key=self._api_key or load_api_key())
        return self._sdk

    def synthesize(
        self,
        text: str,
        voice_id: str,
        model: str = DEFAULT_MODEL,
        output_format: str = DEFAULT_OUTPUT,
        settings: dict[str, Any] | None = None,
    ) -> bytes:
        kwargs: dict[str, Any] = {
            "text": text,
            "model_id": model,
            "output_format": output_format,
        }
        if settings:
            from elevenlabs import VoiceSettings

            kwargs["voice_settings"] = VoiceSettings(**settings)
        sdk = self.sdk
        return with_retries(lambda: _join(sdk.text_to_speech.convert(voice_id, **kwargs)))

    def dialogue(
        self,
        turns: list[dict[str, str]],
        model: str = DEFAULT_MODEL,
        output_format: str = DEFAULT_OUTPUT,
    ) -> bytes:
        """Multi-speaker audio. Uses Text-to-Dialogue when available, else synth + concat."""
        sdk = self.sdk
        ttd = getattr(sdk, "text_to_dialogue", None)
        if ttd is not None:
            from elevenlabs import DialogueInput

            inputs = [DialogueInput(text=t["text"], voice_id=t["voice_id"]) for t in turns]
            return with_retries(
                lambda: _join(
                    ttd.convert(inputs=inputs, model_id=model, output_format=output_format)
                )
            )
        from .fx import concat_audio

        clips = [self.synthesize(t["text"], t["voice_id"], model, output_format) for t in turns]
        return concat_audio(clips)

    def design_voice(self, prompt: str, text: str | None = None) -> list[dict[str, Any]]:
        """Voice Design previews: [{generated_voice_id, audio_base_64, ...}]. Optional feature."""
        sdk = self.sdk
        ttv = getattr(sdk, "text_to_voice", None)
        design = getattr(ttv, "design", None) or getattr(ttv, "create_previews", None)
        if design is None:
            raise VoiceApiError("Voice Design is not supported by the installed elevenlabs SDK")
        kwargs: dict[str, Any] = {"voice_description": prompt}
        if text:
            kwargs["text"] = text
        else:
            kwargs["auto_generate_text"] = True
        resp = with_retries(lambda: design(**kwargs))
        previews = getattr(resp, "previews", []) or []
        return [p.model_dump() if hasattr(p, "model_dump") else dict(p) for p in previews]


_default: VoiceClient | None = None


def default_client() -> VoiceClient:
    global _default
    if _default is None:
        _default = VoiceClient()
    return _default


def synthesize(
    text: str,
    voice_id: str,
    model: str = DEFAULT_MODEL,
    output_format: str = DEFAULT_OUTPUT,
    settings: dict[str, Any] | None = None,
) -> bytes:
    return default_client().synthesize(text, voice_id, model, output_format, settings)


def dialogue(turns: list[dict[str, str]]) -> bytes:
    return default_client().dialogue(turns)


def design_voice(prompt: str, text: str | None = None) -> list[dict[str, Any]]:
    return default_client().design_voice(prompt, text)
