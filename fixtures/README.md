# Fixtures

Fixtures contain synthetic data only. `synthetic.CT` is inventory test data, not a working injection script and must not be activated against any process. It uses invented module names and byte patterns. It exercises nesting, AA sections, a scoped AOB, allocation/symbol operations, embedded Lua and a root Lua script.

Do not add proprietary binaries, executables, memory dumps or third-party tables without appropriate rights. Prefer tiny synthetic cases that isolate one parser behavior.

## Compatibility fixture

`runtime-v0.1.4.json` is an immutable synthetic CE-mock export from Core 0.1.4.
It verifies that the updated runtime schema accepts existing reports without
`dependency_summary`; it contains no live game/process data.

Its original names are deliberately retained: changing them would invalidate its
role as an untouched 0.1.4 compatibility export. Current synthetic tests and
examples use generic names.

## Reproducible application validation

`validation/dawnwalker-replay.json` is a provenance/count manifest, not source
code. The private cached input is retained separately. See the
[validation procedure](../docs/validation/dawnwalker.md). Application names are
confined to validation cases; the detector has no application-specific rules.
