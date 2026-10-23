# CESuite 0.1.9 - D-1 to D-4 documentation/pre-commit hygiene

**LISTO PARA REAUDITORIA DIESEL PRE-RELEASE**

Mission scope: documentation and one-file EOL hygiene. Version remains 0.1.9.
No AIR number assigned. No functional code, test semantics, architecture, CE
installation, ACLs or dependencies changed. No backups or historical artifacts
deleted. No commit, push, tag or release performed. HEAD remains
`10e5b844ea5e112decebe1fa19d376da00d11c3a`; no index/ref mutations.

## Files changed by this mission (not the whole inherited working tree)

- .gitattributes
- CHANGELOG.md
- docs/p0-closure.md
- docs/runtime-core.md
- docs/validation/live-0.1.9.md
- schemas/ct-report.schema.json
- docs/validation/hygiene-0.1.9.md (this report)

A before/after SHA-256 inventory confirmed that the six pre-report changed paths
were exactly the intended documentation/schema/attribute files. Generated bundles
remain identical. The larger Git snapshot below includes inherited uncommitted
work and must not be represented as code newly changed by this hygiene mission.

## D-1: complete

p0-closure now records DIESEL's independent technical closure of P0-05, P0-06 and
P0-07, with Python 3.14.7 64-bit and jsonschema 4.26.0. The dependency was already
installed under prior DG authorization; this mission installed nothing. Current
results supersede the former dependency block. The earlier premium-0.1.9.md
report is retained as a historical snapshot, not rewritten as if it had passed
at the time. Technical closure does not itself publish a release or replace live
acceptance.

## D-2: complete

runtime-core documents SECTION-INDETERMINATE and section="unknown" when a
conditional/opaque section header has no evaluated effective branch. Only an
explicit unmasked header restores known provenance. Lua/RVA, resources, AOBs and
dependencies retain unknown where applicable. No runtime behavior was changed.

## D-3: complete

The 0.1.9 Unreleased section now has explicit overwrite/backups, P0 technical
closure and current DG/AIR Boss live-observation subsections. Module Dump's
0.1.7 introduction and 0.1.8 progress/cancellation remain in chronological entries;
0.1.5/0.1.6 remain historical local development increments included in the current
candidate. Historical 0.1.5/0.1.6 bullet content is preserved. No published-release
date or status is invented. The stale missing-jsonschema/current-live-pending
claims were replaced with the evidence now supplied.

## D-4: complete

The tracked schema baseline has CRLF line endings. Restored those line endings
and retained only the three section-enum extensions (aobs/symbols/allocations).
A structural JSON comparison against HEAD plus exactly those additions passed.

.gitattributes contains only:

```gitattributes
schemas/ct-report.schema.json -text whitespace=cr-at-eol
```

This one-file rule preserves the already tracked CRLF content without Git's
text conversion turning it into a whole-file rewrite. It recognizes CR at line
end for whitespace checks; other whitespace errors remain checked. No repo-wide
EOL normalization or user/global Git configuration was changed.

`git diff --numstat -- schemas/ct-report.schema.json`: **6 additions, 3 deletions**.
`git diff --ignore-cr-at-eol -- schemas/ct-report.schema.json`: exactly three
small enum hunks. `git diff --check`: exit 0, no whitespace errors.

## Live evidence recorded

live-0.1.9.md records A-L as DG/AIR Boss observations, separately from automated
mocks and real local file I/O outside CE. PREMIUM did not repeat the live actions
in this mission or invent missing timestamps/private files.

Passed evidence: clean install/backup/retirement/cold start, parser-01.lua absent,
About 0.1.9 | ready | autorun and one menu; portable singleton and Analyze;
Silksong complete export (692224/692224 bytes, no unreadable ranges,
module-dump-1, atomic_snapshot:false, null fingerprint, binary + JSON, same-second
observation only); FFRS 461701120-byte module progress/responsive UI (including
35.3/440.3 MiB, 8%); Cancel with partial/cancelled:true, 88080384 bytes and readable
JSON; safe progress-window X; busy rejection and recovery; save-dialog cancel/X
with no new binary/partial; overwrite No/X preserving files/no new backup/no dump;
Yes completing replacement with previous_files; .previous and collision
.previous.1 preserving earlier backups; paths with spaces; general recovery.

Pending: real homonymous-module MODULE-SNAPSHOT-INCOMPLETE (conditional on
finding a real case, not an automatic blocker); specific live R-1 same-line
section-header/content case; unobserved internal API paths. No unprovided total
large-export time or completed large-export sidecar is claimed.

Dawnwalker input remains private/unavailable, expected SHA-256
`d2664fee953bc1953dad280119fcd95bd3ddd5b83d2647e421f87d26708007fa`.
117 / 21 / 96 / 21 / 42 / 87 / 16 remain historical and pending current replay;
this is not a mandatory clean-clone gate. No replay was invented.

D-5 (internal path in sidecar error) and D-6 (standalone runner writing ignored
fixtures without output_path) are intentionally deferred post-0.1.9 follow-ups.

## Validation rerun

Environment independently read in this mission: Python **3.14.7, 64-bit**;
jsonschema **4.26.0**. Existing CE Lua 5.3 64-bit library used; no CE launch or
installation mutation. All commands ran from C:\Azuara\CESuite.

| Command | Exit | Result |
| --- | ---: | --- |
| python -m unittest discover -s ce/tests -v | 0 | Ran 20 tests; OK |
| PYTHONPATH=analyzer/src python -m unittest discover -s analyzer/tests -v | 0 | Ran 23 tests; OK (PowerShell environment variable used) |
| python tools/check_parser_parity.py --library "C:/Program Files/Cheat Engine/lua53-64.dll" | 0 | 40/40 |
| python tools/run_lua_tests.py --library "C:/Program Files/Cheat Engine/lua53-64.dll" | 0 | 72 Core + 15 Module Dump + 14 distribution + 1 replay harness = 102 |
| python tools/build_ce.py | 0 | All four outputs regenerated; hashes unchanged |
| git diff --check | 0 | No whitespace errors |
| git status --short --branch | 0 | Snapshot below |
| git diff --ignore-cr-at-eol -- schemas/ct-report.schema.json | 0 | Only three section-enum hunks |

**185 distinct passing checks; 0 skips; 0 failures.** Internal Lua reruns during
Python fixture setup are not double-counted. Exact local commands/return codes
and output are in work/document-hygiene/commands.json and *.log; the local helper
was python work/document-hygiene/verify.py. That ignored scratch area is not
required for clean-clone test reproduction.

## Current SHA-256

All four match the DG-specified values both before and after the build:

| Artifact | SHA-256 |
| --- | --- |
| CESuite_Autorun_v0.1.9.zip | `F681B9EFF594CEEBBFC789349DB540EF23C4C415F346434FB1483461F6914934` |
| CESuite_Core.CT | `2440C9381B8BCFC089CCB7521D22C10997B7D8D240BD688483AAA118AABBDCC2` |
| CESuite_Core.lua | `4322F63987A3801A441909C4FD6AC1DC8BD09B0C0EE76E01E35C5C8284C21D01` |
| CESuite_Core_v0.1.9.CT | `2440C9381B8BCFC089CCB7521D22C10997B7D8D240BD688483AAA118AABBDCC2` |

## Current Git snapshot

Cached branch/remote refs are shown; no fetch or publication performed. Existing
working changes remain unstaged; this mission did not stage or commit them.

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
?? .gitattributes
?? analyzer/tests/test_boundaries.py
?? ce/modules/moduledump.lua
?? ce/tests/module_dump_spec.lua
?? ce/tests/test_fixture_setup.py
?? ce/tests/test_module_dump_contract.py
?? docs/MODULE_DUMP.md
?? docs/p0-closure.md
?? docs/validation/hygiene-0.1.9.md
?? docs/validation/live-0.1.9.md
?? docs/validation/premium-0.1.9.md
?? schemas/module-dump.schema.json
?? tools/check_parser_parity.py
```

## Recommendation

**LISTO PARA REAUDITORIA DIESEL PRE-RELEASE.** D-1 to D-4 are complete, live
evidence is recorded within its supplied limits, 185 checks pass, all candidate
hashes match and diff --check is clean. No release authority is inferred from
this recommendation. The conditional live checks and D-5/D-6 follow-ups remain
explicit and do not become invented passes.
