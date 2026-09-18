# CT Analyzer 0.1 usage

Requires Python 3.10 or newer; no runtime packages or Cheat Engine installation are required. Optional schema tests require `python -m pip install -r analyzer/requirements-dev.txt`; otherwise those tests are skipped. From the repository root, set `PYTHONPATH=analyzer/src`, then run:

```
python -m ct_analyzer path/to/table.CT --output reports/table
python -m unittest discover -s analyzer/tests -v
```

The output directory is created when necessary. Existing `report.json` and `report.md` are replaced. Exit code 0 means the report was generated, including any review warnings; 2 means invalid input or an I/O failure. Outputs are not a transactional pair if an I/O failure interrupts writing.

Input limit: 16 MiB. DTD/entity declarations are rejected, including UTF-16 declarations. The root must be an unnamespaced `CheatTable`; malformed XML and record nesting beyond 128 levels fail clearly. Compressed/encrypted tables and embedded binary payloads are not analyzed. Unknown XML fields are ignored.

AA commands are recognized at the start of a logical line, case-insensitively, with quoted comma arguments preserved. AA comments and embedded Lua are excluded from AA observations. Embedded Lua between `{$lua}` and `{$asm}` is also extracted separately. Source scripts remain available in full for manual review.

This is a lexical inventory, not a complete AA/Lua parser. Includes, generated code, unusual syntax, macros and dynamic addresses can hide operations. Lua warning triggers and dependency matching may match comments/strings. Multiple providers are preserved rather than guessed. The schema describes report structure, not the validity of a CT.

Currently emitted rule IDs: `AA-SYNTAX`, `AOB-UNIQUENESS`, `RESOURCE-OWNERSHIP`, `EMPTY-DISABLE`, `HOOK-REVIEW`, `TIMER-LIFECYCLE`, `BREAKPOINT-OWNERSHIP`, `HANDLER-CHAIN`, `EVENT-LIFECYCLE`. All are review advisories. The broader rule catalog explicitly identifies manual checks.
