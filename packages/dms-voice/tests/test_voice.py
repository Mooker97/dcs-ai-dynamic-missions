from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

import pytest
import yaml  # type: ignore[import-untyped,unused-ignore]
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
    {"id": "l2", "speaker": "dusty", "text": "Loud and clear.", "radio_fx": "vhf_noisy"},
]
REPO = Path(__file__).resolve().parents[3]


class FakeClient:
    def __init__(self) -> None:
        self.calls: list[tuple[str, str, str]] = []
        self.dialogue_calls: list[tuple[list[dict[str, str]], str]] = []
        self._wav = tone(0.5, 440)

    def synthesize(self, text: str, voice_id: str, model: str = "eleven_v3") -> bytes:
        self.calls.append((text, voice_id, model))
        return self._wav

    def dialogue(self, turns: list[dict[str, str]], model: str = "eleven_v3") -> bytes:
        self.dialogue_calls.append((turns, model))
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


# ---- audit fixes: radio_fx, dialogue, model, bible voices ----------------


def test_line_radio_fx_overrides_speaker_and_default(cache: TTSCache) -> None:
    from dms_voice.models import VoiceLine, VoiceProfile
    from dms_voice.render import plan_lines

    prof = VoiceProfile(eleven_voice_id="vp", design_prompt="x", radio_fx="intercom")
    lines: list[Any] = [
        VoiceLine(id="a", speaker="p", text="hi", radio_fx="vhf_noisy"),
        VoiceLine(id="b", speaker="p", text="hi"),
        {"id": "c", "speaker": "q", "text": "hi", "radio_fx": "none"},
    ]
    est = plan_lines(lines, {"p": prof, "q": "vq"}, cache=cache)
    assert [p.fx for p in est.lines] == ["vhf_noisy", "intercom", "none"]


TURN_A = {"speaker": "dusty", "text": "Ops, Dusty, contact north."}
TURN_B = {"speaker": "ops_mustang", "text": "Copy, cleared hot."}
DIALOGUE: dict[str, Any] = {"id": "x1", "turns": [TURN_A, TURN_B]}


def test_dialogue_line_uses_text_to_dialogue_and_caches(tmp_path: Path, cache: TTSCache) -> None:
    from dms_voice.cache import dialogue_cache_key
    from dms_voice.models import VoiceLine

    line = VoiceLine.model_validate(DIALOGUE)
    assert line.speaker == "dusty"
    fake = FakeClient()
    manifest = render_lines([line, LINES[0]], VOICES, tmp_path / "v", client=fake, cache=cache)
    assert len(fake.dialogue_calls) == 1 and len(fake.calls) == 1
    turns, model = fake.dialogue_calls[0]
    assert model == "eleven_v3"
    assert turns == [
        {"text": TURN_A["text"], "voice_id": "vid_dusty"},
        {"text": TURN_B["text"], "voice_id": "vid_mustang"},
    ]
    assert manifest["x1"]["file"] == "x1.ogg" and manifest["x1"]["speaker"] == "dusty"
    key = dialogue_cache_key(
        [("vid_dusty", TURN_A["text"]), ("vid_mustang", TURN_B["text"])], "eleven_v3", "uhf_clean"
    )
    assert cache.get(key) is not None
    meta = cache.meta(key)
    assert meta is not None and len(meta["turns"]) == 2

    render_lines([line], VOICES, tmp_path / "v2", client=fake, cache=cache)
    assert len(fake.dialogue_calls) == 1  # cache hit

    changed = VoiceLine.model_validate(
        {"id": "x1", "turns": [TURN_A, {"speaker": "ops_mustang", "text": "Copy."}]}
    )
    render_lines([changed], VOICES, tmp_path / "v3", client=fake, cache=cache)
    assert len(fake.dialogue_calls) == 2


def test_dialogue_cost_counts_turn_characters(cache: TTSCache) -> None:
    from dms_voice.render import plan_lines

    est = plan_lines([{**DIALOGUE, "speaker": "dusty", "text": "t"}], VOICES, cache=cache)
    assert est.characters == len(TURN_A["text"]) + len(TURN_B["text"])


def test_dialogue_unknown_turn_speaker(cache: TTSCache) -> None:
    from dms_voice.render import plan_lines

    bad = {
        "id": "x",
        "speaker": "dusty",
        "text": "t",
        "turns": [TURN_A, {"speaker": "ghost", "text": "b"}],
    }
    with pytest.raises(KeyError, match="ghost"):
        plan_lines([bad], VOICES, cache=cache)


def test_client_dialogue_uses_sdk_mock() -> None:
    seen: dict[str, Any] = {}

    class TTD:
        def convert(self, **kw: Any) -> Any:
            seen.update(kw)
            return iter([b"ab", b"cd"])

    class SDK:
        text_to_dialogue = TTD()

    turns = [{"text": "a", "voice_id": "v1"}, {"text": "b", "voice_id": "v2"}]
    assert VoiceClient(sdk=SDK()).dialogue(turns, model="eleven_v3") == b"abcd"
    assert seen["model_id"] == "eleven_v3"
    assert [(i.text, i.voice_id) for i in seen["inputs"]] == [("a", "v1"), ("b", "v2")]


def _capture_render(monkeypatch: pytest.MonkeyPatch) -> dict[str, Any]:
    seen: dict[str, Any] = {}

    def fake_render(lines: Any, voices: Any, out: Any, **kw: Any) -> dict[str, Any]:
        seen.update(kw, voices=voices, lines=list(lines))
        return {}

    monkeypatch.setattr(cli, "render_lines", fake_render)
    return seen


def test_cli_model_from_lines_yaml_and_flag_override(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    seen = _capture_render(monkeypatch)
    lines = tmp_path / "lines.yaml"
    lines.write_text(
        "model: eleven_flash_v2_5\nlines:\n  - {id: a, speaker: s, text: Hi.}\n", encoding="utf-8"
    )
    voices = tmp_path / "voices.json"
    voices.write_text(json.dumps({"s": "v"}))
    assert cli.main([str(lines), "--voices", str(voices), "--dry-run"]) == 0
    assert seen["model"] == "eleven_flash_v2_5"
    argv = [str(lines), "--voices", str(voices), "--dry-run", "--model", "eleven_v3"]
    assert cli.main(argv) == 0
    assert seen["model"] == "eleven_v3"


def _campaign(tmp_path: Path) -> Path:
    template = REPO / "campaigns" / "_template" / "bible.yaml"
    bible = yaml.safe_load(template.read_text(encoding="utf-8"))
    base = bible["characters"][0]
    ops_voice = {**base["voice"], "eleven_voice_id": "bible_ops", "radio_fx": "vhf_noisy"}
    wing_voice = {**base["voice"], "eleven_voice_id": None, "radio_fx": "intercom"}
    bible["characters"] = [
        {**base, "id": "ops_main", "voice": ops_voice},
        {**base, "id": "wing", "voice": wing_voice},
    ]
    camp = tmp_path / "campaigns" / "demo"
    mission = camp / "missions" / "m01-x"
    mission.mkdir(parents=True)
    (camp / "bible.yaml").write_text(yaml.safe_dump(bible), encoding="utf-8")
    lines = mission / "lines.yaml"
    lines.write_text(
        "lines:\n"
        "  - {id: a, speaker: ops_main, text: Cleared.}\n"
        "  - {id: b, speaker: wing, text: Two.}\n"
        "  - {id: c, speaker: extra, text: Three.}\n",
        encoding="utf-8",
    )
    return lines


def test_bible_voice_ids_with_voices_json_fallback(tmp_path: Path) -> None:
    from dms_voice.render import find_bible, plan_lines

    lines = _campaign(tmp_path)
    assert find_bible(lines) == (tmp_path / "campaigns" / "demo" / "bible.yaml").resolve()
    voices_json = tmp_path / "voices.json"
    voices_json.write_text(
        json.dumps({"ops_main": "json_ops", "wing": "json_wing", "extra": "json_extra"})
    )
    voices = cli.resolve_voices(lines, voices_json)
    est = plan_lines(cli.load_lines(lines), voices, cache=TTSCache(tmp_path / "c"))
    got = {p.line_id: (p.voice_id, p.fx) for p in est.lines}
    assert got == {
        "a": ("bible_ops", "vhf_noisy"),  # bible id wins over voices.json
        "b": ("json_wing", "intercom"),  # no bible id: voices.json id, bible radio_fx
        "c": ("json_extra", "uhf_clean"),  # not in bible
    }


def test_bible_voice_without_any_id_errors(tmp_path: Path) -> None:
    from dms_voice.render import plan_lines

    lines = _campaign(tmp_path)
    empty = tmp_path / "empty.json"
    empty.write_text("{}")
    voices = cli.resolve_voices(lines, empty)
    with pytest.raises(KeyError, match="wing"):
        plan_lines(cli.load_lines(lines)[:2], voices, cache=TTSCache(tmp_path / "c"))


def test_cli_uses_bible_voices(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    seen = _capture_render(monkeypatch)
    lines = _campaign(tmp_path)
    empty = tmp_path / "empty.json"
    empty.write_text("{}")
    assert cli.main([str(lines), "--voices", str(empty), "--dry-run"]) == 0
    assert seen["voices"]["ops_main"].eleven_voice_id == "bible_ops"
    assert seen["model"] == "eleven_v3"
