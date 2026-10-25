# Reporting and UI Integration (0.3.0 / 030E)

CESuite 0.3.0 integrates dynamic source analysis, provenance tracking, formal 4-dimension coverage, and failure limits into the existing Cheat Engine UI and exported reports.

The mission of 030E is presentation, not new analytical speculation:
> **How to present clearly and truthfully what CESuite already knows, without ever transforming static discovery into a false claim of runtime validation.**

---

## Core Visual Principle

```text
COLLECTED  ≠  DISCOVERED  ≠  VALIDATED  ≠  OPERATED
```

- **Collected:** Sources, records, and modules parsed into memory.
- **Discovered:** Lexical and dynamic signature patterns identified in source (`candidates`).
- **Validated:** Empirical memory verification against a live target process (`unique`, `ambiguous`, `no_match`).
- **Operated:** Health, timing, and execution telemetry of the inspection tool itself.

A candidate signature discovered in static source is **never** presented as working or verified until a memory scan against an attached target confirms uniqueness.

---

## Report Formats

### 1. Diagnostics Summary (UI Viewer)
Triggered via **CESuite $\to$ Diagnostics Summary**.
Renders the Markdown Simple Report inside Cheat Engine's read-only viewer dialog, followed by operational telemetry. It provides immediate, high-value assessment without modifying memory or writing files.

Includes:
- **Coverage Summary:**
  - Collection status and units processed (`complete`, `limit_reached`, `partial`).
  - Discovery status, entities discovered, and linked candidates.
  - Validation status, attempted candidates, and validated matches.
  - Clear contextual notes when detached or when no candidates exist.
- **Dynamic Analysis & Provenance:**
  - Top 10 discovered candidates (symbol, pattern, source location, consumer, status, runtime validation, and provenance trail).
  - Unresolved dependencies (source location, reason).
  - Provenance relationship counts (`defines`, `passes_to`, `calls`, `constructs`, `provides`, `requires`, `consumes`, `derives_from`, `registers`).
  - Discovered Providers and Consumers (or `unknown`).
  - Analysis limitations when limits are encountered (`TABLE_LIMIT`, `PARSE_LIMIT`, `EDGE_LIMIT`, `CANDIDATE_LIMIT`).

### 2. Simple Report (`<base>_Simple.md`)
Generated via **CESuite $\to$ Export Reports**.
Provides a human-readable, bounded Markdown summary.
- Bounded to top 10 candidates and top 10 unresolved dependencies with explicit overflow notes (`... and X more; see extensive report`).
- Contains no JSON dumps or gigantic edge lists.
- Avoids ambiguous percentages: unknown percentages are displayed as text (`null` / unknown); zero denominators never yield `100%`.

### 3. Extensive Report (`<base>_Extensive.json`)
Generated via **CESuite $\to$ Export Reports** (paired export) or **Export Analysis Report**.
Contains the complete structured JSON data adhering to `schemas/runtime-report.schema.json`.
- Embeds root-level `coverage` (Collection, Discovery, Validation).
- Embeds root-level `dynamic_analysis` (full graph of nodes, edges, dependencies, unresolved references, and patterns).
- Deterministic property sorting (`table.sort(keys)`) guarantees byte-for-byte reproducibility across runs.

---

## Candidate Presentation Rules

| Candidate Kind | Rendered Fields | Runtime Validation State |
|---|---|---|
| `literal_pattern` | Symbol, Pattern, Source, Consumer, Provenance | `not attempted` (or runtime scan result) |
| `derived_pattern` | Symbol, Helper name, Helper line, Derivation status | `not attempted` (never validated by static resolution) |
| `conditional_pattern`| Symbol, Condition dependency, Fallback | `not attempted` (resolution stays `unknown`) |
| `symbol_only` | Symbol, Consumer, Target symbol | `not attempted` |

---

## Controlled Terminology

CESuite strictly avoids speculative language:
- **Permitted:** `candidate`, `observed`, `validated (unique)`, `ambiguous`, `no match`, `error`, `unavailable`, `unsupported`, `unresolved`, `not applicable`, `not attempted`.
- **Prohibited:** `working`, `broken`, `compatible`, `incompatible`, `fixed`, `valid`.
