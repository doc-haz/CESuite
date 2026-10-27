# Evidence Advisor — Architecture (032A)

The Evidence Advisor converts evidence already produced by CESuite into
deterministic, explainable findings. It does not observe the target, execute
scripts, modify tables or invent evidence.

```text
CORE → EVIDENCE → ADVISOR → RECOMMENDATION
```

Never:

```text
ADVISOR → invented evidence
NO EVIDENCE → NO ASSERTION
NO EVIDENCE → NO AUTOMATIC CHANGE
```

## 032A/032B/032C status

Architecture, deterministic engine and read-only AdvisorUI integration in the
`0.3.2` release-candidate line. The engine has 67 deterministic Lua checks, 9
Advisor UI checks and 6 Python schema/privacy checks. The released Core v0.3.1
does not load Advisor; the dev Core loads advisor.lua, advisorrules.lua and
advisorui.lua.

## Deliverable checklist

1. Architecture — this document and pure modules.
2. Data model — report/finding/evidence-ref model and schema.
3. Finding taxonomy — neutral category enum.
4. Severity — INFO/LOW/MEDIUM/HIGH/CRITICAL semantics.
5. Confidence — exact/strong/weak/unknown.
6. Evidence refs — structured source/entity/id/field/value references.
7. Observation/interpretation — separate fields and rule builders.
8. Likely causes — bounded hypotheses.
9. Next steps — review-only action enum.
10. Do-not-assume — required for every finding.
11. Ruleset format — rule table with id/code/severity/confidence.
12. Precedence/deduplication — stable order, dedupe key, suppression.
13. Comparability — status-aware gates.
14. Coverage — collection/discovery/validation separated.
15. Target/build — separate target and build findings.
16. Pattern — unchanged/changed/removed/added cases.
17. Dependencies/provenance — provider/consumer/helper/provenance changes.
18. Module/address — inventory and non-ASLR address evidence.
19. Unknown/fail-closed — advisor_unavailable; no silent partial report.
20. JSON schema — schemas/evidence-advisor.schema.json.
21. Advisor identity — adv- SHA-256 canonical input/ruleset.
22. Ruleset versioning — advisor vs ruleset versions.
23. Security/privacy — data-only; no load/network/filesystem.
24. Performance bounds — max findings/refs/observations/causes/steps.
25. Corpus/test matrix — 31 rules tests + schema/privacy tests.
26. Relocation interface — review-only
equest_relocation_candidates.
27. Repair Plan interface — finding/evidence/action/approval only; no mutation.
28. UI concept — future Explain Comparison...; not implemented.
29. Module/API — advisor.lua, advisorrules.lua; pure functions.
30. Risks/unknowns — documented above.
31. Phases — 032A/032B/032C/032D, no public version fixed.

## 032B1 fix pass

M032B audit fixes applied locally:

- dedupe/canonicalize/sort before the 64-finding cap;
- positive V031_MODULES inclusion manifest, independent ZIP/CT isolation guard and sabotage test;
- evidence-value-sensitive finding IDs using canonical evidence refs;
- strict candidate-ID grammar (length 1..1024, no controls or |);
- UNC/device-path privacy detection before referential resolution;
- Lua/schema allowed-property and type parity for input, evidence refs, truncation and rule metadata;
- directly testable field-bounding helper;
- reserved truncation-signal slots;
- frozen per-finding rule metadata used by explain();
- rules as an ordered array with duplicate detection and mandatory assumption contract;
- next-step enum consistency validation;
- source normalization to UNKNOWN_SOURCE;
- historical release count corrected to 541; current release-candidate regression 548.

The published v0.3.1 artifacts remain byte-identical.

## 032D1 native snapshot-pair fix

`LIVE-032D-01` was investigated in the native `Explain Comparison...` flow. The
old UI pattern opened two dialogs, then read `first.FileName` and
`second.FileName` after both selections. If CE returns a reused mutable dialog,
both reads can observe the second selection.

The pair layer now:

```text
select A
capture pathA immediately
read and validate snapshot A
select B
capture pathB immediately
read and validate snapshot B
compare(snapshot A, snapshot B)
```

`Compare Snapshots...` and `Explain Comparison...` share the same helper. Cancel
and read failure return before comparison and cannot reuse a previous snapshot.

Live file audit: the supplied `Snapshot_3.json` and `Snapshot_5.json` are
different files but both contain snapshot_id `snap-ce98110b...`; files 2–5 share
that identity. Therefore `5→3` and `3→5` producing the same input/report ID is
correct for those files, not evidence of menu reuse. A live `1→5` / `5→1` test
produced directional IDs and distinct report IDs.

Synthetic regression uses one shared mutable dialog whose `FileName` changes
between executes. The matrix A→B, B→A, A→A, B→B, cancel A, A+cancel B, corrupt A
and corrupt B is covered; the old post-second-read pattern fails this test.

Native Windows dialog selection and rapid GUI viewer lifecycle stress were
subsequently closed by live human validation: forward/reverse native snapshot
selection, repeat determinism, self-comparison and approximately 15 viewer
open/close cycles.

## 032C development integration

Release-candidate line is `Core.version = 0.3.2`. The v0.3.2 manifest adds
`advisor.lua`, `advisorrules.lua` and `advisorui.lua`; `V031_MODULES` remains
frozen and excludes them.

Menu:

```text
CESuite
  Evidence Snapshots
    Capture Snapshot...
    Open Snapshot...
    Compare Snapshots...
    Explain Comparison...
```

`Explain Comparison...` opens two validated snapshots, calls
`Snapshot.compare`, then `Advisor.analyze`, validates the report with
`Advisor.validate(report,diff)`, and only then renders `AdvisorUI` into the
existing read-only memo. Invalid snapshots/reports show a controlled error and
no partial viewer.

AdvisorUI sections: Overview, Findings, Observed Evidence, Evidence References,
Interpretation, Possible causes, Suggested Next Steps, Do Not Assume,
Limitations, and Rule trace. Partial, not-comparable and truncated reports have
visible banners. No edit controls, export, relocation button or auto-repair.

Live CE validation on `0.3.2`: menu 19 top-level/4 snapshot commands;
same/live snapshot produced `VALIDATION_COVERAGE_UNAVAILABLE` (validation was
unavailable, so no meaningful-change claim); a controlled pattern fixture
produced `PATTERN_CHANGED` + validation-unavailable; invalid snapshot/diff failed
closed; viewer contained all sections; remove/reinstall restored the submenu;
records and debugging remained unchanged.

Fixture-only coverage: partial comparison, not-comparable, truncation banners,
malicious evidence text and field-level bounds.

Known unknowns: Address Evidence remains out of scope; no Advisor persistence or
export; no live validation-lost reproduction. Native Windows dialog selection and
GUI viewer rapid lifecycle stress are closed by live human validation.

## 032B implementation status

The deterministic engine is integrated into the v0.3.2 candidate; released Core v0.3.1 does not load it.
It adds explicit finding truncation, structural + referential validation, canonical
deduplication/identity, rule metadata (26 rules), formal precedence/suppression,
uppercase next-step IDs and a shared do-not-assume library.

Limits:

`	ext
MAX_FINDINGS        64  (truncated + ADVISOR_FINDINGS_CAPPED_AT_64)
MAX_EVIDENCE_REFS   16
MAX_OBSERVATIONS    16
MAX_CAUSES           8
MAX_STEPS            8
MAX_DO_NOT_ASSUME   16
MAX_CANDIDATES    2000
`

Limit-aware confidence: global truncation downgrades exact to strong and
strong to weak, adds ADVISOR_CONFIDENCE_DEGRADED_BY_TRUNCATION, and never
upgrades confidence. The finding cap also emits ADVISOR_FINDINGS_CAPPED_AT_64.

Validation modes:

`	ext
Advisor.validate(report)        structural only
Advisor.validate(report,input)  structural + referential
`

Referential validation resolves source/entity/id/field/value against the
original diff/snapshot/analysis and reports structured errors for missing entity,
missing candidate, unknown field, wrong value, wrong source, duplicate ref and
malformed id. It never claims referential validation when input is absent.

No UI, filesystem, process API, memory access, network, LLM or automatic repair is
present. Address Evidence remains an explicit future integration; 032B does not
emit address-specific findings.

## Scope

Inputs only:

```text
snapshot diff (primary)
single snapshot
structured analysis report (minimal v1)
```

Evidence may include coverage, dynamic analysis, candidates, provenance,
dependencies, unresolved items, limitations, module/target evidence and Address
Evidence where present. The Advisor never reads memory, scans a process, runs
scripts, writes files, uses network or touches Cheat Engine.

No LLM, embedding, remote API, learning, weight tuning or automatic repair is
part of v1.

## Output model

```json
{
  "advisor_version": 1,
  "schema_id": "cesuite.evidence_advisor",
  "advisor_report_id": "adv-<32 hex>",
  "ruleset_version": 1,
  "suite_version": "0.3.1",
  "generated_at": "2026-10-26T00:00:00Z",
  "input": {
    "type": "snapshot_diff",
    "input_id": "snap-a:snap-b",
    "snapshot_a": "snap-a",
    "snapshot_b": "snap-b",
    "comparability": "comparable"
  },
  "findings": [],
  "limitations": [],
  "summary": {
    "finding_count": 0,
    "by_severity": {"INFO": 0, "LOW": 0, "MEDIUM": 0, "HIGH": 0, "CRITICAL": 0},
    "by_category": [],
    "headline": "..."
  }
}
```

Findings are sorted deterministically: severity descending, code, evidence key.
All arrays are bounded. `unknown`/`null` are explicit; unknown is never converted
to false, zero or “no issue”.

## Finding model

```text
finding_id          advf-<hash>
rule_id             e.g. VALIDATION_LOST
code                stable public finding code
category            neutral taxonomy
severity            INFO | LOW | MEDIUM | HIGH | CRITICAL
status              observed | unknown | not_comparable | insufficient_evidence
confidence          exact | strong | weak | unknown
evidence_refs[]     structured references; required
observations[]      direct evidence statements
interpretation      limited explanation
likely_causes[]     hypotheses, never root-cause proof
suggested_next_steps[]  review-only actions
do_not_assume[]     mandatory where repair could be inferred
limitations[]       uncertainty specific to the finding
```

A finding with no `evidence_refs` fails validation unless it is explicitly
general guidance (v1 does not generate such findings).

## Evidence refs

```json
{
  "source": "snapshot_a",
  "entity": "candidate",
  "id": "candidate key",
  "field": "validation.state",
  "value": "unique"
}
```

Valid sources: `diff`, `snapshot_a`, `snapshot_b`, `analysis`, `address`.
Entities: `comparability`, `candidate`, `coverage`, `target`, `module`,
`dependency`, `unresolved`, `operation`, `address`.

Stable candidate keys are used; UI ordering and array index are not evidence
identity. Ref values are values already present in structured evidence.

## Observation vs interpretation

```text
Observation:
A.validation.state = unique
B.validation.state = no_match

Interpretation:
The previously validated pattern may no longer identify the same location.
```

Each is stored separately. Interpretations never appear in `observations`.

## Severity semantics

```text
INFO     context or no meaningful change
LOW      evidence worth review, limited impact
MEDIUM   review should be prioritized; context may be incomplete
HIGH     strong evidence that this item warrants priority review
CRITICAL reserved for direct, severe evidence; v1 has no automatic CRITICAL rules
```

Severity is an operational review priority. It is not proof that a cheat,
script or table is broken, compatible, repaired or functional.

## Confidence semantics

Discrete and deterministic:

```text
exact    direct field comparison or complete structured evidence
strong   structured evidence with minor context gaps
weak     aggregate/partial evidence or truncated universe
unknown  evidence is missing or comparison is not possible
```

No percentages. No statistical claim without a calibrated model.

## Categories

Initial neutral categories:

```text
source_change, pattern_change, validation_change, coverage_gap,
dependency_change, provider_change, target_change, build_change,
unresolved_dependency, candidate_ambiguity, candidate_missing,
candidate_added, runtime_validation_unavailable, module_change,
address_evidence_change, operation_limit, privacy_redaction,
no_meaningful_change, comparability_gap
```

The list is extensible by ruleset version; unknown categories are rejected by
schema v1.

## Rule format

```lua
{
  id = 'VALIDATION_LOST',
  code = 'PATTERN_NO_LONGER_MATCHES_OBSERVED_TARGET',
  category = 'validation_change',
  severity = 'HIGH',
  confidence = 'exact',
  required_evidence = {'candidate.validation.state', 'comparability.status'},
  applies = function(ctx) ... end,
  build = function(ctx) ... end
}
```

`context` contains a normalized view of the diff/snapshot, never raw source or
human text. Every finding carries `rule_id`, matched conditions, evidence refs
and the same deterministic explanation path.

### Ruleset versioning

```text
advisor_version = 1
ruleset_version = 1
```

Changing rules can change findings for the same snapshot; the ruleset version
must change. Snapshots remain unchanged.

## Precedence, deduplication, suppression

Rules are evaluated in stable order:

1. comparability / unknown gate;
2. source / target / build context;
3. limits and coverage gaps;
4. candidate changes;
5. validation changes;
6. dependency / unresolved changes;
7. module / address evidence;
8. no-meaningful-change summary.

Dedupe key: `(code, evidence_entity_id, changed_field)`. A duplicate keeps the
highest severity and merges evidence refs, capped. `NOT_COMPARABLE` suppresses
candidate-level causal findings; observations about source/target remain.
`VALIDATION_UNAVAILABLE` never yields “candidate invalid”. `TARGET_BUILD_UNKNOWN`
never yields “build changed”. Limits cap dependent findings at `weak` confidence
and add a limitation.

## Comparability-aware rules

- `comparable`: candidate-level rules may run.
- `partial_comparison`: only strong candidate identities; weak identities are
  `not_comparable`.
- `different_source`: no full semantic equivalence claim; candidate matches are
  strong-identity only.
- `different_target`: validation and causal claims are contextual only.
- `different_target_build`: review priority may rise; never automatic
  incompatibility.
- `target_build_unknown`: no build-change claim.
- `unknown` / `not_comparable`: no candidate-level causal findings.

## Coverage-aware rules

Collection, discovery and validation remain separate. `validation unavailable`
means “validation could not be established”, never “candidate invalid”. A
reduced/unknown universe may produce a coverage-gap finding, but no percentage
or completeness claim. Limits/truncation are explicit findings.

## Target and build rules

```text
same_target_build      context
different_target_build review priority; no compatibility verdict
target_build_unknown   incomplete build context
different_target       validation context is not directly comparable
```

Never use ASLR base or PID as persistent target identity.

## Pattern rules

Initial cases:

```text
unchanged pattern + unchanged validation → no pattern finding
pattern changed + validation unavailable → pattern-change, weak/strong evidence
pattern changed + validation unique      → pattern-change + review context
pattern changed + validation no_match    → pattern-change + validation-lost
pattern removed                          → candidate_missing
new pattern added                        → candidate_added
```

All use neutral language and do not claim semantic equivalence.

## Provider / consumer / provenance rules

Provider, consumer, helper and provenance-field changes produce change findings
with observations, bounded causes and review steps. They never claim repair.

## Unresolved dependencies

Added/removed/same unresolved entries are evidence. Recommendations are limited
to inspecting helper definitions, loader/include paths and capturing additional
source. No inference that source is invalid.

## Module and address rules

Module inventory changes may produce a module-change finding. Main-module
metadata changes are contextual; ASLR bases are ignored. Address Evidence uses
module, RVA, status and read result only. A correct read is not semantic proof.

## Operation limits

Candidate/dependency/unresolved/snapshot-size limits or partial discovery produce
`operation_limit` findings, cap dependent confidence, and add limitations. The
Advisor never fills truncated data.

## Unknown and fail-closed

Unsupported/missing/corrupt input, unknown advisor/ruleset versions, invalid
evidence refs, oversized arrays or schema violations produce:

```text
advisor_unavailable
```

No partial findings are silently emitted. If a rule cannot get required
evidence, it is skipped and the report limitation records the gap.

### Input classification contract

A non-table root is invalid_input. A table with unsupported shape/type is
unsupported_input.
uleset_version=2 is unsupported_ruleset and cannot
produce a report until a real v2 ruleset exists.

## Advisor identity

```text
advisor_report_id = "adv-" + first 32 hex of
  sha256(canonical(input_type + input_id + advisor_version + ruleset_version))
```

Excludes timestamp, PID and UI order. Same input + same ruleset → same ID.

## Security / privacy

Data only. Never `load`, `loadstring`, `dofile`, `autoAssemble`, shell, network,
CE API or filesystem. The Advisor does not reintroduce paths, usernames,
credentials, raw source, memory bytes or absolute addresses. Input sanitization
is preserved; output messages are static plus structured values already safe.

## Performance bounds

```text
max findings        64
max evidence refs   16 per finding
max observations    16
max likely causes    8
max next steps       8
max do-not-assume   16
max input candidates 2000 (already capped by snapshots)
```

Evaluation is O(rules × bounded changed items), no combinatorial expansion.

## API

```lua
Advisor.analyze(input, options)  -- pure; report or nil,error
Advisor.validate(report)         -- ok, errors
Advisor.summary(report)          -- compact human string/table
Advisor.explain(report, id)      -- finding + rule/evidence trace
AdvisorRules.evaluate(context)   -- deterministic finding list
```

UI and filesystem stay outside these modules.

## Initial rule corpus

At least: no meaningful change; pattern changed; pattern disappeared; new
candidate; unique→no_match; unique→ambiguous; validation unavailable; source
changed; different target build; target unknown; provider changed; consumer
changed; unresolved added/removed; coverage reduced/improved; module inventory
changed; limit reached; weak identity; not comparable.

## Future interfaces

Relocation: a finding may emit
`suggested_next_step.action = REQUEST_RELOCATION_CANDIDATES`; 032A emits no
candidates and performs no relocation.

Repair Plan: future findings may feed a plan with `finding_id`, `evidence_refs`,
`recommended_action_type` and `requires_user_approval=true`. No mutation in 032A.

## UI concept

Future:

```text
CESuite
  Evidence Snapshots
    Capture Snapshot...
    Open Snapshot...
    Compare Snapshots...
    Explain Comparison...
```

"Explain Comparison..." renders the Advisor JSON; it is not implemented in 032A.
No menu explosion: one additional action in the existing submenu.

## Modules

```text
ce/modules/advisor.lua       identity, validation, summary, explain
ce/modules/advisorrules.lua  deterministic rules
```

Pure Lua; no CE UI, filesystem, network or execution.

## Tests

Unit rules, determinism/ID, schema, dedupe/precedence, unknown/not-comparable,
coverage limits, privacy, malformed inputs, ruleset versioning, adversarial
ordering/contradictions. Corpus fixtures should be structured snapshots/diffs,
not prose.

## Phases

```text
032A architecture, schema draft, pure rule prototype, test matrix
032B deterministic rules engine and corpus
032C Advisor UI + snapshot Compare integration
032D live validation / freeze (future version, not fixed here)
```

## Risks / known unknowns

- Candidate identity remains heuristic across source changes.
- Target build hashes may be unavailable.
- Coverage may be incomplete; validation may be unavailable.
- Rules can over-generalize if severity semantics are ignored.
- No calibrated confidence percentages; discrete only.
- Evidence Advisor is not a repair system.
- Schema/ruleset evolution requires explicit versioning.
- Address Evidence remains an explicit future integration; 032B does not emit
  address-specific findings, so no semantic claim is made.
- Native Windows dialog selection: CLOSED BY LIVE HUMAN VALIDATION.
- GUI viewer rapid lifecycle stress: CLOSED BY LIVE HUMAN VALIDATION.
- Published v0.3.1 actual count is 541 (61 ce + 38 analyzer + 40 parser parity
  + 10 static parity + 392 Lua). This is the historical accounting baseline;
  release artifacts are byte-identical. 032B adds one explicit isolation guard, so the
  current release suite is 548 checks.
