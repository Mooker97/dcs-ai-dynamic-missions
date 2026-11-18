"""Render a set of voice lines to ``<line_id>.ogg`` + ``manifest.json``.

The manifest ``{line_id: {file, dur_sec, text, speaker, model[, placeholder]}}`` feeds
``DMS_CONFIG.voice`` (durSec).
Lines with ``turns`` are rendered as one clip with ElevenLabs Text-to-Dialogue.
Lines with ``voiced: false`` are subtitle-only: never sent to ElevenLabs, no .ogg, no manifest
entry (the planner treats lines without a manifest ``dur_sec`` as subtitles).

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
    line_voiced,
    voice_fx_of,
    voice_id_of,
)

DEFAULT_FX = "uhf_clean"
HALF_RATE_MODELS = {"eleven_flash_v2_5": 0.5, "eleven_turbo_v2_5": 0.5}
"""Models billed at 0.5 credit per character; everything else is 1 credit per character."""
VOICES_JSON = Path("data") / "voice" / "voices.json"
BIBLE_FILE = "bible.yaml"


PLACEHOLDER_MODEL = "placeholder"
"""Offline model id: no API calls, a tone-burst clip per line sized to the text (see
:class:`PlaceholderSynth`). The model is part of the cache key, so placeholder clips never
collide with real ElevenLabs renders."""


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
    raw_key: str = ""
    fresh: bool = False
    """Force a fresh take: ignore both the final and the raw TTS cache (``--rerender``)."""

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
    offline: bool = False
    model: str = DEFAULT_MODEL
    subtitle_only: list[str] = field(default_factory=list)
    """Ids of ``voiced: false`` lines: skipped entirely, never billed."""

    @property
    def credits(self) -> int:
        """ElevenLabs credits: 1 per character (v3, multilingual), 0.5 for flash/turbo."""
        if self.offline:
            return 0
        rate = HALF_RATE_MODELS.get(self.model, 1.0)
        return round(self.characters * rate)

    def summary(self) -> str:
        cached = self.total_lines - self.to_render
        head = f"{self.total_lines} lines ({cached} cached, {self.to_render} to render): "
        tail = (
            f"; {len(self.subtitle_only)} subtitle-only (voiced: false, not billed)"
            if self.subtitle_only
            else ""
        )
        if self.offline:
            return head + "offline placeholder clips, 0 ElevenLabs credits" + tail
        return head + f"{self.characters} characters ~= {self.credits} ElevenLabs credits" + tail


class PlaceholderSynth:
    """Offline stand-in for ElevenLabs: a quiet 600 Hz tone whose length tracks the spoken text
    (~14 characters per second, 0.8-12 s). The clip goes through the same radio FX, cache, manifest
    and .miz embedding path as real TTS, so a mission can be built and tested headlessly."""

    CHARS_PER_SEC = 14.0

    def _clip(self, text: str) -> bytes:
        from .fx import tone

        secs = min(12.0, max(0.8, len(text) / self.CHARS_PER_SEC))
        return tone(round(secs, 2), 600.0)

    def synthesize(self, text: str, voice_id: str, model: str = PLACEHOLDER_MODEL) -> bytes:
        return self._clip(text)

    def dialogue(self, turns: list[dict[str, str]], model: str = PLACEHOLDER_MODEL) -> bytes:
        return self._clip(" ".join(t["text"] for t in turns))


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


def resolve_voice(speaker: str, voices: Mapping[str, Any], *, offline: bool = False) -> str:
    entry = voices.get(speaker)
    vid = voice_id_of(entry) if entry is not None else None
    if not vid and offline:
        return f"placeholder:{speaker}"
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
    rerender: Iterable[str] = (),
    no_raw_cache: bool = False,
) -> CostEstimate:
    """``rerender`` line ids (or every line with ``no_raw_cache``) skip both caches and are billed
    again: a fresh ElevenLabs take that then replaces the cached one."""
    cache = cache or TTSCache()
    offline = model == PLACEHOLDER_MODEL
    fresh_ids = set(rerender)
    planned: list[PlannedLine] = []
    subtitle_only: list[str] = []
    seen: set[str] = set()
    for line in lines:
        line_id, speaker, text, fx = line_fields(line)
        if line_id in seen:
            raise ValueError(f"duplicate line id {line_id!r}")
        seen.add(line_id)
        if not line_voiced(line):
            # Subtitle only: no voice lookup, no cache key, no billing, no audio.
            subtitle_only.append(line_id)
            continue
        fx = fx or voice_fx_of(voices.get(speaker)) or fx_preset
        if fx not in PRESETS:
            raise ValueError(f"line {line_id!r}: unknown fx preset {fx!r}")
        raw_turns = line_turns(line)
        turns: list[PlannedTurn] | None = None
        if raw_turns:
            turns = [
                PlannedTurn(s, resolve_voice(s, voices, offline=offline), t) for s, t in raw_turns
            ]
            vid = turns[0].voice_id
            inputs = [(t.voice_id, t.text) for t in turns]
            key = dialogue_cache_key(inputs, model, fx)
            rkey = dialogue_cache_key(inputs, model, "")
        else:
            vid = resolve_voice(speaker, voices, offline=offline)
            key = cache_key(vid, model, text, fx)
            rkey = cache_key(vid, model, text, "")
        fresh = no_raw_cache or line_id in fresh_ids
        cached = not fresh and cache.get(key) is not None
        planned.append(
            PlannedLine(line_id, speaker, text, vid, fx, key, cached, turns, rkey, fresh)
        )
    unknown = sorted(fresh_ids - seen)
    if unknown:
        raise ValueError(f"--rerender: unknown line id(s) {unknown}")
    # Lines whose raw TTS is cached (only the FX changed) cost nothing to re-render.
    todo = [p for p in planned if not p.cached and (p.fresh or cache.get_raw(p.raw_key) is None)]
    chars = sum(p.characters for p in todo)
    return CostEstimate(len(planned), len(todo), chars, planned, offline, model, subtitle_only)


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
    rerender: Iterable[str] = (),
    no_raw_cache: bool = False,
) -> dict[str, dict[str, Any]]:
    """Render lines; returns the manifest. In dry-run nothing is written and dur_sec is only
    filled for cache hits. ``rerender``/``no_raw_cache``: see :func:`plan_lines`."""
    cache = cache or TTSCache()
    voices = load_voices() if voices is None else voices
    est = plan_lines(
        lines,
        voices,
        model=model,
        fx_preset=fx_preset,
        cache=cache,
        rerender=rerender,
        no_raw_cache=no_raw_cache,
    )
    placeholder = model == PLACEHOLDER_MODEL
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
                "model": model,
                "cached": p.cached,
            }
            if placeholder:
                manifest[p.line_id]["placeholder"] = True
        return manifest

    if est.to_render and client is None and model == PLACEHOLDER_MODEL:
        client = PlaceholderSynth()
    if est.to_render and client is None:
        from .client import default_client

        client = default_client()
    out.mkdir(parents=True, exist_ok=True)
    for line_id in est.subtitle_only:
        # A line switched to voiced: false must not keep an old take next to the manifest.
        (out / f"{line_id}.ogg").unlink(missing_ok=True)
    for p in est.lines:
        cached_path = None if p.fresh else cache.get(p.key)
        if cached_path is None:
            raw = None if p.fresh else cache.get_raw(p.raw_key)
            if raw is None:
                assert client is not None
                raw = _synthesize(p, client, model)
                cache.put_raw(p.raw_key, raw)
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
            "model": model,
        }
        if placeholder:
            manifest[p.line_id]["placeholder"] = True
    (out / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    return manifest
