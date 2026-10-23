# Static Lua AOB Analysis

Passive source inventory for Lua scripts in Cheat Engine tables (`.CT`).

## Purpose

Cheat Engine tables frequently configure and register AOB scans through Lua scripts
rather than pure Auto Assembler (AA) headers. This tool performs a bounded,
passive lexical scan of:

- Root `<LuaScript>` blocks.
- Embedded Lua files stored under `<Files>` (decompressed via Ascii85/DEFLATE).
- Embedded Lua blocks inside Auto Assembler scripts (`{$lua} ... {$asm}`).

It inventories literal and statically resolvable AOB patterns without executing
inspected Lua code, starting a Lua VM or attaching to target processes.

## Capabilities and Constraints

- **Supported sinks:** `aobScan`, `aobScanModule`, `aobScanRegion`, `customScan`,
  and common wrappers like `Register.multiCustomScan` and `Register.onEnable`.
- **Resolvable expressions:** single-assignment string literals, string
  concatenation (`..`), aliases, table field lookups (`t.field`, `t[idx]`),
  and nested row declarations.
- **Library declarations:** unlinked library patterns (such as `Obj.Sig` or
  `UE.Sig.*`) are inventoried as unlinked declarations without assuming object
  initialization.
- **Fail-safe boundaries:** reassignments, runtime calls (`func()`), forward
  references, dynamic control flow, arithmetic, and expressions exceeding depth or
  token limits remain `status: "unknown"` with `pattern: null`.
- **No runtime promotion:** static candidates are labeled `provenance: "static-lua"`
  and `uniqueness: "unverified"`. They are never merged into runtime-verified AOB
  match results.

## CLI and In-CE Usage

Run from the repository root:

```powershell
$env:PYTHONPATH = 'analyzer/src'
python -m ct_analyzer input.CT --output reports/static
python -m unittest discover -s analyzer/tests -v
python tools/enrich_static_aobs.py input.CT runtime.json reports/enriched.json
```

The enrichment command preserves original runtime observations and adds
`static_lua_analysis`. Input hashes establish provenance, not that the CT is
the same table loaded when the runtime report was produced.

In addition to offline Python analysis, CESuite 0.2.0-beta1 adds two in-CE menu commands under CESuite:
- `Static Lua AOB Analysis`: runs passive lexical Lua analysis on the loaded table and displays results in the viewer.
- `Export Static Lua Report`: exports a full runtime report enriched with the `static_lua_analysis` section.

### Versioning and Provenance

Reports distinguish between engine compatibility and tool suite release:
- `core_version`: `0.1.9` indicates the baseline runtime report format and schema contract compatibility level. Existing automated consumers relying on `0.1.9` runtime semantics continue to parse reports without breaking changes.
- `suite_version`: `0.2.0-beta1` records the actual CESuite release that executed the analysis and generated the static/enriched report. When available, it is exposed in the `static_lua_analysis` section and in the in-CE viewer.

## Synthetic Test Fixture

`fixtures/lua-static-synthetic.CT` contains 22 synthetic row declarations (21 unique
patterns) modeling multi-custom-scan wrappers, duplicate patterns, and unknown arguments. It is 100% synthetic, contains no proprietary binaries or game-specific content, and was created solely for test suite validation. Tests also cover
unknown calls, concatenation/indexing, comments, malformed payloads, resource
limits and JSON output. No live matching or uniqueness test is implied.
