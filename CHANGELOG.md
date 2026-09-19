# Changelog

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
- Add synthetic regression coverage for Dawnwalker-style Lua/RVA hooks.
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