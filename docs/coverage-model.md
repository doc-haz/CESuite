# Coverage Model (0.3.0 / 030C)

CESuite reports three independent coverage dimensions. None of them implies the
others, and none is a correctness or compatibility verdict.

```text
collection  — how much of the captured source was traversed
discovery   — how much analyzed material produced recognized entities
validation  — how much of what was discovered was checked with runtime evidence
```

`operation` telemetry (timings, status, warnings) answers a fourth, different
question: how the operation executed. Coverage never changes operation statuses.

## Block shape

```json
{
  "coverage": {
    "collection": {
      "scope": "captured_scripts_and_embedded_lua",
      "units_discovered": 205,
      "units_processed": 205,
      "complete": true,
      "universe_known": true,
      "denominator": "captured_units",
      "status": "complete",
      "percentage": 100.0,
      "limitations": []
    },
    "discovery": {
      "patterns_discovered": 32,
      "patterns_literal": 28,
      "patterns_derived": 3,
      "patterns_conditional": 1,
      "patterns_symbol_only": 21,
      "entities_discovered": 52,
      "candidates": 31,
      "linked": 31,
      "unresolved": 1,
      "unsupported": 0,
      "complete": false,
      "universe_known": false,
      "denominator": "discovered_entities",
      "status": "unknown",
      "percentage": null,
      "limitations": ["The total number of patterns in uncaptured source is unknown."]
    },
    "validation": {
      "candidates": 31,
      "runtime_attempted": 0,
      "runtime_validated": 0,
      "runtime_unique": 0,
      "runtime_ambiguous": 0,
      "runtime_no_match": 0,
      "runtime_error": 0,
      "runtime_unavailable": 0,
      "unresolved": 1,
      "unsupported": 0,
      "complete": false,
      "universe_known": false,
      "denominator": "validation_candidates",
      "status": "unavailable",
      "percentage": null,
      "limitations": ["No runtime scan was attempted for the discovered candidates."]
    }
  }
}
```

## Collection

- `scope` is fixed per report (`captured_scripts_and_embedded_lua`).
- `units_discovered` / `units_processed` count captured units, not patterns.
- `complete` is false for `PARSE_LIMIT`, `TABLE_LIMIT`, `EDGE_LIMIT`,
  `CANDIDATE_LIMIT`, capture failure or truncation.
- `universe_known` is true for the captured set.
- `denominator` is `captured_units`.
- Zero captured units: `complete=true` but `percentage=null` (no division by
  zero).

## Discovery

- Counts come from `dynamic_analysis` (`counts` is the single source of truth):
  `literal + derived + symbol_only = specs`; `candidates = literal + derived`;
  `entities_discovered = specs`.
- `patterns_discovered = literal + derived + conditional`.
- `unresolved` counts unresolved candidates; the conditional dependency is
  represented once, not twice.
- `complete` can be true **only** when `universe_known=true` and there are no
  unresolved/unsupported entities. For live uncaptured source the total pattern
  universe is unknown, so `complete=false`, `status=unknown` and
  `percentage=null`.
- `denominator` is `discovered_entities`.

## Validation

- `candidates` is the discovered candidate count (denominator
  `validation_candidates`).
- `runtime_attempted` counts AOB records whose scan was actually attempted.
- `runtime_validated` increments only for an `observed` unique match. It is
  never incremented by literals, wrappers, provenance, helpers, schema or any
  static analysis.
- Runtime result mapping:

```text
observed + unique       -> runtime_validated / runtime_unique
observed + multiple     -> runtime_ambiguous
observed + zero         -> runtime_no_match
error                   -> runtime_attempted + runtime_error
invalidated             -> runtime_attempted + runtime_unavailable
unavailable             -> runtime_unavailable
unsupported/unresolved  -> unresolved / unsupported
```

- `status`:
  - `not_applicable` when there are no candidates;
  - `unavailable` when candidates exist but no scan was attempted (detached or
    static-only);
  - `partial` when attempted < candidates, errors occurred, or the universe is
    unknown;
  - `complete` only with `universe_known=true`, every candidate attempted and no
    errors.
- `complete` is false for static-only reports and detached targets.

## Universe and denominators

`universe_known=true` requires a demonstrated total. The fixture (47 entries,
52 specs) can be marked known through the analysis option; live captured source
cannot claim it. Every percentage declares its denominator:

```text
collection.percentage = units_processed / captured_units
discovery.percentage  = linked / discovered_entities
validation.percentage = runtime_validated / validation_candidates
```

A percentage is `null` when `universe_known=false`, denominator is zero, or the
numerator is unknown. `0%` is never used for “unknown”.

## Legacy `operation.source_complete`

`operation.source_complete` is retained unchanged and maps **only** to
collection completion. It must never be read as discovery completeness,
validation completeness, compatibility, or correctness. A detached run can have
`collection.complete=true` and `operation.source_complete=false` (the operation
did not traverse a live target) while `validation.status=unavailable`.

## script-95 fixture

```text
collection.complete          true
discovery.literal            28
discovery.derived             3
discovery.conditional         1
discovery.symbol_only        21
discovery.candidates         31
validation.candidates        31
validation.runtime_attempted  0
validation.runtime_validated  0
validation.status         unavailable
validation.complete        false
```

## Detached target

Static source remains available:

```text
collection = complete/known
discovery  = available (unknown universe unless fixture)
validation = unavailable (never attempted)
```

Never `validation.failed` merely because no target was attached.

## Limits

Any structural limit forces:

```text
collection.complete = false
collection.status   = limit_reached
discovery.status    = limit_reached
percentage          = null
```

`universe_known` is not forced to true after truncation.

## Static vs runtime

- Static Lua report: discovery from static text; validation is
  `unavailable`/`not_applicable`, `runtime_attempted=0`,
  `runtime_validated=0`.
- Runtime report: collection from captured scripts, discovery from the same
  static analyzer, validation from existing AOB scan results. Existing AOB
  scan logic is not modified; results are only classified.

## Determinism

Counts, denominators, statuses and nullable percentages depend only on the
input text and recorded AOB results. Timestamps, PID, addresses and unordered
iteration do not influence them.

Regression fixtures and the fixture contract are documented in
[regression-corpus.md](regression-corpus.md).

## Reporting and Presentation

Presentation of the coverage model in the Simple Report and Extensive JSON
document is detailed in [reporting-ui.md](reporting-ui.md). The interface
strictly maintains the separation `COLLECTED ≠ DISCOVERED ≠ VALIDATED`.
