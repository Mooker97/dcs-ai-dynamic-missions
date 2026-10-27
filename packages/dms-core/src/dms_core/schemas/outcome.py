"""MissionOutcome: facts the Lua runtime reports via ``[DMS.OUTCOME] {json}`` lines in dcs.log."""

from __future__ import annotations

import json
import re
from typing import Any

from pydantic import Field, field_validator

from ._common import DMSModel, OutcomeValue

OUTCOME_MARKER = "[DMS.OUTCOME]"
_LINE_RE = re.compile(r"\[DMS\.OUTCOME\]\s*(\{.*\})\s*$")
_TS_RE = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?)")
_CAMEL_RE = re.compile(r"(?<!^)(?=[A-Z])")
_ALIASES = {"outcome": "outcomes", "t": "time", "mission": "mission_id"}


def camel_to_snake(name: str) -> str:
    """'missionId' -> 'mission_id'."""
    return _CAMEL_RE.sub("_", name).lower()


class MissionOutcome(DMSModel):
    """One outcome report. A mission usually emits several (per beat, plus a final summary)."""

    mission_id: str | None = Field(default=None, description="Mission id from DMS_CONFIG.")
    time: float | None = Field(default=None, ge=0, description="Mission time (s) when emitted.")
    kind: str | None = Field(
        default=None, description="Report kind, e.g. 'beat', 'objective', 'summary', 'end'."
    )
    beat: str | None = Field(default=None, description="Beat id that emitted it, if any.")
    result: str | None = Field(default=None, description="'success' / 'failure' for end reports.")
    flags: dict[str, bool] = Field(default_factory=dict, description="Flag states.")
    outcomes: dict[str, OutcomeValue] = Field(
        default_factory=dict, description="Outcome facts, e.g. {hvt_killed: true}."
    )
    kills: dict[str, int] = Field(
        default_factory=dict, description="Enemy kills by category or type, e.g. {ground: 7}."
    )
    losses: dict[str, int] = Field(
        default_factory=dict, description="Friendly losses by category or type."
    )
    players: list[str] = Field(default_factory=list, description="Player names involved.")
    log_timestamp: str | None = Field(default=None, description="dcs.log wall-clock timestamp.")
    extra: dict[str, Any] = Field(default_factory=dict, description="Unrecognised keys, verbatim.")

    @field_validator("flags", "outcomes", "kills", "losses", "extra", mode="before")
    @classmethod
    def _empty_lua_table(cls, v: Any) -> Any:
        # A tiny Lua JSON encoder cannot tell {} from [] and may emit [] for an empty table.
        return {} if v == [] else v

    @classmethod
    def from_payload(
        cls, payload: dict[str, Any], log_timestamp: str | None = None
    ) -> MissionOutcome:
        """Build from a decoded JSON payload (camelCase or snake_case keys)."""
        known = set(cls.model_fields) - {"extra", "log_timestamp"}
        data: dict[str, Any] = {"extra": {}, "log_timestamp": log_timestamp}
        for key, value in payload.items():
            snake = camel_to_snake(key)
            snake = _ALIASES.get(snake, snake)
            if snake in known:
                data[snake] = value
            else:
                data["extra"][key] = value
        return cls.model_validate(data)

    def merge(self, other: MissionOutcome) -> MissionOutcome:
        """Combine two reports; values in `other` win, counters take the max."""

        def _max(a: dict[str, int], b: dict[str, int]) -> dict[str, int]:
            return {k: max(a.get(k, 0), b.get(k, 0)) for k in {*a, *b}}

        return MissionOutcome(
            mission_id=other.mission_id or self.mission_id,
            time=max(t for t in (self.time, other.time, 0.0) if t is not None),
            kind=other.kind or self.kind,
            beat=other.beat or self.beat,
            result=other.result or self.result,
            flags={**self.flags, **other.flags},
            outcomes={**self.outcomes, **other.outcomes},
            kills=_max(self.kills, other.kills),
            losses=_max(self.losses, other.losses),
            players=list(dict.fromkeys([*self.players, *other.players])),
            log_timestamp=other.log_timestamp or self.log_timestamp,
            extra={**self.extra, **other.extra},
        )


def parse_dcs_log(text: str) -> list[MissionOutcome]:
    """Extract every well-formed ``[DMS.OUTCOME] {json}`` line from dcs.log text, in order.

    Malformed JSON or non-object payloads are skipped silently.
    """
    results: list[MissionOutcome] = []
    for line in text.splitlines():
        if OUTCOME_MARKER not in line:
            continue
        m = _LINE_RE.search(line)
        if not m:
            continue
        try:
            payload = json.loads(m.group(1))
        except json.JSONDecodeError:
            continue
        if not isinstance(payload, dict):
            continue
        ts = _TS_RE.match(line)
        try:
            results.append(MissionOutcome.from_payload(payload, ts.group(1) if ts else None))
        except ValueError:
            continue
    return results


def summarize_outcomes(outcomes: list[MissionOutcome]) -> dict[str, MissionOutcome]:
    """Merge reports per mission id (None key becomes '')."""
    merged: dict[str, MissionOutcome] = {}
    for o in outcomes:
        key = o.mission_id or ""
        merged[key] = merged[key].merge(o) if key in merged else o
    return merged
