# Version and evidence profile (Core 0.1.6, P0-04)

Every new Core report includes `semantics_profile`. It describes the reference
used to reason about CE, not a certificate of compatibility or a capability probe.
It is metadata only: no additional CE API calls, inspected source execution,
binary inspection, symbol resolution or parser changes.

## Fields and evidence layers

| Field | Meaning and population in profile revision 1 |
| --- | --- |
| `profile_version` | `"1"`, the metadata format revision. |
| `profile_id` | `ce-public-ec45d5f-to-runtime-r1`, the fixed evidence profile. |
| `source_profile.repository` | Official `https://github.com/cheat-engine/cheat-engine` repository. |
| `source_profile.commit` | Exact reference snapshot `ec45d5f47f92a239ba0bf51ec5d04a7509c3fd37`; required and fixed by this profile's schema. Missing, malformed or different SHAs are rejected. |
| `source_profile.version_label` | `7.5.1 public-source baseline`, a human research label, not an exact binary identity or asserted release tag. |
| `source_profile.version_label_basis` | `research_context_not_binary_identity`. The commit is the reproducible source identity. |
| `runtime_profile.declared_version` | `null`: there is no current report input for a separately evidenced version declaration. |
| `runtime_profile.declared_version_basis` | `not_available`. The user's external validation target is CE 7.7.1; it is not injected into reports. |
| `runtime_profile.api_version` | Exact copy of the existing `ce_version` string, already populated by `tostring(getCEVersion())` through the guarded API call. `unknown` when the existing collector cannot obtain a value. No second API call. |
| `runtime_profile.file_version` | `null`: no executable version metadata is collected. |
| `runtime_profile.binary_sha256` | `null`: no executable hash is collected. |
| `source_runtime_equivalence` | Always `unverified`. Partial tests and changelog entries never upgrade this state. |
| `known_post_source_changes` | A small, non-exhaustive chronology of announced changes; included independently of observed runtime version. It does not assert those features exist in the current process. |

For example, API value `7.71` produces `api_version: "7.71"` and
`declared_version: null`. It never becomes `7.7.1`. Even a more detailed API
string is retained only as API evidence, not a proven build/commit identity.
The `unknown` sentinel is inherited from `ce_version`, not an inferred version.
This revision deliberately only accepts null declared/file/hash fields. Adding
an evidence-backed collection or declaration path needs a future contract change.

## Internal release-note references

The following references name the user-supplied chronology summarized in
**CESuite CE Semantics Profile**, second research pass, revision 1,
19–20 September 2026, sections A1–A7. They are internal identifiers, not URLs.
That research pass used the user's textual chronology as secondary evidence;
it did not re-read the original Patreon images. No private URLs, exact post dates
or unprovided quotations are asserted here.

| Entry ID | Reference | Announced change relevant to CESuite |
| --- | --- | --- |
| `luacode-no-dll-injection` | `user-chronology/7.5.2` | LuaCode no longer requires DLL injection. |
| `globalalloc-save` | `user-chronology/7.6.1` | Globalalloc symbols no longer saved in tables. |
| `aa-conditionals-aob` | `user-chronology/7.6.2` | IFDEF/IFNDEF/ENDIF also apply to AOB scans. |
| `aa-hook-unhook` | `user-chronology/7.6.3` | HOOK/UNHOOK commands introduced. |
| `aobscanex-executable-fix` | `user-chronology/7.7.1` | Fix for AOBSCANEX not being limited to executable memory; not a claim that it intentionally scans all memory. |
| `async-thread-ondestroy` | `user-chronology/7.7.1` | OnDestroy of the asynchronous Memory Record thread; not a generic Memory Record event claim. |

Each row has `id`, `version`, `feature`, `evidence_kind`, `evidence_ref` and
`runtime_validation`. The last two evidence states are always
`release_note_evidence` and `not_performed`, respectively. These are announced
changes, not source code or fresh live observations. The list is representative,
not a complete changelog or a feature support matrix.

## Compatibility and remaining scope

Current Core identifies itself as `0.1.9`; schema version stays `0.1` for this additive
extension. The new schema accepts valid old Core 0.1.0–0.1.5 reports without
`semantics_profile`. The profile remains optional through 0.1.9. If present,
its fields are required and additional fields are rejected. Existing requirements
continue: dependencies for 0.1.4–0.1.9, dependency_summary for 0.1.5–0.1.9.
Unchanged old validators can reject new reports because of their core-version
enum and root `additionalProperties: false`; compatibility is old data read by
the new schema, not new data read by old validators.

`dependencies[*].status` stays `unverified`. Aggregation, resources, AOB results,
Lua/RVA inventory, lifecycle and passive capture retain their existing semantics.
Profile metadata does not resolve a dependency or establish ownership, hook
safety, runtime availability or source/runtime equivalence.

The 0.1.9 tree implements conservative P0-05 boundaries and P0-06 ambiguity
checks separately from this metadata profile. See [closure status](p0-closure.md)
for regression evidence and pending independent/live review. No P1/P2 feature support is added.
Synthetic tests validate the report contract only; live CE compatibility remains
unverified for this increment.

Section `unknown` is a provenance state introduced by the local 0.1.9 audit
correction. It is accepted in resources, AOBs, dependency occurrences and summary
locations/sections; it does not upgrade the evidence profile or evaluate branches.
