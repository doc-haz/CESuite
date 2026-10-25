# Dynamic Table Analysis (0.3.0 / 030B)

This document covers the static dataflow core added for CESuite 0.3.0. It is a
text analyzer: CESuite never executes table Lua, never calls `load`,
`loadstring`, `dofile`, `require`, `autoAssemble` or scan APIs from this module.

## What it does

`ce/modules/dynamic.lua` resolves a deliberately small Lua subset:

- local scalar and table declarations;
- ordered table constructors (string/numeric keys, nested rows);
- identifier, member and index references (`UE.Sig.GEnigne[2]`);
- function calls and call arguments (static values only);
- lexical scopes with shadowing;
- loader patterns that bind embedded helper files to globals
  (`findTableFile` / `_G.Name = include('Name')`);
- known wrapper contracts.

It does **not** emulate Lua. It does not evaluate arbitrary expressions,
`type()`, arithmetic, control flow, function returns or runtime state. Anything
outside the subset is retained as an unresolved node, never guessed.

## Static values

Internally a value is one of:

```text
string | number | boolean | nil | table | identifier | member | index |
call | binary | conditional | unknown
```

Tables keep ordered entries `{key, value, source_line}`. `UE.Sig.GEnigne[2]`
stays a member/index expression until a helper table is available; the resolved
string keeps `derivation.path`, `source_file` and `source_line`.

## Wrapper contracts

Contracts are declarative, not hardcoded FFRS semantics:

```lua
['register.onenable'] = {
  kind = 'table_sets',
  forwards_to = 'register.multicustomscan',
  consumer_role = 'scan_spec_table',
  constructs = 'aobScanRegion'
}
['register.multicustomscan'] = { kind = 'spec_rows', ... }
```

`Register.onEnable(prior, DhaosCollider)` is therefore read as:

```text
passes_to: prior -> Register.onEnable
passes_to: DhaosCollider -> Register.onEnable
calls:     Register.onEnable -> Register.multiCustomScan
constructs: Register.multiCustomScan -> aobScanRegion   (provenance only)
```

The contract never claims a callback. `DhaosCollider` is a local table of
record-keyed spec rows; its name is irrelevant.

New wrappers can be added to the contract table without rewriting the parser.

## Provenance model

Every relationship is an edge:

```json
{
  "relation": "passes_to",
  "from": "DhaosCollider",
  "to": "Register.onEnable",
  "provenance": "wrapper",
  "source_script": "script-95",
  "source_line": 177,
  "status": "linked",
  "confidence": "high"
}
```

Relations include `defines`, `reads`, `passes_to`, `calls`, `constructs`,
`provides`, `requires`, `includes`, `registers`, `consumes`, `derives_from`.
A dependency can carry several edges; it is never collapsed to a single
`source`. Provenance vocabulary: `aa`, `lua_local`, `lua_literal`,
`lua_dynamic`, `include`, `wrapper`, `callback`, `external_helper`, `runtime`,
`unknown`. `callback` is only emitted with real callback evidence;
`runtime` is never emitted by this static module.

## Pattern candidates

Each spec row becomes a candidate with an explicit kind:

```text
literal_pattern | derived_pattern | conditional_pattern | symbol_only | unknown
```

Literal and derived rows carry `pattern`, `pattern_length`, `symbol`, source
script/line, consumer, provenance edges and `runtime_validated=false`.
`symbol_only` rows are not patterns. Conditional expressions are published as a
JSON-safe object, never as an internal AST:

```json
{
  "kind": "conditional_expression",
  "text": "(type(LaunchUEInfoScanner) == \"function\") and start",
  "dependencies": ["LaunchUEInfoScanner"],
  "resolution": "unknown",
  "fallback": "start"
}
```

They are not evaluated and remain `unresolved`. Duplicate instances (for
example `func_give_item`) keep separate ids and share the same normalized
pattern; they are not silently deduplicated.

Exact provenance edges are de-duplicated by
`relation/from/to/source_script/source_line/provenance`. Different lines,
different relations, or different endpoints are preserved. Limits
(`TABLE_LIMIT`, `PARSE_LIMIT`, `EDGE_LIMIT`, `CANDIDATE_LIMIT`, ...) are
propagated to `status=limit_reached`; truncation is never silent.

## Loader / external helpers

`findTableFile("Register.lua")` / `_G.Register = include('Register')` produce
`includes` and `provides` edges for `Register`, `UE`, `Starter` and `Recorder`.
Helper tables are parsed from captured file text. If a helper is not available,
a derived pattern stays `unresolved`; it is not guessed and not promoted to
runtime validated.

## script-95 acceptance (fixture)

Input: `ce/tests/fixtures/dynamic/script95.lua`, `ue.lua`, `loader.lua`.

```text
entries              47
specs                52
literal patterns     28
literal unique       27
derived patterns      3
conditional specs     1
symbol_only          21   (includes the conditional row; pure symbol_only = 20)
unique symbols       30
candidates           31
runtime validated     0
unresolved            LaunchUEInfoScanner
```

The counts sum as `28 + 3 + 21 = 52`; `conditional=1` is a subset of
`symbol_only`. `candidates = 28 + 3`.

## Shared locals limitation

`parser.lua` keeps a conservative per-record `sharedLocals` set: a local
declared in an earlier Lua block suppresses a later same-name global in the
same record. This under-reports instead of inventing scope and is documented
as a limitation, not treated as a full Lua scoping model.

## Determinism and limits

Ordering is source-line based; ids are derived from source script/line/counter.
No addresses, process state, timestamps or unordered table iteration influence
the result. Limits: tokens 200000, depth 12, table entries 2000, edges 5000,
candidates 5000, symbols 2000, wrapper depth 4. Exceeding a limit yields
`limit_reached` and structured unresolved entries; it never crashes.

## Static report

`Core.analyzeStaticLua` adds an optional `dynamic_analysis` object to the
standalone static report when candidates are discovered. It is additive; the
existing observations, diagnostics, `source_complete`/operation telemetry and
runtime report are unchanged. The block contains `patterns`, `edges`, `nodes`,
`dependencies`, `providers`, `counts`, `unresolved`, `limits` and `status`.

## Not in 030B

No coverage model (`collection`/`discovery`/`validation`), no percentages, no
UI, no runtime tracing, no snapshot viewer, no compatibility scoring, no AI
inference, no active instrumentation.

## Coverage

The discovery counts feed `coverage.discovery`; validation is separate and is
never promoted from static analysis. See [coverage-model.md](coverage-model.md).

Regression fixtures and the fixture contract are documented in
[regression-corpus.md](regression-corpus.md).
