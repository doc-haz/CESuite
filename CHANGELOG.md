# Changelog

## 0.1.1 - autorun distribution (pre-release, live CE validation pending)

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
