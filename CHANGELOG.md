# Changelog

## 0.3.1 - Evidence Snapshots

- Evidence Snapshots menu with Capture, Open and Compare.
- Deterministic snapshot identity with source and target fingerprints.
- Coverage, candidates, provenance, dependencies, unresolved evidence and limitations preserved as observed.
- Read-only sectioned memo viewer; comparison uses neutral classifications only.
- Bounded 8 MiB JSON storage, temporary-file promotion, overwrite preservation and fail-closed corruption handling.
- Privacy sanitization for provider/helper paths, condition dependencies, limitations and target/module names.
- Snapshot corpus and corruption fixtures.
- 542 consolidated checks, 0 failures, 0 skips.
- v0.3.0 remains the published baseline.

## 0.3.0 - Dynamic Table Analysis and Validation Coverage

Release candidate. Adds dynamic Lua/table analysis, provenance for table-driven
pattern candidates, an explicit collection/discovery/validation coverage model,
coverage-aware reporting, and a reproducible regression corpus.

- Script-95 fixture and live table: 47 entries, 52 specs, 31 candidates, 0 runtime validated.
- Runtime AOB results are the only source of validation; static resolution is not validation.
- Limits remain fail-closed and percentages stay null when the universe is unknown.
- 476 consolidated checks, 0 failures, 0 skips.
- Published v0.3.0 baseline.

## 0.3.0-dev - Reporting & UI Integration

- **Coverage Summary**: Diagnostics Summary and Simple Report extend the assessment with an explicit, compact `Coverage Summary` block detailing Collection, Discovery, and Validation dimensions without conflating static discovery with runtime validation.
- **Dynamic Analysis & Provenance presentation**: Simple Report surfaces top discovered candidates, derivation provenance (helper source and line), conditional branches (resolution unknown), top unresolved dependencies, provenance edge counts, and discovered providers/consumers.
- **Controlled Terminology**: eliminates speculative language (`working`, `broken`, `fixed`); uses strict status taxonomy (`candidate`, `validated (unique)`, `ambiguous`, `no match`, `error`, `unavailable`, `unresolved`, `not applicable`).
- **Bounded Presentations**: candidate and unresolved listings bounded to top 10 with explicit overflow indicators; limitations clearly stated when thresholds (`TABLE_LIMIT`, `PARSE_LIMIT`, etc.) are reached.
- **Extensive Report Parity**: runtime JSON report embeds `dynamic_analysis` alongside `coverage`; schema updated and validated with Draft 2020-12.
- **Tests & Verification**: 476 consolidated passing checks across all suites (Python contracts, analyzer tests, Lua specs, reporting UX specs, and parity checkers), 0 failures, 0 skips.

## 0.3.0-dev - Dynamic Table Analysis (unreleased)

- **Static dataflow core**: new `ce/modules/dynamic.lua` resolves local scalar/table declarations, ordered nested rows, member/index references and lexical scopes without executing table Lua.
- **Wrapper contracts**: declarative contracts follow `Register.onEnable` table sets through `Register.multiCustomScan` and record `constructs` provenance for the generated `aobScanRegion` AA text.
- **Helper resolution**: captured helper files provide `UE.Sig.FName`, `UE.Sig.GUObjectArray` and `UE.Sig.GEnigne[2]` values; `findTableFile`/`_G.Name = include(...)` loader bindings become `includes`/`provides` edges.
- **Multi-provenance graph**: dependencies carry multiple edges (`passes_to`, `calls`, `constructs`, `provides`, `requires`, `derives_from`, ...) with `lua_local`/`lua_literal`/`lua_dynamic`/`wrapper`/`external_helper` provenance.
- **Pattern candidates**: `literal_pattern`, `derived_pattern`, `conditional_pattern` and `symbol_only`; duplicate instances are preserved; every candidate keeps `runtime_validated=false`.
- **script-95 acceptance fixture**: 47 entries, 52 specs, 28 literal (27 unique), 3 derived, 1 conditional, 21 symbol_only (20 pure), 30 unique symbols, 31 candidates, 0 runtime validated.
- **Local scope fix**: locals declared in an earlier Lua block of the same AA script are no longer reported as globals in later blocks.
- **Static report**: optional `dynamic_analysis` block; runtime report, operation telemetry and Address Evidence are unchanged.
- **Corrective pass**: conditional candidates now expose a public JSON-safe `condition` (`conditional_expression`, text, dependencies, resolution=unknown, fallback) instead of an internal AST; table/parse/edge/candidate limits propagate to `status=limit_reached`; exact duplicate edges are de-duplicated by relation/from/to/script/line/provenance; conservative `sharedLocals` remains documented.
- **Coverage model**: optional `coverage` block with independent `collection`, `discovery` and `validation` dimensions, explicit denominators, `universe_known`, nullable percentages and fail-closed limits. `source_complete` remains collection-only. Runtime AOB results map only to runtime validation counts.
- No coverage model, UI, runtime tracing or release artifacts in this phase.

## 0.3.0-dev - Regression Corpus

- Added `ce/tests/fixtures/corpus/` with a manifest and fixtures for dynamic tables, wrappers, real callbacks, data-table non-callbacks, helpers, loaders, constructed AA, provenance, duplicate patterns, scope, limits, coverage and runtime replay.
- Added explicit callback provenance for `registerCallback`-style APIs, without name-based inference; `DhaosCollider` remains a local data table.
- Added `docs/regression-corpus.md` (fixture contract, clean-room guidance, static/runtime separation).
- Corpus manifest validation checks unique ids, categories, files, invariants and `runtime_required`.
- No parser/coverage semantic change beyond the callback fixture; runtime scanning is not modified.

## 0.2.3 - Performance & Operation Diagnostics

- **Separate Operation Metadata**: runtime and static Lua reports may carry an optional `operation` block with `status` (`complete`, `partial`, `cancelled`, `failed`, `unavailable`), `source_complete`, `partial`, `cancelled`, structured `warnings` and metrics. Evidence statuses are unchanged and remain independent.
- **Reliable Metrics Only**: `duration_ms`, `parse_ms`, `scan_ms`, `export_ms`, `serialize_ms`, `write_ms`, `source_bytes`, `export_bytes`, `items_processed`, `items_total`, `operations_attempted`, `operations_completed`. Metrics are nullable; no invented numbers. Timings are decimal milliseconds.
- **Clock**: `getTickCount()` (millisecond tick count, wrap-safe) is preferred; `os.clock()` CPU time is a documented fallback marked `TIMING_APPROXIMATE`. No UTC timestamp arithmetic.
- **Fail-Open Telemetry**: a missing clock or metric yields `null` plus `TIMING_UNAVAILABLE`; analysis, validation, export and Address Evidence never fail because of telemetry.
- **Source Completeness**: `source_complete` is true only when the live target and every planned scan/source unit were traversed; cancellation, truncation, bounded limits, target changes and unavailable runtime evidence clear it.
- **Export Timing**: `Core.last_export_operation` and the paired export result expose `export_ms`/`serialize_ms`/`write_ms`/`export_bytes`; the timing is deliberately not written into the document it measures (that would be circular).
- **Operation Summary**: Diagnostics Summary appends an informative Operation Summary. No FAST/SLOW/GOOD/BAD verdicts are produced.
- **Detached Completeness Hotfix**: a cached PID with an empty module inventory no longer counts as a live target. `source_complete` also requires `items_processed = items_total` (or zero planned items), so a detached run with 7 planned AOBs and 0 completed can never report `complete`/`source_complete=true`; it reports `unavailable` with `RUNTIME_SOURCE_UNAVAILABLE`.
- **Address Evidence**: remains a pure evidence document without an `operation` block.
- **Tests**: 371 passing checks (Lua runtime, operations, diagnostic assessment, address evidence, module dump, distribution, parser parity, static Lua parity, static Lua, assessment and address-evidence schemas, Python contracts), 0 failures, 0 unexpected skips.
- **Compatibility**: additive. Existing schemas, APIs, menu names and report fields remain valid; `core_version` stays `0.1.9`.

## 0.2.2 - Address Evidence Inspector

- **Explicit Address Inspection**: `Core.inspectAddress(input, options)` collects read-only evidence for one address. It is never called from `collectReport()` and never writes memory, sets breakpoints or installs hooks.
- **Controlled Input Grammar**: hex literals (`0x…` or bare hex), `module+RVA` resolved through the module inventory, and numeric Memory Viewer selections. Arbitrary CE expressions are not evaluated (`getAddress`/`getAddressSafe` are not used).
- **Structured Evidence**: query resolution, target, module/RVA, memory region and protection, bounded bytes, instruction decode, memory operand, effective address, type advisory, provenance, status, limits and limitations.
- **Conservative Decoder From Bytes**: new self-contained decoder (prefixes, REX, selected one-byte opcodes, selected SSE opcodes and x87 memory forms) that never calls `disassemble()` or `splitDisassembledString()`. Unsupported opcodes report `unsupported`; truncated bytes report `truncated`. Operand size is tracked in bits, so byte opcodes (`88`/`8A`/`C6`) always decode as 8-bit. 8-bit registers follow REX semantics: without REX indexes 4-7 are `ah/ch/dh/bh`, with any REX prefix they are `spl/bpl/sil/dil`, and `r8b`-`r15b` are available in 64-bit mode. SSE `0F 10/11/28/29` differentiate on prefixes: no prefix `movups/movaps`, `66` `movupd/movapd`, `F3` `movss`, `F2` `movsd`.
- **Effective Address Only When Proven**: RIP-relative and absolute static operands are resolved; register-dependent operands report `requires_runtime_context` and never read Lua register globals.
- **Type Advisory**: `movss`/`movsd`/SSE arithmetic and x87 `dword`/`qword` operands suggest `Float`/`Double` with documented confidence. The report states an inferred advisory type, never a confirmed type.
- **Region and Protection Evidence**: `getMemoryRegionInfo` preferred, bounded `enumMemoryRegions` fallback. Raw protection mask preserved; `READONLY`, `READWRITE`, `WRITECOPY`, `EXECUTE*`, `GUARD`, `NOACCESS` decoded. `Allocation Size` is not invented from `RegionSize`.
- **Bounded Bytes**: maximum 64 bytes per inspection; region-boundary clamping, partial reads and a bounded byte-by-byte fallback. A partial read never becomes a fatal error.
- **Standalone Schema**: `schemas/address-evidence.schema.json` (strict, `suite_version 0.2.2`, `core_version 0.1.9`). The runtime report schema is unchanged.
- **In-CE UI**: `Address Evidence Inspector` with `Inspect`, `Use Memory Viewer Selection`, `Copy JSON`, `Export JSON` and `Close`; read-only form, no timers or background work.
- **Detached Target Safety**: a cached PID or process name is no longer proof of attachment. CESuite requires a non-empty module inventory from the live target; otherwise it reports `target.attached=false` and `target.status=detached` (or `unknown` when no process is opened), clears the cached process name, keeps module/region/bytes `unknown`, and never emits `OUTSIDE_MODULE` or `UNMAPPED_ADDRESS` as `observed`. Hex addresses still resolve syntactically; `module+RVA` becomes `unavailable`. New `TARGET_DETACHED`/`TARGET_UNAVAILABLE` diagnostics.
- **Native Menu Icons**: commands reuse Cheat Engine's own menu icons through a version-guarded mapping of `ImageIndex` values validated on CE 7.72 (16x16 host ImageList, 40 images). CESuite never writes to, replaces or copies host image resources. Unknown CE versions, a missing ImageList or an out-of-range index leave the menu text-only; icon failure never affects command behavior. A one-shot self-destroying refresh re-applies the mapping after CE finishes populating its ImageList. Command names, callbacks and behavior are unchanged.
- **Menu Organization**: the CESuite menu is grouped with real menu separators into inspection, analysis, export and maintenance blocks, with About CESuite last. Command names, callbacks and behavior are unchanged.
- **Out of Scope**: breakpoints, watchpoints, tracing, patching, pointer records, AOB generation, CE expression evaluation, disassembler hooks and memory writes.
- **Tests**: 352 passing checks (Lua runtime, diagnostic assessment, address evidence, module dump, distribution, parser parity, static Lua parity, static Lua, assessment and address-evidence schemas, Python contracts), 0 failures, 0 unexpected skips.

## 0.2.1 - Reporting & Repair Guidance

- **Diagnostic Model**: New derived layer (`ce/modules/diagnose.lua`) interprets evidence that already exists in a runtime report and produces a structured `assessment` with deterministic ordering. It never scans, edits, executes inspected code or invents evidence.
- **Simple Report**: New Markdown report (`<base>_Simple.md`) that states what CESuite analyzed, what looks OK, what presents problems, the evidence and confidence behind each problem, possible causes, suggested next steps, limitations, do-not-assume notes and a fixed review order.
- **Extensive Report**: New JSON report (`<base>_Extensive.json`) containing the runtime report, static Lua evidence and the same `assessment`, usable manually or by external tooling.
- **New Menu Actions**:
  - `Diagnostics Summary`: shows the Simple Report in the read-only viewer without writing files.
  - `Export Reports`: writes the Simple and Extensive reports from one single collection.
- **Supported diagnostics (evidence already collected)**: missing attachment, process change, unavailable or ambiguous module snapshot, AOB zero-match, AOB multiple-match, AOB unique (healthy), AOB not scanned, AOB unsupported, AOB scope unresolved, AOB scan error, aggregated unavailable/invalidated scans, unresolved lexical dependency provider, static Lua candidate only, unresolved static pattern, static analysis limit, aggregated review diagnostics and insufficient evidence.
- **Status and confidence semantics**: `observed`, `candidate`, `unknown`, `unsupported`; `high`, `medium`, `low`, `unknown` with documented criteria. Static and lexical evidence can never be reported as a runtime observation; the schema enforces it.
- **Fixed Repair Path**: documented, deterministic priority (target, modules, zero-match, ambiguous, unusable scans, dependencies, static-only, review, insufficient evidence); within a priority, sorted by severity and diagnostic id.
- **Schema Extension**: `assessment` added to the runtime report schema as an optional, additive object. `core_version` remains `0.1.9` and existing reports still validate.
- **No Autofix**: v0.2.1 does not modify AOBs, scripts, offsets, hooks, memory or target code.
- **Dependency inventory**: Cheat Engine AOB scan API spellings (`AOBScanModule`, `AOBScanRegion`) are no longer treated as table dependencies, and the diagnostic layer never reports AOB sink names as unresolved table symbols.
- **Paired Export**: `Export Reports` now behaves as one atomic pair. Both documents are written to reserved temporary names, existing reports are moved to reserved backup names, and the pair is only promoted when both documents are complete. A failure restores the previous pair and leaves no partial or mixed output; reserved names are never deleted. Exact semantics in `docs/reporting.md`.
- **Controlled Export Errors**: `Core.exportReports()` returns `complete`, `cancelled` or `failed` status tables (with the previous files intact) instead of leaving a partial write; the simple-report writer reports I/O errors instead of throwing, and the busy guard is always released.
- **Credits**: single attribution, `doc-haz` (formerly `dokkoriax`), with a note that earlier history may use the previous handle; schema `$id` aligned to the current repository handle.
- **Documentation**: new `docs/reporting.md` (rules, confidence, ordering, formats, export semantics, limits); installation documentation generalized for supported Cheat Engine versions; neutral AI-assisted development statement restored in the README credits without internal team names; new `docs/validation/live-0.2.1.md` live evidence.
- **Tests**: 284 passing checks (Lua runtime, diagnostic assessment, paired export, module dump, distribution, parser parity, static Lua parity, static Lua schema, assessment schema and Python contracts), 0 failures, 0 unexpected skips.

## 0.2.0 - Final Stable Release

- **Static Lua AOB Analysis**: Passive lexical analysis of table Lua scripts for supported AOB patterns (literal assignments, variable concatenations, table indexing, multi-custom-scan wrappers, and unlinked library declarations).
- **In-CE Menu Actions**:
  - `Static Lua AOB Analysis`: runs passive lexical Lua analysis on the loaded table and displays results in the read-only JSON viewer.
  - `Export Static Lua Report`: exports a full runtime report enriched with the `static_lua_analysis` section.
- **Formal Standalone Schema**: Added `schemas/static-lua-report.schema.json` formalizing the exact contract of standalone static Lua analysis reports produced by `Core.analyzeStaticLua()`.
- **Enriched Runtime Reports**: `Core.exportEnriched()` exports a full runtime report enriched with the `static_lua_analysis` section alongside standard runtime observations without executing user scripts or target code.
- **Strict Evidence Separation**: Lexical static source observations are held under `static_lua_analysis` (or `lua_aobs`) with `provenance: "static-lua"` and `uniqueness: "unverified"`; lexical candidates are never promoted to memory-verified runtime observations.
- **Single Source of Truth for suite_version**: Canonical tool version defined in `Core.version` (`0.2.0`), shared across runtime, exporter, tooling and tests.
- **Parity & Dual Implementation**: Dual Lua 5.3 and Python analyzer engines verified with 10/10 corpus test parity.
- **Licensing**: Formally licensed under the Apache License, Version 2.0.
- **Runtime Compatibility**: Runtime report format, `core_version: "0.1.9"` compatibility level, and runtime schema validation are strictly preserved.

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
- Independent technical review closed P0-05/P0-06/P0-07 criteria: **185 checks,
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
