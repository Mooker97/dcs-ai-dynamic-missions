"""ScenarioPlan -> a running BeamNG scenario, behind a small interface.

``ScenarioSink`` is the seam: ``BeamNGpySink`` drives BeamNGpy (imported lazily, optional
extra ``dms-beamng[beamngpy]``); tests pass a fake module. A future MCP / mod-zip sink for
Steam BeamNG.drive (see docs/beamng/BACKEND.md) implements the same protocol.

BeamNGpy names used here were checked against the BeamNGpy README / API docs; the ones marked
``[?]`` were not (see BACKEND.md).
"""

from __future__ import annotations

import importlib
from dataclasses import dataclass, field
from types import ModuleType
from typing import Any, Protocol

from .planner import ScenarioPlan

__all__ = [
    "BeamNGpySink",
    "BeamNGpyUnavailableError",
    "BuildResult",
    "ScenarioSink",
    "scenario_name",
]


class BeamNGpyUnavailableError(RuntimeError):
    """beamngpy is not installed (it is an optional dependency)."""


@dataclass
class BuildResult:
    """What a sink produced. ``handles`` holds live objects (bng, scenario, vehicles)."""

    sink: str
    scenario_name: str
    plan_hash: str
    steps: list[str] = field(default_factory=list)
    handles: dict[str, Any] = field(default_factory=dict)


class ScenarioSink(Protocol):
    """Anything that can realise a ScenarioPlan."""

    def build(self, plan: ScenarioPlan) -> BuildResult:
        """Create, load and start the scenario described by ``plan``."""
        ...


def scenario_name(plan: ScenarioPlan) -> str:
    """Stable scenario name, unique per mission + variant."""
    return f"dms_{plan.mission_id}_v{plan.variant}"


def _load_beamngpy() -> ModuleType:
    try:
        return importlib.import_module("beamngpy")
    except ImportError as exc:  # pragma: no cover - depends on the environment
        raise BeamNGpyUnavailableError(
            "beamngpy is not installed: uv pip install 'dms-beamng[beamngpy]'. Note that "
            "BeamNGpy needs BeamNG.tech (tech/techCore), which Steam BeamNG.drive 0.40 lacks."
        ) from exc


class BeamNGpySink:
    """Build via BeamNGpy. ``module`` lets tests inject a fake ``beamngpy``."""

    def __init__(
        self,
        host: str = "localhost",
        port: int = 25252,
        home: str | None = None,
        user: str | None = None,
        launch: bool = True,
        module: ModuleType | Any | None = None,
    ) -> None:
        self.host = host
        self.port = port
        self.home = home
        self.user = user
        self.launch = launch
        self._module = module

    def _bp(self) -> Any:
        if self._module is None:
            self._module = _load_beamngpy()
        return self._module

    def build(self, plan: ScenarioPlan) -> BuildResult:
        """Open BeamNG, make + load + start the scenario, then traffic, time of day and AI."""
        bp = self._bp()
        name = scenario_name(plan)
        res = BuildResult(sink="beamngpy", scenario_name=name, plan_hash=plan.plan_hash)

        bng = bp.BeamNGpy(self.host, self.port, home=self.home, user=self.user)
        bng.open(launch=self.launch)  # launch= kwarg [?]
        res.steps.append("open")

        scenario = bp.Scenario(plan.level, name, description=plan.title)
        v = plan.player
        vkw: dict[str, Any] = {"model": v.model}
        if v.license:
            vkw["license"] = v.license
        if v.config:
            vkw["part_config"] = v.config  # [?]
        vehicle = bp.Vehicle(v.vid, **vkw)
        scenario.add_vehicle(vehicle, pos=v.pos, rot_quat=v.rot_quat)
        res.steps.append(f"add_vehicle:{v.vid}")

        scenario.make(bng)
        bng.scenario.load(scenario)
        bng.scenario.start()
        res.steps += ["make", "load", "start"]

        bng.env.set_tod(plan.time_of_day)  # argument semantics [?]
        res.steps.append(f"tod:{plan.time_of_day}")

        if plan.traffic.amount > 0:
            police = plan.traffic.police_ratio
            if plan.pursuit is not None:
                police = max(police, 0.1)
            bng.traffic.spawn(
                max_amount=plan.traffic.amount,
                police_ratio=police,
                parked_amount=plan.traffic.parked,
            )
            res.steps.append(f"traffic:{plan.traffic.amount}")

        if plan.ai_driver:
            # Targeted driving to an arbitrary point needs a level waypoint or the MCP
            # `drive_to` tool; 'span' keeps the proxy moving through traffic meanwhile.
            vehicle.ai.set_mode("span")
            vehicle.ai.set_aggression(0.3)
            res.steps.append("ai:span")

        res.handles = {"bng": bng, "scenario": scenario, "vehicles": {v.vid: vehicle}}
        return res
