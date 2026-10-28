"""Render a set of voice lines to ``<line_id>.ogg`` + ``manifest.json``.

The manifest ``{line_id: {file, dur_sec, text, speaker}}`` feeds ``DMS_CONFIG.voice`` (durSec).
Lines with ``turns`` are rendered as one clip with ElevenLabs Text-to-Dialogue.

Voice ids resolve per speaker from the campaign bible (``characters[].voice``, a
``VoiceProfile``) first and ``data/voice/voices.json`` (or ``--voices``) second.
"""

from __future__ import annotations

import json
import shutil
from collections.abc import Iterable, Mapping
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Protocol

import yaml  # type: ignore[import-untyped,unused-ignore]

from .cache import TTSCache, cache_key, dialogue_cache_key
from .client import DEFAULT_MODEL
from .fx import PRESETS, apply_fx, duration_seconds
from .models import (
    StoryBible,
    VoiceProfile,
    bible_voices,
    line_fields,
    line_turns,
    voice_fx_of,
    voice_id_of,
)

DEFAULT_FX = "uhf_clean"
VOICES_JSON = Path("data") / "voice" / "voices.json"
BIBLE_FILE = "bible.yaml"


class Synthesizer(Protocol):
    def synthesize(self, text: str, voice_id: str, model: str = ...) -> bytes: ...

    def dialogue(self, turns: list[dict[str, str]], model: str = ...) -> bytes: ...


@dataclass
class PlannedTurn:
    speaker: str
    voice_id: str
    text: str


@dataclass
class PlannedLine:
    line_id: str
    speaker: str
    text: str
    voice_id: str
    fx: str
    key: str
    cached: bool
    turns: list[PlannedTurn] | None = None

    @property
    def characters(self) -> int:
        """Billable characters: the turn texts for dialogue, else the line text."""
        if self.turns:
            return sum(len(t.text) for t in self.turns)
        return len(self.text)


@dataclass
class CostEstimate:
    total_lines: int
    to_render: int
    characters: int
    lines: list[PlannedLine] = field(default_factory=list)

    def summary(self) -> str:
        cached = self.total_lines - self.to_render
        return (
            f"{self.total_lines} lines ({cached} cached, {self.to_render} to render): "
            f"{self.characters} characters ~= {self.characters} ElevenLabs credits"
        )


def find_voices_json(start: Path | None = None) -> Path | None:
    here = (start or Path.cwd()).resolve()
    for d in (here, *here.parents):
        cand = d / VOICES_JSON
        if cand.is_file():
            return cand
    return None


def load_voices(path: Path | str | None = None) -> dict[str, Any]:
    """Load speaker -> voice mapping. Accepts {"speaker": "id"|{voice_id|eleven_voice_id}} or a
    legacy-style {"voices": {...}} wrapper."""
    p = Path(path) if path else find_voices_json()
    if p is None:
        return {}
    data = json.loads(Path(p).read_text(encoding="utf-8"))
    if isinstance(data, dict) and isinstance(data.get("voices"), dict):
        data = data["voices"]
    if not isinstance(data, dict):
        raise ValueError(f"{p}: expected a JSON object mapping speaker -> voice")
    return data


def find_bible(lines_path: Path | str) -> Path | None:
    """``campaigns/<slug>/bible.yaml`` for ``campaigns/<slug>/missions/<id>/lines.yaml``:
    the bible sits two levels above the mission folder."""
    mission_dir = Path(lines_path).resolve().parent
    parents = mission_dir.parents
    if len(parents) < 2:
        return None
    cand = parents[1] / BIBLE_FILE
    return cand if cand.is_file() else None


def load_bible_voices(path: Path | str) -> dict[str, VoiceProfile]:
    """Load and validate a story bible; return character id -> VoiceProfile."""
    data = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    return bible_voices(StoryBible.model_validate(data))


def merge_voices(bible: Mapping[str, VoiceProfile], fallback: Mapping[str, Any]) -> dict[str, Any]:
    """Bible ``VoiceProfile.eleven_voice_id`` wins; ``fallback`` (voices.json) fills missing ids.
    The bible's ``radio_fx`` is kept even when the id comes from the fallback."""
    merged: dict[str, Any] = dict(fallback)
    for speaker, prof in bible.items():
        if prof.eleven_voice_id:
            merged[speaker] = prof
            continue
        fb_id = voice_id_of(fallback.get(speaker)) if speaker in fallback else None
        if fb_id:
            merged[speaker] = {"eleven_voice_id": fb_id, "radio_fx": prof.radio_fx}
        else:
            merged[speaker] = prof
    return merged


def resolve_voice(speaker: str, voices: Mapping[str, Any]) -> str:
    entry = voices.get(speaker)
    vid = voice_id_of(entry) if entry is not None else None
    if not vid:
        raise KeyError(
            f"no ElevenLabs voice id for speaker {speaker!r}; set the character's "
            "VoiceProfile.eleven_voice_id in bible.yaml or add it to data/voice/voices.json"
        )
    return vid


def plan_lines(
    lines: Iterable[Any],
    voices: Mapping[str, Any],
    *,
    model: str = DEFAULT_MODEL,
    fx_preset: str = DEFAULT_FX,
    cache: TTSCache | None = None,
) -> CostEstimate:
    cache = cache or TTSCache()
    planned: list[PlannedLine] = []
    seen: set[str] = set()
    for line in lines:
        line_id, speaker, text, fx = line_fields(line)
        if line_id in seen:
            raise ValueError(f"duplicate line id {line_id!r}")
        seen.add(line_id)
        fx = fx or voice_fx_of(voices.get(speaker)) or fx_preset
        if fx not in PRESETS:
            raise ValueError(f"line {line_id!r}: unknown fx preset {fx!r}")
        raw_turns = line_turns(line)
        turns: list[PlannedTurn] | None = None
        if raw_turns:
            turns = [PlannedTurn(s, resolve_voice(s, voices), t) for s, t in raw_turns]
            vid = turns[0].voice_id
            key = dialogue_cache_key([(t.voice_id, t.text) for t in turns], model, fx)
        else:
            vid = resolve_voice(speaker, voices)
            key = cache_key(vid, model, text, fx)
        planned.append(
            PlannedLine(line_id, speaker, text, vid, fx, key, cache.get(key) is not None, turns)
        )
    todo = [p for p in planned if not p.cached]
    return CostEstimate(len(planned), len(todo), sum(p.characters for p in todo), planned)


def _synthesize(p: PlannedLine, client: Synthesizer, model: str) -> bytes:
    if p.turns:
        inputs = [{"text": t.text, "voice_id": t.voice_id} for t in p.turns]
        return client.dialogue(inputs, model=model)
    return client.synthesize(p.text, p.voice_id, model=model)


def render_lines(
    lines: Iterable[Any],
    voices: Mapping[str, Any] | None,
    out_dir: Path | str,
    dry_run: bool = False,
    *,
    model: str = DEFAULT_MODEL,
    fx_preset: str = DEFAULT_FX,
    client: Synthesizer | None = None,
    cache: TTSCache | None = None,
) -> dict[str, dict[str, Any]]:
    """Render lines; returns the manifest. In dry-run nothing is written and dur_sec is only
    filled for cache hits."""
    cache = cache or TTSCache()
    voices = load_voices() if voices is None else voices
    est = plan_lines(lines, voices, model=model, fx_preset=fx_preset, cache=cache)
    out = Path(out_dir)
    manifest: dict[str, dict[str, Any]] = {}

    if dry_run:
        print(f"[dry-run] {est.summary()}")
        for p in est.lines:
            hit = cache.meta(p.key) if p.cached else None
            manifest[p.line_id] = {
                "file": f"{p.line_id}.ogg",
                "dur_sec": hit.get("duration") if hit else None,
                "text": p.text,
                "speaker": p.speaker,
                "cached": p.cached,
            }
        return manifest

    if est.to_render and client is None:
        from .client import default_client

        client = default_client()
    out.mkdir(parents=True, exist_ok=True)
    for p in est.lines:
        cached_path = cache.get(p.key)
        if cached_path is None:
            assert client is not None
            raw = _synthesize(p, client, model)
            ogg = apply_fx(raw, p.fx)
            dur = round(duration_seconds(ogg), 2)
            meta: dict[str, Any] = {
                "text": p.text,
                "voice": p.voice_id,
                "speaker": p.speaker,
                "model": model,
                "fx": p.fx,
                "duration": dur,
            }
            if p.turns:
                meta["turns"] = [
                    {"speaker": t.speaker, "voice": t.voice_id, "text": t.text} for t in p.turns
                ]
            cached_path = cache.put(p.key, ogg, meta)
        else:
            cached_meta = cache.meta(p.key) or {}
            cached_dur = cached_meta.get("duration")
            if isinstance(cached_dur, int | float):
                dur = float(cached_dur)
            else:
                dur = round(duration_seconds(cached_path.read_bytes()), 2)
        shutil.copyfile(cached_path, out / f"{p.line_id}.ogg")
        manifest[p.line_id] = {
            "file": f"{p.line_id}.ogg",
            "dur_sec": dur,
            "text": p.text,
            "speaker": p.speaker,
        }
    (out / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    return manifest
