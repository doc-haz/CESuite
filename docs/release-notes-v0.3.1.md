# CESuite 0.3.1 — Evidence Snapshots

CESuite 0.3.1 adds a read-only Evidence Snapshot Viewer for preserving what
CESuite currently knows and comparing that evidence later.

## Highlights

- **Capture Snapshot**: capture current table/script evidence into a versioned
  JSON snapshot.
- **Open Snapshot**: inspect a snapshot in a read-only, sectioned viewer.
- **Compare Snapshots**: compare two snapshots with neutral classifications.
- **Deterministic identity**: source and target fingerprints plus a stable
  `snapshot_id`; timestamps, PID, timings and ASLR bases are not identity.
- **Evidence preserved**: coverage (collection, discovery, validation),
  candidates, provenance, dependencies, unresolved entries and limitations are
  stored as observed.
- **Safe bounded storage**: 8 MiB limit, bounded JSON decoder, temporary-file
  promotion, overwrite preservation and explicit corruption errors.
- **Privacy-aware**: provider/helper paths, condition dependencies, limitations
  and target/module names are sanitized; absolute paths and PID are not stored as
  identity.
- **Read-only**: snapshots and the viewer never activate records, modify the
  table, write memory, patch scripts or execute snapshot content.

## Comparison semantics

Differences are evidence changes, not verdicts. The viewer uses only:

```text
unchanged, added, removed, changed, unknown, not comparable
```

It does not claim a table is working, broken, compatible, repaired or fixed.
Validation is reported only from actual AOB scan results; static analysis and
wrapper resolution are never promoted to runtime validation.

## Limitations

- Snapshots describe observed evidence, not ground truth or compatibility.
- Static source fingerprints cover the captured surface; unobserved source is
  unknown.
- Target build identity may be unavailable; modules are not identified by ASLR
  base.
- Comparison across changed source is partial and limited to strong candidate
  identities.
- The viewer is a read-only sectioned memo; it is not a repair or rollback tool.
