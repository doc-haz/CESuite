# Changelog

## 0.1.6 - Unreleased (P0-04)

- Add a pinned source/runtime evidence profile, without asserting equivalence
  or changing dependency/resource semantics. Preserve the CE API version string;
  declared version, executable file version and binary hash remain null.
- Record six representative user-chronology release-note entries as secondary,
  runtime-unvalidated evidence; no feature detection or inspected code execution.
- Extend the runtime schema to accept 0.1.6 while retaining valid legacy reports
  without the optional profile. Old validators may reject new reports.
- See docs/semantics-profile.md for evidence provenance and deferred scope.

## 0.1.5 - Unreleased

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
  Inspect Selected Script and Export ChatGPT Report.

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
