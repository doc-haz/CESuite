# Validation case: cached Dawnwalker report

This is an explicit regression case, not a naming rule or application-specific
feature. `fixtures/validation/dawnwalker-replay.json` records the exact cached
input SHA-256 and expected metrics. The source report remains local; it is not
bundled with the runtime or required by the synthetic suite.

Both the pre-generalized parser and the generic parser were run against the same
cached AA/Lua source text, without executing that text. Complete `dependencies`,
`resources` and `dependency_summary` arrays matched, including provenance.

| Metric | Before | Generic detector |
| --- | --- | --- |
| Occurrences | 117 | 117 |
| Provides / requires | 21 / 96 | 21 / 96 |
| Names | 21 | 21 |
| Lua/RVA resources | 16 | 16 |
| Summary groups | 42 | 42 |
| Summary locations | 87 | 87 |

The retained application-specific names are evidence only. No such prefix occurs
in a parser condition, schema constraint or environment exclusion set. CE `pause`,
`unpause` and `speedhack_setSpeed` are excluded as documented CE APIs.

## Reproduce with the retained private report

From the repository root, replace the input path with the retained report and
use an existing output directory:

```powershell
python tools/replay_dependencies.py C:/private/cached-report.json --output C:/private/replayed.json --library "C:/Program Files/Cheat Engine/lua53-64.dll" --expect fixtures/validation/dawnwalker-replay.json
```

The tool checks the input hash before replay, passes script bodies only as escaped
string data to the trusted parser, and fails if expected counts change. To compare
versions, use `--modules` with a trusted prior CESuite module directory and a
separate output; compare complete arrays, not only counts. Keep source and module
versions fixed. Reformatted copies can have equal counts but different lines.

This is not new live CE integration, hook compatibility, runtime availability or
activation-order validation. No game process was opened or modified.
