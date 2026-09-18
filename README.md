# CESuite

Private, early-stage Cheat Engine CT analysis, diagnostics, porting and authoring toolkit for authorized software research. Scope includes general applications, development tools, simulations and games; it is not game-specific.

## CESuite Core Runtime 0.1.0

The next milestone adds a local observation/export runtime for Cheat Engine. Open
[`releases/CESuite_Core.CT`](releases/CESuite_Core.CT) to install the CESuite menu,
then load the target table and attach CE yourself. Use **Export ChatGPT Report**
for one normalized `CESuite_Runtime_Report.json`. No GitHub access is needed.
The core does not activate scripts, patch memory or execute inspected AA/Lua.

See [runtime usage, API coverage and limitations](docs/runtime-core.md),
[runtime schema](schemas/runtime-report.schema.json) and [changelog](CHANGELOG.md).
Source is modular under `ce/`; `python tools/build_ce.py` builds the single CT and
an alternative Lua loader. Synthetic tests pass; live CE integration remains unverified.

## CT Analyzer 0.1 (offline)

A dependency-free Python 3.10+ offline CLI. It reads CT XML, never executes AA/Lua, never attaches to a process, and writes `report.json` and `report.md`.

```powershell
$env:PYTHONPATH = "analyzer/src"
python -m ct_analyzer fixtures/synthetic.CT --output reports/example
python -m unittest discover -s analyzer/tests -v
```

On Linux/macOS, prefix commands with `PYTHONPATH=analyzer/src` instead.

Reports contain the MemoryRecord tree (stable report-local keys, parent/child links and original IDs), exact extracted script text, AOB scope/pattern observations, symbol operations, alloc/dealloc operations, dependency candidates and review warnings. XML decoding normalizes line endings; extraction is semantic text, not byte-for-byte source preservation. Input files are not modified.

This version does **not** compile, emulate, disassemble or validate a hook. A clean report is not proof of compatibility or safety. See [analyzer usage](analyzer/README.md), [architecture](docs/architecture.md), [rules](docs/analyzer-rules.md) and [roadmap](docs/roadmap.md).

Only synthetic fixtures belong in this repository. Do not commit proprietary binaries, executables, memory dumps, credentials or unlicensed third-party tables. Keep repository visibility private; this scaffold does not modify repository settings.
