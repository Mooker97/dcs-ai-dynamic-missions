# 0002. Edit existing missions via a lupa dict round-trip

Status: Accepted · 2026-10-27

## Context

The legacy approach (`MizParser`, `miz-modification/`) edited the Lua text in `mission` with regex.
That broke on nested structures and was hard to get right (see
[`../reference/lessons.md`](../reference/lessons.md)). pydcs load/save is lossy (ADR 0001), and
slpp mangles string escapes. lupa runs real Lua, so it parses the table exactly. Combined with our
deterministic serializer, it gave a byte-exact round-trip on all 5 test missions.

## Decision

`dms_core` miz I/O works like this:

1. Unzip the `.miz`.
2. Parse `mission`, `options`, `warehouses` and `l10n/*/dictionary` with lupa into Python dicts.
3. Edit the dicts.
4. Serialize deterministically.
5. Re-zip, copying every other file byte for byte.

`dcs.lua` loads/dumps is an acceptable pure-Python fallback. When an edit touches triggers, it
must also update the compiled `trig.actions` / `trig.conditions` / `trig.func` strings.

## Consequences

- Inspection and editing share one correct parse path. There is no regex on Lua text.
- lupa (a C extension) becomes a hard dependency of `dms-core`.
- Every fixture in `tests/fixtures/miz/` needs a round-trip test.
