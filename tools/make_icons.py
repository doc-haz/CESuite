"""Generate CESuite menu icons from the provided sprite sheet.

Build-time tool only: CESuite does not need Pillow at runtime, and building the
ZIP does not require running this script (the generated PNGs are committed).

The sheet is a 4x4 grid, transparent background, drawn in the CESuite palette
(dark navy strokes + blue accents). Each cell is cropped to its alpha bounding
box, padded to a square and downscaled with LANCZOS so the icon stays sharp at
the target size.

Usage:
    python tools/make_icons.py [--size 24] [--source PATH] [--out DIR]

Regenerate after changing the sheet or the target size. Keep the generated files
in assets/icons/<size>/ and do not edit them by hand.
"""
from pathlib import Path
import argparse

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / 'assets/icons/source/CESuite_Icons_sheet.png'
DEFAULT_OUT = ROOT / 'assets/icons'

# 4x4 grid order, matching the labelled reference sheet.
ICONS = [
    ('analyze-process', 0, 0),
    ('analyze-table', 1, 0),
    ('validate-aobs', 2, 0),
    ('inspect-script', 3, 0),
    ('address-evidence', 0, 1),
    ('dependency-summary', 1, 1),
    ('diagnostics-summary', 2, 1),
    ('export-analysis', 3, 1),
    ('export-reports', 0, 2),
    ('export-module-dump', 1, 2),
    ('static-lua', 2, 2),
    ('export-static-lua', 3, 2),
    ('remove-menu', 0, 3),
    ('about', 1, 3),
]


def build(size: int, source: Path, out_root: Path) -> None:
    sheet = Image.open(source).convert('RGBA')
    width, height = sheet.size
    cell_w, cell_h = width / 4.0, height / 4.0
    padding = max(1, round(size / 12))
    inner = size - 2 * padding
    target = out_root / str(size)
    target.mkdir(parents=True, exist_ok=True)
    for name, column, row in ICONS:
        box = (round(column * cell_w), round(row * cell_h),
               round((column + 1) * cell_w), round((row + 1) * cell_h))
        cell = sheet.crop(box)
        bounds = cell.getchannel('A').getbbox()
        if bounds:
            cell = cell.crop(bounds)
        scale = min(inner / cell.width, inner / cell.height)
        new_w = max(1, round(cell.width * scale))
        new_h = max(1, round(cell.height * scale))
        cell = cell.resize((new_w, new_h), Image.LANCZOS)
        canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        canvas.paste(cell, ((size - new_w) // 2, (size - new_h) // 2), cell)
        canvas.save(target / f'{name}.png', optimize=True)
    print(f'wrote {len(ICONS)} icons at {size}x{size} to {target}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--size', type=int, default=24)
    parser.add_argument('--source', type=Path, default=DEFAULT_SOURCE)
    parser.add_argument('--out', type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    build(args.size, args.source, args.out)
