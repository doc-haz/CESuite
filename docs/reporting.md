# Reporting and repair guidance (0.2.1)

CESuite turns collected evidence into two reports that answer different questions:

- **Simple Report** (`*_Simple.md`): what CESuite analyzed, what looks fine, what
  looks wrong, the evidence behind each problem, and a fixed order in which to
  review it. Written for users, table makers, support and AI tooling.
- **Extensive Report** (`*_Extensive.json`): the full runtime report, the static Lua
  evidence and the same assessment as structured JSON.

CESuite never repairs, patches, injects, rewrites signatures or changes memory.
It states what the evidence supports and what should be reviewed next.

**Evidence first. Recommendations second. No guessing.**

## Architecture

```text
Evidence Core (existing collection: environment, table, AOB, dependencies, static Lua)
      |
      +--> Diagnostic Model      ce/modules/diagnose.lua        (assessment)
                |
                +--> Simple Report     ce/modules/simplereport.lua (Markdown)
                +--> Extensive Report  runtime report + assessment (JSON)
```

One collection produces one assessment. Both reports render that same object, so a
single observation cannot produce different conclusions in the two reports. There is
no second engine and no separate analysis pass.

Menu actions:

| Action | Output |
|---|---|
| **Diagnostics Summary** | Markdown Simple Report in the read-only viewer; no files written |
| **Export Reports** | `<base>_Simple.md` and `<base>_Extensive.json` from one collection |

`Export Analysis Report` and `Export Static Lua Report` keep their previous
behaviour and file names.

## Diagnostic record

| Field | Meaning |
|---|---|
| `id` | Stable identifier derived from the evidence (for example `aob:aob-1`) |
| `rule` | Machine-readable rule name (for example `AOB-NO-MATCH`) |
| `category` | `target`, `module`, `aob`, `dependency`, `static`, `review`, `evidence` |
| `severity` | `high`, `medium`, `low` or `info` |
| `status` | `observed`, `candidate`, `unknown` or `unsupported` |
| `outcome` | `problem`, `healthy`, `advisory` or `not_assessed` |
| `label` | Short human name for the subject |
| `summary` | One conservative sentence |
| `evidence` | Structured facts; each item also carries a human `description` |
| `confidence` | `high`, `medium`, `low` or `unknown` |
| `confidence_reason` | Why the level was chosen |
| `likely_causes` | Plausible causes, explicitly not proven |
| `suggested_next_steps` | What to inspect or verify next |
| `limitations` | What the evidence does not cover |
| `do_not_assume` | Conclusions the evidence does **not** support |
| `source` | `runtime`, `lexical`, `static` or `structural` |

## Status model

| Status | Meaning |
|---|---|
| `observed` | Backed by a runtime observation recorded in this collection (`source` must be `runtime`) |
| `candidate` | Lexical or static evidence only; runtime validity is not established |
| `unknown` | The evidence was insufficient or the operation could not be completed |
| `unsupported` | The construct is outside the analysis CESuite supports |

The schema enforces three invariants:

1. a `healthy` outcome must be `observed` and come from `runtime` evidence;
2. `lexical` and `static` sources can never be `observed`;
3. `observed` status must come from `runtime` evidence.

Static Lua candidates therefore remain `candidate` even when a runtime scan for the
same normalized pattern also exists; the runtime scan is recorded as separate
corroborating evidence, not as a promotion.

## Outcome and severity

- `problem`: the evidence shows something worth investigating (missing signature,
  ambiguous signature, missing process/module, unresolved scope).
- `healthy`: a completed check passed (for example exactly one match).
- `advisory`: lexical or static finding that needs manual review.
- `not_assessed`: CESuite could not establish anything (no attachment, unsupported
  syntax, insufficient evidence).

Severity ranks within the repair path (`high` before `medium` before `low` before
`info`) but never changes what the evidence says.

## Confidence criteria

| Level | Criterion |
|---|---|
| `high` | Value read from a completed runtime scan, or a definitive structural fact (no attached process, process changed) |
| `medium` | Runtime-derived but degraded: scan error visibility unavailable, uniqueness unverified, process changed, or an explicit resolution failure |
| `low` | Lexical or static inference only |
| `unknown` | No usable evidence |

No percentages are used.

## Supported rules (0.2.1)

| Rule | Condition | Status | Outcome | Confidence |
|---|---|---|---|---|
| `PROCESS-NOT-ATTACHED` | `target.attached == false` | observed | problem | high |
| `PROCESS-CHANGED` | `PROCESS-CHANGED` was recorded, or an AOB result was invalidated | observed | problem | high |
| `MODULES-UNAVAILABLE` | `MODULES-UNAVAILABLE` diagnostic present | unknown | problem | high |
| `MODULE-AMBIGUOUS` | `MODULE-SNAPSHOT-INCOMPLETE` diagnostic present | observed | problem | high |
| `AOB-NO-MATCH` | AOB `status == observed` and `match_count == 0` | observed | problem | high, or medium when error visibility is unavailable |
| `AOB-UNIQUE` | AOB `status == observed` and `match_count == 1` | observed | healthy | high (medium if unverified) |
| `AOB-AMBIGUOUS` | AOB `status == observed` and `match_count > 1` | observed | problem | high (medium if unverified) |
| `AOB-NOT-SCANNED` | AOB `status == not_scanned` | unknown | not_assessed | unknown |
| `AOB-UNSUPPORTED` | AOB `status == unsupported` | unsupported | not_assessed | unknown |
| `AOB-SCOPE-UNRESOLVED` | AOB `status == unresolved` | unknown | problem | medium |
| `AOB-SCAN-ERROR` | AOB `status == error` | unknown | problem | medium |
| `AOB-SCAN-UNAVAILABLE` | one or more AOBs `status == unavailable` (aggregated) | unknown | problem | high |
| `AOB-INVALIDATED` | one or more AOBs `status == invalidated` (aggregated) | unknown | problem | high |
| `DEPENDENCY-UNRESOLVED-PROVIDER` | a lexical `requires` name has no `provides` occurrence in the analyzed scripts | candidate | advisory | low |
| `STATIC-CANDIDATE-ONLY` | a static Lua observation resolved to a literal pattern | candidate | advisory | low, or medium when the same normalized pattern was also observed at runtime |
| `STATIC-UNRESOLVED` | static observations without a resolvable pattern (aggregated) | unknown | not_assessed | unknown |
| `STATIC-ANALYSIS-LIMIT` | static analyzer reported a limit or tokenizer failure | unknown | not_assessed | high |
| any other report diagnostic rule | aggregated once per rule, evidence up to five occurrences | candidate | advisory | low |
| `EVIDENCE-INSUFFICIENT` | no scripts, AOB records, dependencies or static candidates | unknown | not_assessed | unknown |

Dependency diagnostics are bounded at 200 names per report, sorted, so a large table
cannot flood the assessment; the complete inventory remains in `dependencies`.
Names the static analyser classifies as AOB scan calls (`aobScan`, `aobScanModule`,
`aobScanRegion`, `customScan`, case-insensitive) are not reported as unresolved table
symbols, because the same evidence is classified as an AOB sink elsewhere.

## Suggested repair path

Each `problem` and `advisory` diagnostic produces one ordered step. Priority is
fixed and documented; it does not depend on AI judgement or hidden heuristics:

| Priority | Rules |
|---|---|
| 1 | `PROCESS-NOT-ATTACHED`, `PROCESS-CHANGED` |
| 2 | `MODULES-UNAVAILABLE`, `MODULE-AMBIGUOUS` |
| 3 | `AOB-NO-MATCH` |
| 4 | `AOB-AMBIGUOUS` |
| 5 | `AOB-SCOPE-UNRESOLVED`, `AOB-SCAN-ERROR`, `AOB-SCAN-UNAVAILABLE`, `AOB-INVALIDATED`, `AOB-UNSUPPORTED` |
| 6 | `DEPENDENCY-UNRESOLVED-PROVIDER` |
| 7 | `STATIC-CANDIDATE-ONLY`, `STATIC-UNRESOLVED`, `STATIC-ANALYSIS-LIMIT` |
| 8 | aggregated review diagnostics |
| 9 | `EVIDENCE-INSUFFICIENT` |

AOB scans that could not complete rank above dependency and static review because
they block trust in the AOB evidence itself. Within one priority, steps are sorted
by severity and then by diagnostic id, so the same evidence always produces the same
order.

## Paired export semantics

`Export Reports` is one operation that produces two files. `Core.exportReports()`
returns a status table; it does not throw for I/O errors and always releases the
busy guard.

| Status | Meaning |
|---|---|
| `complete` | Both files are in place and come from the same collection |
| `cancelled` | The overwrite confirmation was declined; nothing was written |
| `failed` | No report file was created or changed; existing reports are intact |

Exact failure semantics:

1. The simple and extensive documents are first written to reserved temporary
   names, `<target>.cesuite-partial`. Nothing at the destination is touched yet.
2. If either write fails, both temporary files are removed and the export returns
   `failed`. Both destinations keep their previous content (or remain absent).
3. Only when both temporary documents are complete are the destinations updated.
   Existing reports are moved aside to `<target>.cesuite-backup`, then the temporary
   files are renamed into place.
4. If a promotion fails, the newly promoted file is removed and every backup is
   restored, so the previous pair is never left mixed with a new file.
5. After a successful promotion the backups are deleted. If deletion fails, the
   export still reports `complete`, keeps the backups and sets `retained_backups`
   so the caller can mention them; no report content is lost.
6. If a reserved `.cesuite-partial` or `.cesuite-backup` name already exists, the
   export fails closed and never deletes it: CESuite cannot prove it created it.

Existing reports are only replaced after the user confirms the overwrite prompt.
This is not a filesystem transaction: the only interval without a destination is
the two renames after both documents are already complete on disk.

## Simple Report format

Markdown with fixed sections: what CESuite analyzed, what looks OK, problems
(with evidence, confidence, possible causes, next steps, do-not-assume and
limitations), source-only advisories, not assessed, the suggested repair path and
the status/confidence legend. User-controlled text is neutralised (backticks,
newlines, angle brackets), so a symbol name cannot inject headings. Presentation
caps are 50 problems, 12 advisories, 10 not-assessed items and 20 passing checks;
the extensive report keeps everything.

## Extensive Report format

`<base>_Extensive.json` contains the runtime report (same fields and
`core_version: "0.1.9"`), the `static_lua_analysis` block and an optional
`assessment` object. The schema addition is additive and optional: reports without
`assessment` remain valid. Diagnostic ordering, counts and the repair path in the
JSON are exactly the data the Simple Report renders.

## Compatibility

- `core_version` stays `0.1.9`: the assessment is optional and additive; no
  existing required field, type or meaning changed.
- `CESuite_Runtime_Report.json` and `CESuite_Runtime_Report_enriched.json` keep
  their names and content.
- Existing reports (including v0.1.4) still validate against the extended schema.
- Schema conditionals reject any attempt to label static or lexical evidence as a
  runtime observation.
- The Address Evidence Inspector (0.3.0) is a separate, explicitly invoked report
  with its own schema; it does not add fields to the runtime report or to the
  Simple/Extensive reports.

## Limits

- Diagnostics interpret one collection; re-run after changing the table, target or
  attached process.
- No claim about other builds, hook compatibility or memory accessibility.
- Dependency findings are lexical; the provider may exist in table Lua, a CE
  built-in or generated code that passive capture cannot see.
- Static Lua analysis never executes Lua and cannot see computed patterns.
- A missing signature does not prove a feature was removed, and an ambiguous
  signature does not identify the correct match.

## Operation metadata (0.3.0)

Runtime and static Lua reports may include an optional operation block with
status, source_complete, partial, cancelled, structured warnings and nullable
metrics. It is separate from evidence diagnostics and never affects them. See
[performance-diagnostics.md](performance-diagnostics.md) for the exact metrics,
semantics and clock limitations.
