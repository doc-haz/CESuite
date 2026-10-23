# Inherited P0 closure on local Core 0.1.9

Implementation and automated evidence are distinct from independent review and live CE validation.
No release, commit, push or tag is authorized in this task.

## Conservative boundaries

Both lexical passes fail closed on incomplete or embedded LuaCode and mask it until an unquoted/uncommented ASM boundary,
including unfinished Lua long comments/literals. LuaCode is not embedded table
Lua and creates no AA commands, AOBs, resource or dependency candidates.
All IFDEF/IFNDEF/ENDIF directives on a line are processed in order, with unmatched/incomplete diagnostics;
unknown branch bodies are omitted rather than evaluated. HOOK, UNHOOK, HOOK5,
aobscanfunction and aobscanregion yield opaque diagnostics only, even with complex
arguments. This deliberately reduces the former classic region-AOB inventory.
Existing report schema shapes remain valid, including legacy region reports.

Conditional/opaque section headers emit SECTION-INDETERMINATE and set section
to unknown until an explicit unmasked header. Lua globals and Lua/RVA candidates
retain that section provenance.

Module resolution rejects invalid/empty queries and counts matching names/normalized paths before using metadata.
Multiple matches remain unresolved; no first-match preference is used. Duplicate
names omit getModuleSize lookups and emit MODULE-SNAPSHOT-INCOMPLETE with null
sizes. Module Dump retains its existing duplicate-name rejection. The environment and
AOB resolver share util.moduleNorm/moduleMatch; name and path candidates use
the same rules. Size is omitted whenever the name cannot resolve uniquely or the normalized
path itself is ambiguous; null/invalid paths do not create an empty match.

## Historical passive reductions retained

- MemoryRecord.Address is not read during passive capture (callback risk).
- getLuaEngine is not evidence of standalone table Lua; that source is unavailable.
- Passive analysis omits disassembly callback context.

The source/runtime evidence profile remains unverified. Lexical observations do
not establish executed branches, resource ownership, AOB robustness or hook safety.

## Validation gates

DIESEL's independent reaudit, reported by the DG, closed the technical criteria:

| Gate | State |
| --- | --- |
| P0-05 | CERRADO |
| P0-06 | CERRADO |
| P0-07 | CERRADO |

Verified environment: Python **3.14.7 64-bit**, jsonschema **4.26.0**, installed
previously under explicit DG authorization. The former missing-dependency block
is resolved; this documentation mission installs nothing.

| Automated evidence | Passing checks |
| --- | ---: |
| Core Lua | 72 |
| Module Dump | 15 |
| CT/autorun distribution | 14 |
| Inert replay harness | 1 |
| Lua subtotal | 102 |
| Lua/Python parser parity | 40/40 |
| analyzer/tests | Ran 23 tests; OK |
| ce/tests runtime/contracts | Ran 20 tests; OK |
| Total independently verified by DIESEL | **185; 0 skips; 0 failures** |

Automated mocks and real local file I/O outside CE remain distinct from live CE
acceptance. The DG/AIR Boss separately completed clean installation/cold start,
portable/singleton, complete small export, large-export progress/responsiveness,
cancellation/OnClose, busy guard, save dialogs, overwrite rejection/confirmation,
backup collision, paths with spaces and recovery. See the precise observations
and remaining conditional checks in [live-0.1.9.md](validation/live-0.1.9.md).
This document records DG-supplied evidence; it does not claim that PREMIUM
personally repeated those live actions during this documentation mission.

The documentation/EOL hygiene rerun also passed all 185 checks with no skips or
failures, and all four candidate hashes stayed unchanged. See the
[current hygiene report](validation/hygiene-0.1.9.md).

Technical closure and passing automated tests do not by themselves publish a
release or substitute for live validation. No commit/push/tag/release is authorized
here; final pre-release DIESEL review remains the next step. The old
[PREMIUM correction report](validation/premium-0.1.9.md) is a historical snapshot
of the earlier missing-dependency state, superseded here for current gate status.

The private Dawnwalker input remains unavailable; its historical counts are
pending current revalidation, not a mandatory clean-clone gate. D-5 (internal
path in sidecar errors) and D-6 (standalone runner's ignored generated fixtures)
remain nonblocking post-0.1.9 follow-ups, without code changes in this mission.

## Reproduce without dependency installation

```powershell
python tools/build_ce.py
python tools/run_lua_tests.py --library "C:/Program Files/Cheat Engine/lua53-64.dll"
python tools/check_parser_parity.py --library "C:/Program Files/Cheat Engine/lua53-64.dll"
$env:PYTHONPATH = "analyzer/src"
python -m unittest discover -s analyzer/tests -v
python -m unittest discover -s ce/tests -v
git diff --check
```

The formal dependency is `jsonschema>=4.18,<5` in `analyzer/requirements-dev.txt`.
The schema suites require an existing jsonschema installation. If absent, record
skips/import errors and leave the full-suite gate open; do not install packages
under this task's authorization. The private historical replay input is not in
this repository, so the documented 117-occurrence case must be replayed with the
retained original before asserting its current totals.


## Clean-clone fixtures and contract coverage

RuntimeContractTests.setUpClass creates a fresh temporary directory and invokes
the trusted Lua harness via `CESUITE_LUA_LIBRARY` (Windows CE Lua 5.3 fallback).
The three serialized runtime fixtures are regenerated there; ignored
ce/tests/generated-*.json files are not inputs. test_fixture_setup exercises
that path independently even when jsonschema is unavailable. The isolated Lua test state freezes generated observation timestamps, and the
fixture setup test compares two regenerations byte for byte. Production clocks
are unchanged; trusted synthetic sources and inventory are fixed. No private process data is needed.

ModuleDumpContractTests invokes the synthetic-memory harness with real local
file I/O, captures persisted sidecars before cleanup and checks backup mappings
and complete/partial/cancelled outcomes. JSON Schema validation is a separate
subgate requiring jsonschema. Declined overwrite writes no sidecar.

Parser parity uses 40 fixed adversarial cases (the original DIESEL 33-case corpus
was not supplied). It compares command/arguments/section/line, resource and AOB
inventories/state, relevant diagnostic rule/line sequences and embedded Lua text
and source boundaries. Dependency contracts differ: runtime occurrences are
compared to a projection from Python AA inventory; Python cross-script provider
visibility is checked against runtime providers. Simple Lua globals also have
explicit expectations; this does not assert identical dependency JSON formats.

MAGNA's startswith('aobscan') KeyError did not reproduce: the anchored COMMAND
allowlist constrains every reachable mapping key. Unknown-prefix regressions pass;
no speculative change was made to that dispatch.
