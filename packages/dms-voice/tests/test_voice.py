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
from dms_voice.fx import PRESETS, apply_fx, duration_seconds, fx_signature, tone
from dms_voice.render import PLACEHOLDER_MODEL, plan_lines, render_lines

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
    sig = fx_signature("uhf_clean")
    assert len(sig) == 12
    expected = hashlib.sha256(f"v|eleven_v3|hello|uhf_clean@{sig}".encode()).hexdigest()
    assert cache_key("v", "eleven_v3", "hello", "uhf_clean") == expected
    raw = hashlib.sha256(b"v|eleven_v3|hello|").hexdigest()
    assert cache_key("v", "eleven_v3", "hello", "") == raw  # raw key is FX-independent
    assert cache_key("v", "eleven_v3", "hello", "none") != expected
    assert cache_key("v2", "eleven_v3", "hello", "uhf_clean") != expected


def test_final_key_tracks_preset_params(monkeypatch: pytest.MonkeyPatch) -> None:
    import dataclasses

    from dms_voice import fx as fxmod
    from dms_voice.cache import dialogue_cache_key

    before = cache_key("v", "m", "t", "uhf_clean")
    raw_before = cache_key("v", "m", "t", "")
    dia_before = dialogue_cache_key([("v", "t")], "m", "uhf_clean")
    assert fx_signature("uhf_clean", 44100) != fx_signature("uhf_clean")
    tuned = dataclasses.replace(PRESETS["uhf_clean"], drive_db=6)
    monkeypatch.setitem(fxmod.PRESETS, "uhf_clean", tuned)
    assert cache_key("v", "m", "t", "uhf_clean") != before
    assert dialogue_cache_key([("v", "t")], "m", "uhf_clean") != dia_before
    assert cache_key("v", "m", "t", "") == raw_before
    intercom = fx_signature("intercom")
    monkeypatch.setattr(fxmod, "OGG_CODEC_ARGS", ("-c:a", "libvorbis", "-q:a", "6", "-f", "ogg"))
    assert fx_signature("intercom") != intercom


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


# ---- raw cache, offline placeholder, credits -------------------------------


def test_fx_change_reuses_raw_tts_without_api_call(tmp_path: Path, cache: TTSCache) -> None:
    fake = FakeClient()
    render_lines(LINES[:1], VOICES, tmp_path / "a", client=fake, cache=cache)
    assert len(fake.calls) == 1
    est = plan_lines(LINES[:1], VOICES, fx_preset="vhf_noisy", cache=cache)
    assert est.to_render == 0 and est.characters == 0  # raw TTS cached: FX re-run is free
    m = render_lines(
        LINES[:1], VOICES, tmp_path / "b", fx_preset="vhf_noisy", client=fake, cache=cache
    )
    assert len(fake.calls) == 1
    assert (tmp_path / "b" / "l1.ogg").read_bytes()[:4] == b"OggS"
    assert m["l1"]["dur_sec"] > 0


def test_offline_placeholder_needs_no_voice_ids_or_key(
    tmp_path: Path, cache: TTSCache, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.delenv("ELEVENLABS_API_KEY", raising=False)
    lines = [*LINES, {"id": "l3", "speaker": "stranger", "text": "No voice id for me at all."}]
    est = plan_lines(lines, {}, model=PLACEHOLDER_MODEL, cache=cache)
    assert est.credits == 0 and "0 ElevenLabs credits" in est.summary()
    m = render_lines(lines, {}, tmp_path / "v", model=PLACEHOLDER_MODEL, cache=cache)
    assert set(m) == {"l1", "l2", "l3"}
    for lid, entry in m.items():
        assert (tmp_path / "v" / f"{lid}.ogg").read_bytes()[:4] == b"OggS"
        assert 0.8 <= entry["dur_sec"] <= 13
    # the model is in the key, so placeholders never satisfy a real render
    assert plan_lines(LINES, VOICES, cache=cache).to_render == 2


def test_cli_offline_flag_and_env(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setenv("DMS_TTS_CACHE", str(tmp_path / "c"))
    monkeypatch.delenv("ELEVENLABS_API_KEY", raising=False)
    lines = tmp_path / "m" / "lines.yaml"
    lines.parent.mkdir()
    lines.write_text("lines:\n  - {id: a, speaker: nobody, text: Splash HVT.}\n", encoding="utf-8")
    none = tmp_path / "none.json"
    none.write_text("{}", encoding="utf-8")
    assert cli.main([str(lines), "--voices", str(none)]) == 2  # no voice id, no --offline
    assert cli.main([str(lines), "--offline", "--voices", str(none)]) == 0
    monkeypatch.setenv("DMS_VOICE_OFFLINE", "1")
    assert cli.main([str(lines), "--voices", str(none)]) == 0
    manifest = json.loads((lines.parent / "voice" / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["a"]["file"] == "a.ogg" and manifest["a"]["dur_sec"] > 0
    assert "wrote 1 lines" in capsys.readouterr().out


def test_flash_model_costs_half_credits(cache: TTSCache) -> None:
    v3 = plan_lines(LINES, VOICES, cache=cache)
    flash = plan_lines(LINES, VOICES, model="eleven_flash_v2_5", cache=cache)
    assert v3.credits == v3.characters
    assert flash.credits == round(flash.characters * 0.5)
    assert f"~= {flash.credits} ElevenLabs credits" in flash.summary()


def test_manifest_records_model_and_placeholder(tmp_path: Path, cache: TTSCache) -> None:
    m = render_lines(LINES[:1], VOICES, tmp_path / "a", client=FakeClient(), cache=cache)
    assert m["l1"]["model"] == "eleven_v3" and "placeholder" not in m["l1"]
    disk = json.loads((tmp_path / "a" / "manifest.json").read_text(encoding="utf-8"))
    assert disk["l1"]["model"] == "eleven_v3"
    m = render_lines(LINES[:1], {}, tmp_path / "b", model=PLACEHOLDER_MODEL, cache=cache)
    assert m["l1"]["model"] == PLACEHOLDER_MODEL and m["l1"]["placeholder"] is True
    dry = render_lines(LINES[:1], {}, tmp_path / "c", True, model=PLACEHOLDER_MODEL, cache=cache)
    assert dry["l1"]["placeholder"] is True


def test_rerender_forces_fresh_take(tmp_path: Path, cache: TTSCache) -> None:
    fake = FakeClient()
    render_lines(LINES, VOICES, tmp_path / "a", client=fake, cache=cache)
    assert len(fake.calls) == 2
    est = plan_lines(LINES, VOICES, cache=cache, rerender=["l2"])
    assert est.to_render == 1 and est.characters == len(LINES[1]["text"])
    render_lines(LINES, VOICES, tmp_path / "b", client=fake, cache=cache, rerender=["l2"])
    assert [c[0] for c in fake.calls[2:]] == [LINES[1]["text"]]
    render_lines(LINES, VOICES, tmp_path / "c", client=fake, cache=cache)
    assert len(fake.calls) == 3  # the fresh take replaced the cached one
    render_lines(LINES, VOICES, tmp_path / "d", client=fake, cache=cache, no_raw_cache=True)
    assert len(fake.calls) == 5
    with pytest.raises(ValueError, match="unknown line id"):
        plan_lines(LINES, VOICES, cache=cache, rerender=["nope"])


def test_cli_rerender_and_offline_model_warning(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    seen = _capture_render(monkeypatch)
    lines = tmp_path / "lines.yaml"
    lines.write_text("lines:\n  - {id: a, speaker: s, text: Hi.}\n", encoding="utf-8")
    none = tmp_path / "none.json"
    none.write_text("{}", encoding="utf-8")
    argv = [str(lines), "--voices", str(none), "--rerender", "a", "--rerender", "b"]
    assert cli.main([*argv, "--no-raw-cache"]) == 0
    assert seen["rerender"] == ["a", "b"] and seen["no_raw_cache"] is True
    assert cli.main([str(lines), "--voices", str(none), "--offline", "--model", "eleven_v3"]) == 0
    assert seen["model"] == PLACEHOLDER_MODEL
    assert "offline mode ignores --model eleven_v3" in capsys.readouterr().err


@pytest.mark.parametrize(
    ("value", "offline"),
    [
        ("1", True),
        ("true", True),
        ("YES", True),
        ("on", True),
        ("0", False),
        ("false", False),
        ("no", False),
        ("off", False),
        ("", False),
    ],
)
def test_env_offline_truthy_only(
    monkeypatch: pytest.MonkeyPatch, value: str, offline: bool
) -> None:
    monkeypatch.setenv("DMS_VOICE_OFFLINE", value)
    assert cli.env_offline() is offline
