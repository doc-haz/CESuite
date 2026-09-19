# CESuite Core Runtime 0.1

Local, observation/export-first CE extension. No injection, target writes, target
allocation, automatic attachment, table activation, debugger changes, symbol
registration, GitHub calls or credentials. The menu and report viewer live in CE;
scans use CE-owned temporary result files, and report export writes a user-selected
JSON file. Collected scripts are data and are never executed by the analyzer.

## Use the single CT

For permanent startup loading, use the separate autorun ZIP described in
[installation.md](installation.md). Version 0.1.3 shares a singleton guard between
both modes; repeated loads reuse the existing Core and menu. CESuite 0.1.3 has been
live-validated on Cheat Engine 7.7.1, including autorun loading, loaded-table
analysis, selected-script inspection, AOB validation, report export, and
conservative Lua/RVA hook inventory.

1. Open `releases/CESuite_Core.CT` in CE and allow **this core's** table Lua to run.
   The CT contains no MemoryRecords and does not attach or scan on load.
2. Open the CT you want to inspect, then attach CE to the process yourself.
   The installed menu persists across table loads in the same Lua session.
   Opening a CT normally replaces the address list: load the core **first**.
   Alternatively run the generated `releases/CESuite_Core.lua` from CE's Lua
   engine to install the menu without replacing an already loaded address list.
   Loading/activating another table is CE behavior, outside CESuite's observation
   boundary; CESuite itself never executes that table's scripts.
3. Use the **CESuite** menu:
   - **Analyze Current Process**: PID/name, architecture, modules/bases/sizes.
   - **Analyze Loaded Table**: current MemoryRecords, AA, embedded Lua, table Lua
     editor text and conservative lifecycle diagnostics; no scans.
   - **Validate AOBs**: fresh process/table snapshot followed by scoped scans.
   - **Inspect Selected Script**: inventory of the selected MemoryRecord.
   - **Export ChatGPT Report**: choose `CESuite_Runtime_Report.json`; collect a
     **fresh full snapshot and re-scan** before writing. Never exports an old scan
     against a newly selected process/table.
   - **Remove CESuite Menu**: destroy only CESuite's owned menu/viewer objects.
   - **About CESuite**: show version, status and initial distribution mode.

Analysis commands show a read-only JSON viewer. The most recent object is also
available as `CESuiteCore.last_report`. Developer calls:
`CESuiteCore.analyze('validate')`, `CESuiteCore.export(path)`,
`CESuiteCore.shutdown()`. Reports can contain scripts and local paths; review their
contents before sharing. No automatic upload is provided.

Scans are synchronous and can take considerable time for a large process or many
signatures. The CE interface may be busy until completion. There is no cancellation
or scan timeout in 0.1. The core prevents reentrant commands. MemoryRecord inventory
is limited to 10,000 records with an explicit diagnostic if truncated.

## Evidence and scope

`schemas/runtime-report.schema.json` is the new runtime contract; the existing
offline contract remains unchanged. Join manually by script text, record hierarchy,
original record IDs and AOB command/line; report-local IDs are **not** cross-report
identities. Static/runtime automatic merging and fingerprints remain future work.

Addresses are uppercase hex **strings**, avoiding JSON integer precision loss.
Missing counts/addresses are `null`, arrays stay arrays even when empty. Runtime
version, CE version, schema version and collection timestamps are included. A
module base/size/path is an observation, not an executable build fingerprint.

Each AOB preserves its command, arguments, symbol, pattern, section and line:

| Original command | Observed scan |
| --- | --- |
| `aobscan` | Process-wide MemScan, start 0, unsigned all-addresses stop sentinel. |
| `aobscanmodule` | Enumerated module base through base + image size, matching AA's stop argument. |
| `aobscanregion` | Resolved original start/stop expressions passed unchanged to MemScan. |

All use no alignment and `*X*C*W` protection flags. No missing module or unresolved
region falls back to a broader scan. Only literal byte/nibble wildcards are scanned;
macro patterns, malformed directives and entirely wildcard patterns stay unsupported.
Resolution handles AA hex literals, `$hex`, `0xhex`, `#decimal`, module names,
simple +/- constants and noncyclic simple `define` aliases. Arbitrary CE symbols,
pointers, allocations, Lua calculations and symbol lookup callbacks are not evaluated.
AA `17` means hex 0x17 (23 decimal); Lua `17` means decimal 17.

`match_count` is the complete FoundList count. Up to 256 addresses are exported;
`matches_truncated` explicitly reports address-list truncation. Context is limited
to the first 8 matches and first 8 resolved hook candidates. Counts are not truncated.
Results mean matches in **CE-readable scanned memory**: inaccessible pages and CE
memory-type scan preferences can limit coverage. A zero count is not proof that a
signature is absent from every possible page. The target is not paused; neither
memory nor module snapshots are atomic. PID changes invalidate results, but PID
reuse and same-process unload/reload races cannot all be detected.

`unique_current_scan` requires one counted match and an available, empty scan
`ErrorString`. Older CE builds lacking that property retain the observed count but
leave uniqueness `unverified`. Errors are never reported as zero matches.
`cross_build_robustness` is always `unverified`. Literal AA statements in conditional
or Lua-assisted scripts remain **lexical observations**, not proof that AA would
execute the same statement. Scripts are never compiled even for a syntax check.

Signature anchors are the observed scan addresses. Separate hook candidates come
from AA placement labels referring to an AOB symbol plus a constant, including simple
`define` aliases. Repeated AOB symbols suppress inference. One observed match permits
an inferred absolute hook address; multiple matches do not select one. A placement
label is not proof of a patch, valid instruction boundary or suitable overwrite span.

## Disassembly and CE API coverage

48 bytes starting 16 bytes before a candidate and up to 8 forward instructions are
captured. Forward decoding starts at the candidate; its boundary is explicitly
unverified. No guessed backward disassembly is presented as a known instruction
stream. CE metadata identifies calls, returns and jumps and supplies operand
addresses where available. A small documented byte-decoder subset recognizes
RIP-relative legacy ModRM forms; unsupported SSE/VEX/EVEX and other forms remain
`unknown`. This is not a complete decoder, effective-address evaluator or relocator.

MemoryRecords use the documented address-list APIs. Table Lua uses
`getLuaEngine().mScript.Lines.Text`: this is an editor snapshot which may include
unsaved edits, not proof of executed source. External Lua files, runtime closures,
arbitrary globals, table attachments and generated AA are not inspected. The core
does not save/reload the table to obtain source. Existing active records may have
already modified memory; they are marked with review diagnostics.

Ownership, empty DISABLE and restore-before-free are advisory diagnostics. Empty
DISABLE can be intentional for a persistent library. Actual teardown safety,
in-flight callbacks, complete overwritten bytes, allocation reach, short5/far14 and
relocation are unverified. No clean report certifies a hook or port as functional.

API references consulted:
- [CE Lua API documentation](https://github.com/cheat-engine/cheat-engine/blob/master/Cheat%20Engine/bin/celua.txt)
- [CE Auto Assembler scope implementation](https://github.com/cheat-engine/cheat-engine/blob/master/Cheat%20Engine/autoassembler.pas)
- [CE Lua MemScan argument adapter](https://github.com/cheat-engine/cheat-engine/blob/master/Cheat%20Engine/LuaMemscan.pas)

The installed CE documentation also exposes `MemScan.ErrorString` (not present in
all older online documentation). API access is guarded and missing capabilities
produce unknown/error states. CE 7.7+ is the intended test target. CESuite 0.1.3 has been live-validated on
Cheat Engine 7.7.1 in an x64 process session.

## Build and tests

Python 3.10+ builds both distribution modes without dependencies:

```text
python tools/build_ce.py
```

Lua modules under `ce/modules/` use a private in-bundle loader, not global
`package.preload`. The generated CT and Lua carry every module and require no repo
at runtime. The separate Lua artifact is an alternative loader for an existing CT.
The build is deterministic, UTF-8 and XML-escaped; it has no timestamp-dependent data.
The ZIP carries an absolute-path loader and the same modules; see
[installation.md](installation.md) for artifact names and installation structure.

```powershell
python -m pip install -r analyzer/requirements-dev.txt
python tools/build_ce.py
python tools/run_lua_tests.py --library 'C:/Program Files/Cheat Engine/lua53-64.dll'
python -m unittest discover -s ce/tests -v
$env:PYTHONPATH = 'analyzer/src'
python -m unittest discover -s analyzer/tests -v
```

The Lua runner loads a matching-architecture Lua 5.3 library into Python; it does
not launch CE or use its process APIs. Linux can use a system `liblua5.3.so.0`.
Alternatively run `lua5.3 ce/tests/runtime_spec.lua` from the repo root. Tests produce
ignored synthetic JSON fixtures used by the schema tests. They verify actual Lua
serialization and the generated bundle with CE API **mocks**, not CE integration.

For broader runtime certification, manually test both x86/x64 targets using an
owned synthetic application: no attachment; attachment; module enumeration; 0/1/N
matches in all scopes; region endpoints; unreadable pages; active records; duplicate
IDs; selected script; table switching; unavailable APIs; export errors; menu reinstall
and removal. Compare AOB counts with CE's manual scans using identical flags and
memory-type preferences. Confirm no writes, activation or debugger changes. Keep
that runtime evidence separate from synthetic tests. Do not commit process reports,
proprietary binaries or memory dumps.

## Evolution

Each real CT that exposes a reusable limitation should lead to a minimal synthetic
regression fixture, a focused module change, schema migration when needed and an
explicit changelog entry. Retain old reports where practical; never silently upgrade
`unknown` into a verified assertion. Future tools can consume this evidence without
turning the observation core into an implicit patching framework.
