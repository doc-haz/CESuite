# CESuite

Private, early-stage Cheat Engine CT analysis, diagnostics, porting and authoring toolkit for authorized software research. Scope includes general applications, development tools, simulations and games; it is not game-specific.

## CESuite Core Runtime 0.1.9 (local audit candidate)

CESuite provides a local observation/export runtime for Cheat Engine. Open
[releases/CESuite_Core.CT](releases/CESuite_Core.CT) to install the CESuite menu,
then load the target table and attach CE yourself. Use **Export ChatGPT Report**
for one normalized `CESuite_Runtime_Report.json`. No GitHub access is needed.
The core does not activate scripts, patch memory or execute inspected AA/Lua.

See [runtime usage, API coverage and limitations](docs/runtime-core.md),
[runtime schema](schemas/runtime-report.schema.json) and [changelog](CHANGELOG.md).
Source is modular under `ce/`; `python tools/build_ce.py` produces
`releases/CESuite_Core_v0.1.9.CT` and `releases/CESuite_Autorun_v0.1.9.zip`, plus
the existing unversioned CT and alternative Lua loader. The ZIP extracts directly
into `C:\Program Files\Cheat Engine\autorun\` for permanent startup loading.
Both modes share duplicate-load guards and require no network at runtime.
See [exact installation, upgrade and removal instructions](docs/installation.md).

Synthetic tests cover both modes. CESuite 0.1.3 has been live-validated on
Cheat Engine 7.7.1, including autorun loading, loaded-table analysis,
selected-script inspection, AOB validation, report export, and conservative
Lua/RVA hook inventory without executing inspected Lua.

Core 0.1.9 includes **Dependency Summary** in the menu and
`dependency_summary` in JSON (introduced in 0.1.5) while preserving raw `dependencies`.
Embedded Lua detection uses generic identifiers with conservative exclusions for
locals, Lua builtins and known CE APIs; it has no game-specific naming rule.
CESuite describes generic capabilities; games appear only as reproducible validation cases.
See [aggregation and compatibility contract](docs/dependencies-v0.1.5.md).
It also includes the 0.1.6 [source/runtime evidence profile](docs/semantics-profile.md).
This local tree is not a published release; offline tests do not establish live CE integration.

The inherited P0 review masks dynamic LuaCode and unknown conditional branches,
keeps HOOK/UNHOOK/HOOK5/aobscanfunction/aobscanregion opaque, and refuses
ambiguous module resolution. See [closure and validation scope](docs/p0-closure.md).

## CT Analyzer 0.1 (offline)

A dependency-free Python 3.10+ offline CLI. It reads CT XML, never executes AA/Lua, never attaches to a process, and writes `report.json` and `report.md`.

```powershell
$env:PYTHONPATH = "analyzer/src"
python -m ct_analyzer fixtures/synthetic.CT --output reports/example
python -m unittest discover -s analyzer/tests -v
```


### Module memory export (0.1.9)

Use **CESuite → Export Module Dump** to save a loaded module when its disk file cannot be read. Exports include completion metadata and retain incomplete results as .partial. See [MODULE_DUMP.md](docs/MODULE_DUMP.md).


The 0.1.9 audit corrections fail closed on incomplete/embedded LuaCode and empty
module queries. Every same-line conditional is processed; a conditional section
header makes later inventory `section: "unknown"` until an unequivocal header.
The user reported a successful BIN + reports + PREMIUM-generated table workflow
on the first attempt. This is user-reported practical evidence for that case;
it does not validate every current overwrite/cancel/backup UI path. Automated
mocks, real local file I/O outside CE, historical observations and live CE
acceptance are recorded separately. No release is published by this mission.
