# Regression Corpus (0.3.0 / 030D)

The corpus turns audited real-world behavior into small, reproducible fixtures.
CESuite does not learn automatically; a behavior becomes experience only when a
fixture and its invariants are formalized and tested.

## Layout

```text
ce/tests/fixtures/corpus/
  manifest.json
  dynamic/
  provenance/
  coverage/
  callbacks/
  constructed-aa/
  loaders/
  runtime-replay/
  negative/
  limits/
  scope/
  duplicates/
```

`manifest.json` is the source of truth for fixture metadata:

```text
id, title, category, source_kind, purpose, origin, files,
expected_behavior, invariants, runtime_required, dependencies, known_unknowns
```

Every fixture has a matching `test('<id>')` in `ce/tests/corpus_spec.lua`; the
Python manifest test verifies IDs, categories, files and the static/runtime
declaration.

## Fixture contract

1. Identify a real behavior (audit finding or live case).
2. Minimize the source to the smallest fragment that still reproduces it.
3. Classify the claim as observed, supported inference, or unknown.
4. Add a fixture file and a manifest entry.
5. Add explicit expected invariants (counts, statuses, edges, providers,
   unresolved entries, coverage) — not a giant snapshot.
6. Add the corpus test.
7. Re-audit; do not add fixtures merely to increase a number.

Fixtures are deterministic. They must not depend on PID, live process, installed
game, CE version, timestamps or filesystem paths. `runtime_required=false`
fixtures are pure text; `runtime_required=true` fixtures use the replay state
files (`runtime-replay/*.lua`) and never start a scan.

## Canonical fixture: FFRS script-95

`ffrs-script95-static` keeps the audited behavior:

```text
entries 47, specs 52, literal 28 (27 unique), derived 3,
conditional 1, symbol_only 21 (20 pure), unique_symbols 30,
candidates 31, runtime_validated 0
LaunchUEInfoScanner = unresolved
DhaosCollider = local data table, callback provenance 0
coverage: collection complete, discovery 52 entities / 31 candidates,
          validation unavailable
```

The full script is retained because it is the reference case; helper files are
minimized to the signature table and loader binding needed for the invariants.
No third-party source is copied beyond the already-audited working case.

## Callback vs data table

`callbacks/real-callback.lua` registers a real function through
`registerCallback` and produces `callback` provenance. `callbacks/data-table.lua`
passes a `DhaosCollider`-style table to `Register.onEnable`; it produces
`passes_to`/wrapper provenance and **zero** callback provenance. Naming is never
used as evidence.

## Negative / fail-closed fixtures

- `negative/unknown-wrapper.lua`: no candidates, universe unknown.
- `negative/missing-helper.lua`: `UE.Sig.SomePattern` stays a derived candidate
  with `status=unresolved`, `runtime_validated=false`.
- `loaders/dynamic-binding.lua`: `_G[var]=...` and `rawset(_G,...)` do not
  invent providers.
- `constructed-aa/dynamic-format.lua`: dynamic format string/args produce no
  candidate. Only the demonstrated wrapper contract is modeled in 030D; a
  general `string.format` expander is intentionally absent.

## Scope fixtures

Local/global, shadowing and the conservative `sharedLocals` case are explicit.
The known limitation is documented, not hidden: a local in an earlier block can
hide a later same-name global in the same record.

## Limits and coverage fixtures

Separate fixtures cover `PARSE_LIMIT`, `TABLE_LIMIT`, `EDGE_LIMIT`,
`CANDIDATE_LIMIT` and combined limits. Coverage assertions require
`status=limit_reached`, `complete=false` and `percentage=null`.

Coverage fixtures cover empty source, zero candidates, script-95, detached target
and runtime replay states. Validation never claims runtime evidence without an
actual replay result.

## Runtime replay

Replay files are CESuite-authored test data:

```text
unique, ambiguous, no_match, error, invalidated, unavailable,
unsupported, unresolved
```

They are loaded by the corpus test only; no CE scan, process, memory read or
breakpoint is involved. Mapping is the 030C classification: only a unique
observed match increments `runtime_validated`.

## Clean room

Fixtures are minimized synthetic fragments derived from demonstrated behavior.
Do not copy unrelated third-party code, comments, paths or personal data. Keep
only the structure necessary to reproduce an invariant, record conceptual
origin in the manifest, and do not assume a third-party license for copied code.

## Running

The corpus runs as part of `tools/run_lua_tests.py`; the manifest contract runs
in `ce/tests/test_corpus_manifest.py`. Both are deterministic and offline.
