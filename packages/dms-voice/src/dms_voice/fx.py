"""Radio FX via ffmpeg filtergraphs (bundled binary from imageio-ffmpeg).

Presets band-limit to the voice band, compress, add light overdrive, optionally lay a noise bed,
and wrap the line in a short squelch click (lead) and squelch tail. Output defaults to mono
OGG Vorbis at 22.05 kHz, which DCS plays happily via ``trigger.action.outSound*``.
"""

from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass
from functools import lru_cache
from typing import Literal

OutputFormat = Literal["ogg", "wav"]


class FFmpegError(RuntimeError):
    pass


@dataclass(frozen=True)
class FxPreset:
    name: str
    highpass_hz: float | None = None
    lowpass_hz: float | None = None
    comp_ratio: float = 1.0
    drive_db: float = 0.0
    noise_amp: float = 0.0
    lead_s: float = 0.0
    tail_s: float = 0.0
    squelch_amp: float = 0.0


PRESETS: dict[str, FxPreset] = {
    "none": FxPreset("none"),
    "uhf_clean": FxPreset(
        "uhf_clean",
        highpass_hz=300,
        lowpass_hz=3400,
        comp_ratio=4,
        drive_db=4,
        noise_amp=0.0,
        lead_s=0.04,
        tail_s=0.12,
        squelch_amp=0.12,
    ),
    "vhf_noisy": FxPreset(
        "vhf_noisy",
        highpass_hz=350,
        lowpass_hz=3000,
        comp_ratio=6,
        drive_db=8,
        noise_amp=0.025,
        lead_s=0.05,
        tail_s=0.18,
        squelch_amp=0.25,
    ),
    "intercom": FxPreset(
        "intercom",
        highpass_hz=250,
        lowpass_hz=4000,
        comp_ratio=3,
        drive_db=2,
        noise_amp=0.004,
        lead_s=0.0,
        tail_s=0.0,
        squelch_amp=0.0,
    ),
}


DEFAULT_SAMPLE_RATE = 22050
"""Output sample rate of :func:`apply_fx` (part of :func:`fx_signature`)."""
OGG_CODEC_ARGS: tuple[str, ...] = ("-c:a", "libvorbis", "-q:a", "4", "-f", "ogg")
"""ffmpeg encoder args for the final .ogg (part of :func:`fx_signature`)."""


def fx_signature(preset: str, sample_rate: int = DEFAULT_SAMPLE_RATE) -> str:
    """Short hash of everything that shapes a preset's output: its parameters, the output sample
    rate and the codec args. The final (post-FX) cache key includes it, so re-tuning a preset
    invalidates the old clips; the raw TTS key does not, so the re-render costs 0 credits."""
    import hashlib
    from dataclasses import asdict

    params = asdict(PRESETS[preset]) if preset in PRESETS else {"name": preset}
    blob = json.dumps(
        {"preset": params, "sample_rate": sample_rate, "codec": list(OGG_CODEC_ARGS)},
        sort_keys=True,
        separators=(",", ":"),
    )
    return hashlib.sha256(blob.encode()).hexdigest()[:12]


@lru_cache(maxsize=1)
def ffmpeg_exe() -> str:
    import imageio_ffmpeg  # type: ignore[import-untyped,unused-ignore]

    return str(imageio_ffmpeg.get_ffmpeg_exe())


def run_ffmpeg(args: list[str], stdin: bytes | None = None) -> bytes:
    cmd = [ffmpeg_exe(), "-hide_banner", "-loglevel", "error", "-nostdin", *args]
    if stdin is not None:
        cmd.remove("-nostdin")
    proc = subprocess.run(cmd, input=stdin, capture_output=True, check=False)
    if proc.returncode != 0:
        msg = proc.stderr.decode(errors="replace").strip()
        raise FFmpegError(f"ffmpeg failed ({proc.returncode}): {msg}")
    return proc.stdout


def _fmt(sr: int) -> str:
    return f"aformat=sample_fmts=fltp:sample_rates={sr}:channel_layouts=mono"


def _squelch(label: str, dur: float, amp: float, sr: int, hp: float, lp: float) -> str:
    fade = max(dur * 0.6, 0.01)
    return (
        f"anoisesrc=d={dur}:c=white:a={amp}:r={sr},highpass=f={hp},lowpass=f={lp},"
        f"afade=t=out:st={dur - fade:.3f}:d={fade:.3f},{_fmt(sr)}[{label}]"
    )


def build_filtergraph(preset: FxPreset, sample_rate: int) -> str:
    sr = sample_rate
    chain = [f"[0:a]aresample={sr}", _fmt(sr)]
    if preset.highpass_hz:
        chain += [f"highpass=f={preset.highpass_hz}", f"highpass=f={preset.highpass_hz}"]
    if preset.lowpass_hz:
        chain += [f"lowpass=f={preset.lowpass_hz}", f"lowpass=f={preset.lowpass_hz}"]
    if preset.comp_ratio > 1:
        chain.append(
            f"acompressor=threshold=0.1:ratio={preset.comp_ratio}:attack=5:release=60:makeup=2"
        )
    if preset.drive_db > 0:
        chain += [
            f"volume={preset.drive_db}dB",
            "asoftclip=type=tanh",
            f"volume=-{preset.drive_db / 2}dB",
        ]
    parts = [",".join(chain) + "[v0]"]
    cur = "v0"
    hp = preset.highpass_hz or 300
    lp = preset.lowpass_hz or 3400
    if preset.noise_amp > 0:
        parts.append(
            f"anoisesrc=c=pink:a={preset.noise_amp}:r={sr},highpass=f={hp},lowpass=f={lp},"
            f"{_fmt(sr)}[nz]"
        )
        parts.append(f"[{cur}][nz]amix=inputs=2:duration=first:normalize=0[v1]")
        cur = "v1"
    segs: list[str] = []
    if preset.lead_s > 0 and preset.squelch_amp > 0:
        parts.append(_squelch("lead", preset.lead_s, preset.squelch_amp, sr, hp, lp))
        segs.append("[lead]")
    segs.append(f"[{cur}]")
    if preset.tail_s > 0 and preset.squelch_amp > 0:
        parts.append(_squelch("tail", preset.tail_s, preset.squelch_amp, sr, hp, lp))
        segs.append("[tail]")
    if len(segs) > 1:
        parts.append(f"{''.join(segs)}concat=n={len(segs)}:v=0:a=1[out]")
    else:
        parts.append(f"[{cur}]anull[out]")
    return ";".join(parts)


def apply_fx(
    in_bytes: bytes,
    preset: str = "uhf_clean",
    *,
    output_format: OutputFormat = "ogg",
    sample_rate: int = DEFAULT_SAMPLE_RATE,
) -> bytes:
    """Apply a radio preset to any ffmpeg-readable audio (mp3/wav/...) and return encoded bytes."""
    if preset not in PRESETS:
        raise ValueError(f"unknown fx preset {preset!r}; choose from {sorted(PRESETS)}")
    graph = build_filtergraph(PRESETS[preset], sample_rate)
    codec = (
        list(OGG_CODEC_ARGS)
        if output_format == "ogg"
        else [
            "-c:a",
            "pcm_s16le",
            "-f",
            "wav",
        ]
    )
    args = [
        "-i",
        "pipe:0",
        "-filter_complex",
        graph,
        "-map",
        "[out]",
        "-ac",
        "1",
        "-ar",
        str(sample_rate),
        *codec,
        "pipe:1",
    ]
    return run_ffmpeg(args, stdin=in_bytes)


def duration_seconds(audio: bytes) -> float:
    """Exact duration by decoding to 8 kHz mono s16 PCM and counting samples."""
    rate = 8000
    pcm = run_ffmpeg(
        [
            "-i",
            "pipe:0",
            "-ac",
            "1",
            "-ar",
            str(rate),
            "-f",
            "s16le",
            "-c:a",
            "pcm_s16le",
            "pipe:1",
        ],
        stdin=audio,
    )
    return len(pcm) / 2 / rate


def concat_audio(chunks: list[bytes], *, gap_s: float = 0.3) -> bytes:
    """Concatenate encoded clips (any format) into one WAV with short gaps between them."""
    import tempfile
    from pathlib import Path

    if not chunks:
        raise ValueError("nothing to concatenate")
    with tempfile.TemporaryDirectory() as td:
        args: list[str] = []
        for i, chunk in enumerate(chunks):
            p = Path(td) / f"c{i}.bin"
            p.write_bytes(chunk)
            args += ["-i", str(p)]
        sr = 44100
        parts: list[str] = []
        labels: list[str] = []
        for i in range(len(chunks)):
            pad = f",apad=pad_dur={gap_s}" if i < len(chunks) - 1 else ""
            parts.append(f"[{i}:a]aresample={sr},{_fmt(sr)}{pad}[a{i}]")
            labels.append(f"[a{i}]")
        parts.append(f"{''.join(labels)}concat=n={len(chunks)}:v=0:a=1[out]")
        return run_ffmpeg(
            [
                *args,
                "-filter_complex",
                ";".join(parts),
                "-map",
                "[out]",
                "-c:a",
                "pcm_s16le",
                "-f",
                "wav",
                "pipe:1",
            ]
        )


def tone(seconds: float = 1.0, freq: float = 1000.0, sample_rate: int = 44100) -> bytes:
    """Generate a sine test tone as WAV bytes (used by tests)."""
    return run_ffmpeg(
        [
            "-f",
            "lavfi",
            "-i",
            f"sine=frequency={freq}:duration={seconds}:sample_rate={sample_rate}",
            "-ac",
            "1",
            "-c:a",
            "pcm_s16le",
            "-f",
            "wav",
            "pipe:1",
        ]
    )
