# CESuite

A local analysis, diagnostics and evidence-export toolkit for Cheat Engine tables and attached processes.

[Latest Release](https://github.com/doc-haz/CESuite/releases/latest) · [Installation](docs/installation.md) · [Runtime Reference](docs/runtime-core.md)

## What is CESuite?

CESuite adds a **CESuite** menu to Cheat Engine (CE). It helps you inspect the loaded cheat table (CT), understand its scripts and dependencies, check supported array-of-bytes (AOB) signatures against an attached process, and export structured evidence for further analysis.

It is intended for authorized software research across applications, development tools, simulations and games. The runtime runs locally: no Python, GitHub connection, credentials or network access are required.

## What problem does it solve?

A CT can contain many scripts, symbols, allocations, dependencies and signatures whose assumptions are difficult to review by hand.

CESuite collects that information into structured reports so you can investigate broken tables, understand how a table is built, review dependencies, compare assumptions against a running process, or prepare a port to another build.

When the executable on disk cannot be read or does not represent the currently loaded image, CESuite can also export a loaded module directly from process memory.

**Think of CESuite as an evidence collector and table inspector, not an automatic table fixer.**

Its output can support debugging, manual porting and AI-assisted analysis, but CESuite does not automatically repair a table or certify that a hook works.

## How it works

**Load CESuite in CE → load your target CT and attach CE yourself → analyze → export a report or module dump → review the evidence.**

CESuite reads table metadata and script text, inventories supported constructs, and uses Cheat Engine memory scans only for supported AOB validation.

Unknown, dynamic or ambiguous constructs remain unsupported, opaque or unresolved rather than being executed or guessed.

Module dumping is a separate, explicit action.

## Main features

| Menu action | What it provides |
| --- | --- |
| **Analyze Current Process** | Attached process identity, architecture and enumerated modules with bases and available sizes. |
| **Analyze Loaded Table** | MemoryRecord hierarchy, AA (Auto Assembler) and embedded Lua inventory, resources, dependencies and review diagnostics; no AOB scans. |
| **Inspect Selected Script** | Focused inventory of the selected MemoryRecord's script. |
| **Validate AOBs** | Fresh process/table capture and scans for supported literal `aobscan` / `aobscanmodule` patterns, with counts and available match addresses. |
| **Dependency Summary** | Grouped lexical dependency occurrences, preserving raw evidence; not a resolved runtime dependency graph. |
| **Export Analysis Report** | Saves a fresh normalized JSON report for manual review, AI-assisted analysis or external tooling. You choose where to save it; nothing is uploaded. |
| **Export Module Dump** | A loaded PE module in mapped-image layout, plus JSON metadata, progress, cancellation and backup-preserving overwrite confirmation. |

## Installation

Download either asset from the [latest release](https://github.com/doc-haz/CESuite/releases/latest):

- **Autorun ZIP — persistent installation:** close CE, back up and retire any previous CESuite loader/module folder, then extract the contents of the versioned Autorun ZIP into your CE installation's `autorun` directory, for example:

  `C:\Program Files\Cheat Engine\autorun\`

  `CESuite_Autorun.lua` and the `cesuite` folder must sit directly inside it. Restart CE and do not mix CESuite versions.

- **Portable CT — session use:** open the versioned portable CT and allow **CESuite's own** table Lua to install the menu. It is self-contained; the ZIP is unnecessary. Load CESuite before your target CT, since opening a CT can replace the address list. The CESuite menu persists across table loads in that Lua session.

Both modes share a duplicate-load guard. After an upgrade, restart CE to replace an already loaded runtime.

See [installation, upgrade and removal instructions](docs/installation.md) for details.

## Quick start

1. Start CE with CESuite installed, or load the portable CT first.
2. Open **CESuite → About CESuite** and confirm the displayed version matches the release you installed and the status is `ready`.
3. Load the CT you want to inspect.
4. Attach CE to the intended process yourself.
5. Leave target scripts disabled while reviewing them.
6. Use **Analyze Current Process** to inspect the current target.
7. Use **Analyze Loaded Table** or **Inspect Selected Script** to inspect the CT.
8. Use **Validate AOBs** when you need current memory-match evidence.
9. Use **Export Analysis Report** to save a normalized analysis report.
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
| `report.json` + `report.md` | Reports produced by the separate offline CT Analyzer. |

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

  A module dump does not establish build identity or compatibility by itself.

## CT Analyzer (offline)

The repository also includes a dependency-free **Python 3.10+ CLI** for static CT XML review.

It does not require Cheat Engine or an attached process, never executes AA/Lua, and writes JSON and Markdown reports.

From the repository root in PowerShell:

```powershell
$env:PYTHONPATH = "analyzer/src"
python -m ct_analyzer path/to/table.CT --output reports/table
```

Existing `report.json` and `report.md` files in that destination are replaced.

The analyzer inventories scripts, supported AA constructs, dependencies and review advisories. It does not validate live memory matches. Compressed/encrypted tables and embedded binary payloads are not analyzed.

See [CLI usage and input limits](analyzer/README.md).

## Validation and release status

**Use the latest published release of CESuite.**

Download assets and published SHA-256 values from the [current release page](https://github.com/doc-haz/CESuite/releases/latest).

P0-05, P0-06 and P0-07 are closed.

Recorded automated validation totals:

- **185 passing checks**
- **0 skips**
- **0 failures**

These cover Lua runtime tests, module dump behavior, distribution checks, parser parity and Python/schema contracts.

Recorded live validation includes:

- clean autorun installation and cold restart;
- portable/singleton behavior;
- Analyze after portable loading;
- complete module export;
- large-module progress and responsive UI;
- cancellation and partial-output retention;
- SaveDialog cancel/close behavior;
- overwrite confirmation and rejection;
- `.previous` and `.previous.N` backup handling;
- busy-operation guard;
- recovery after cancellation and dialog exits.

This validation does not establish universal compatibility with every Cheat Engine version, every table or every process.

Still pending as nonblocking follow-up work:

- real homonymous-module `MODULE-SNAPSHOT-INCOMPLETE` validation;
- live R-1 check;
- private historical replay validation;
- D-5 / D-6 and O-1–O-4 cleanup items targeted for later development.

See [P0 closure and automated evidence](https://github.com/doc-haz/CESuite/blob/main/docs/p0-closure.md) and [exact v0.1.9 live observations and limits](https://github.com/doc-haz/CESuite/blob/main/docs/validation/live-0.1.9.md).

## Credits

CESuite is developed and maintained by **doc-haz**.

Special thanks to the AI-assisted engineering team used during development and validation:

- **CHATSY®** — project coordination, technical review and release planning
- **MAGNA** — engineering and implementation support
- **DIESEL** — independent auditing and verification
- **PREMIUM** — implementation, testing and release-preparation support

Final technical and release decisions remain with the project maintainer.

## Documentation

- [Installation, upgrade and removal](docs/installation.md)
- [Runtime behavior, supported scans and API limits](docs/runtime-core.md)
- [Module dump format and failure behavior](docs/MODULE_DUMP.md)
- [Dependency summary contract](docs/dependencies-v0.1.5.md)
- [Source/runtime evidence profile](docs/semantics-profile.md)
- [Offline analyzer review rules](docs/analyzer-rules.md)
- Schemas:
  - [Runtime report](schemas/runtime-report.schema.json)
  - [Module dump](schemas/module-dump.schema.json)
  - [Offline CT report](schemas/ct-report.schema.json)
- [Changelog](CHANGELOG.md)
- [Architecture](docs/architecture.md)
