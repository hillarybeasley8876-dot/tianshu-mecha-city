"""Contact sheet: sheet.py OUT.jpg IMG... [--h 640] — tiles images in one row per 5, labelled with file names."""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

args = sys.argv[1:]
h = 640
if "--h" in args:
    i = args.index("--h")
    h = int(args[i + 1])
    del args[i:i + 2]
out, files = args[0], args[1:]
font = ImageFont.truetype("/System/Library/Fonts/Hiragino Sans GB.ttc", 22)
tiles = []
for f in files:
    im = Image.open(f).convert("RGB")
    tiles.append((Path(f).name, im.resize((max(1, int(im.width * h / im.height)), h))))
rows = [tiles[i:i + 5] for i in range(0, len(tiles), 5)]
W = max(sum(t[1].width for t in r) + 10 * (len(r) + 1) for r in rows)
sheet = Image.new("RGB", (W, len(rows) * (h + 46) + 10), (28, 28, 30))
d = ImageDraw.Draw(sheet)
y = 10
for r in rows:
    x = 10
    for name, im in r:
        sheet.paste(im, (x, y + 36))
        d.text((x + 4, y + 4), name, fill=(255, 220, 60), font=font)
        x += im.width + 10
    y += h + 46
sheet.save(out, quality=86)
print(out, sheet.size)
