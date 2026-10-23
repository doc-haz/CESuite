# Changelog

## 0.2.0-beta1 - Beta

- **Static Lua AOB Analysis**: Added passive lexical analysis of table Lua scripts for supported AOB patterns (literal assignments, variable concatenations, table indexing, multi-custom-scan wrappers, and unlinked library declarations).
- **Two New In-CE Menu Actions**:
  - `Static Lua AOB Analysis`: runs passive lexical Lua analysis on the loaded table and displays results in the read-only JSON viewer.
  - `Export Static Lua Report`: exports a full runtime report enriched with the `static_lua_analysis` section.
- **Enriched Export**: `Core.exportEnriched()` exports a full report with `static_lua_analysis` without executing user scripts or target code.
- **Strict Evidence Separation**: Lexical static source observations are held under `static_lua_analysis` (or `lua_aobs`) with `provenance: "static-lua"` and `uniqueness: "unverified"`; lexical candidates are never promoted to memory-verified runtime observations.
- **Runtime Compatibility**: Runtime report format, `core_version: "0.1.9"` compatibility level, and runtime schema validation are strictly preserved.
- **Rollback Procedure (Beta → v0.1.9.1)**:
  To roll back from 0.2.0-beta1 to v0.1.9.1:
  1. Completely delete or move the `cesuite/` folder and `CESuite_Autorun.lua` from your CE `autorun` directory. Do not overwrite or blend files in-place to avoid leaving `luastatic.lua` orphaned.
  2. Extract the complete clean `CESuite_Autorun_v0.1.9.1.zip` archive into the `autorun` directory.
  3. Restart Cheat Engine completely.
  4. Verify **CESuite → About CESuite** reports `0.1.9.1` and status `ready`.

## 0.1.9.1 - Hotfix

- Renamed the user-facing `Export ChatGPT Report` action to `Export Analysis Report`.
- Updated documentation to describe the report as vendor-neutral structured analysis evidence.
- No report schema, JSON structure or runtime behavior changed.

## 0.1.9 - Unreleased (current local candidate)

### Overwrite and backups

- Add explicit Module Dump overwrite confirmation covering binary, partial and
  JSON outputs. Declining preserves existing files; confirming retains prior
  outputs as `.previous` / `.previous.N`, recorded in `previous_files`.
- Failed/cancelled replacement exports preserve those backups.

### P0-05 / P0-06 / P0-07 technical closure

- Fail closed on incomplete/embedded LuaCode; process all same-line conditionals.
  Keep unknown branches and HOOK/UNHOOK/HOOK5/aobscanfunction/aobscanregion opaque.
- Emit SECTION-INDETERMINATE for conditional/opaque section headers and preserve
  `section: "unknown"` until an explicit unmasked header establishes provenance.
- Share name/path module matching; reject invalid/empty names before MemScan and
  omit ambiguous module sizes with MODULE-SNAPSHOT-INCOMPLETE. No first-match.
- Add module-dump-1 JSON Schema, real serialized-sidecar contract coverage,
  deterministic isolated runtime fixtures and 40-case Lua/Python evidence parity.
- Update complete 0.1.9 installation/upgrade instructions with mandatory CE restart.
- DIESEL independently closed P0-05/P0-06/P0-07 technical criteria: **185 checks,
  0 skips, 0 failures**, using Python 3.14.7 64-bit and jsonschema 4.26.0.
- Dawnwalker metrics remain historical pending the exact private input; no new
  historical replay or clean-clone requirement is asserted.

### Current live observations (DG/AIR Boss)

- Clean autorun installation/cold start and portable loading retain one singleton
  and one menu; About remains 0.1.9 | ready | autorun; Analyze works.
- Small Silksong module export completed (692224 bytes); large FFRS export showed
  responsive progress. Cancel/close safely retained partial output and readable JSON.
- Save-dialog cancel/close, busy guard/recovery, overwrite No/close and Yes,
  `.previous`/`.previous.1` collision handling, `previous_files`, and paths with
  spaces were exercised. See docs/validation/live-0.1.9.md for exact evidence/limits.
- These observations do not establish every internal API path or general performance.
  Real homonymous modules and the specific same-line section/header R-1 check
  remain conditional/pending. No release has been published by this mission.

## 0.1.8 - Local development increment (included in 0.1.9 candidate)

- Fix the unresponsive Module Dump UI with progress, Cancel and event handling
  between blocks; remove redundant per-byte Lua validation overhead. Preserve
  partial-file and busy-state safeguards.

## 0.1.7 - Local development increment (included in 0.1.9 candidate)

- Introduce explicit Export Module Dump with mapped-image output, status sidecar,
  bounded reads, partial-file handling and PID/module checks. Passive report
  capture is unchanged. See docs/MODULE_DUMP.md.

## 0.1.6 - Local development increment (P0-04; included in 0.1.9 candidate)

- Add a pinned source/runtime evidence profile, without asserting equivalence
  or changing dependency/resource semantics. Preserve the CE API version string;
  declared version, executable file version and binary hash remain null.
- Record six representative user-chronology release-note entries as secondary,
  runtime-unvalidated evidence; no feature detection or inspected code execution.
- Extend the runtime schema to accept 0.1.6 while retaining valid legacy reports
  without the optional profile. Old validators may reject new reports.
- See docs/semantics-profile.md for evidence provenance and deferred scope.

## 0.1.5 - Local development increment (included in 0.1.9 candidate)

- Preserve raw dependency occurrences and add deterministic lexical groups by
  exact name, kind, source and relation; deduplicate displayed locations only.
- Retain occurrence counts and one-based references to the original evidence,
  with unique script IDs and sections; never infer resolved edges or availability.
- Add a Dependency Summary menu view and backward-compatible runtime schema.
- Generalize Lua global detection beyond a fixed namespace; exclude explicit locals,
  keywords, standard Lua names and a static exact-name CE API catalog.
- Keep AA detection and Lua/RVA resources unchanged; no inspected code runs.
- Add same-line, cross-script, mixed-relation and legacy JSON regressions.
- Offline validation only; no new live CE validation or release.

## 0.1.4 - First lexical dependency inventory

- Extend embedded Lua inventory with conservative namespace-limited global occurrences,
  source lua_lexical and status unverified; exclude strings/comments and explicit
  locals, retain parent source lines and ENABLE/DISABLE sections.
- Add partial, unverified provides/requires occurrences with script, line, section
  and command provenance; no source execution or cross-script resolution.
- Preserve existing resources, labels, defines and diagnostics.
- Extend runtime schema 0.1 with dependencies required for Core 0.1.4; retain older
  reports and describe the existing 0.1.3 Lua/RVA hook resource shape.
- Add synthetic parser, exported JSON contract and distribution regression tests.
- Live CE integration for this increment remains unverified.
- See docs/dependencies-v0.1.4.md for the deliberately limited detection rules.

## 0.1.3 - Lua/RVA hook inventory

- Add conservative lexical detection of Lua static RVA hooks without executing
  inspected Lua or generated Auto Assembler.
- Detect module + RVA hook structure from patterns such as `getAddress(module)`
  followed by `source = base + RVA`.
- Capture expected/original byte arrays and report their observed lengths.
- Report whether the inspected Lua contains runtime AA generation and target-side
  allocation candidates such as `autoAssemble(...)` and `allocateMemory(...)`.
- Add `LUA-RVA-HOOK` review diagnostics while retaining `DYNAMIC-SOURCE` to keep
  runtime semantics explicitly unverified.
- Add synthetic regression coverage for static Lua/RVA hooks.
- Verified against Cheat Engine 7.7.1 using a live selected-script inspection.

## 0.1.2 - CE 7.7.1 UI hotfixes

- Fix report viewer compatibility when `Memo.Lines` is unavailable by falling
  back to `Memo.Text`.
- Keep the report viewer alive with `caHide` so closing the window does not leave
  stale native object references.
- Prevent the Access Violation observed when reopening CESuite reports after
  closing the viewer.
- Live-tested on Cheat Engine 7.7.1 with Analyze Loaded Table, Validate AOBs,
  Inspect Selected Script and Export Analysis Report.

## 0.1.1 - autorun distribution (pre-release)

- Add permanent `CESuite_Autorun.lua` and modular `cesuite/` ZIP packaging using
  `getAutorunPath()` and explicit absolute-path loading in private environments.
- Share singleton/reentrant-load guards between portable and autorun modes;
  preserve existing instance/report state and guard repeated menu installation.
- Add version/status/distribution exposure and About menu; handle failed module
  loading and partial menu creation with cleanup and retry support.
- Generate deterministic versioned CT/ZIP artifacts while retaining existing
  portable CT/Lua paths. No network, credentials or Release publication.
- Accept Core 0.1.1 in the unchanged 0.1 report format, retaining 0.1.0 reports.
- Document exact CE 7.7.1 installation paths, local permissions, upgrade/removal
  and remaining live validation. Add extracted-package and mixed-load tests.

## Core Runtime 0.1.0 — 2026-09-18

- Add modular local/offline CE process, CT/AA/Lua, AOB and disassembly observations.
- Preserve original AOB scopes; count all scan matches and export bounded context.
- Separate observed signature anchors from inferred hook candidates and keep
  current-scan uniqueness distinct from unverified cross-build robustness.
- Add versioned runtime JSON schema, CE menu/report viewer, lifecycle diagnostics,
  deterministic self-contained CT/Lua release packaging and synthetic Lua/Python tests.
- Keep unsupported APIs/expressions and ownership/restore/relocation claims explicit.
- Validation is synthetic/static only; live CE x86/x64 process acceptance is pending.

## CT Analyzer 0.1 — existing baseline

- Offline CT XML inventory, conservative AA/Lua diagnostics and report schemas.
