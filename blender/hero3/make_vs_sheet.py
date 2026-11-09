"""Build the rest-pose A/B sheet the lead judges the asset look from (hero-v3, lead review r1).

    python3 blender/hero3/make_vs_sheet.py

Top row: the raw Tripo source `art/tripo/hero3_a1/model.glb`, same four cameras, scaled to 16 m.
Bottom row: the rigged build `game/player/model/hero3/hero3.glb`.
Apart from thin cut lines at the joints the two must look the same. Writes captures/hero3_vs_a1.jpg.
"""
import os

from PIL import Image, ImageDraw

ROOT = os.path.expanduser("~/m/mecha-city")
SHOTS = ["front34", "side", "rear34", "close_front34"]
ROWS = [("hero3_a1cmp", "SOURCE  art/tripo/hero3_a1/model.glb"),
        ("hero3_rest", "BUILD   game/player/model/hero3/hero3.glb")]
TILE_W = 470
PAD = 6
HEADER = 30
OUT = os.path.join(ROOT, "captures", "hero3_vs_a1.jpg")


def main() -> None:
    tiles = []
    for prefix, _ in ROWS:
        row = []
        for shot in SHOTS:
            path = os.path.join(ROOT, "captures", "blender", "%s_studio_%s.jpg" % (prefix, shot))
            if not os.path.exists(path):
                raise SystemExit("missing %s -- render it first" % path)
            img = Image.open(path).convert("RGB")
            img = img.resize((TILE_W, int(img.height * TILE_W / img.width)), Image.LANCZOS)
            row.append(img)
        tiles.append(row)
    height = tiles[0][0].height
    width = len(SHOTS) * TILE_W + (len(SHOTS) + 1) * PAD
    total = HEADER + len(ROWS) * (height + HEADER + PAD) + PAD
    sheet = Image.new("RGB", (width, total), (18, 18, 20))
    draw = ImageDraw.Draw(sheet)
    for r, (_, label) in enumerate(ROWS):
        top = PAD + r * (height + HEADER + PAD)
        draw.text((PAD + 4, top + 8), label, fill=(235, 235, 240))
        for c, tile in enumerate(tiles[r]):
            left = PAD + c * (TILE_W + PAD)
            sheet.paste(tile, (left, top + HEADER))
            draw.text((left + 6, top + HEADER - 14), SHOTS[c], fill=(150, 150, 160))
    sheet.save(OUT, quality=88)
    print("WROTE %s (%dx%d, %d views x %d rows)"
          % (OUT, sheet.width, sheet.height, len(SHOTS), len(ROWS)))


main()
