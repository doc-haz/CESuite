# PREMIUM: CESuite 0.1.9 correction mission

Date: 2026-10-22 (DG client date). No AIR identifier assigned.
Repository: C:\Azuara\CESuite. Version retained: 0.1.9.

**Recommendation: NO LISTO for an unconditional final release audit.** The code
candidate can be reviewed, but jsonschema is absent and the mandatory full
schema-suite gate has not passed. No commit, push, tag or GitHub Release was made;
no dependencies, ACL changes or CE installation changes were performed.

## Defect disposition

| Finding | Correction and reproducible evidence | State |
| --- | --- | --- |
| F-01 | Incomplete LuaCode opens an opaque region; no AA/resource/AOB/label/define/dependency escape. EOF emits OPAQUE-INCOMPLETE. Lua/Python regressions. | Implemented; available tests pass |
| F-02 | Embedded LuaCode masks its entire line and opens an opaque body. AA prefix is deliberately omitted; no syntax/execution semantics invented. | Implemented; Lua/Python/parity pass |
| F-03 | Ordered scan processes every IFDEF/IFNDEF/ENDIF, including nesting and extra ENDIF. Comments/quoted directives do not alter depth; following inventory survives balanced directives. | Implemented; Lua/Python/parity pass |
| F-04 | Conditional/opaque section headers emit SECTION-INDETERMINATE; subsequent section is unknown until an explicit unmasked header. Resources, AOBs, Lua globals and Lua/RVA retain provenance; schemas accept unknown. | Implemented; synthetic tests pass; schema validator unavailable |
| F-05 | Shared moduleNorm returns nil for invalid/non-string/empty/whitespace/quoted-empty input; moduleMatch rejects it before comparisons. aobscanmodule(x,,90) performs no MemScan. | Implemented; Lua regression pass |
| F-06 | Shared moduleMatch counts all normalized name/path matches. Ambiguous name or duplicate normalized path omits snapshot size and emits MODULE-SNAPSHOT-INCOMPLETE. Exact unique paths retain resolution; no first-match/modulePreference. Module Dump duplicate-name preflight still fails closed. | Implemented; Lua/Module Dump regressions pass |
| F-07 | Added schemas/module-dump.schema.json for persisted module-dump-1, all requested fields and optional/conditional previous_files/error/cancelled. Python checks real Lua sidecars, backup identity and byte relationships. Decline returns in memory without a new sidecar. | Implemented; I/O test passes; JSON Schema subgate blocked |

MAGNA's AOB-prefix KeyError did not reproduce. COMMAND is an anchored explicit
allowlist; every AOB key reaching the mapping is present, and region commands
are masked upstream. Unknown AOB prefixes are regression-tested. The dispatch
was left intact rather than making an unproven change.

## Added coverage and fixture reproduction

Seven focused Lua test functions cover F-01 to F-06 and unknown Lua/RVA provenance;
five new Python boundary tests cover F-01 to F-04 and MAGNA's prefix concern.
One runtime schema test for unknown provenance was added but cannot run without
jsonschema. New Python fixture-setup and Module Dump contract modules contain
three test functions (two executable here, one schema-dependent skip).

Parity grew from 17 to **40** fixed cases, including F-01/F-02/F-03/F-04, nested
same-line conditionals, comments, quoted directives, unknown sections, ordinary
AA resources/AOBs and embedded Lua boundaries. The exact DIESEL 33-case corpus
was not provided, so this is not represented as that identical corpus.

Parity compares command/arguments/section/line, resources, AOB inventories and
static status/uniqueness, diagnostic rule/line sequences, embedded Lua text and
start lines. Dependency JSON contracts differ: runtime AA occurrences are
compared with a projection from Python inventory, Python cross-script provider
visibility is checked, and simple Lua globals have explicit expectations. It
is not a claim of identical complete dependency formats.

Runtime schema fixture setup now generates the three JSON inputs in its own
fresh temporary directory with a trusted Lua harness and fixed test timestamps.
The independent fixture test compares two regenerations byte for byte. It does
not read preexisting ignored ce/tests/generated-*.json files. Production clocks
are unchanged. Module Dump tests use mocked memory/CE APIs and **real local
filesystem I/O outside CE**; they are not live CE tests.

## Exact final execution results

All commands run from the repository root, with Python 3.14 (64-bit),
PYTHONPATH=analyzer/src and the already installed CE Lua 5.3 64-bit library.
No package installation occurred.

| Command | Exit | Result |
| --- | --- | --- |
| python tools/build_ce.py | 0 | Candidate CT/Lua/ZIP generated |
| python tools/run_lua_tests.py --library "C:/Program Files/Cheat Engine/lua53-64.dll" | 0 | 72 Core Lua + 15 Module Dump + 14 distribution + 1 inert replay-harness test pass = 102 |
| python tools/check_parser_parity.py --library "C:/Program Files/Cheat Engine/lua53-64.dll" | 0 | 40 parity cases pass |
| python -m unittest discover -s analyzer/tests -v | 0 | 23 discovered: 21 pass, 2 schema skips |
| python -m unittest discover -s ce/tests -v | 1 | 4 unittest entries: 2 pass, 1 schema skip, 1 runtime-module import error |
| git diff --check | 0 | No whitespace errors after correction |
| git status --short --branch | 0 | Local modified/untracked candidate; snapshot below |
| git diff --no-ext-diff | 0 | Reviewed; full tracked diff saved locally |

The runtime import failure is ModuleNotFoundError: No module named jsonschema.
All **17** test_runtime.py methods are consequently blocked before discovery;
the import-error placeholder is not counted as an executed runtime test.
Three schema tests are skipped in total (two analyzer, one module-dump).
There are **165 distinct passing test/case checks** (102 + 40 + 21 + 2),
**3 skips and 1 import error**; this is **not a green full suite**. The Lua and
Module Dump suites rerun inside Python fixture setup are not double-counted.

The declared dependency is jsonschema>=4.18,<5 in analyzer/requirements-dev.txt.
It was absent in the normal Python and bundled app Python; the registered 3.13
interpreter was unavailable. No project virtualenv/vendor mechanism was found.
Provision that dependency separately under DG authorization, then rerun the same
commands; a clean clone also needs a compatible Lua 5.3 shared library, selected
with CESUITE_LUA_LIBRARY for the Python fixture setup. Installation is not part
of this mission.

Commands, return codes and unabridged local output are retained in
work/validation-0.1.9/commands.json and *.log. The trusted local orchestration was
python work/verify_candidate.py; it additionally built in two independent empty
temporary directories, compared every output against each other and releases/,
validated ZIP CRC/unique member set/UTF-8 source contents, and checked actual CT
XML Lua against the current bundle. This helper/log area is deliberately ignored;
the commands and results above remain versionable in this report.

## Reproducibility and SHA-256

Two independent builds are byte-identical for all four generated files and
match releases/. ZIP contains exactly the loader, bootstrap/core and all 13
current modules, with no parser-01.lua. CT XML is valid and self-contained.

| Artifact | SHA-256 |
| --- | --- |
| CESuite_Autorun_v0.1.9.zip | `f681b9eff594ceebbfc789349db540ef23c4c415f346434fb1483461f6914934` |
| CESuite_Core.CT | `2440c9381b8bcfc089ccb7521d22c10997b7d8d240bd688483aaa118aabbdcc2` |
| CESuite_Core.lua | `4322f63987a3801a441909c4fd6ac1dc8bd09b0c0ee76e01e35c5c8284c21d01` |
| CESuite_Core_v0.1.9.CT | `2440c9381b8bcfc089ccb7521d22c10997b7d8d240bd688483aaa118aabbdcc2` |

Pre-audit current artifacts were copied, before rebuilding, into
local-backups/pre-audit-20261022-191112-941765/. Historical versioned artifacts and
existing backups were not deleted. Generated versioned CT and ZIP remain ignored
local outputs under the existing project policy; their absence from git status
is not evidence that they were omitted from validation.

## Historical and live evidence

The exact private Dawnwalker input with SHA-256
`d2664fee953bc1953dad280119fcd95bd3ddd5b83d2647e421f87d26708007fa`
was not available in the repository. The 117/21/96/21/42/87/16 metrics are
**historical and pending current revalidation**. No replay result is invented;
--expect is documented as an optional private-input gate, not a clean-clone gate.
The manifest retains the expected counts with explicit historical/private status.

The DG's successful BIN + reports + PREMIUM-generated-table workflow is recorded
as user-reported practical evidence for that case. Earlier 0.1.3 CE observations
and the 440 MiB attempt remain historical. No new live CE acceptance was performed.

Exact pending live validations (full record sheet: docs/validation/live-0.1.9.md):
complete export; progress/percentage; total elapsed time; Cancel during large dump;
correct .partial; cancelled:true; unchanged files on declined overwrite; confirmed
overwrite; .previous; .previous.N; real previous_files JSON; absolute paths;
createSaveDialog; messageDialog; processMessages(); OnClose; busy guard; real
homonymous-module MODULE-SNAPSHOT-INCOMPLETE where a case is available; cold
startup/About/module file/hash verification and broader portable/report/AOB checks.

The mixed installed tree was not altered. docs/installation.md gives exact manual
backup/retirement/extraction/file-list/SHA-256 instructions. parser-01.lua is
retired with the entire old tree into backup, never deleted; CE must cold-restart.
About/version alone is explicitly not a per-module provenance proof.

## Final gates

| Gate | Status | Basis |
| --- | --- | --- |
| P0-05 | CERRADO (proposed; implementation/available synthetic evidence only) | F-01..F-04, 40-case parity and existing dependency/resource/AOB/Lua-RVA regressions pass; independent DIESEL review pending |
| P0-06 | CERRADO (proposed; implementation/available synthetic evidence only) | Invalid/ambiguous queries fail closed, aligned metadata and duplicate-name Module Dump preflight pass; independent review pending |
| P0-07 | BLOQUEADO | Documentation/schema/fixture changes complete, but the required full schema suite is unavailable without jsonschema |

Recommendation: **NO LISTO** for unconditional final acceptance until the schema
subgate is run successfully. Independent DIESEL review may inspect the candidate
and this explicit blocker; nothing here grants release authority. No AIR number
has been assigned.

## Git snapshot and changed files

Changes below include inherited uncommitted 0.1.7/0.1.8/0.1.9 work. They are not
all new edits from this mission; valid prior functions were retained.

HEAD remains `10e5b844ea5e112decebe1fa19d376da00d11c3a`. No refs or index entries were changed. Branch/remote
status uses cached refs; no fetch or remote publication was performed.

```text
## main...origin/main
 M .gitignore
 M CHANGELOG.md
 M README.md
 M analyzer/src/ct_analyzer/core.py
 M analyzer/tests/test_analyzer.py
 M ce/CESuite_Core.lua
 M ce/modules/aob.lua
 M ce/modules/environment.lua
 M ce/modules/parser.lua
 M ce/modules/ui.lua
 M ce/modules/util.lua
 M ce/tests/distribution_spec.lua
 M ce/tests/runtime_spec.lua
 M ce/tests/test_runtime.py
 M docs/analyzer-rules.md
 M docs/dependencies-v0.1.4.md
 M docs/installation.md
 M docs/runtime-core.md
 M docs/semantics-profile.md
 M docs/validation/dawnwalker.md
 M fixtures/validation/dawnwalker-replay.json
 M releases/CESuite_Core.CT
 M releases/CESuite_Core.lua
 M schemas/ct-report.schema.json
 M schemas/runtime-report.schema.json
 M tools/run_lua_tests.py
?? analyzer/tests/test_boundaries.py
?? ce/modules/moduledump.lua
?? ce/tests/module_dump_spec.lua
?? ce/tests/test_fixture_setup.py
?? ce/tests/test_module_dump_contract.py
?? docs/MODULE_DUMP.md
?? docs/p0-closure.md
?? docs/validation/live-0.1.9.md
?? docs/validation/premium-0.1.9.md
?? schemas/module-dump.schema.json
?? tools/check_parser_parity.py
```
