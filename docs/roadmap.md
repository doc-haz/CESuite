# Roadmap

## 0.1 — offline baseline (implemented)

Bounded CT XML ingestion, MemoryRecord hierarchy, full AA/Lua extraction, common AA command inventory, dependency hints, advisory warnings, JSON/Markdown reports, synthetic regression fixtures and versioned schemas.

## Next — stronger static diagnostics (planned)

Token-aware AA/Lua parsing; include provenance without execution; source spans; configurable severity; resource ownership and lifecycle modeling; duplicate-ID diagnostics; dependency graph review; schema validation in CI; larger synthetic corpus.

## Later — explicit runtime evidence (planned)

Opt-in current-build AOB scope/uniqueness validation, architecture-aware disassembly and relocation analysis, exact overwrite/restore comparison, allocation reach and quiescence checks. Results must distinguish observed runtime facts from static guesses and never infer cross-build support from one build.

## Later — porting and authoring (planned)

Source-preserving CT diffs, guided injection plans, lifecycle templates, diagnostics UI and export. Preserve existing functionality and originals. Runtime writes and generated hooks require a separate explicit user workflow; 0.1 generates no executable patches.
