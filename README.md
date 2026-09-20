# CESuite

Private, early-stage Cheat Engine CT analysis, diagnostics, porting and authoring toolkit for authorized software research. Scope includes general applications, development tools, simulations and games; it is not game-specific.

## CESuite Core Runtime 0.1.6 (unreleased)

CESuite provides a local observation/export runtime for Cheat Engine. Open
[releases/CESuite_Core.CT](releases/CESuite_Core.CT) to install the CESuite menu,
then load the target table and attach CE yourself. Use **Export ChatGPT Report**
for one normalized `CESuite_Runtime_Report.json`. No GitHub access is needed.
The core does not activate scripts, patch memory or execute inspected AA/Lua.

See [runtime usage, API coverage and limitations](docs/runtime-core.md),
[runtime schema](schemas/runtime-report.schema.json) and [changelog](CHANGELOG.md).
Source is modular under `ce/`; `python tools/build_ce.py` produces
`releases/CESuite_Core_v0.1.6.CT` and `releases/CESuite_Autorun_v0.1.6.zip`, plus
the existing unversioned CT and alternative Lua loader. The ZIP extracts directly
into `C:\Program Files\Cheat Engine\autorun\` for permanent startup loading.
Both modes share duplicate-load guards and require no network at runtime.
See [exact installation, upgrade and removal instructions](docs/installation.md).

Synthetic tests cover both modes. CESuite 0.1.3 has been live-validated on
Cheat Engine 7.7.1, including autorun loading, loaded-table analysis,
selected-script inspection, AOB validation, report export, and conservative
Lua/RVA hook inventory without executing inspected Lua.

The published baseline is v0.1.4. Local 0.1.5 adds **Dependency Summary** to the
menu and `dependency_summary` to JSON while preserving raw `dependencies`.
Embedded Lua detection uses generic identifiers with conservative exclusions for
locals, Lua builtins and known CE APIs; it has no game-specific naming rule.
CESuite describes generic capabilities; games appear only as reproducible validation cases.
See [aggregation and compatibility contract](docs/dependencies-v0.1.5.md).
0.1.6 adds the [source/runtime evidence profile](docs/semantics-profile.md).
It is unreleased; offline tests do not establish live CE integration.

## CT Analyzer 0.1 (offline)

A dependency-free Python 3.10+ offline CLI. It reads CT XML, never executes AA/Lua, never attaches to a process, and writes `report.json` and `report.md`.

```powershell
$env:PYTHONPATH = "analyzer/src"
python -m ct_analyzer fixtures/synthetic.CT --output reports/example
python -m unittest discover -s analyzer/tests -v
```
