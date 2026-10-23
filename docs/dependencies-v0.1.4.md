# First dependency inventory (Core 0.1.4)

`report.dependencies` contains partial lexical occurrences, not a resolved graph.
Every row retains `script_id`, `line`, `section`, `command`, `name`, `kind`,
`relation`, `source: lexical` (AA) or `source: lua_lexical` (Lua), and
`status: unverified`.
`provides` means the source declares a candidate; it does not prove execution,
availability, ownership, uniqueness, export visibility or activation order.
`requires` can refer to a name in the same script; it is not automatically an
external dependency. Repeated names and occurrences remain separate.

| Source | Occurrences |
| --- | --- |
| aobscan / aobscanmodule / aobscanregion with expected argument count | symbol provides |
| define(name, value) | name: symbol provides; simple symbolic value: symbol requires |
| label(name) | symbol provides |
| alloc(name, size[, near]) / globalalloc(name, size) | resource provides and symbol provides; simple near symbol requires |
| registersymbol(name[, name...]) | each name: symbol requires and registered_symbol provides |
| unregistersymbol(name[, name...]) | each name: symbol requires |
| dealloc(name) | resource requires |
| name: | symbol requires, never inferred as a definition |

Only unquoted ASCII identifiers `[A-Za-z_][A-Za-z0-9_]*` are collected; pure hex
tokens are omitted because they can denote numeric addresses. Complex expressions,
wildcards, module-qualified addresses, macros and instruction operands are outside
the AA detector. A matching argument count is not full AA syntax validation.
Embedded Lua is handled separately below; inspected source is never compiled or evaluated. Includes,
preprocessor directives and Lua can change source semantics, so all results remain
unverified and existing dynamic-source diagnostics are retained.

Common, ENABLE and DISABLE occurrences retain their section. Cleanup occurrences
describe lexical needs, not proof that anything was allocated or registered.
The existing resources, defines, labels and warnings retain their previous behavior.

## Embedded Lua globals

Core 0.1.4 restricted bare globals to a fixed namespace. Core 0.1.5 removes
that restriction; see [generic detection rules](dependencies-v0.1.5.md).
The neutral examples below describe the current semantics, with
`kind: lua_global` and the parent AA script ID and line.

| Source | Occurrence |
| --- | --- |
| `local s=MOD_PLAYER` or `MOD_PLAYER.enabled` | `requires`, `lua_global_reference` |
| `MOD_GODMODE={...}` or other single non-nil assignment | `provides`, `lua_global_assignment` |
| `function customHelper(...)` | `provides`, `lua_global_assignment` |
| `GAME_STATE=nil` or `GAME_STATE.enabled=false` | `requires`, never proof of creation |
| `GAME_STATE=GAME_STATE or {}` | one provides and one requires occurrence |

Quoted strings, escaped quotes, line comments, long strings/comments with arbitrary
equals-delimiter levels, member names and constructor keys are excluded. Explicit
locals, function parameters and loop variables are suppressed throughout their
chunk, deliberately under-reporting instead of resolving lexical scope. Section
markers and Lua/ASM directives inside multiline literals/comments are ignored.
Real ENABLE/DISABLE markers retain section provenance even without an ASM switch.

This is not a Lua parser: multiple assignment, computed `_G[...]`/`rawget`/`rawset`,
environment rebinding, dynamically generated code, standalone table Lua and full
scope/control-flow analysis are unsupported. Constructor-context assignments may
be omitted. Assignments to nil are cleanup references; no availability or lifetime
is inferred. Repeated occurrences are not deduplicated or linked across scripts.
Neither the original source nor the masked text is passed to a compiler/evaluator.

Schema version remains 0.1 with an additive field: dependencies is required for
Core 0.1.4 and optional for older reports. The schema also accepts Core 0.1.2/0.1.3
and the already implemented Lua/RVA resource shape. Consumers using an older
closed schema must update it before validating 0.1.4 reports.

Validation uses synthetic Lua/CE mocks, JSON exports and schema rejection tests.
Application-specific evidence belongs in [reproducible validation cases](validation/dawnwalker.md).

Current 0.1.9 boundary: aobscanregion is opaque and no longer emits a provider.
The table above records the original 0.1.4 lexical contract; see p0-closure.md.
