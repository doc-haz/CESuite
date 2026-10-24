# CESuite 0.2.1 Live Validation Evidence

**Date:** 2026-10-24
**Cheat Engine version:** 7.72 64-bit
**Execution environment:** Windows 11 (x86_64)
**Candidate version:** `0.2.1`
**Distribution:** Autorun package (`C:\Program Files\Cheat Engine\autorun\cesuite\`)

## Artifacts under test

- **Final live artifact (corrected build):**
  - File: `CESuite_Autorun_v0.2.1.zip`
  - Size: 156,804 bytes
  - SHA-256: `9601B5E5F7EFA71DA3E09931388E23360E2B942F29140E9842B2D17AE438C00D`
- **Corresponding versioned CT artifact of the same build:**
  - File: `CESuite_Core_v0.2.1.CT`
  - Size: 143,746 bytes
  - SHA-256: `3EE702F54416294A86FF325B075D1B10A15EF3A3897FF198C6835BFF3F31F89C`

The autorun package was deployed into the Cheat Engine `autorun` directory. The
versioned CT above is the matching artifact of the same build; this record does not
claim it was the deployment mechanism used for the autorun session.

## Final re-smoke results (corrected build)

| Check | Expected | Observed | Status |
|---|---|---|---|
| **Cold start** | Clean startup without error | `CESuiteCore.version` = `0.2.1`, status `ready`, distribution `autorun` | PASS |
| **Menu registration** | Exactly one CESuite menu | Exactly one top-level `CESuite` menu | PASS |
| **Menu inventory** | Exactly 13 commands | Exactly 13 commands | PASS |
| **About CESuite** | Version and status | `CESuite 0.2.1 \| ready \| autorun` | PASS |
| **Diagnostics Summary** | Markdown report generated | Generated correctly in the viewer | PASS |
| **Viewer lifecycle** | Reopen and close safely | Opened and closed twice; zero access violations | PASS |
| **Export Reports (detached)** | Both reports from one collection | Simple Markdown and Extensive JSON generated | PASS |
| **No partial files** | No reserved temporaries remain | No `.cesuite-partial` file present | PASS |
| **No backup files** | No reserved backups remain | No `.cesuite-backup` file present | PASS |
| **Overwrite prompt — decline** | Cancel without writing | Status `cancelled`; previous reports intact | PASS |
| **Overwrite prompt — confirm** | Replace both reports | Status `complete`; outputs replaced correctly | PASS |
| **Busy guard** | Released after the operation | `Core.state.busy == false` | PASS |
| **Coexistence — analysis export** | Prior export still works | `Export Analysis Report` worked afterwards | PASS |
| **Coexistence — static export** | Prior export still works | `Export Static Lua Report` worked afterwards | PASS |
| **Limited attached smoke test** | Attach to the Cheat Engine host process | Attached; Extensive JSON generated | PASS |
| **Schema validation** | Reports conform to the runtime schema | 4 live JSON reports validated against `schemas/runtime-report.schema.json`; 0 violations | PASS |

## Earlier session (pre-correction build)

An earlier live session covered the same feature set on the build before the paired
export correction:

- File: `CESuite_Autorun_v0.2.1.zip`
- Size: 153,336 bytes
- SHA-256: `3FB830B4A39CB8E327426FDDDA9D28A127F9A75591B54C8C370B92373792B6DF`

That session recorded cold start, `About` `0.2.1`, 13 commands, `Diagnostics Summary`,
paired export with overwrite decline/confirm, busy release and a limited attached
self-process smoke test. It is kept for traceability only; the results above are the
final re-smoke on the corrected bytes.

## Scope note on attached testing

The attached check is a **limited attached smoke test** against the Cheat Engine host
process itself. It verifies that attachment state is reflected in
`target.attached`/`target.pid`, that the assessment reflects the attached state, and
that no inspected script or code block is executed during passive collection.

## Limitations

The final live validation does **not** demonstrate:

- compatibility with every game or protected process;
- compatibility with anti-cheat systems;
- behaviour on all target architectures;
- operating-system-level filesystem atomicity for the paired export;
- forced destructive I/O failures in a live session.

Paired-export failure paths (write error, reserved names, rollback to the previous
pair) remain covered by the automated test suite. Forcing an I/O failure inside a
live Cheat Engine session is not safe or non-destructive, so it is not exercised
there.
