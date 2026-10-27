from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

import pytest
from dms_voice import cli
from dms_voice.cache import TTSCache, cache_key, default_root
from dms_voice.client import (
    MissingApiKeyError,
    VoiceApiError,
    VoiceClient,
    load_api_key,
    with_retries,
)
from dms_voice.fx import PRESETS, apply_fx, duration_seconds, tone
from dms_voice.render import render_lines

VOICES = {"ops_mustang": "vid_mustang", "dusty": {"eleven_voice_id": "vid_dusty"}}
LINES = [
    {"id": "l1", "speaker": "ops_mustang", "text": "Dusty, Mustang. Radio check, over."},
    {"id": "l2", "speaker": "dusty", "text": "Loud and clear.", "fx": "vhf_noisy"},
]


class FakeClient:
    def __init__(self) -> None:
        self.calls: list[tuple[str, str, str]] = []
        self._wav = tone(0.5, 440)

    def synthesize(self, text: str, voice_id: str, model: str = "eleven_v3") -> bytes:
        self.calls.append((text, voice_id, model))
        return self._wav


@pytest.fixture
def cache(tmp_path: Path) -> TTSCache:
    return TTSCache(tmp_path / "cache")


# ---- cache ---------------------------------------------------------------


def test_cache_key_matches_contract() -> None:
    expected = hashlib.sha256(b"v|eleven_v3|hello|uhf_clean").hexdigest()
    assert cache_key("v", "eleven_v3", "hello", "uhf_clean") == expected
    assert cache_key("v", "eleven_v3", "hello", "none") != expected
    assert cache_key("v2", "eleven_v3", "hello", "uhf_clean") != expected


def test_cache_env_override(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setenv("DMS_TTS_CACHE", str(tmp_path))
    assert default_root() == tmp_path
    monkeypatch.delenv("DMS_TTS_CACHE")
    assert default_root() == Path.home() / ".dms" / "tts-cache"


def test_cache_put_get(cache: TTSCache) -> None:
    key = cache_key("v", "m", "t", "none")
    assert cache.get(key) is None
    path = cache.put(key, b"OggS...", {"text": "t", "duration": 1.0})
    assert cache.get(key) == path and path.name == f"{key}.ogg"
    assert cache.meta(key) == {"key": key, "text": "t", "duration": 1.0}


# ---- fx ------------------------------------------------------------------


@pytest.mark.parametrize("preset", sorted(PRESETS))
def test_fx_produces_ogg_with_expected_duration(preset: str) -> None:
    src = tone(1.0, 1000)
    out = apply_fx(src, preset)
    assert out[:4] == b"OggS"
    p = PRESETS[preset]
    extra = (p.lead_s + p.tail_s) if p.squelch_amp > 0 else 0.0
    assert duration_seconds(out) == pytest.approx(1.0 + extra, abs=0.06)


def test_fx_wav_output_and_unknown_preset() -> None:
    out = apply_fx(tone(0.3), "intercom", output_format="wav", sample_rate=44100)
    assert out[:4] == b"RIFF"
    assert duration_seconds(out) == pytest.approx(0.3, abs=0.03)
    with pytest.raises(ValueError):
        apply_fx(b"", "nope")


# ---- render --------------------------------------------------------------


def test_render_pipeline_and_cache_hits(tmp_path: Path, cache: TTSCache) -> None:
    fake = FakeClient()
    out = tmp_path / "voice"
    manifest = render_lines(LINES, VOICES, out, client=fake, cache=cache)
    assert len(fake.calls) == 2
    assert {c[1] for c in fake.calls} == {"vid_mustang", "vid_dusty"}
    assert set(manifest) == {"l1", "l2"}
    assert manifest["l1"]["file"] == "l1.ogg"
    assert manifest["l1"]["speaker"] == "ops_mustang"
    assert manifest["l1"]["dur_sec"] == pytest.approx(0.5 + 0.16, abs=0.06)
    assert (out / "l1.ogg").read_bytes()[:4] == b"OggS"
    assert json.loads((out / "manifest.json").read_text()) == manifest

    out2 = tmp_path / "voice2"
    manifest2 = render_lines(LINES, VOICES, out2, client=fake, cache=cache)
    assert len(fake.calls) == 2  # all cache hits
    assert manifest2 == manifest

    changed = [*LINES[:1], {**LINES[1], "text": "Five by five."}]
    render_lines(changed, VOICES, out2, client=fake, cache=cache)
    assert len(fake.calls) == 3


def test_dry_run_estimates_cost(
    tmp_path: Path, cache: TTSCache, capsys: pytest.CaptureFixture[str]
) -> None:
    fake = FakeClient()
    render_lines(LINES[:1], VOICES, tmp_path / "a", client=fake, cache=cache)
    calls = len(fake.calls)
    manifest = render_lines(LINES, VOICES, tmp_path / "b", dry_run=True, client=fake, cache=cache)
    assert len(fake.calls) == calls
    assert not (tmp_path / "b").exists()
    text = capsys.readouterr().out
    assert f"{len(LINES[1]['text'])} characters" in text
    assert "1 cached, 1 to render" in text
    assert manifest["l1"]["cached"] is True and manifest["l1"]["dur_sec"] is not None
    assert manifest["l2"]["cached"] is False and manifest["l2"]["dur_sec"] is None


def test_render_unknown_speaker(tmp_path: Path, cache: TTSCache) -> None:
    with pytest.raises(KeyError, match="nobody"):
        render_lines(
            [{"id": "x", "speaker": "nobody", "text": "hi"}],
            VOICES,
            tmp_path,
            client=FakeClient(),
            cache=cache,
        )


def test_cli_dry_run(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setenv("DMS_TTS_CACHE", str(tmp_path / "c"))
    lines = tmp_path / "lines.yaml"
    lines.write_text(
        "lines:\n  - {id: a, speaker: ops_mustang, text: Splash HVT.}\n", encoding="utf-8"
    )
    voices = tmp_path / "voices.json"
    voices.write_text(json.dumps({"voices": {"ops_mustang": {"voice_id": "v"}}}))
    assert cli.main([str(lines), "--voices", str(voices), "--dry-run"]) == 0
    assert "11 characters" in capsys.readouterr().out


# ---- client --------------------------------------------------------------


def test_missing_key_error(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.delenv("ELEVENLABS_API_KEY", raising=False)
    monkeypatch.chdir(tmp_path)  # no .env reachable... unless a parent has one
    monkeypatch.setattr("dotenv.find_dotenv", lambda *a, **k: "")
    with pytest.raises(MissingApiKeyError, match="ELEVENLABS_API_KEY"):
        load_api_key()
    with pytest.raises(MissingApiKeyError):
        VoiceClient().synthesize("hi", "v")


def test_retries_then_succeeds_and_gives_up() -> None:
    class Err(Exception):
        def __init__(self, status: int) -> None:
            self.status_code = status

    attempts: list[int] = []
    sleeps: list[float] = []

    def flaky() -> bytes:
        attempts.append(1)
        if len(attempts) < 3:
            raise Err(429)
        return b"ok"

    assert with_retries(flaky, sleep=sleeps.append) == b"ok"
    assert sleeps == [1.0, 2.0]

    def bad() -> bytes:
        raise Err(401)

    with pytest.raises(VoiceApiError, match="401"):
        with_retries(bad, sleep=sleeps.append)


def test_client_uses_sdk_mock() -> None:
    class TTS:
        def convert(self, voice_id: str, **kw: Any) -> Any:
            assert kw["model_id"] == "eleven_v3"
            return iter([b"ab", b"cd"])

    class SDK:
        text_to_speech = TTS()

    assert VoiceClient(sdk=SDK()).synthesize("hi", "v") == b"abcd"


def test_voice_profile_fx_default(tmp_path: Path, cache: TTSCache) -> None:
    from dms_voice.models import VoiceProfile
    from dms_voice.render import plan_lines

    prof = VoiceProfile(eleven_voice_id="vp", design_prompt="calm male", radio_fx="intercom")
    est = plan_lines([{"id": "a", "speaker": "p", "text": "hi"}], {"p": prof}, cache=cache)
    assert est.lines[0].voice_id == "vp" and est.lines[0].fx == "intercom"
