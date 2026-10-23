# CESuite 0.1.9 live acceptance - DG/AIR Boss evidence

Source: the DG's explicit mission record supplied for this documentation pass.
These actions were executed by DG/AIR Boss in live Cheat Engine, separately from
DIESEL's automated reaudit. PREMIUM records that evidence here and did not repeat
or instrument those live actions in this documentation mission. Exact session
timestamps, CE executable/build details and raw private outputs were not supplied
with this record; they are not invented. No release is declared published.

The reported package is CESuite_Autorun_v0.1.9.zip. The expected candidate hashes
are recorded in the current hygiene report; this mission separately compares
current local files with those hashes. Automated mocks, real I/O outside CE,
current live observations and historical evidence remain distinct.

## A - Clean install and cold start: PASSED

- [x] Existing installation backed up; old tree retired without deletion.
- [x] Complete clean installation from CESuite_Autorun_v0.1.9.zip.
- [x] parser-01.lua absent from the active tree.
- [x] Cheat Engine cold-restarted; About observed **CESuite 0.1.9 | ready | autorun**.
- [x] Exactly one CESuite menu.

## B - Portable and singleton: PASSED

- [x] CESuite_Core_v0.1.9.CT opened with autorun already active.
- [x] No second instance; exactly one menu remained.
- [x] About remained **0.1.9 | ready | autorun**; Analyze still worked.

## C - Complete small export (Silksong): PASSED

Process/module: `Hollow Knight Silksong.exe`.

```json
{
  "status": "complete",
  "bytes_written": 692224,
  "size": 692224,
  "unreadable_ranges": [],
  "schema_version": "module-dump-1",
  "atomic_snapshot": false,
  "binary_fingerprint": null
}
```

Binary and JSON were produced. The operation finished within the same second in
this particular test; this is an observation, not a general benchmark or a
subsecond precision measurement. atomic_snapshot:false and null fingerprint
remain limitations, not claims of atomicity or build identity.

## D - Large export, progress and responsiveness: PASSED for observed UI

Module: `FFRS-WinGDK-Shipping.exe`; size **461701120 bytes**, about **440.3 MiB**.

- [x] Progress window updated MiB and percentage. Observed example:
      **35.3 / 440.3 MiB (8%)**, with other percentages during tests.
- [x] CE remained responsive; the earlier apparent "Not responding" state did
      not recur during these tests.

This evidence does not assert a complete large export or a measured total large
export time: neither result was supplied. It also does not prove instrumentation
of the internal processMessages() call merely from visible responsiveness.

## E - Cancel and progress-window close: PASSED

- [x] Cancel button worked; readable JSON and `.module.bin.partial` were produced.
- [x] Observed sidecar values:

```json
{
  "status": "partial",
  "cancelled": true,
  "bytes_written": 88080384,
  "size": 461701120,
  "atomic_snapshot": false
}
```

Reported reason: `Cancelled by user`. This is the supplied reason, not an
invented exact full error string or internal source-path transcript.

- [x] Closing the progress window with X requested/produced safe cancellation.
- [x] Partial output was correctly generated; CE did not remain blocked.

The UI close behavior is observed; no additional claim about uninstrumented
internal OnClose/native-object paths is made.

## F - Busy guard: PASSED

- [x] During an active dump, a second protected action was rejected with
      `CESuite is already analyzing`.
- [x] The export already in progress continued.
- [x] After cancellation/completion CESuite recovered its normal state.

## G - Save dialog: PASSED

- [x] Cancelling the file selector created neither binary nor .partial.
- [x] Closing the selector with X had the same safe behavior.
- [x] CESuite returned to normal and Analyze worked afterwards.

These are live save-dialog behaviors; other unobserved internal API paths remain
unverified rather than inferred from mocks.

## H - Overwrite decline and close: PASSED

- [x] Dialog displayed existing files.
- [x] Selecting No displayed `overwrite cancelled; existing files were kept.`
- [x] Existing files were preserved; no new .previous was created and no dump began.
- [x] Closing the confirmation dialog with X acted as a safe rejection.

Preservation is DG-observed. No unsupplied before/after hash or timestamp
measurement is claimed.

## I - Overwrite confirmation: PASSED

- [x] Yes preserved previous outputs; the new dump completed.
- [x] .previous backups appeared and the new JSON contained previous_files.
- [x] Real reported mapping (basenames shown; no destination path invented):

| original | backup |
| --- | --- |
| Hollow Knight Silksong.exe.module.bin | Hollow Knight Silksong.exe.module.bin.previous |
| Hollow Knight Silksong.exe.module.bin.json | Hollow Knight Silksong.exe.module.bin.json.previous |

## J - Backup collision: PASSED

- [x] A second overwrite preserved .previous and created .previous.1.
- [x] previous_files pointed correctly to .previous.1; earlier backups remained.

## K - Paths with spaces: PASSED for reported paths

- [x] Exercised with `Hollow Knight Silksong.exe.module.bin` and WindowsApps paths
      containing spaces. Exact full paths are not supplied here or invented.

## L - General recovery: PASSED

- [x] Following cancellation, dialogs and overwrites, CESuite returned to normal.
- [x] Analyze worked and the busy guard did not remain engaged.

## Pending or conditional live checks

- [ ] MODULE-SNAPSHOT-INCOMPLETE with two real homonymous modules, **conditional
      on obtaining a real case**. This is optional/conditional, not an automatic blocker.
- [ ] Specific R-1 check for section header plus content on the same line inside CE.
- [ ] Any internal API path without direct DG evidence, including precise native
      dialog/object-lifetime or processMessages instrumentation. UI observations
      above must not be expanded into blanket internal API validation.
- [ ] Exact total large-export duration and successful complete large-export
      sidecar, if a separate performance/completion record is desired. Neither
      was supplied in the present evidence.

Historical CE 0.1.3 observations, the old 440 MiB attempt and the successful
BIN/report/PREMIUM-generated-table workflow remain separate observations. The
private Dawnwalker replay input is still unavailable: expected SHA-256
`d2664fee953bc1953dad280119fcd95bd3ddd5b83d2647e421f87d26708007fa`;
metrics 117 / 21 / 96 / 21 / 42 / 87 / 16 remain historical and pending current
revalidation. That replay is not a mandatory clean-clone gate.
