# CESuite 0.3.0 — Release Notes (Draft)

CESuite 0.3.0 adds read-only analysis of Lua tables used to construct AOB scan
definitions, together with explicit coverage reporting and a reproducible
regression corpus.

## Highlights

- **Dynamic Lua/table analysis**: local tables, nested rows, wrapper contracts,
  conditional candidates, symbol-only rows and multi-provenance edges.
- **Provenance**: candidates retain source script, line, consumer, wrapper,
  helper/provider and resolution status.
- **Coverage model**: collection, discovery and validation are reported as
  separate dimensions with explicit denominators.
- **Runtime validation honesty**: only a unique observed AOB scan increments
  `runtime_validated`; static resolution and wrapper contracts never do.
- **Reporting**: Coverage Summary and Discovered Candidates in the Simple
  Report, with matching coverage and dynamic analysis in the Extensive JSON.
- **Regression corpus**: minimized fixtures for script-95, callbacks, loaders,
  constructed AA, duplicates, scope, limits, coverage and runtime replay.
- **Fail-closed limits**: parse, table, edge and candidate limits propagate to
  `limit_reached`; percentages remain null.

## Compatibility

`core_version` remains `0.1.9`; `suite_version` is `0.3.0`. Existing Address
Evidence, operation telemetry and report schemas remain additively compatible.

## Limitations

- Static analysis does not execute Lua, evaluate callbacks or prove runtime
  behavior.
- Dynamic discovery is limited to the captured table/script source and to
  supported syntax; unsupported constructs stay unresolved or unavailable.
- Validation is unavailable when no runtime scan is attempted, including
  detached targets and static-only analysis.
- No compatibility, correctness, ownership or restore-safety claim is made.
- No complete address-space coverage is claimed; CE-readable memory may be
  incomplete.
