#!/usr/bin/env python3
"""Stack finished contact sheets into ONE image, so a whole round's reels can be reviewed in one read.

    tools/trailer/stack_sheets.py -o tmp/trailer/r6/reels.jpg --width 1500 \
        captures/trailer/sheets/TIANSHU_showcase_segments.jpg \
        captures/trailer/sheets/TIANSHU_trailer_v2_shots.jpg

Each sheet is scaled to `--width` and stacked vertically with a caption strip. Used at the end of a
round: the showcase reel's 29-segment sheet and trailer v2's 23-shot sheet are two reads otherwise, and
the image budget for a session is fourteen.
"""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

FONT = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
BG = (16, 16, 20)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("sheets", nargs="+", type=Path)
    ap.add_argument("-o", "--out", type=Path, required=True)
    ap.add_argument("--width", type=int, default=1500)
    args = ap.parse_args()

    parts: list[tuple[str, Image.Image]] = []
    for p in args.sheets:
        im = Image.open(p).convert("RGB")
        h = round(im.height * args.width / im.width)
        parts.append((p.stem, im.resize((args.width, h), Image.LANCZOS)))

    cap = 26
    total = sum(im.height + cap for _n, im in parts)
    sheet = Image.new("RGB", (args.width, total), BG)
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.truetype(FONT, 17)
    y = 0
    for name, im in parts:
        draw.text((8, y + 5), name, font=font, fill=(255, 240, 180))
        y += cap
        sheet.paste(im, (0, y))
        y += im.height
    args.out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(args.out, quality=84)
    print(f"stack_sheets: {len(parts)} sheets -> {args.out} ({sheet.width}x{sheet.height})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
