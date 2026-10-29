"""Generate an image with ElevenLabs Image & Video (``POST /v1/flows/image``).

The API is asynchronous: create a generation, poll ``GET /v1/flows/image/{id}`` until it is
``completed`` or ``failed``, then download ``content_url`` (a signed URL that expires in ~1 h).

The key is read from ``ELEVENLABS_API_KEY`` (the environment first, then ``DMS/.env``). It needs
the ``image_video_generation`` permission, and the account needs a Pro plan or above. The key is
never printed or logged.

Responses carry no cost field. If the key also has ``user_read``, the credits used are measured
from ``/v1/user/subscription`` before and after; otherwise they are reported as unknown.

Usage::

    uv run python tools/image_gen/elevenlabs_image.py --prompt "..." --out briefing.png
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

API = "https://api.elevenlabs.io"
DEFAULT_MODEL = "gemini-3.1-flash-lite-image"
MODELS = (
    "gemini-3.1-flash-lite-image",
    "gemini-3.1-flash-image",
    "gemini-2.5-flash-image",
    "gemini-3-pro-image",
    "gpt-image-1",
    "gpt-image-1.5",
    "gpt-image-2",
    "gpt-image-2.5-sunburst",
    "gpt-image-2.5-flare",
    "bytedance-seedream-5-lite",
    "bytedance-seedream-5-pro",
)
ENV_FILE = Path(__file__).resolve().parents[2] / ".env"
POLL_SECS = 3.0
TIMEOUT_SECS = 300.0


@dataclass
class HttpResult:
    status: int
    body: bytes


# (method, url, headers, json body or None) -> HttpResult. Injected in tests.
Transport = Callable[[str, str, dict[str, str], dict[str, Any] | None], HttpResult]


class ImageGenError(RuntimeError):
    pass


def urllib_transport(
    method: str, url: str, headers: dict[str, str], body: dict[str, Any] | None
) -> HttpResult:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return HttpResult(resp.status, resp.read())
    except urllib.error.HTTPError as exc:
        return HttpResult(exc.code, exc.read())


def load_api_key(env_file: Path = ENV_FILE) -> str:
    key = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    if not key and env_file.is_file():
        for line in env_file.read_text(encoding="utf-8").splitlines():
            name, sep, value = line.strip().removeprefix("export ").partition("=")
            if sep and name.strip() == "ELEVENLABS_API_KEY":
                key = value.strip().strip("'\"")
    if not key:
        raise ImageGenError("ELEVENLABS_API_KEY is not set (environment or DMS/.env).")
    return key


def _error_text(res: HttpResult) -> str:
    try:
        detail = json.loads(res.body).get("detail", {})
    except (ValueError, AttributeError):
        return f"HTTP {res.status}"
    if isinstance(detail, dict):
        return f"HTTP {res.status} {detail.get('status', '')}: {detail.get('message', '')}".strip()
    return f"HTTP {res.status}: {detail}"


def build_request(
    prompt: str,
    model: str,
    aspect_ratio: str | None,
    resolution: str | None,
    quality: str | None,
    seed: int | None,
) -> dict[str, Any]:
    body: dict[str, Any] = {"model_id": model, "prompt": prompt}
    for name, value in (
        ("aspect_ratio", aspect_ratio),
        ("resolution", resolution),
        ("quality", quality),
        ("seed", seed),
    ):
        if value is not None:
            body[name] = value
    return body


def credits_used_so_far(key: str, http: Transport) -> int | None:
    """Return the subscription's character/credit count, or None if the key can't read it."""
    res = http("GET", f"{API}/v1/user/subscription", {"xi-api-key": key}, None)
    if res.status != 200:
        return None
    value = json.loads(res.body).get("character_count")
    return value if isinstance(value, int) else None


def generate(
    body: dict[str, Any],
    key: str,
    http: Transport = urllib_transport,
    sleep: Callable[[float], None] | None = None,
    poll_secs: float = POLL_SECS,
    timeout_secs: float = TIMEOUT_SECS,
) -> tuple[bytes, str]:
    """Run one generation to completion and return (image bytes, mime type)."""
    pause = sleep or time.sleep
    headers = {"xi-api-key": key, "Content-Type": "application/json"}
    res = http("POST", f"{API}/v1/flows/image", headers, body)
    if res.status != 200:
        raise ImageGenError(f"create failed: {_error_text(res)}")
    gen_id = json.loads(res.body)["id"]

    waited = 0.0
    while True:
        res = http("GET", f"{API}/v1/flows/image/{gen_id}", {"xi-api-key": key}, None)
        if res.status == 429:
            data: dict[str, Any] = {"status": "pending"}
        elif res.status != 200:
            raise ImageGenError(f"status check failed: {_error_text(res)}")
        else:
            data = json.loads(res.body)
        status = data.get("status")
        if status == "completed":
            break
        if status == "failed":
            raise ImageGenError(
                f"generation {gen_id} failed ({data.get('failure_reason')}): "
                f"{data.get('error_message')}"
            )
        if waited >= timeout_secs:
            raise ImageGenError(f"generation {gen_id} still {status} after {timeout_secs:.0f}s")
        pause(poll_secs)
        waited += poll_secs

    # The signed content URL must not receive the API key.
    img = http("GET", data["content_url"], {}, None)
    if img.status != 200:
        raise ImageGenError(f"download failed: HTTP {img.status}")
    return img.body, str(data.get("content_mime_type", "image/png"))


def main(argv: list[str] | None = None, http: Transport = urllib_transport) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0] if __doc__ else None)
    p.add_argument("--prompt", required=True, help="text prompt")
    p.add_argument("--out", required=True, type=Path, help="output image path (.png/.jpg)")
    p.add_argument("--model", default=DEFAULT_MODEL, help=f"model_id (known: {', '.join(MODELS)})")
    p.add_argument("--aspect", dest="aspect_ratio", help="aspect ratio, e.g. 1:1, 16:9, 4:3")
    p.add_argument("--resolution", help="resolution, e.g. 512, 1K, 2K, 4K (model dependent)")
    p.add_argument("--quality", help="quality for gpt-image models: low, medium, high")
    p.add_argument("--seed", type=int, help="seed (seedream models)")
    args = p.parse_args(argv)

    try:
        key = load_api_key()
        body = build_request(
            args.prompt, args.model, args.aspect_ratio, args.resolution, args.quality, args.seed
        )
        before = credits_used_so_far(key, http)
        image, mime = generate(body, key, http)
        after = credits_used_so_far(key, http) if before is not None else None
    except ImageGenError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes(image)
    print(f"wrote {args.out} ({mime}, {len(image)} bytes, model {args.model})")
    if before is not None and after is not None:
        print(f"credits used: {after - before}")
    else:
        print("credits used: unknown (key lacks user_read; see the ElevenLabs usage page)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
