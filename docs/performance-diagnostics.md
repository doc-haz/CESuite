# Performance and Operation Diagnostics (0.2.3)

This document defines the optional `operation` block added to the runtime report
and the static Lua report. It is operational metadata about CESuite's own work,
never evidence about the target and never a correctness verdict.

## Separation from evidence

| Dimension | Values | Meaning |
|---|---|---|
| Evidence `status` | `observed`, `candidate`, `unknown`, `unsupported`, `invalidated` | What was proven about the address/table |
| Operation `status` | `complete`, `partial`, `cancelled`, `failed`, `unavailable` | How far the operation got |
| `source_complete` | boolean | The full planned source/range was demonstrably traversed |
| `partial` | boolean | Usable output exists but the planned scope was not completed |
| `cancelled` | boolean | The operation was stopped by an existing safe mechanism |

A slow operation is not a problem. A partial operation can still contain
`observed` evidence. Timings are never converted into diagnostics.

## Block shape

```json
{
  "operation": {
    "status": "partial",
    "source_complete": false,
    "partial": true,
    "cancelled": false,
    "stage": "analysis",
    "provenance": "instrumented",
    "timing_source": "getTickCount",
    "warnings": [
      { "code": "SOURCE_INCOMPLETE", "message": "...", "stage": "analysis" }
    ],
    "metrics": {
      "duration_ms": 12.4,
      "parse_ms": 3.1,
      "scan_ms": 8.9,
      "export_ms": null,
      "serialize_ms": null,
      "write_ms": null,
      "source_bytes": 4096,
      "export_bytes": null,
      "items_processed": 7,
      "items_total": 8,
      "operations_attempted": 8,
      "operations_completed": 7
    }
  }
}
```

All metrics are nullable and use decimal milliseconds for time.

## What each metric measures

| Metric | Runtime report | Static Lua report | Export |
|---|---|---|---|
| `parse_ms` | Environment capture plus table/AA parsing (`CT.capture`) | Environment capture plus table/AA parsing | n/a |
| `scan_ms` | AOB validation scans | Static Lua source analysis | n/a |
| `duration_ms` | Whole collection | Whole static analysis | n/a |
| `export_ms` | null (analysis is not an export) | null | Whole paired export (or single export) |
| `serialize_ms` | null | null | Extensive JSON encoding |
| `write_ms` | null | null | File writes (simple + extensive) |
| `source_bytes` | Sum of captured script text bytes | Sum of captured script text bytes | null |
| `export_bytes` | null | null | Bytes written by the export |
| `items_*`, `operations_*` | AOB units scanned vs planned | Observations produced | Documents written (2) |

`bytes_processed` is deliberately not emitted: source, memory and export bytes
are different units. Specific names are used instead.

## Semantics

- `complete`: the operation ran to its planned end and traversed the planned
  source. For runtime collection this also requires a live target and every
  planned AOB scan completing.
- `partial`: usable evidence exists, but at least one planned unit did not
  complete, or the match list was truncated.
- `cancelled`: only used where CESuite already has a safe stop path (declining
  the overwrite confirmation in the paired export). No new threads, hooks or
  persistent timers were added. Operations without a safe stop path always
  report `cancelled = false`.
- `failed`: the operation aborted; failure details remain in the existing error
  field or diagnostics.
- `unavailable`: no proven live target was available. The target is considered
  live only with a non-empty module inventory; a cached PID after the target
  exits cannot prove attachment. This clears `source_complete`, adds
  `RUNTIME_SOURCE_UNAVAILABLE` and forces `status = unavailable`.

`source_complete` additionally requires `items_total = 0` or
`items_processed = items_total`. A report can never claim `source_complete = true`
with planned AOB items that were not processed (for example `0/7`). Unresolved or
unsupported AOB scopes are an evidence outcome: they clear `source_complete` but
are not automatically converted into `partial`; `partial` is reserved for scans
that were attempted but did not complete.

`source_complete` is never true by default. It is cleared by cancellation,
truncation, bounded limits, target changes, unavailable runtime evidence and
errors during traversal.

## Warnings

Warnings are structured `{code, message, stage}` entries, de-duplicated per
stage. They describe operational limitations, not functional problems:

- `TIMING_UNAVAILABLE`
- `TIMING_APPROXIMATE`
- `SOURCE_INCOMPLETE`
- `RUNTIME_SOURCE_UNAVAILABLE`
- `PROCESS_CHANGED_DURING_CAPTURE`
- `MATCHES_TRUNCATED`

Functional diagnostics (schema, scan, target, address evidence) remain in their
existing `diagnostics` arrays and are not duplicated here.

## Clock and precision

1. `getTickCount()` is preferred: a millisecond tick count since Windows start.
   Deltas are wrap-safe (32-bit wrap).
2. `os.clock()` CPU time is the fallback and is marked
   `TIMING_APPROXIMATE`; it underestimates wall time.
3. If neither is available, durations are `null` and `TIMING_UNAVAILABLE` is
   emitted.

CESuite does not claim precision beyond the source. Values are reported as
floating milliseconds only because the delta is converted to a number; the
underlying resolution is one millisecond for `getTickCount()`.

## Export timing is not embedded in the file it measures

`Core.export`, `Core.exportEnriched` and `Core.exportReports` measure the export
and expose it as `Core.last_export_operation` and `result.operation`. The
exported document itself only carries the analysis operation. Writing the
export duration into the same file would require a second serialization/write
and would misreport the measured work.

## Determinism

Timings naturally vary between runs. Deterministic fixture generation freezes
the clock; tests assert types, ranges and invariants (`duration_ms >= 0`,
nullable metrics, stable statuses), never exact durations. Semantic results are
identical with or without instrumentation.

## Address Evidence

Address Evidence is not instrumented. It remains a pure evidence document with
no `operation` block, so its schema and consumers are unchanged.
