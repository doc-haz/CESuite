# Roadmap

## 0.1 — offline baseline (implemented)

Bounded CT XML ingestion, MemoryRecord hierarchy, full AA/Lua extraction, common AA command inventory, dependency hints, advisory warnings, JSON/Markdown reports, synthetic regression fixtures and versioned schemas.

## Next — stronger static diagnostics (planned)

Token-aware AA/Lua parsing; include provenance without execution; source spans; configurable severity; resource ownership and lifecycle modeling; duplicate-ID diagnostics; dependency graph review; schema validation in CI; larger synthetic corpus.

## Core Runtime 0.1.0 — observation/export milestone (implemented; live acceptance pending)

Modular CE process/architecture/module observations, loaded-table AA/Lua inventory,
scoped AOB match counts, separate anchor/hook candidates, bounded bytes/disassembly,
branch metadata and limited RIP-relative recognition, runtime schema, CE menu/viewer,
offline JSON export and a deterministic self-contained `CESuite_Core.CT`.
Synthetic Lua/API-mock and schema/package tests cover implementation behavior.
Live x86/x64 CE API, scope endpoints and UI acceptance remain to be performed.

## Next — stronger runtime evidence and integration (planned)

Static/runtime evidence joining, stable fingerprints and semantic diff; asynchronous
scan progress/cancellation; richer parser provenance and CE version coverage;
broader instruction decoding and relocation analysis; exact overwrite/restore
comparison, allocation reach and quiescence checks. Preserve explicit unknowns.
Current-build uniqueness never implies cross-build support or hook compatibility.

## Later — porting and authoring (planned)

Source-preserving CT diffs, guided injection plans, lifecycle templates, diagnostics UI and export. Preserve existing functionality and originals. Runtime writes and generated hooks require a separate explicit user workflow; 0.1 generates no executable patches.
