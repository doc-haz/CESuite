# Export Module Dump (0.1.9)

This explicit menu action exports a loaded PE module from the process attached to
Cheat Engine. It is useful when the on-disk executable cannot be read, including
some Xbox/WinGDK installations. It works with enumerated modules generally; it
does not assume that every WinGDK executable has the same file restrictions.

1. Restart CE after updating CESuite (an older singleton is deliberately retained
   until restart). Attach to the intended process; leave trainer hooks disabled.
2. Choose **CESuite → Export Module Dump**. Enter the exact module filename. The
   first enumerated module is offered initially; verify it is the intended one.
3. Choose a new writable destination, for example `game.module.bin` in Documents.
   If `.bin`, `.bin.partial` or `.bin.json` already exist, confirm replacement or cancel. Confirmed previous outputs are retained as `.previous` (numbered when necessary); the new JSON records their paths.
4. Wait for the result in the progress window. Cancel stops between blocks and keeps
   a partial file. UI events are processed between blocks; an individual OS read
   can still delay responsiveness. The process is not suspended and memory can change.
5. Share the resulting `.bin` **and** `.bin.json`. Compressing the binary is often
   useful. A `.partial` result is incomplete and must not be treated as a full dump.

The action reads the module base from `enumModules`, checks its MZ/PE headers and
reads SizeOfImage. Numeric reads avoid evaluating table symbols or user address
expressions. It streams memory in 64 KiB blocks with bounded string conversion,
checks the PID for every block, and checks module base and header size again
before finalizing. No target writes, injections, process opening, table execution
or disassembler calls are performed. Passive analysis/report export never calls
this feature.

On success the file has mapped-image layout: file offset equals RVA from the
recorded base. It is **not** a rebuilt on-disk PE. It can include relocations,
runtime modifications and already-installed hooks. It is not an atomic snapshot
and does not establish gameplay compatibility, build identity or complete
accessibility of other process memory. No binary hash is claimed by the exporter.

On an unreadable block, exception, PID/base change, output error or finalization
failure, export stops. Written data stays at `.partial`; it is never padded with
invented zeros. The sidecar records status, PID, module, path, base, expected size,
completed bytes, times and the failed block if applicable. Bytes after a failed
block are not attempted. A same-PID process replacement or unload/reload at the
same base cannot be excluded by these checks. If metadata cannot be written, the
UI reports that failure explicitly; retain any binary as unverified.

Validation for this change uses synthetic CE API mocks, real local file I/O and
both generated distributions. A prior real 440 MiB export attempt exposed an
unresponsive UI and motivated 0.1.8; this historical observation alone does not
prove completion or validate the current tree. Live validation of cancellation,
overwrite decline/confirmation, backup retention and current completion remains pending.

Version 0.1.8 fixes the unresponsive window observed during a real 440 MiB export.
It pumps UI events between bounded blocks under the CESuite busy guard, displays
percentage/MiB and provides Cancel. CE timers can still run while events are
processed, so leave trainer hooks disabled and avoid other operations during export.
The per-byte Lua validation loop was removed; string.char validates byte ranges.

Version 0.1.9 adds explicit overwrite confirmation covering the binary and sidecars.
Declining preserves all files; confirming moves previous outputs to unused .previous
paths before starting. If a subsequent dump fails or is cancelled, the old outputs
remain available in those backups. No automatic backup cleanup is performed.


## Persisted sidecar contract

[schemas/module-dump.schema.json](../schemas/module-dump.schema.json) defines
`module-dump-1`, including optional `previous_files` entries `{original, backup}`.
Persisted statuses are complete/partial; cancellation during reads is partial
with `cancelled:true` and an error. Declining overwrite returns an in-memory
cancelled result and deliberately writes no new sidecar. Preflight failures may
raise before any sidecar exists. `binary_fingerprint` remains null and
`atomic_snapshot` remains false. Byte-count/size relationships and backup identity
are additionally checked by the Python contract over actual Lua serialization.

The DG reported successful BIN + reports + PREMIUM-generated table use on the
first attempt. This is user-reported practical evidence for that workflow,
without an exact current package hash or a recorded overwrite/cancel UI matrix.
The [current live checklist](validation/live-0.1.9.md) remains pending.
