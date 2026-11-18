# 0006. LLMs write schema-validated files; code compiles them

Status: Accepted · 2026-10-27

## Context

When an LLM emits coordinates, unit IDs or Lua directly, the output is unreliable and can't be
reviewed. Structured, declarative intent is different: it can be validated and repaired.

## Decision

- Every LLM stage writes YAML that conforms to a pydantic v2 model in `dms_core.schemas`. The
  models use `extra="forbid"`, and their field descriptions double as LLM guidance.
- `dms validate` reports errors with suggested fixes. Claude repairs the file, for at most 3 loops.
- `dms plan` turns a `MissionSpec` into an exact `BuildPlan` deterministically.
- No step interprets free prose.
- The LLM picks areas, roles and intent. Python picks coordinates, unit types and IDs, using the
  grounding tools (`find_airbase`, `list_units`, `list_loadouts`).

## Consequences

- Specs can be diffed and reviewed, and seeded reruns are reproducible.
- The schemas are a contract, so version changes need care.
- `dms schema` exports JSON Schemas for editors and skills.
