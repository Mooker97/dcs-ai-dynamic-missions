"""Tests for tools/image_gen/elevenlabs_image.py with a fake HTTP transport (no network)."""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path
from types import ModuleType
from typing import Any

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "image_gen" / "elevenlabs_image.py"


def _load() -> ModuleType:
    spec = importlib.util.spec_from_file_location("dms_elevenlabs_image", SCRIPT)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules["dms_elevenlabs_image"] = mod
    spec.loader.exec_module(mod)
    return mod


eli = _load()
API = eli.API


class FakeHttp:
    def __init__(self, routes: dict[tuple[str, str], list[tuple[int, Any]]]) -> None:
        self.routes = routes
        self.calls: list[tuple[str, str, dict[str, str], dict[str, Any] | None]] = []

    def __call__(
        self, method: str, url: str, headers: dict[str, str], body: dict[str, Any] | None
    ) -> Any:
        self.calls.append((method, url, headers, body))
        queue = self.routes[(method, url)]
        status, payload = queue.pop(0) if len(queue) > 1 else queue[0]
        raw = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        return eli.HttpResult(status, raw)


def _happy_routes(sub_status: int = 401) -> dict[tuple[str, str], list[tuple[int, Any]]]:
    return {
        ("POST", f"{API}/v1/flows/image"): [(200, {"id": "g1", "status": "pending"})],
        ("GET", f"{API}/v1/flows/image/g1"): [
            (200, {"id": "g1", "status": "generating"}),
            (
                200,
                {
                    "id": "g1",
                    "status": "completed",
                    "content_url": "https://cdn.example/g1.png",
                    "content_mime_type": "image/png",
                },
            ),
        ],
        ("GET", "https://cdn.example/g1.png"): [(200, b"\x89PNGfake")],
        ("GET", f"{API}/v1/user/subscription"): [
            (sub_status, {"character_count": 100}),
            (sub_status, {"character_count": 130}),
        ],
    }


def test_build_request_omits_unset_options() -> None:
    body = eli.build_request("p", "gpt-image-1", "1:1", None, "low", None)
    assert body == {
        "model_id": "gpt-image-1",
        "prompt": "p",
        "aspect_ratio": "1:1",
        "quality": "low",
    }


def test_generate_polls_and_downloads_without_leaking_key() -> None:
    http = FakeHttp(_happy_routes())
    sleeps: list[float] = []
    data, mime = eli.generate({"model_id": "m", "prompt": "p"}, "KEY", http, sleeps.append)
    assert data == b"\x89PNGfake"
    assert mime == "image/png"
    assert len(sleeps) == 1
    download = [c for c in http.calls if c[1].startswith("https://cdn.example")]
    assert download and "xi-api-key" not in download[0][2]


def test_failed_generation_raises() -> None:
    routes = _happy_routes()
    routes[("GET", f"{API}/v1/flows/image/g1")] = [
        (200, {"id": "g1", "status": "failed", "failure_reason": "moderated", "error_message": "x"})
    ]
    with pytest.raises(eli.ImageGenError, match="moderated"):
        eli.generate({}, "KEY", FakeHttp(routes), lambda _s: None)


def test_missing_permission_message_is_surfaced() -> None:
    detail = {
        "status": "missing_permissions",
        "message": "missing the permission image_video_generation",
    }
    routes = {("POST", f"{API}/v1/flows/image"): [(401, {"detail": detail})]}
    with pytest.raises(eli.ImageGenError, match="image_video_generation"):
        eli.generate({}, "KEY", FakeHttp(routes), lambda _s: None)


def test_main_writes_file_and_reports_credits(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setenv("ELEVENLABS_API_KEY", "KEY")
    monkeypatch.setattr(eli.time, "sleep", lambda _s: None)
    out = tmp_path / "img" / "briefing.png"
    rc = eli.main(["--prompt", "p", "--out", str(out)], http=FakeHttp(_happy_routes(200)))
    assert rc == 0
    assert out.read_bytes() == b"\x89PNGfake"
    printed = capsys.readouterr().out
    assert "credits used: 30" in printed
    assert "KEY" not in printed


def test_load_api_key_from_env_file(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("ELEVENLABS_API_KEY", raising=False)
    env = tmp_path / ".env"
    env.write_text("OTHER=1\nELEVENLABS_API_KEY='abc'\n", encoding="utf-8")
    assert eli.load_api_key(env) == "abc"
    with pytest.raises(eli.ImageGenError):
        eli.load_api_key(tmp_path / "missing.env")
