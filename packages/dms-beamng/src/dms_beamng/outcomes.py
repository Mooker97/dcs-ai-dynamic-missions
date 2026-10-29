"""Telemetry -> DMS-style outcome reports.

The harness (or a future GE-Lua director) feeds ``Telemetry`` snapshots to an
``OutcomeTracker``. It evaluates objectives and beats and emits payloads shaped like the DCS
runtime's ``DMS.Log.outcome{...}``: ``missionId``, ``t``, ``kind`` (``update`` | ``end``),
``result``, ``outcome``, ``flags``, ``beats``, ``qualityDeltas``. ``format_outcome_line``
renders ``[DMS.OUTCOME] {json}``, so ``dms_core.schemas.parse_dcs_log`` and
``MissionOutcome.from_payload`` read BeamNG reports unchanged.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from typing import Any

from dms_core.schemas import MissionOutcome

from .planner import PlannedObjective, ScenarioPlan
from .spec import DriveBeat

__all__ = ["OutcomeTracker", "Telemetry", "format_outcome_line", "to_mission_outcome"]

Vec3 = tuple[float, float, float]


@dataclass(frozen=True)
class Telemetry:
    """One snapshot of the player car and pursuit state."""

    t: float
    pos: Vec3
    damage: float = 0.0
    arrested: bool = False
    evaded: bool = False


def format_outcome_line(payload: dict[str, Any]) -> str:
    """``[DMS.OUTCOME] {json}`` (compact, keys sorted for stable logs)."""
    return "[DMS.OUTCOME] " + json.dumps(payload, sort_keys=True, separators=(",", ":"))


def to_mission_outcome(payload: dict[str, Any]) -> MissionOutcome:
    """Payload -> dms_core MissionOutcome (camelCase handled by from_payload)."""
    return MissionOutcome.from_payload(payload)


def _dist(a: Vec3, b: Vec3) -> float:
    return math.dist(a, b)


class OutcomeTracker:
    """Pure state machine over telemetry; no I/O."""

    def __init__(self, plan: ScenarioPlan) -> None:
        self.plan = plan
        self.done: dict[str, bool] = {o.id: False for o in plan.objectives}
        self._inside_since: dict[str, float] = {}
        self.outcome: dict[str, bool | int | float | str] = {}
        self.quality_deltas: dict[str, float] = {}
        self.fired: list[str] = []
        self.level = 0
        self.max_damage = 0.0
        self.result: str | None = None
        self.ended = False
        self._started = False
        self._t = 0.0

    # -- helpers ---------------------------------------------------------------------------

    def _payload(self, kind: str) -> dict[str, Any]:
        p: dict[str, Any] = {
            "missionId": self.plan.mission_id,
            "t": round(self._t, 2),
            "kind": kind,
            "outcome": dict(self.outcome),
            "flags": {f"{k}_done": v for k, v in self.done.items()},
            "beats": list(self.fired),
            "qualityDeltas": dict(self.quality_deltas),
            "backend": "beamng",
            "variant": self.plan.variant,
        }
        if self.result is not None:
            p["result"] = self.result
        return p

    def _fire(self, beat: DriveBeat) -> None:
        if beat.once and beat.id in self.fired:
            return
        self.fired.append(beat.id)
        eff = beat.effects
        self.outcome.update(eff.outcome)
        for k, d in eff.quality_deltas.items():
            self.quality_deltas[k] = self.quality_deltas.get(k, 0) + d
        if eff.end_mission is not None and self.result is None:
            self.result = eff.end_mission

    def _beats(self, event: str, **match: Any) -> None:
        for b in self.plan.beats:
            w = b.when
            if w.event != event:
                continue
            if event == "objective.complete" and w.objective != match.get("objective"):
                continue
            if event == "pursuit.level" and w.level is not None and w.level != match.get("level"):
                continue
            if event == "time" and (w.after_sec or 0) > self._t:
                continue
            if event == "damage.above" and (w.damage or 0) >= self.max_damage:
                continue
            self._fire(b)

    def _ready(self, o: PlannedObjective) -> bool:
        return o.after is None or self.done.get(o.after, False)

    def _required_met(self) -> bool:
        for o in self.plan.objectives:
            if o.optional or o.type in ("survive", "max_damage"):
                continue
            if not self.done[o.id]:
                return False
        return True

    def _damage_ok(self) -> bool:
        return all(
            o.optional or o.max_damage is None or self.max_damage <= o.max_damage
            for o in self.plan.objectives
            if o.type == "max_damage"
        )

    # -- API -------------------------------------------------------------------------------

    def update(self, tel: Telemetry) -> list[dict[str, Any]]:
        """Feed one snapshot; returns the payloads to log (empty if nothing changed)."""
        if self.ended:
            return []
        self._t = tel.t
        before = (dict(self.done), len(self.fired), self.level, dict(self.outcome))

        if not self._started:
            self._started = True
            self._beats("start")
        self._beats("time")

        self.max_damage = max(self.max_damage, tel.damage)
        self.outcome["damage"] = round(self.max_damage, 3)
        self._beats("damage.above")

        p = self.plan.pursuit
        if p is not None and tel.t >= p.start_after_sec:
            self.outcome["pursuit"] = True
            level = 1 + sum(1 for s in p.escalation if tel.t >= p.start_after_sec + s.after_sec)
            while self.level < level:
                self.level += 1
                self._beats("pursuit.level", level=self.level)
            self.outcome["pursuit_level"] = self.level

        for o in self.plan.objectives:
            if self.done[o.id] or not self._ready(o):
                continue
            if o.type in ("reach", "stop_at") and o.pos is not None:
                inside = _dist(tel.pos, o.pos) <= o.radius_m
                if not inside:
                    self._inside_since.pop(o.id, None)
                    continue
                since = self._inside_since.setdefault(o.id, tel.t)
                if tel.t - since >= o.hold_sec:
                    self._complete(o)
            elif o.type == "evade" and tel.evaded:
                self._complete(o)

        if tel.evaded and "evaded" not in self.outcome:
            self.outcome["evaded"] = True
            self._beats("evaded")
        if tel.arrested:
            self.outcome["arrested"] = True
            self._beats("arrested")
            self.result = self.result or "failure"

        limit = self.plan.time_limit_sec
        if self.result is None and limit is not None and tel.t >= limit:
            self.outcome["time_limit"] = True
            self._beats("time_limit")
            self.result = self.result or "failure"

        if self.result is None and self._required_met():
            self.result = "success" if self._damage_ok() else "partial"

        if self.result is not None:
            return self._end()
        after = (self.done, len(self.fired), self.level, self.outcome)
        return [self._payload("update")] if after != before else []

    def _complete(self, o: PlannedObjective) -> None:
        self.done[o.id] = True
        self.outcome[o.id] = True
        self._beats("objective.complete", objective=o.id)

    def _end(self) -> list[dict[str, Any]]:
        self.ended = True
        for o in self.plan.objectives:
            if o.type == "survive" and not self.outcome.get("arrested"):
                self.done[o.id] = True
                self.outcome[o.id] = True
            if o.type == "max_damage":
                ok = o.max_damage is None or self.max_damage <= o.max_damage
                self.done[o.id] = ok
                self.outcome[o.id] = ok
        self.outcome["time_taken"] = round(self._t, 2)
        return [self._payload("end")]

    def abort(self, t: float) -> list[dict[str, Any]]:
        """Harness gave up (crash, timeout): end with result 'aborted'."""
        if self.ended:
            return []
        self._t = t
        self.result = "aborted"
        return self._end()
