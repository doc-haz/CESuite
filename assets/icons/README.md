# CESuite menu icons (source material, not shipped)

Source: `source/CESuite_Icons_sheet.png` (4x4 grid, transparent background).
Generated: `python tools/make_icons.py` (build-time only; Pillow is not needed to
build or run CESuite). Output: `24/<name>.png`, 24x24 RGBA.

## Current status

v0.2.2 uses Cheat Engine's own native menu icons through a version-guarded
`ImageIndex` mapping (`CE 7.72`), because runtime diagnosis showed that CE paints
menu icons from `MainForm.Menu.Images` and ignores per-item image lists. These
CESuite PNGs are therefore not shipped in the ZIP.

They are kept as source material for a future release if Cheat Engine exposes a
supported per-item image API. Do not distribute them as CE icons or copy images
out of Cheat Engine; the native mapping only references indices the local CE
installation already loaded.
