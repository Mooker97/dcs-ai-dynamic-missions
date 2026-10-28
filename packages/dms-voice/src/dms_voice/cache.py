"""On-disk TTS cache: ``<root>/<sha256>.ogg`` plus a ``<sha256>.json`` sidecar.

Single-voice key = ``sha256(voice_id|model|text|fx_preset)`` (docs/CONTRACTS.md).
Dialogue key (multi-speaker ``turns``) = sha256 of the canonical JSON of the full
Text-to-Dialogue request: ``{"kind": "dialogue", "model", "fx", "inputs": [{voice_id, text}]}``.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Any

ENV_VAR = "DMS_TTS_CACHE"


def default_root() -> Path:
    override = os.environ.get(ENV_VAR)
    return Path(override) if override else Path.home() / ".dms" / "tts-cache"


def cache_key(voice_id: str, model: str, text: str, fx_preset: str) -> str:
    return hashlib.sha256(f"{voice_id}|{model}|{text}|{fx_preset}".encode()).hexdigest()


def dialogue_cache_key(inputs: list[tuple[str, str]], model: str, fx_preset: str) -> str:
    """Key for a Text-to-Dialogue render; ``inputs`` is ``[(voice_id, text), ...]`` in order."""
    request = {
        "kind": "dialogue",
        "model": model,
        "fx": fx_preset,
        "inputs": [{"voice_id": v, "text": t} for v, t in inputs],
    }
    blob = json.dumps(request, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(blob.encode()).hexdigest()


class TTSCache:
    def __init__(self, root: Path | str | None = None) -> None:
        self.root = Path(root) if root is not None else default_root()

    def audio_path(self, key: str) -> Path:
        return self.root / f"{key}.ogg"

    def meta_path(self, key: str) -> Path:
        return self.root / f"{key}.json"

    def get(self, key: str) -> Path | None:
        path = self.audio_path(key)
        return path if path.is_file() and path.stat().st_size > 0 else None

    def meta(self, key: str) -> dict[str, Any] | None:
        path = self.meta_path(key)
        if not path.is_file():
            return None
        data: dict[str, Any] = json.loads(path.read_text(encoding="utf-8"))
        return data

    def put(self, key: str, audio: bytes, meta: dict[str, Any]) -> Path:
        self.root.mkdir(parents=True, exist_ok=True)
        path = self.audio_path(key)
        tmp = path.with_suffix(".ogg.tmp")
        tmp.write_bytes(audio)
        os.replace(tmp, path)
        self.meta_path(key).write_text(
            json.dumps({"key": key, **meta}, indent=2, ensure_ascii=False), encoding="utf-8"
        )
        return path
