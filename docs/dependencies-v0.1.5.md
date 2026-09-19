# Dependency aggregation (Core 0.1.5, unreleased)

`dependencies` retains its v0.1.4 array shape and original lexical evidence.
Generic Lua detection may add names outside the former fixed namespace.
The summary representation, AA detector and all resources including Lua/RVA
retain their contracts.
No inspected AA/Lua is compiled or executed. See [detection limits](dependencies-v0.1.4.md).

`dependency_summary` is a derived array, rebuilt after collection in every mode
(an empty JSON array in process-only or empty-table reports). The new
**Dependency Summary** menu command analyzes the loaded table and displays this
array. Full report views and exports include both arrays. The summary view is
not a graph of resolved dependencies, an activation order, or proof of availability.

## Group and location identity

One group per exact `(name, kind, source, relation)`, retaining case. AA symbols,
resources, registered symbols and Lua globals cannot merge merely because their
names match. `provides` and `requires` always remain separate groups. Every group
has `status: unverified`, even when a candidate provider exists.

| Field | Meaning |
| --- | --- |
| `occurrence_count` | Total original rows in the group, including repeated uses |
| `location_count` | Distinct `(script_id, section, line, command)` locations |
| `script_ids`, `sections` | Unique values in first-observed order |
| `locations` | Unique locations, each with its own `occurrence_count` and `occurrence_indices` |
| `occurrence_indices` | One-based positions in the same report's `dependencies` array |

Groups, locations and value arrays retain first-observed order; re-aggregation of
the same input is deterministic and does not mutate the input. Indices are local
to one analysis; never join indices across independently refreshed reports.

Repeated rows at the same location are displayed once, with their multiplicity
and every original index. There is intentionally no claim of a distinct-token
count: v0.1.4 has no column/offset, so two genuine uses on one line cannot safely
be distinguished from duplicate evidence. Neither is deleted. Different lines,
scripts, sections, commands, kinds, sources or relations retain their provenance.
Length-prefixed internal keys avoid collisions with delimiters in script IDs.

For `print(GAME_STATE,GAME_STATE)`, the requires group has occurrence count 2,
location count 1 and both indices. A use in another script adds another location
and script ID. `GAME_STATE=GAME_STATE or {}` creates separate provides/requires
groups; it does not establish a verified or external dependency.

## Generic Lua detection and exclusions

Bare identifiers use `[A-Za-z_][A-Za-z0-9_]*`, with exact case and no prefix or
uppercase requirement. A simple non-nil global assignment or named global
function is a candidate `provides`; a read, unknown function call, member root,
nil assignment or member update is a candidate `requires`. All use
`source: lua_lexical`, `kind: lua_global`, `status: unverified`.

Examples: `GAME_STATE={}` provides; `local x=MOD_PLAYER` requires;
`modPlayer.enabled=false` requires `modPlayer`; `customHelper(TEST_GLOBAL)`
requires both names. An unrecognized call is not proof that a function exists.

The detector excludes explicit locals, function parameters, loop variables,
implicit method `self`, keywords, comments/strings, constructor keys, member
names, numeric literals, goto labels, and known Lua/CE environment names.
`ce/modules/luanames.lua` contains reviewable, case-sensitive, exact-name sets:
Lua 5.1–5.4 standard names and a bounded catalog of common CE APIs, context
globals (`syntaxcheck`, `memrec`, etc.) and constants. CE spellings are based on
`celua.txt` and `defines.lua`. No prefix such as `get*` or `read*` is excluded wholesale. The
detector never consults ambient `_G`, resolves a symbol, or invokes an API to
decide whether a name is a dependency. Results do not depend on loaded plugins.

This is conservative lexical analysis, not a complete Lua parser. False positives
remain possible for unknown CE/plugin APIs, custom environment names, or syntax
outside the recognized subset. False negatives are possible when a user rebinds
a known builtin/API name, when chunk-wide local suppression hides a global use
outside the local's real scope, or for multiple assignments, computed `_G` access,
environment rebinding, includes, generated code, standalone table Lua and
constructor-context assignments. Same-name definitions do not prove a resolved
dependency. Exclusion sets should be extended by exact, documented API names,
never by names taken from a particular application.

## Compatibility and verification

Schema version stays `0.1`. The updated runtime schema accepts Core 0.1.0–0.1.5;
`dependencies` is required for 0.1.4/0.1.5, and `dependency_summary` only for 0.1.5.
Older reports need no migration. Closed older schemas must be updated before
validating a new report. Existing occurrence fields and arrays are not renamed,
removed or reinterpreted. The separate Python CT Analyzer report contract remains
unchanged: it is not the Core Runtime report.

The schema checks structure and unverified status; regression tests additionally
check cross-field counts, group identities, and indices back to original rows.
An immutable synthetic 0.1.4 export verifies compatibility. Lua tests cover same
line repetitions, cross-script names, both relations, namespace/case separation,
excluded false positives, deterministic aggregation and no input mutation.
Packaging tests exercise portable/autorun loading with CE mocks. These checks
do not constitute live CE integration validation.

Application-specific metrics and input provenance belong in the
[reproducible validation case](validation/dawnwalker.md), not in detection rules.
