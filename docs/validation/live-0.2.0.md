# CESuite 0.2.0 Live Validation Evidence

**Date:** 2026-10-24
**Cheat Engine Version:** 7.72 64-bit
**Candidate Version:** `0.2.0`
**Distribution:** Autorun package (`C:\Program Files\Cheat Engine\autorun\cesuite\`)
**Execution Environment:** Windows 11 (x86_64)

## Summary of Results

All required verification gates for CESuite 0.2.0 live behavior were executed directly inside Cheat Engine 7.72.

| Check | Expected | Observed Result | Status |
|---|---|---|---|
| **Cold start** | Clean startup without error | Single top-level `CESuite` menu registered | PASS |
| **Menu count** | Exactly 1 CESuite menu | 1 menu with 11 commands; no duplicate entries | PASS |
| **About CESuite** | Version and status | `CESuite 0.2.0 \| ready \| autorun` | PASS |
| **Detached Static Lua Analysis** | Report generated with `attached: false` | `title: "CESuite Static Lua AOB Analysis"`, `suite_version: "0.2.0"`, `core_version: "0.1.9"`, `attached: false` | PASS |
| **Limited attached smoke test** | Connect to CE self process | PID attached (3076), `attached: true`, `suite_version: "0.2.0"` | PASS |
| **Synthetic fixture analysis** | Passive lexical analysis on loaded table | Candidate count: 1 (injected synthetic record), 1 unique pattern, no code execution | PASS |
| **Report Viewer** | Form display, scrollable memo, safe exit | Viewer opened (`Caption: "CESuite observation report"`), memo rendered (1,319 bytes), closed with `caHide` without AV | PASS |
| **Export Static Lua Report** | Enriched JSON export | Saved `live_enriched_output.json`, validated against `schemas/runtime-report.schema.json` | PASS |
| **Busy guard & Recovery** | State guard active during run, clean exit | `Core.state.busy == false` immediately after operation; repeatable without lockup | PASS |
| **Coexistence** | Prior features undamaged | `Analyze Loaded Table` (1 record, 2 scripts) and `Dependency Summary` (1 group) fully functional | PASS |

## Scope Note on Attached Process Testing

The attached validation conducted in this session is a **limited attached smoke test** performed against the Cheat Engine host process itself. It verifies that:
- process attachment state is properly reflected in `target.attached` and `target.pid`;
- static Lua parsing and reporting operate normally while attached;
- no inspected script or code block is executed during passive collection.

It does **not** assert universal hook compatibility, process memory accessibility across varied game anti-cheats, or runtime behavior on foreign target architectures.

## Release Artifact & Installed Candidate Details

- **Final reproducible release artifact corresponding to the validated source state:**
  - File: `CESuite_Autorun_v0.2.0.zip`
  - SHA-256: `97B64F1DEBBE72F867DE9A5AB2EAEFC9E02C029BAD12A11B6A65EC14CD27655A`
  - Size: 103,053 bytes
- **Package directly installed and tested:**
  - Files directly deployed into `C:\Program Files\Cheat Engine\autorun\` (`CESuite_Autorun.lua`, `LICENSE`, and `cesuite/*.lua`) matching the validated source state from which the reproducible release archive is generated.
