"""Fixtures: the example spec and a fake ``beamngpy`` module that records every call."""

from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace
from typing import Any

import pytest
from dms_beamng import DrivingMissionSpec, load_spec

EXAMPLE = Path(__file__).resolve().parents[1] / "examples" / "b01-getaway.yaml"


class _Recorder:
    def __init__(self, log: list[tuple[str, Any]], prefix: str) -> None:
        self._log = log
        self._prefix = prefix

    def __getattr__(self, name: str) -> Any:
        def call(*args: Any, **kwargs: Any) -> None:
            self._log.append((f"{self._prefix}.{name}", (args, kwargs)))

        return call


def make_fake_beamngpy() -> tuple[SimpleNamespace, list[tuple[str, Any]]]:
    log: list[tuple[str, Any]] = []

    class BeamNGpy:
        def __init__(self, host: str, port: int, **kwargs: Any) -> None:
            log.append(("BeamNGpy", ((host, port), kwargs)))
            self.scenario = _Recorder(log, "bng.scenario")
            self.env = _Recorder(log, "bng.env")
            self.traffic = _Recorder(log, "bng.traffic")

        def open(self, **kwargs: Any) -> None:
            log.append(("bng.open", ((), kwargs)))

    class Vehicle:
        def __init__(self, vid: str, **kwargs: Any) -> None:
            log.append(("Vehicle", ((vid,), kwargs)))
            self.vid = vid
            self.ai = _Recorder(log, f"{vid}.ai")

    class Scenario:
        def __init__(self, level: str, name: str, **kwargs: Any) -> None:
            log.append(("Scenario", ((level, name), kwargs)))

        def add_vehicle(self, vehicle: Vehicle, **kwargs: Any) -> None:
            log.append(("scenario.add_vehicle", ((vehicle.vid,), kwargs)))

        def make(self, bng: BeamNGpy) -> None:
            log.append(("scenario.make", ((), {})))

    return SimpleNamespace(BeamNGpy=BeamNGpy, Vehicle=Vehicle, Scenario=Scenario), log


@pytest.fixture
def spec() -> DrivingMissionSpec:
    return load_spec(EXAMPLE)


@pytest.fixture
def fake_bp() -> tuple[SimpleNamespace, list[tuple[str, Any]]]:
    return make_fake_beamngpy()
