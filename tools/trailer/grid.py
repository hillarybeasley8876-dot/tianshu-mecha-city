#!/usr/bin/env python3
"""Tile arbitrary stills into one labelled comparison sheet (A/B rows).

    tools/trailer/grid.py -o captures/trailer/sheets/tod_ab.jpg --cols 3 \
        "tod 0.00=captures/trailer/tod/tod0.0_t0_6.jpg,captures/trailer/tod/tod0.0_t2_0.jpg"

Each argument is `row label=file,file,...`; every row must have the same number of files (the number
of columns). Used for the time-of-day and grade A/Bs the lead asked for.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
CELL_W = 620
PAD = 6
LABEL_W = 150
BG = (16, 16, 20)
FONT = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("rows", nargs="+", help="label=file,file,...")
    ap.add_argument("-o", "--out", type=Path, required=True)
    ap.add_argument("--cols", type=int, default=0, help="default: the files in the first row")
    args = ap.parse_args()

    rows: list[tuple[str, list[Path]]] = []
    for spec in args.rows:
        label, _, files = spec.partition("=") if "=" in spec else ("", "", spec)
        paths = [Path(f) if Path(f).is_absolute() else ROOT / f for f in files.split(",") if f]
        missing = [p for p in paths if not p.exists()]
        if missing:
            raise SystemExit(f"grid: missing {missing[0]}")
        rows.append((label, paths))
    cols = args.cols or len(rows[0][1])
    if any(len(p) != cols for _l, p in rows):
        raise SystemExit(f"grid: every row needs {cols} files")

    cell_h = int(CELL_W * 9 / 16)
    w = LABEL_W + cols * (CELL_W + PAD) + PAD
    h = PAD + len(rows) * (cell_h + PAD)
    sheet = Image.new("RGB", (w, h), BG)
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.truetype(FONT, 22)
    small = ImageFont.truetype(FONT, 16)
    for r, (label, paths) in enumerate(rows):
        y = PAD + r * (cell_h + PAD)
        if label:
            draw.text((10, y + cell_h // 2 - 12), label, font=font, fill=(255, 255, 255))
        for c, path in enumerate(paths):
            x = LABEL_W + c * (CELL_W + PAD)
            sheet.paste(Image.open(path).convert("RGB").resize((CELL_W, cell_h), Image.LANCZOS), (x, y))
            draw.text((x + 6, y + 6), path.stem, font=small, fill=(255, 240, 180))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(args.out, quality=88)
    print(f"grid: {len(rows)}x{cols} -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
