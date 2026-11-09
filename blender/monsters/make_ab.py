"""Tile look-review before/after pairs into one sheet (monster-assets).

    python3 blender/monsters/make_ab.py captures/look_monster-assets_hive_ab.jpg \
        "before.jpg,after.jpg,hive 25 m" "before2.jpg,after2.jpg,hive 70 m"

Each argument is one row: BEFORE on the left, AFTER on the right, with the camera label burned in.
Paths are relative to `captures/`. Plain python3 — no Blender needed. The two halves must come from
the same camera and the same world build, or the pair proves nothing.
"""
import argparse
import os

from PIL import Image, ImageDraw

ROOT = os.path.expanduser("~/m/mecha-city/captures")
CELL = 640
BANNER = 22
BG = (12, 12, 16)


def half(path: str, label: str, tag: str) -> Image.Image:
    """One side of a row: the capture, letterboxed into a cell, with `label tag` on top."""
    image = Image.open(os.path.join(ROOT, path)).convert("RGB")
    image.thumbnail((CELL, CELL))
    canvas = Image.new("RGB", (CELL, image.height + BANNER), BG)
    canvas.paste(image, ((CELL - image.width) // 2, BANNER))
    ImageDraw.Draw(canvas).text((6, 5), "%s  %s" % (label, tag), fill=(230, 230, 235))
    return canvas


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("out")
    parser.add_argument("rows", nargs="+", help="before.jpg,after.jpg,label")
    args = parser.parse_args()
    rows = []
    for entry in args.rows:
        before, after, label = entry.split(",")
        sides = [half(before, label, "BEFORE"), half(after, label, "AFTER")]
        row = Image.new("RGB", (CELL * 2, max(s.height for s in sides)), BG)
        for i, side in enumerate(sides):
            row.paste(side, (i * CELL, 0))
        rows.append(row)
    sheet = Image.new("RGB", (CELL * 2, sum(r.height for r in rows)), BG)
    y = 0
    for row in rows:
        sheet.paste(row, (0, y))
        y += row.height
    sheet.save(args.out, quality=82)
    print("wrote %s %s" % (args.out, sheet.size))


main()
