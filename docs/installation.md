# CESuite 0.3.1 installation

Choose either mode. Both run locally without Python, GitHub, network access,
credentials or tokens.

## Permanent autorun installation

CESuite targets **Cheat Engine 7.x**. Live validation has been recorded on
**7.7.1** and **7.72**; other 7.x builds are expected to work but are not
individually verified. The default install directory `C:\Program Files\Cheat Engine`
is used below; adjust it to your own Cheat Engine version and path.

1. Close Cheat Engine. Back up any previous `CESuite_Autorun.lua` and `cesuite`
   folder before upgrading. Do not mix modules from different versions.
2. Extract **the contents** of `CESuite_Autorun_v0.3.1.zip` directly into
   `C:\Program Files\Cheat Engine\autorun\`.
3. Verify these exact locations; do not add another `autorun` or ZIP-name folder:

   ```text
   C:\Program Files\Cheat Engine\autorun\
   |-- CESuite_Autorun.lua
   |-- LICENSE
   `-- cesuite\
       |-- address.lua
       |-- aob.lua
       |-- bootstrap.lua
       |-- core.lua
       |-- coverage.lua
       |-- ct.lua
       |-- dependencies.lua
       |-- diagnose.lua
       |-- disassembly.lua
       |-- dynamic.lua
       |-- environment.lua
       |-- exporter.lua
       |-- json.lua
       |-- lifecycle.lua
       |-- luanames.lua
       |-- luastatic.lua
       |-- moduledump.lua
       |-- operations.lua
       |-- parser.lua
       |-- semantics.lua
       |-- simplereport.lua
       |-- snapshot.lua
       |-- snapshotdiff.lua
       |-- snapshotstore.lua
       |-- snapshotui.lua
       |-- ui.lua
       `-- util.lua
   ```

4. Restart CE after every upgrade; replacing files does not reload an existing
   singleton. Open CE. The **CESuite** menu should appear without opening a table. **About
   CESuite** displays the Core version, status and initial distribution mode.
5. Load your target CT and attach CE yourself. Use the analysis/export actions
   documented in [runtime-core.md](runtime-core.md).

The prior folder ACL inspection indicated administrator rights may not be needed
on this machine. Copying into Program Files still depends on the local account
and current permissions; if Windows requests elevation, approve the copy normally
or use portable mode. Do not change folder ACLs just to install CESuite.

Do not edit `main.lua`. Do not place a second loader in `autorun\custom\`,
`Extensions\` or `lua\`. Existing CE scripts and extensions are left in place.
`getAutorunPath()` selects the running CE installation; all modules load by explicit
absolute paths in a private environment, independent of working directory,
`package.path` and `package.loaded`. Missing or malformed modules produce an error
and do not publish a partially loaded singleton. Correct the package and restart CE.

To uninstall, close CE and remove only `autorun\CESuite_Autorun.lua`, `autorun\LICENSE` and
`autorun\cesuite\`. **Remove CESuite Menu** hides it for the current session;
the next CE start loads it again. To roll back to a previous release (such as v0.1.9.1),
close CE, remove the v0.3.1 autorun files, and restore the previous `CESuite_Autorun_v0.1.9.1.zip`
package or backed-up files.

## Portable CT

Open `CESuite_Core_v0.3.1.CT` and allow this Core's table Lua. The existing
`releases/CESuite_Core.CT` remains an identical unversioned compatibility path.
The CT is self-contained and does not need the ZIP. Load it before your target CT,
because opening a CT can replace CE's current address list. For an existing table,
the generated `CESuite_Core.lua` can also be run from CE's Lua engine.

Loading the **same new version** in either order (autorun then portable, or portable
then autorun) reuses `CESuiteCore` and its menu/report state. Repeated `install()`
calls do not add another menu. After removal, loading either mode reinstalls one
menu. A different version or legacy singleton is preserved with a restart message.
Upgrade with CE closed. Old 0.1.0 loaders predate these guards: do not run an old CT
after installing the new autorun package.

Developer-visible fields: `CESuiteCore.version`, `.status` (`ready`, `stopped`, or
transient `loading`), `.distribution` (`autorun` or `portable`, first successful
load). Bootstrap failures are reported through CE's message dialog, or the console
when no dialog API is available.

## Build and validation

Run `python tools/build_ce.py` from the repository to generate both versioned
artifacts under `releases/`, plus the existing unversioned CT and Lua paths.
`--output PATH` selects another destination. Version comes from
`ce/CESuite_Core.lua`. ZIP metadata and ordering are fixed for reproducible builds.
Generated ZIPs and versioned CTs are build outputs under `releases/`.

Run the Lua runner and Python checks listed in [runtime-core.md](runtime-core.md).
The Lua runner also extracts a freshly built ZIP into a temporary path containing
spaces and executes both its loader and Lua extracted from the actual versioned CT.
Tests cover both load orders, repeated loads, removal/reinstall, version conflicts,
foreign globals, orphan menus, missing/corrupt modules, partial menu creation,
absolute paths and isolation from ambient module search. These use synthetic CE
objects, not a running Cheat Engine instance.

Still required in live CE: cold startup without a CT; About/version/status; loading
the portable CT afterwards with exactly one menu; table switching; removal and
restart; and a real process/table analysis, AOB validation and JSON export. Test
each application only against its actual installed build; static packaging tests
do not establish runtime or hook compatibility. Keep the broader x86/x64 runtime
validation checklist in runtime-core.md before declaring a stable Release.


## Repair the reported mixed local installation (DG-operated; not executed)

The reported installation mixed 0.1.9 core/UI/dump with 0.1.8 parser/AOB/environment
and contained an extra `parser-01.lua`. Do not overlay a ZIP onto that tree. Close
all CE instances first, back up the entire existing loader/folder, then move the
old tree outside autorun and extract a complete package. Nothing in this mission
changes the CE installation. Do not alter ACLs; use normal elevation for the copy
if Windows requires it.

Run manually after reviewing the paths (PowerShell). The source ZIP must be the
candidate built and checked for this mission, not a historical package:

```powershell
$ceAutorun = 'C:\Program Files\Cheat Engine\autorun'
$ceBackup = Join-Path 'C:\CESuiteBackup' ('CE-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
$cePackage = 'C:\CESuiteBackup\CESuite_Autorun_v0.3.1.zip'
$ceOldTree = Join-Path $ceAutorun 'cesuite'
$ceOldLoader = Join-Path $ceAutorun 'CESuite_Autorun.lua'
if (-not (Test-Path -LiteralPath $cePackage)) { throw 'Package missing' }
if ((Resolve-Path -LiteralPath $ceAutorun).Path -ne 'C:\Program Files\Cheat Engine\autorun') { throw 'Unexpected target' }
if (Test-Path -LiteralPath $ceBackup) { throw 'Backup destination already exists' }
New-Item -ItemType Directory -Path $ceBackup | Out-Null
if (Test-Path -LiteralPath $ceOldTree) {
    Copy-Item -LiteralPath $ceOldTree -Destination (Join-Path $ceBackup 'copy-cesuite') -Recurse
    Move-Item -LiteralPath $ceOldTree -Destination (Join-Path $ceBackup 'retired-cesuite')
}
if (Test-Path -LiteralPath $ceOldLoader) {
    Copy-Item -LiteralPath $ceOldLoader -Destination (Join-Path $ceBackup 'copy-CESuite_Autorun.lua')
    Move-Item -LiteralPath $ceOldLoader -Destination (Join-Path $ceBackup 'retired-CESuite_Autorun.lua')
}
Expand-Archive -LiteralPath $cePackage -DestinationPath $ceAutorun
if (Test-Path -LiteralPath (Join-Path $ceOldTree 'parser-01.lua')) { throw 'Unexpected parser-01.lua in new tree' }
```

`parser-01.lua` is retired with the old folder, preserved under the backup, never
deleted. Verify the new loader and every `cesuite/*.lua` against the ZIP: extract
the ZIP to a separate temporary folder and compare the complete file list and
SHA-256 of each relative path. Expected modules are exactly the tree above; there
must be no extra module. Use `Get-FileHash -Algorithm SHA256` for both copies.

Exact disk-file verification, in the same manually operated PowerShell session:

```powershell
$ceVerify = Join-Path $ceBackup 'package-verification'
Expand-Archive -LiteralPath $cePackage -DestinationPath $ceVerify
$ceExpected = @(Get-ChildItem -LiteralPath $ceVerify -File -Recurse | ForEach-Object {
    $_.FullName.Substring($ceVerify.Length).TrimStart('\')
})
$ceActual = @(Get-ChildItem -LiteralPath $ceAutorun -File -Recurse | ForEach-Object {
    $_.FullName.Substring($ceAutorun.Length).TrimStart('\')
})
if (Compare-Object ($ceExpected | Sort-Object) ($ceActual | Sort-Object)) { throw 'Installed file list differs from ZIP' }
foreach ($ceRelative in $ceExpected) {
    $ceSourceHash = (Get-FileHash -LiteralPath (Join-Path $ceVerify $ceRelative) -Algorithm SHA256).Hash
    $ceInstalledHash = (Get-FileHash -LiteralPath (Join-Path $ceAutorun $ceRelative) -Algorithm SHA256).Hash
    if ($ceSourceHash -ne $ceInstalledHash) { throw "Module hash differs: $ceRelative" }
    Write-Output "$ceRelative $ceInstalledHash"
}
```

Restart CE (mandatory). About CESuite must report **0.3.1**, **ready**, **autorun**,
with exactly one CESuite menu. In CE's Lua console:

```lua
assert(CESuiteCore and CESuiteCore.version=='0.3.1')
assert(CESuiteCore.status=='ready' and CESuiteCore.distribution=='autorun')
print(CESuiteCore.version, CESuiteCore.status, CESuiteCore.distribution)
```

There is no per-module loaded-version API: About alone cannot prove module
provenance. The complete disk-file/hash check plus a cold restart verifies the
normal absolute-path loader's input. Do not run a stale portable CT/Lua loader or
mix module versions after that restart. Repeat the recorded checklist in
[live-0.2.1.md](validation/live-0.2.1.md) against the build you install, and record
the exact package hashes and results for that build.
