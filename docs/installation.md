# CESuite 0.1.1 installation (pre-release build)

Choose either mode. Both run locally without Python, GitHub, network access,
credentials or tokens. The build is not yet a validated GitHub Release.

## Permanent autorun installation

The user's confirmed installation is **Cheat Engine 7.7.1**, executables reporting
**7.7.1.10828**, under `C:\Program Files\Cheat Engine` (no version in the folder name).

1. Close Cheat Engine. Back up any previous `CESuite_Autorun.lua` and `cesuite`
   folder before upgrading. Do not mix modules from different versions.
2. Extract **the contents** of `CESuite_Autorun_v0.1.1.zip` directly into
   `C:\Program Files\Cheat Engine\autorun\`.
3. Verify these exact locations; do not add another `autorun` or ZIP-name folder:

   ```text
   C:\Program Files\Cheat Engine\autorun\
   ├── CESuite_Autorun.lua
   └── cesuite\
       ├── bootstrap.lua
       ├── core.lua
       ├── environment.lua
       ├── aob.lua
       ├── disassembly.lua
       ├── exporter.lua
       ├── ui.lua
       ├── ct.lua
       ├── parser.lua
       ├── lifecycle.lua
       └── util.lua
   ```

4. Open CE. The **CESuite** menu should appear without opening a table. **About
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

To uninstall, close CE and remove only `autorun\CESuite_Autorun.lua` and
`autorun\cesuite\`. **Remove CESuite Menu** hides it for the current session;
the next CE start loads it again. Restore backed-up files with CE closed to roll back.

## Portable CT

Open `CESuite_Core_v0.1.1.CT` and allow this Core's table Lua. The existing
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
Generated ZIPs and versioned CTs are local build outputs; no Release is published.

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
