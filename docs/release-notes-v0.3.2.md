# CESuite 0.3.2 — Evidence Advisor

CESuite 0.3.2 adds a deterministic, read-only Evidence Advisor for understanding
what changed between two Evidence Snapshots.

## Highlights

- **Explain Comparison...** in the existing Evidence Snapshots submenu.
- **Read-only findings** with Overview, Findings, Observed Evidence, Evidence
  References, Interpretation, Possible causes, Suggested Next Steps, Do Not
  Assume, Limitations and Rule trace.
- **Evidence and interpretation remain separate.** Observations are never
  promoted to guesses.
- **Deterministic report identity** from the input evidence and ruleset.
- **Neutral comparison semantics**: unchanged, added, removed, changed, unknown
  and not comparable; no compatibility or repair verdict.
- **Safe native snapshot selection**: snapshot A is captured and validated before
  snapshot B is selected; cancel and read failures leave no stale comparison.
- **No automatic repair, relocation candidate generation, table mutation,
  record activation or memory write.**

## Validation

- Native Windows dialog selection: **CLOSED BY LIVE HUMAN VALIDATION**
  (forward/reverse selection, repeat determinism and self-comparison).
- GUI viewer rapid lifecycle: **CLOSED BY LIVE HUMAN VALIDATION**
  (approximately 15 open/close cycles).

## Limitations

- The Advisor describes observed evidence, not ground truth.
- Validation may be unavailable; that is reported literally.
- Partial comparisons only use strong candidate identities.
- Address Evidence remains outside the Advisor's v0.3.2 scope.
- `REQUEST_RELOCATION_CANDIDATES` is a review recommendation only.

Implementation, review, testing and documentation were AI-assisted. Final
technical decisions and validation remain under user control.
