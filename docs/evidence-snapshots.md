# Evidence Snapshots (031A design)

An evidence snapshot is a reproducible, versioned record of what CESuite
observed at one moment. It is not ground truth, a working state, a compatibility
verdict, or an automatic repair point.

```text
snapshot = observed evidence at time T
diff     = evidence changed
diff     ≠ game broke / signature invalid / table incompatible
```

## Reference boundary

The audited “Accessed Snapshot Viewer” (mul0 v1.0) is accepted only as a
conceptual UI/lifecycle reference. It is not a dependency, code base or snapshot
model for CESuite.

```text
Accessed Snapshot Viewer = CPU/FPU/live-state viewer
CESuite Evidence Snapshot = persistent structured analysis evidence
```

Adopted conceptually: capture/model/render separation, explicit lifecycle and
cleanup, capability detection, visible fallback, safe guards around CE APIs,
bounded preview caches, explicit `unavailable` states and DPI/layout discipline.

Rejected expressly: internal CE structure offsets, pointer-based identity,
polling, automatic snapshots, capture timers, register/FPU reads in Evidence
Snapshot v1, form reparenting as a data mechanism, dependence on internal CE
class/caption heuristics, clipboard as evidence, and any code from the reference.

Registers/FPU may become a separate capability later; they are out of v1. The
future implementation is clean-room.

## Scope

031A defines the model, schema, normalization, identity, comparability and
privacy rules. 031B adds bounded storage, the JSON reader, the Capture/Open/
Compare menu, the read-only viewer, the snapshot corpus and corruption handling.
There is no automatic capture, background monitoring, register/FPU capture or
advisor.

## Architecture

```text
CESuite report (runtime or static)
        │
        ▼
Snapshot.capture(report, options)       pure model
        │  sanitize, project, sort, fingerprint
        ▼
evidence_snapshot v1 (JSON)             pure data
        │
        ├── Snapshot.validate(snapshot) fail-closed
        ├── Snapshot.summary(snapshot)  human summary
        └── Snapshot.compare(a,b)       snapshotdiff, neutral classifications
```

Proposed files:

```text
ce/modules/snapshot.lua       capture / normalize / validate / summary / encode
ce/modules/snapshotdiff.lua   comparison semantics
schemas/evidence-snapshot.schema.json
docs/evidence-snapshots.md
```

UI and filesystem stay outside the pure modules. A later phase can add a thin
menu/controller and explicit user-selected storage.

## Snapshot model v1

```json
{
  "snapshot_version": 1,
  "schema_id": "cesuite.evidence_snapshot",
  "snapshot_id": "snap-<32 hex>",
  "created_at": "2026-10-26T15:00:00Z",
  "suite_version": "0.3.1",
  "core_version": "0.1.9",
  "source": {},
  "target": {},
  "coverage": {},
  "operation": {},
  "provenance": {},
  "candidates": [],
  "dependencies": [],
  "unresolved": [],
  "modules": {},
  "limitations": [],
  "redactions": [],
  "address_evidence": []
}
```

`created_at` is the only intentional timestamp. Report generation timestamps are
not copied into the identity payload. `snapshot_id` is deterministic over the
normalized source, target, coverage, candidates, dependencies, unresolved,
modules and provenance summary; it excludes `created_at`, PID and operation
timings.

## Source fingerprint

For a runtime report:

```text
source.kind               runtime_report
source.fingerprint_scope  captured_scripts
source.fingerprint        sha256 over sorted script ids + normalized text
record_count              number of captured records
script_count              number of captured scripts
source_bytes              normalized Lua source bytes
```

For a static report without raw scripts:

```text
source.kind               static_lua_report
source.fingerprint_scope  derived_candidates
source.fingerprint        sha256 over sorted candidate surface fields
```

This distinguishes same source, modified source and another source in the
captured surface. It never claims semantic identity. A static fingerprint is a
derived surface, not proof that no unobserved source changed.

Normalization for the hash: line endings to LF, ordering by script id and line,
no paths; trailing whitespace is preserved because changing it can be real
source change. The source text itself is not stored.

## Target fingerprint

Recorded:

```text
process_name
architecture
main module name
main module size
main module timestamp/hash only when already available
attached
```

Not used for identity: PID, module base, absolute executable path, ASLR address.

`target.fingerprint` is `sha256(process_name | architecture | main name | main
size | available module timestamp/hash)`. Equal name is not equal build. If the
module metadata is insufficient, `build_fingerprint_known=false` and the target
is reported as `target_build_unknown`; no build identity is invented.

PID is optional context (`include_pid`) and is excluded from the snapshot ID and
all comparisons. It is null by default.

## Coverage projection

The snapshot copies, rather than recomputes, the coverage observed:

```text
collection: status, complete, units_discovered, units_processed,
            universe_known, denominator, percentage, limitations
discovery:  status, complete, entities_discovered, patterns_discovered,
            literal, derived, conditional, symbol_only, candidates, linked,
            unresolved, unsupported, universe_known, denominator, percentage
validation: status, complete, candidates, attempted, validated, unique,
            ambiguous, no_match, error, unavailable, unsupported, unresolved,
            universe_known, denominator, percentage
```

`not attempted` and `no match` are distinct validation states. A snapshot never
turns an absent runtime scan into a negative result.

## Candidate projection

Only stable, JSON-safe fields are stored:

```text
identity.key, identity.kind, occurrence
symbol, kind, normalized pattern
source_script, source_line, consumer
provider, helper
validation.state, validation.attempted
runtime_validated
provenance.kinds / count
condition (public JSON-safe form only)
```

No AST, raw source, internal node, function, memory bytes or absolute address is
stored.

### Candidate identity

Identity is assigned deterministically:

1. If a symbol exists and script/consumer/kind are present: **strong**
   `length(source_script) + source_script + length(consumer) + consumer +
    length(kind) + kind + length(symbol) + symbol`
2. Otherwise, if a source line exists: **weak**
   `length(source_script) + source_script + length(line) + line +
    length(consumer) + consumer + length(kind) + kind`
3. If neither exists: identity is unknown.

Length-prefixed segments prevent delimiter collisions. Occurrence is assigned
in stable discovery order, never by lexicographic pattern; a pattern change does
not swap `#1`/`#2`. Only strong identity is eligible for matching across a
changed source. A pattern change remains a change on the same strong identity;
a genuine added/removed candidate has a different identity.

This is a comparison aid, not a claim that two candidates are semantically the
same function across builds.

## Provenance

v1 stores a summary, not the full graph:

```text
provenance.edge_count
provenance.kinds[] = {kind, count}
candidate.provenance.kinds[] / count
candidate.provider / helper
```

A future optional detail file may contain the full graph. The summary is enough
to detect provider change, consumer disappearance, unresolved helper, new
dependency and registration path change without snapshot bloat.

## Modules and Address Evidence

`modules` stores the module count, main module metadata and an inventory
fingerprint over sorted names/sizes. Bases and absolute addresses are excluded.

Address Evidence is optional. It is stored as module name/size + RVA when
available, read/instruction/symbol statuses, and no absolute address, path,
bytes or symbol callback data. If the module changes, the evidence is not
directly comparable.

## Normalization rules

Before identity/comparison:

- LF line endings; stable ordering by candidate identity, dependency key,
  unresolved key and module name.
- PID omitted by default.
- module bases and absolute addresses omitted.
- `created_at`, report timestamps and operation timings excluded from identity.
- local absolute paths, usernames and temp directories redacted;
  `provider` is reduced to its file basename and `helper` to a sanitized
  logical name; executed redactions are recorded alphabetically.
- normalized patterns lower-case with whitespace removed; `??` becomes
  `xx`, so `48 xx 5C` and `48 ?? 5C` canonicalize equally.
- U.null serialized as JSON null.

Fields representing real evidence (pattern, provider, consumer, validation
state, coverage counts) are never normalized away.

## Snapshot ID

```text
snapshot_id = "snap-" + first 32 hex of
  sha256(canonical_json(identity_payload))
```

`identity_payload` contains snapshot version, suite/core version, source, target,
coverage, candidates, dependencies, unresolved, modules and provenance summary.
It excludes ID, created_at, PID and operation timings. Same evidence produces
the same ID even at different times or with different timings.

## Comparison semantics

`Snapshot.compare(a, b)` returns only neutral classifications:

```text
unchanged | added | removed | changed | unknown | not comparable
```

It returns:

- `comparability`: same_source, source_changed, same_target_build,
  different_target_build, target_build_unknown, different_target,
  candidate_comparable, strong_identity_only, partial_comparison, status.
- `coverage`: collection, discovery and validation separately, with A/B values.
- `candidates`: added/removed/changed/unknown/unchanged count; changed fields.
- `dependencies`, `unresolved`, `modules`, `limitations`.
- `notes` explaining why a comparison is partial.

Validation changes are first-class:

```text
unique → no_match
unique → ambiguous
not attempted → unique
unavailable → unavailable
```

No automatic conclusions such as fixed/broken/regressed/compatible are emitted.
v1 does not emit a confidence score or confidence percentage; it emits only the
neutral classification and the compared values.
If the source or candidate identity is not comparable, the diff says
`not comparable`; it does not guess.

### Comparability rules

```text
snapshot_version unsupported          → not comparable
source fingerprint missing           → partial / not comparable for candidates
source fingerprints equal            → same_source
source fingerprints differ           → partial_comparison
target names differ                  → different_target
both build fingerprints known, equal → same_target_build
both known, different                → different_target_build
one/both unknown                      → target_build_unknown
coverage universe unknown            → partial comparison note
```

Same source: full candidate comparison. Different source: only candidates with
strong symbol identity are matched; weak/line-only identities are
`not_comparable`. The result is explicitly `partial_comparison` with
`source_changed=true`, `candidate_comparable=true` and
`strong_identity_only=true`; `same_source` remains false and no semantic
equivalence is claimed. Coverage comparison remains visible even when candidate
matching is not comparable.

## UI implementation

Implemented placement:

```text
CESuite
  Evidence Snapshots
    Capture Snapshot…
    Open Snapshot…
    Compare Snapshots…
```

This is a small submenu, not a new top-level menu family. If Diagnostics grows
an explicit "Evidence" section later, these actions can move there. No automatic
capture, timers or monitoring.

The viewer is a read-only memo with section headings: Overview, Target, Source,
Coverage, Validation, Candidates, Provenance, Dependencies, Unresolved,
Limitations, Modules, optional Address Evidence. It is not a tabbed interface and
does not present raw JSON as the primary UX. Candidate/dependency lists are
bounded to 50 rows per section.

## API proposal

```lua
Snapshot.capture(report, options)   -- pure; no filesystem/UI
Snapshot.normalize(snapshot)        -- canonical ordering and ID
Snapshot.validate(snapshot)         -- ok, errors
Snapshot.summary(snapshot)          -- compact table
Snapshot.encode(snapshot)           -- JSON-safe deterministic encoding
Snapshot.compare(a, b)              -- delegates to snapshotdiff
```

Filesystem/UI in a later phase:

```lua
Snapshot.write(snapshot, path)      -- explicit user path only
Snapshot.read(path)                 -- bounded, fail-closed
```

No `load`, `loadstring`, `dofile`, `autoAssemble` or shell execution is ever used
on snapshot content.

## Storage

- User-selected path or explicit CESuite directory; never automatically inside a
  game directory.
- No silent persistence and no background snapshots in 031A/031B.
- Proposed filename: `CESuite_<source>_<target>_<created>_<id>.json`.
- Write via the existing explicit exporter pattern, with temp/rename safety when
  filesystem support is added. v1 prototype does not write files.

## Privacy

Never store: local absolute paths, usernames, temp directories, credentials,
environment secrets, raw source, full module lists, memory dumps, absolute
addresses or symbol callbacks.

Sanitization is explicit and recorded in `redactions`. Module path is reduced to
module name; Address Evidence path is dropped; PID is null by default. String
fields are still treated as data, never executed.

## Limits and corrupted snapshots

- `MAX_SNAPSHOT_BYTES` (proposed 8 MiB) and per-array caps: candidates 2000,
  dependencies 500, unresolved 200, limitations 200, address evidence 64.
- Reject invalid JSON, unknown/missing `snapshot_version`, wrong types, truncated
  files, oversized arrays and impossible IDs with a clear error. Planned 031B
  error codes: `snapshot_too_large`, `invalid_json`, `truncated_file`,
  `unsupported_snapshot_version`, `schema_invalid`, `identity_invalid`.
- Read only with a bounded parser; never `load`, `loadstring`, `dofile` or any
  other execution path. 031B implements the bounded JSON decoder and file reader.
- Atomic writes use `.cesuite-partial` and rename; existing files are preserved
  unless overwrite is explicitly accepted.
- Read v1, write v1. Unsupported versions are rejected; no migration is
  attempted in 031A/031B. Future readers may migrate explicitly.
- Schema is versioned and strict; unknown extra fields are rejected in v1.

## Test plan

Unit:

- capture required fields and JSON-safe serialization;
- source fingerprint stability/change;
- target fingerprint excludes PID/base/path;
- candidate identity: stable, duplicate occurrence, pattern change, provider
  change, consumer change, validation change;
- normalization ordering and idempotence;
- snapshot ID same evidence/different timestamps;
- validation rejects unsupported version/missing fields/wrong types/oversized
  arrays;
- privacy: no local path, username, temp dir or PID by default;
- limit-reached coverage preserved;
- comparison: identical, candidate added/removed, pattern/provider/consumer/
  validation changed, unknown identity, different source, different target,
  partial comparability, limit reached;
- no forbidden conclusion words in diff output.

Schema/integration:

- `schemas/evidence-snapshot.schema.json` validates captured snapshots;
- corrupted/legacy JSON rejection (031B read layer);
- corpus fixtures for all comparison cases;
- FFRS reference snapshot: 47 entries, 52 specs, 31 candidates,
  `LaunchUEInfoScanner` unresolved, no runtime validation;
- deterministic serialization and repeated comparison.

## Corpus plan

Add `ce/tests/fixtures/corpus/snapshots/` with minimal synthetic snapshots for:

```text
identical
candidate-added
candidate-removed
pattern-changed
validation-changed
provider-changed
unknown-comparison
different-target
different-source
coverage-changed
limit-reached
```

The FFRS reference snapshot is derived from the canonical fixture, contains no
private paths/PID, and is not a rigid requirement for unrelated snapshots.

## Migration

`snapshot_version=1` now. Strategy: read v1, write current v1; unsupported
versions rejected. Future v2 may add optional fields and a reader migration; no
complex migration pipeline is designed in 031A.

## Risks

- Candidate identity can collide or split when duplicate symbols/lines change;
  occurrence handling is deterministic but still an inference aid.
- Static reports lack raw source; their fingerprint is a derived surface, so
  unobserved source changes cannot be detected.
- Runtime reports may not link every AOB result to a candidate; aggregate
  validation may be stronger than per-candidate validation.
- Module build identity is often unavailable; do not treat name as build ID.
- Snapshots can grow if all edges/modules are copied; v1 stores summaries.
- Different targets can make validation comparisons misleading; comparability
  marks this explicitly.
- Schema v1 strictness may require a v2 for future fields.

## Known unknowns

- Stable cross-build candidate identity remains unproven.
- A safe, portable module build hash is not guaranteed across CE versions.
- The UI location may move once Diagnostics gains an Evidence section.
- Storage safety/temp-rename semantics require implementation review in 031B.
- Per-candidate runtime mapping depends on report structure not yet universal.

## Phases

```text
031A  design, schema draft, pure capture/compare prototype, tests
031B  capture UI, bounded read/write, viewer, corpus snapshots
031C  live FFRS validation, comparison UX, hardening
031D  optional Evidence Advisor consuming structured snapshots/diffs
```

## Prototype checks executed in 031A

The pure model is exercised without CE UI or a live process:

| Area | Checks |
|---|---|
| required v1 surface and validation | capture, required fields, conditions |
| serialization | deterministic JSON, no local path/PID |
| identity | snapshot id stable across timestamps/timings/PIDs |
| fingerprints | source change, module size change, target name/path |
| candidates | duplicate occurrence stability, added/removed, pattern/provider/consumer changes |
| validation evidence | not_attempted → no_match, unique mapping |
| coverage | limit_reached preserved, validation unavailable |
| comparability | same source, changed source strong identity, weak identity, different target, known/unknown build |
| normalization | sorted arrays, idempotent id |
| security | unsupported version, missing fields, oversized arrays, truncation limitations |
| privacy | provider/helper paths redacted, redactions populated, no absolute path/PID |
| static source | derived-candidate fingerprint scope |
| diff language | no fixed/broken/regressed/compatible output |
| schema | `evidence-snapshot.schema.json` validates captured snapshots |

031B adds 60 snapshot Lua checks and Python schema/corpus checks. The released
v0.3.0 artifacts are untouched; the local development build is v0.3.1.

## 031B implementation status

Implemented locally: `json.lua` (bounded decoder), `snapshotstore.lua`
(atomic read/write, 8 MiB limit, corruption errors), `snapshotui.lua`
(sectioned viewer and neutral diff), Core snapshot APIs, and the
`CESuite > Evidence Snapshots` submenu. Snapshot JSON corpus and corruption
fixtures live under `ce/tests/fixtures/corpus/snapshots/`.

Live CE validation (031C) covered GUI capture through the real SaveDialog,
GUI open through the real OpenDialog, the read-only viewer, compare via
Core/storage (native Compare dialogs were not automated), detached capture and a
controlled source-change comparison. Optional Evidence Advisor and register/FPU
capability remain future work. The development build is not released.

Snapshot-related checks: 39 pure model + 9 storage + 12 corpus/UI = 60 local Lua
checks, plus Python schema/corpus checks.

## 031C live facts

- CE: Cheat Engine x86_64, normal Windows desktop.
- Target inspected by the live workflow: FFRS-WinGDK-Shipping.exe (module
  metadata), via the sanitized FFRS table; no game update or memory write.
- Live table: 377 records, 205 scripts, 229829 source bytes, 31 candidates,
  52 entities, 1 unresolved (LaunchUEInfoScanner), validation unavailable.
- Real `Capture Snapshot...` SaveDialog wrote a schema-valid snapshot with no
  detected local paths/PII.
- Real `Open Snapshot...` OpenDialog opened the read-only sectioned viewer.
- Compare via Core/viewer produced comparable/unchanged for the same snapshot
  and partial_comparison with one changed pattern after a controlled source
  mutation. Native Compare dialogs were not automated.
- Detached capture: pid 0, target unattached, 31 candidates, validation
  unavailable, file re-read successfully.
- Menu: 19 CESuite items, Evidence Snapshots submenu with 3 commands; remove and
  reinstall restored exactly one menu/submenu.
- No debugging, record activation, symbol registration or memory write by the
  snapshot feature.

## Future work / conceptual references

Roadmap only; none is implemented in 031C:

- Evidence Advisor
- Relocation Candidate Engine
- Repair Plan
- Evidence-Based CT Reconstruction

AOBMaker-style concerns remain conceptual corpus/reference material only:
partial coverage, uniqueness unproven, repeated instructions, branch landing
inside overwrite, Mono/JIT without a module, LABEL+N and `jmp far newmem`.
There is no runtime dependency, copied code or integration.
