# Architecture

CESuite separates offline evidence collection from future runtime validation and authoring. No runtime component is implemented in 0.1.

1. A bounded reader accepts CT XML and rejects DTD/entity declarations.
2. The inventory preserves MemoryRecord parent/child relationships, IDs, addresses, offsets and script text. Report-local keys avoid collisions when CT IDs repeat or are missing.
3. A conservative lexical pass inventories common AA commands, section and line provenance, and embedded Lua. It preserves AOB scope and raw arguments without interpreting addresses or numeric literals.
4. Dependency candidates link address/script tokens to observed definitions. They are hints, not resolved symbols or an activation graph.
5. JSON and Markdown serializers expose the same evidence. Markdown stores arbitrary source text inside dynamically sized code fences.

`schemas/ct-report.schema.json` is the versioned output contract. `schemas/injection.schema.json` is a draft authoring/validation plan contract, not executable code or a compatibility certificate. Future disassembly, current-build scan validation, runtime ownership and UI integrations must preserve evidence provenance and explicit unknown states.

Trust boundary: table content is untrusted data. Never evaluate Lua, assemble AA, follow source directives, load embedded binaries, fetch includes or attach to the target during offline analysis. Treat reports as potentially sensitive because scripts can contain local paths or application details. The analyzer itself uses no network.
