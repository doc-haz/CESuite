# Address Evidence Inspector (0.2.2)

The inspector answers one question:

> What can CESuite demonstrate about this address?

It does not repair, patch, set breakpoints, trace execution or guess. It resolves
one explicit address, reads a bounded window of bytes, decodes at most one
instruction from those bytes and reports what it can prove, with the reason for
everything it cannot.

## Entry points

- In-CE command: **Address Evidence Inspector** (read-only form with
  `Inspect`, `Use Memory Viewer Selection`, `Copy JSON`, `Export JSON`).
- `CESuiteCore.inspectAddress(input, options)` returns the evidence object.
- `CESuiteCore.exportAddressEvidence(evidence, path)` writes it as JSON.

The inspector is **never** invoked by `collectReport()`. It is explicit, on demand
and independent from the runtime report and from the Simple/Extensive reports.

## Accepted input

| Form | Example | `resolution_method` |
|---|---|---|
| Hex with prefix | `0x7FF612345678` | `hex_literal` |
| Hex without prefix | `7FF612345678` | `hex_literal` |
| Module + RVA | `game.exe+1234`, `module.dll+0xABC` | `module_rva` |
| Numeric selection | Memory Viewer address | `memory_viewer_selection` |

Arbitrary Cheat Engine expressions are **not** evaluated. `getAddress` and
`getAddressSafe` are never called: their semantics exceed an evidence inspector.

`resolution_status` is one of `resolved`, `invalid_input`, `unresolved_module`,
`ambiguous_module`, `out_of_range`, `unavailable`. An ambiguous module name is never
resolved by picking the first match.

## Evidence blocks

| Block | Evidence |
|---|---|
| `query` | Raw input, kind, method, status, resolved address, failure reason |
| `target` | Attachment state (`observed`/`detached`/`unknown`), PID, architecture (`x86_64`/`i386`/`unknown`), pointer size, process name |
| `module` | Module name/base/size/path, `inside_module`, RVA, ambiguity list |
| `symbol` | Deliberately `not_collected` (symbol lookup can invoke table callbacks) |
| `region` | Base, end, size, allocation base, state, type, raw and decoded protection, R/W/X, guard, offsets, source |
| `bytes` | Requested/read length, hex window, read status, partial flag |
| `instruction` | Decode status, length, prefixes, opcode, ModRM, SIB, displacement, mnemonic, operand text, RIP-relative |
| `memory_operand` | Base/index register, scale, displacement, RIP-relative, absolute, expression text, stack reference |
| `effective_address` | Address plus status: `resolved_rip_relative`, `resolved_static`, `requires_runtime_context`, `unsupported`, `unavailable` |
| `type_advisory` | Suggested `Float`/`Double`, category, confidence, status and reason |
| `diagnostics` | Structured observations with severity and provenance |
| `limits` | Hard bounds for the operation |
| `limitations` | What this evidence does not prove |

## Status and provenance

Blocks use the CESuite vocabulary: `observed`, `candidate`, `unknown`, `unsupported`,
`invalidated`. `observed` means runtime or byte-level evidence recorded in this
inspection; `candidate` is an inference (type advisory); `unknown` keeps its reason.

Provenance values: `runtime_read`, `ce_region_api`, `enumerated_regions`,
`module_inventory`, `static_bytes`, `derived`, `memory_viewer_selection`,
`unavailable`. Observed and inferred values are never mixed in the same field
without a source.

If the opened process changes during inspection, the result becomes `invalidated`
and dependent blocks are marked `invalidated`; two process states are never mixed.

## Target validity

A non-zero `getOpenedProcessID()` is **not** proof of attachment: Cheat Engine can
keep a stale PID and a cached process name after the target exits. CESuite only
claims a live target when the module inventory is available and non-empty.

When that proof is missing:

- `target.attached = false`;
- `target.status = detached` if a cached PID was present, `unknown` if no process
  was opened;
- `target.process_name = null` (the cached name is not reused);
- `module`, `region` and `bytes` stay `unknown`; `OUTSIDE_MODULE` and
  `UNMAPPED_ADDRESS` are never emitted as `observed`;
- a hex address is still resolved syntactically (`resolution_status = resolved`)
  because parsing does not depend on the target; `module+RVA` becomes
  `unavailable`;
- diagnostics `TARGET_DETACHED` or `TARGET_UNAVAILABLE` explain the result.

A live target whose bytes cannot be read remains attached: a failed read is
`read_failed`/`unknown`, not a detachment.

## Region and protection

`getMemoryRegionInfo(address)` is preferred; `enumMemoryRegions()` is a bounded
fallback. The raw protection mask is preserved and the decoded text keeps every
modifier, for example `READWRITE | GUARD` or `NOACCESS`. `guard` is reported
separately.

`Allocation Size` is **not** emitted: it is a different concept from `RegionSize`
and no available API proves it. Offsets from the region base and allocation base are
reported instead.

## Bytes

- Maximum 64 bytes per inspection (default 32).
- A read is declared complete only when `#bytes == requested_length`.
- Reads are clamped to the known region end and marked `is_partial`.
- If a full read fails, a bounded byte-by-byte fallback salvages the readable prefix
  and reports `short_read`. A partial read never turns the inspection into a fatal
  error.
- An unreadable page (`NOACCESS`) is reported as `unreadable` and the read is skipped.

## Instruction decoder

The core decodes from **bytes**, never from `disassemble()` or
`splitDisassembledString()`. Supported input:

- legacy prefixes (`66 67 F0 F2 F3` and segment overrides) and REX in 64-bit mode;
- single-byte opcodes: `mov` (88/89/8A/8B/C6/C7), `lea` (8D), `add`, `or`, `and`,
  `sub`, `xor`, `cmp`, `test` (01/03/09/0B/21/23/29/2B/31/33/39/3B/85), `movsxd`
  (63, 64-bit only). Operand width is tracked in bits: `88`, `8A` and `C6` are
  always 8-bit and `66`/REX.W never widen them; `89`, `8B`, `01`… use 16/32/64
  according to `66` and REX.W;
- SSE: `movups`/`movupd`/`movss`/`movsd` and `movaps`/`movapd` selected by the
  `66`/`F3`/`F2` prefixes, `addss/sd`, `mulss/sd`, `subss/sd`, `divss/sd`,
  `comiss/sd`, `ucomiss/sd`;
- x87 memory forms: `fld`/`fst`/`fstp` with dword (D9) or qword (DD) operands.

8-bit registers follow the REX rule: without any REX prefix, ModRM indexes 4-7
name `ah/ch/dh/bh`; with a REX prefix (even one without bits) they name
`spl/bpl/sil/dil`; `r8b`-`r15b` require REX. Anything else is
`decode_status: "unsupported"` with a reason. A truncated or
invalid byte window is `truncated`/`invalid`, never guessed.

## Type advisory

Rules (always an advisory, never a fact):

| Instruction | Suggested | Confidence |
|---|---|---|
| `movss`, `addss`, `subss`, `mulss`, `divss`, `comiss`, `ucomiss` | `Float` | high |
| `movsd`, `addsd`, `subsd`, `mulsd`, `divsd`, `comisd`, `ucomisd` | `Double` | high |
| `fld`/`fst`/`fstp` with `dword ptr` | `Float` | medium |
| `fld`/`fst`/`fstp` with `qword ptr` | `Double` | medium |

Integer instructions, `lea`, `cmp`, `test` and register-only forms report
`not_applicable`. Unsupported opcodes report `unsupported`. The report reads
"Observed instruction: movss / Inferred advisory type: Float", never "Value type is
Float".

## Limits

| Bound | Value |
|---|---|
| Addresses per inspection | 1 |
| Bytes per inspection | 64 (default 32) |
| Region lookups | 1 (enumeration only as fallback, once) |
| Persistent timers | 0 |
| Runtime breakpoints | 0 |
| Memory writes | 0 |

## Schema

`schemas/address-evidence.schema.json` is a strict, standalone contract. It rejects
unknown fields, unknown status/provenance values and inconsistent combinations
(for example `read_ok` with a non-observed byte block, or a `candidate` type without
a suggested type). `core_version` stays `0.1.9`; the runtime report schema is
unchanged.

## Limitations

- One snapshot: the target can change immediately afterwards.
- Effective addresses that depend on registers are not computed; no register state
  is collected.
- The decoder is a whitelist; many valid instructions remain `unsupported`.
- Module membership is only claimed when a provable base/size range exists.
- Region enumeration can be incomplete; "unmapped" is evidence, not absolute proof.
- Symbol names are not collected because symbol lookup can invoke table-provided
  callbacks.
- No breakpoints, no tracing, no patching, no pointer records, no memory writes.
