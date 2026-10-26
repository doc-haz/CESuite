# Static Lua AOB Analysis

`ct_analyzer` extracts literal Auto Assembler AOB patterns from Cheat Tables.
`ct_analyzer.lua_static` extends that capability to table Lua without
executing inspected scripts, user-defined functions or target memory.

## Capabilities

The static analyzer resolves:

- literal variable assignments and aliases: `local pattern = '48 8B 05 ??'`;
- string concatenations (`..`) of string literals and resolved variables;
- static table construction and literal indexing: `patterns.godmode`, `tbl[1]`;
- supported sink calls (case-insensitive):
  - `aobScan` / `AOBScan`
  - `aobScanModule` / `AOBScanModule`
  - `aobScanRegion` / `AOBScanRegion`
  - `customScan`
  - `Register.multiCustomScan`
  - `Register.onEnable`
- unlinked library signature declarations: tables or properties declared with `*.Sig` / `*.Sig.*`;
- embedded Lua blocks (`{$lua}`) in Auto Assembler scripts;
- base85 and DEFLATE compressed embedded table files (`Files/*.lua`).

## Safety and Limits

- **Passive only:** input source is parsed into tokens and analyzed via bounded
  AST traversal. No Lua code or target process API is called.
- **Fail-closed:** dynamic concatenations, function returns, unresolved table
  lookups, cycles and loops remain `status: "unknown"` with pattern `null`.
- **Resource bounds:** input source is capped at 2 MiB, token count at 150,000,
  AST depth at 48 levels, and resolved string length at 64 KiB.
- **Observation only:** extracted patterns are recorded with `status: "source-candidate"`,
  `confidence: "lexical"`, `match_count: null`, and `uniqueness: "unverified"`.
  They are never promoted to runtime-verified AOBs without explicit memory scans.

## Integration

Use `ct_analyzer.lua_static.analyze_lua(source, script_id)` directly, or use
`tools/enrich_static_aobs.py` to add `static_lua_analysis` to an existing
runtime report:

```bash
python tools/enrich_static_aobs.py table.CT runtime.json enriched.json
```

The enrichment command preserves original runtime observations and adds
`static_lua_analysis`. Input hashes establish provenance, not that the CT is
the same table loaded when the runtime report was produced.

In addition to offline Python analysis, CESuite 0.2.0 adds two in-CE menu commands under CESuite:
- `Static Lua AOB Analysis`: runs passive lexical Lua analysis on the loaded table and displays results in the viewer.
- `Export Static Lua Report`: exports a full runtime report enriched with the `static_lua_analysis` section.

### Versioning, Provenance and Schema

Reports distinguish between engine compatibility and tool suite release:
- `core_version`: `0.1.9` indicates the baseline runtime report format and schema contract compatibility level. Existing automated consumers relying on `0.1.9` runtime semantics continue to parse reports without breaking changes.
- `suite_version`: `0.3.1` records the actual CESuite release that executed the analysis and generated the static/enriched report. When available, it is exposed in the `static_lua_analysis` section and in the in-CE viewer.
- A dedicated JSON schema for standalone static Lua reports is available at [`schemas/static-lua-report.schema.json`](../schemas/static-lua-report.schema.json).

## Synthetic Test Fixture

`fixtures/lua-static-synthetic.CT` contains 22 synthetic row declarations (21 unique
patterns) modeling multi-custom-scan wrappers, duplicate patterns, and unknown arguments. It is 100% synthetic, contains no proprietary binaries or game-specific content, and was created solely for test suite validation. Tests also cover
unknown calls, concatenation/indexing, comments, malformed payloads, resource
limits and JSON output. No live matching or uniqueness test is implied.

## Dynamic table analysis (0.3.0)

The standalone static report may also contain an optional `dynamic_analysis`
block produced by `ce/modules/dynamic.lua`. It adds local-table resolution,
wrapper contracts (`Register.onEnable`/`Register.multiCustomScan`), helper
`UE.Sig.*` resolution, pattern candidates and multi-provenance edges. It is
text-only and does not execute table Lua. See
[dynamic-table-analysis.md](dynamic-table-analysis.md).

Static reports include an optional `coverage` block whose validation layer is
`unavailable`/`not_applicable`; static text never counts as runtime validation.
See [coverage-model.md](coverage-model.md).
