# Analyzer rule catalog

These engineering rules were supplied from legacy review. They describe review obligations, not proof that 0.1 automatically detects every violation. `review` is the only emitted severity. Manual checks remain necessary even when no warnings appear.

| Topic | Rule | 0.1 coverage |
| --- | --- | --- |
| AOB scope | Preserve process, module or explicit region scope and all arguments; never silently broaden scans during porting. | Scope/arguments inventoried. |
| Anchor vs hook | A signature anchor may differ from the actual hook address by an offset or calculation. Track both separately. | Generic HOOK-REVIEW; no address resolution. |
| Uniqueness | Require exactly one match in the intended scope on the current executable build before patching. | AOB-UNIQUENESS marks every scan unverified. |
| Overwrite and restore | Overwrite whole instructions; restore exactly every overwritten byte, including padding and the full jump span. | Manual disassembly/byte comparison required. |
| short5/far14 | Account for a 5-byte relative jump versus a 14-byte far-jump form on x64, allocation reach and actual assembler output. Never assume every JMP occupies five bytes. | Generic HOOK-REVIEW only. |
| Relocation | Recompute branch targets and RIP-relative operands when moving stolen instructions; copying bytes alone may be invalid. | Manual; no disassembler. |
| Teardown | Restore original bytes before freeing memory that hooks can reach; ensure no in-flight execution or callback still uses the allocation. | Operations inventoried; temporal safety not proven. |
| Resource ownership | Avoid broad dealloc/unregister. Clean up only explicitly owned resources, accounting for shared persistent allocations. | RESOURCE-OWNERSHIP catches empty/wildcard cleanup arguments. |
| Timers | Disable/destroy owned timers and stop callbacks before freeing state. Timer ownership must be explicit. | Lua lexical TIMER-LIFECYCLE hint. |
| Handler chaining | Preserve prior handlers, chain according to their return-value contract and restore without clobbering a newer owner. | Lua lexical HANDLER-CHAIN hint. |
| Breakpoints | Record ownership and remove only owned breakpoints; do not clear global debugger state. | Lua lexical BREAKPOINT-OWNERSHIP hint. |
| Runtime scratch | Shared scratch storage is unsafe under concurrent or reentrant hooks; use per-thread/per-invocation state or proven synchronization. | Manual. |
| Slot counters | Reserve slots atomically; specify overflow, reuse and publication ordering. Atomic increment alone is not a complete data protocol. | Manual. |
| Buffer capacity | Derive capacity from header + count × stride, alignment and bounds; account for terminators, concurrency and integer overflow. | Manual. |
| Build evidence | Current-build uniqueness and cross-build robustness are separate claims. Test candidate signatures on each supported build. | AOB warning; runtime status remains unverified. |
| UI models | UI-bound edits may be overwritten by model refresh, persistence or event callbacks. Find the authoritative model and synchronization direction. | Generic EVENT-LIFECYCLE candidate only. |
| Event lifecycle | Bind/unbind events with explicit ownership, re-enable behavior and teardown order; avoid duplicate handlers and use-after-free. | Lua lexical EVENT-LIFECYCLE hint. |
| Numeric literals | AA unprefixed numeric literals are hexadecimal; Lua unprefixed numerics are decimal. Preserve explicit forms and context rather than converting text globally. | Arguments retained as text; no numeric evaluation. |
| Empty DISABLE | An empty `[DISABLE]` may be intentional for a persistent library. Check the persistence contract rather than treating it as an unconditional bug. | EMPTY-DISABLE advisory, never an error. |

Warnings carry script IDs and line numbers when tied to recognized commands. Whole-script hints have a null line. Embedded Lua reports have their own script IDs; origins point back to the containing AA script. Lua and dependency heuristics can produce false positives from comments and strings. Do not use this catalog or an empty warning list as authorization to run a table.
