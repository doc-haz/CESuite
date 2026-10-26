# CESuite

Offline and in-CE Lua AOB static analysis supports literal assignments,
concatenation, tables and embedded Lua libraries without executing inspected
code. See [usage and limitations](docs/static-lua-aobs.md).

A local analysis, diagnostics and evidence-export toolkit for Cheat Engine tables and attached processes.

[Latest Release](https://github.com/doc-haz/CESuite/releases/latest) · [Installation](docs/installation.md) · [Runtime Reference](docs/runtime-core.md) · [Reporting](docs/reporting.md) · [Reporting & UI](docs/reporting-ui.md) · [Address Evidence](docs/address-evidence.md)

CESuite runs locally inside Cheat Engine 7.x (Windows, 64-bit and 32-bit processes).

It provides:

- passive inspection of loaded `.CT` tables, records, Auto Assembler scripts and Lua code;
- offline and in-CE static Lua analysis and AOB signature extraction;
- validation and uniqueness verification for supported literal AOB scans;
- conservative dependency analysis for symbols, resources and registered names;
- diagnostic assessment that explains apparent failures, the evidence behind them and a fixed review order;
- read-only Address Evidence Inspector for one explicit address (hex or module+RVA), with stale-PID/detached-target detection;
- optional operation telemetry (timings, source completeness and structured warnings) kept separate from evidence diagnostics;
- static dynamic-table analysis (0.3.0): local tables, wrapper contracts and multi-provenance pattern candidates;
- explicit coverage model (0.3.0): collection, discovery and validation are separate dimensions;
- reproducible regression corpus (0.3.0): real-world fixtures for callbacks, loaders, limits, coverage and runtime replay;
- reporting and UI integration (0.3.0): Coverage Summary, Discovered Candidates, and Provenance presentation without confusing discovery with validation;
- Evidence Snapshots (0.3.1): read-only capture/open/compare with source and target fingerprints, bounded JSON storage and neutral comparison;
- native Cheat Engine menu icons (validated mapping for CE 7.72, never modifying host resources);
- Simple (Markdown) and Extensive (JSON) reports derived from the same evidence;
- mapped PE module dumping with structured JSON sidecars;
- structured JSON evidence export for manual review and auditing.

Module dumping is an explicit action: CESuite never reads module memory or writes `.bin` files automatically.

## CESuite v0.3.1 — Evidence Snapshots

Capture what CESuite currently knows, save that evidence, and compare it later
without modifying the table or target. The viewer is a read-only, sectioned memo
(not a tabbed UI). Snapshots are bounded JSON files with explicit Capture, Open
and Compare actions.

v0.3.1 remains a freeze candidate; publication is a separate authorization step.
The local freeze suite is 542 checks.

## User-facing actions

Under the **CESuite** menu in Cheat Engine's main form. Commands are grouped with
real menu separators in five blocks: inspection, analysis, export, maintenance and
about. `About CESuite` is always the last item. Commands reuse a small, semantic
mapping of Cheat Engine's own native menu icons (validated only for CE 7.72); the
host `ImageList` is never modified or replaced, and unknown versions keep the menu
text-only.

| Action | Description |
| --- | --- |
| **Analyze Current Process** | Process status, architecture and loaded modules. No table or script dependencies. |
| **Analyze Loaded Table** | Complete passive inspection of the current table: records, AA scripts, resources, dependencies and diagnostics. Target memory is not read. |
| **Validate AOBs** | Fresh process/table capture and scans for supported literal `aobscan` / `aobscanmodule` patterns, with counts and available match addresses. |
| **Inspect Selected Script** | Narrows analysis to the currently highlighted record and its script. |
| **Address Evidence Inspector** | Read-only evidence for one explicit address: resolution, module/RVA, region and protection, bounded bytes, a conservative instruction decode, operand/effective-address evidence and a type advisory. No breakpoints, writes or expression evaluation. |
| **Dependency Summary** | Grouped lexical dependency occurrences, preserving raw evidence; not a resolved runtime dependency graph. |
| **Diagnostics Summary** | Derives the diagnostic assessment from one fresh collection and shows the readable Simple Report (Markdown) in the viewer. No files are written. |
| **Export Analysis Report** | Saves a fresh normalized JSON report for manual review, external tooling or later analysis. You choose where to save it; nothing is uploaded. |
| **Export Reports** | Writes `<base>_Simple.md` and `<base>_Extensive.json` from the same collection. The extensive report contains runtime evidence, static Lua evidence and the structured assessment. Existing files need explicit overwrite confirmation. |
| **Export Module Dump** | A loaded PE module in mapped-image layout, plus JSON metadata, progress, cancellation and backup-preserving overwrite confirmation. |
| **Static Lua AOB Analysis** | Passive lexical analysis of table Lua scripts for supported AOB patterns, displayed in the read-only viewer without live scans. |
| **Export Static Lua Report** | Exports a full runtime report enriched with the static_lua_analysis section (JSON). |
| **Remove CESuite Menu** | Closes the Core session and removes only CESuite's owned menu/viewer objects. |
| **About CESuite** | Shows version, status and distribution mode. |


## Reports and repair guidance

CESuite produces two reports from one evidence model:

- **Simple Report** (Markdown): what CESuite analyzed, what looks OK, what presents
  problems, the evidence and confidence behind each problem, possible causes, what
  to review next, and a fixed review order. Written for people and external tooling; it
  never recommends an automatic repair.
- **Extensive Report** (JSON): the complete runtime report, static Lua evidence and
  the same `assessment` object, with provenance, confidence, limitations and
  suggested next steps.

The assessment is derived only from evidence already collected. Signatures with zero
matches, multiple matches, unusable scans and unresolved source-only candidates are
reported with their limits, and static Lua candidates are never promoted to runtime
observations. See [Reporting and repair guidance](docs/reporting.md).

## Installation

### Method A: Permanent autorun installation (recommended)

1. Open Cheat Engine.
2. In the Cheat Engine menu, select **Settings**.
3. In the left tree, select **General Settings**.
4. Look for the **Cheat Engine Plugins / Autorun** directory, or locate `autorun/` in your Cheat Engine installation path (for example, `C:\Program Files\Cheat Engine 7.5\autorun\`).
5. Extract the entire `cesuite/` folder and `CESuite_Autorun.lua` from `CESuite_Autorun_v0.3.0.zip` into the `autorun/` directory:

```text
Cheat Engine/
  autorun/
    CESuite_Autorun.lua
    cesuite/
      core.lua
      aob.lua
      ct.lua
      ...
```

6. Restart Cheat Engine. The **CESuite** menu will appear in the main window.

### Method B: Portable / per-table use

1. Download `CESuite_Core_v0.3.0.CT` from the latest release.
2. Open Cheat Engine.
3. Open `CESuite_Core_v0.3.0.CT` (**File → Open Table** or Ctrl+O).
4. The table script runs automatically and adds the **CESuite** menu to Cheat Engine.
5. You can now open your own game table; CESuite remains active in the menu.

## Quick start

1. Start Cheat Engine.
2. Attach Cheat Engine to your target process (**File → Open Process**).
3. Open your Cheat Table (`.CT`).
4. Select **CESuite → Analyze Loaded Table**.
5. Review the analysis results in the report viewer.
6. Select **CESuite → Validate AOBs** to check pattern match counts against the attached process.
7. Select **CESuite → Static Lua AOB Analysis** to view passive lexical analysis of table Lua scripts.
8. Select **CESuite → Export Analysis Report** to save `CESuite_Runtime_Report.json`.
9. Select **CESuite → Export Static Lua Report** to save `CESuite_Runtime_Report_enriched.json`.
10. If you also need module bytes, choose **Export Module Dump**, verify the exact module filename and select a writable destination.

Review exported scripts, paths and memory contents before sharing them with a person or AI service.

## Outputs

| File | Contents / meaning |
| --- | --- |
| `CESuite_Runtime_Report.json` | Default runtime report name: process/modules, table/script inventory, dependencies and summary, diagnostics, supported AOB results and collection/version metadata. |
| `<name>.module.bin` | Completed module dump. File offset corresponds to RVA from the recorded module base. The destination name is user-selected. |
| `<name>.module.bin.json` | Dump sidecar containing status, process/module identity, base, expected size, bytes written, timestamps and relevant errors, cancellation or backup metadata. |
| `<name>.module.bin.partial` | Incomplete dump retained after cancellation or failure. Never treat it as a complete image. Metadata is written when possible. |
| `*.previous`, `*.previous.1`, … | Previous outputs preserved after confirmed overwrite. The new sidecar records the backup mappings. |
| `CESuite_Runtime_Report_enriched.json` | Runtime report enriched with `static_lua_analysis`, documenting static source candidates without promoting them to runtime-verified AOBs. |
| `report.json` + `report.md` | Reports produced by the separate offline CT Analyzer. |

### Report Versioning and Schemas

- `core_version`: `0.1.9` indicates the baseline runtime report format and schema compatibility level for downstream consumers.
- `suite_version`: `0.3.0` records the specific CESuite toolkit version that generated the report or static analysis.
- Dedicated schemas available under `schemas/`:
  - `schemas/runtime-report.schema.json`: Runtime observation report contract.
  - `schemas/static-lua-report.schema.json`: Standalone static Lua analysis report contract.
  - `schemas/ct-report.schema.json`: Offline table analyzer contract.

## Safety and limitations

- **Observation and export:** CESuite does not execute inspected AA/Lua, activate scripts, patch target memory, inject code or attach automatically. Its own loader and UI code run inside CE. Opening or activating another CT can execute that table's code through CE, outside CESuite's analysis boundary.

- **Conservative, fail-closed parsing:** CESuite performs lexical analysis, not full AA/Lua interpretation. Unknown conditional branches, dynamic or incomplete LuaCode and unsupported constructs remain opaque. Ambiguous module resolution is rejected.

- **Diagnostics are evidence, not proof:** reports and warnings help review a table but do not prove executed behavior, hook safety or compatibility with another game/build version.

- **Incomplete source visibility:** runtime capture cannot passively obtain standalone table Lua. External Lua files, generated code and runtime closures are not inspected. Disassembly context is deliberately omitted.

- **AOB evidence has limits:** counts describe CE-readable scanned memory at collection time. A unique match does not prove cross-build robustness. Unsupported patterns or scopes are not widened into broader scans. AOB scans are synchronous and may temporarily keep CE busy.

- **A module dump is a non-atomic mapped image, not a rebuilt disk executable.** The process keeps running during export. Bytes may contain relocations, runtime changes and existing hooks. Unreadable blocks stop export without invented zero padding.

- Module dump metadata records:

  `atomic_snapshot: false`

  `binary_fingerprint: null`

  `layout: "mapped_image"`

## Validation

Automated regression test results:

- **476 passing checks**
- **0 skips**
- **0 failures**

These cover Lua runtime tests, diagnostic assessment, address evidence, module dump behavior, distribution checks, parser parity, static Lua parity, static Lua, assessment and address-evidence schema validation, and Python/schema contracts.

Recorded live validation includes:

- v0.2.1 in Cheat Engine 7.72 64-bit on Windows 11: cold start, About `0.2.1`, 13 commands, `Diagnostics Summary`, `Export Reports`, overwrite confirm/cancel, detached analysis, a limited attached self-process smoke test and extensive-report schema validation ([details](https://github.com/doc-haz/CESuite/blob/main/docs/validation/live-0.2.1.md)); its target bytes predate the paired-export correction;
- clean autorun installation and cold restart;
- portable/singleton behavior;
- Analyze after portable loading;
- static Lua AOB analysis viewer and detached/attached operation;
- enriched report export and busy-guard safety;
- complete module export;
- large-module progress and responsive UI;
- cancellation and partial-output retention;
- SaveDialog cancel/close behavior;
- overwrite confirmation and rejection;
- `.previous` and `.previous.N` backup handling;
- busy-operation guard;
- recovery after cancellation and dialog exits.

Download assets and published SHA-256 values from the [current release page](https://github.com/doc-haz/CESuite/releases/latest).

Still pending as nonblocking follow-up work:

- v0.2.2 live validation of the Address Evidence Inspector on Cheat Engine 7.72;
- targeted live re-smoke of `Export Reports` on the corrected v0.2.1 bytes (success, overwrite, cancellation, busy recovery);
- real homonymous-module `MODULE-SNAPSHOT-INCOMPLETE` validation;
- live R-1 check;
- private historical replay validation;
- D-5 / D-6 and O-1–O-4 cleanup items targeted for later development.

See [P0 closure and automated evidence](https://github.com/doc-haz/CESuite/blob/main/docs/p0-closure.md), [exact v0.1.9 live observations and limits](https://github.com/doc-haz/CESuite/blob/main/docs/validation/live-0.1.9.md), [v0.2.0 live validation evidence](https://github.com/doc-haz/CESuite/blob/main/docs/validation/live-0.2.0.md) and [v0.2.1 live validation evidence](https://github.com/doc-haz/CESuite/blob/main/docs/validation/live-0.2.1.md).

## Credits

CESuite is designed, implemented, tested and maintained by:

- **doc-haz** (formerly **dokkoriax**) — architecture, reverse engineering, initial prototypes, schema and analysis pipeline design, core runtime implementation, testing and maintenance.

Earlier project history or commits may reference the previous handle `dokkoriax`.

Development uses automated tests, schema checks and review. Final technical and release decisions remain with the project maintainer.

Released under the [Apache License, Version 2.0](LICENSE).
