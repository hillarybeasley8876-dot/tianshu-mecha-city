"""Tile hero3 filmstrip frames into the contact sheets the lead judges (hero-v3).

    uv run --with pillow python3 blender/hero3/make_strip.py walk run strafe back turn

Reads captures/hero3_strip_<name>_<view>_<n>.jpg and writes captures/hero3_strip_<name>.jpg: one
row per view, eight frames each, labelled with the frame's position in the cycle.

If `captures/hero3_strip_<name>.txt` exists (the metrics line the strip scene prints, saved by
`blender/hero3/shoot_strips.sh`), it is drawn across the top of the sheet: stride, cadence, double
support and pelvis height are numbers the lead should not have to eyeball.
"""
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.expanduser("~/m/mecha-city")
CAPTURES = os.path.join(ROOT, "captures")
FRAMES = 8
VIEWS = ["front", "side"]
CELL = (360, 460)      ## per frame in the sheet
PAD = 4
LABEL_H = 18
METRICS_H = 20
## The camera looks at y = 8 m from 46 m with a 42 deg fov, so a 16 m mech occupies the middle ~45 %
## of the frame height. Crop to that band, with the width taken from the cell's aspect so nothing is
## squashed.
CROP_H = 0.74
CROP_CY = 0.48


def frames_for(name: str, view: str) -> list:
    out = []
    for i in range(FRAMES):
        path = os.path.join(CAPTURES, "hero3_strip_%s_%s_%d.jpg" % (name, view, i))
        if os.path.exists(path):
            out.append(path)
    return out


def metrics_for(name: str) -> str:
    path = os.path.join(CAPTURES, "hero3_strip_%s.txt" % name)
    if not os.path.exists(path):
        return ""
    with open(path) as handle:
        return handle.read().strip()


def crop(image: Image.Image) -> Image.Image:
    w, h = image.size
    ch = int(h * CROP_H)
    cw = min(int(ch * CELL[0] / CELL[1]), w)
    cx, cy = int(w * 0.5), int(h * CROP_CY)
    return image.crop((cx - cw // 2, cy - ch // 2, cx + cw // 2, cy + ch // 2)).resize(
        CELL, Image.LANCZOS)


def build(name: str) -> str:
    rows = [(view, frames_for(name, view)) for view in VIEWS]
    rows = [(view, paths) for view, paths in rows if paths]
    if not rows:
        raise SystemExit("make_strip: no frames for %s" % name)
    metrics = metrics_for(name)
    width = FRAMES * (CELL[0] + PAD) + PAD
    height = len(rows) * (CELL[1] + LABEL_H + PAD) + PAD + (METRICS_H if metrics else 0)
    sheet = Image.new("RGB", (width, height), (14, 14, 17))
    draw = ImageDraw.Draw(sheet)
    top0 = PAD
    if metrics:
        draw.text((PAD, top0), metrics, fill=(150, 230, 190))
        top0 += METRICS_H
    for r, (view, paths) in enumerate(rows):
        top = top0 + r * (CELL[1] + LABEL_H + PAD)
        draw.text((PAD, top), "%s -- %s   (frames 0-7 of one left-right cycle, 2 steps)"
                % (name, view), fill=(210, 210, 220))
        for i, path in enumerate(paths):
            sheet.paste(crop(Image.open(path).convert("RGB")),
                    (PAD + i * (CELL[0] + PAD), top + LABEL_H))
    out = os.path.join(CAPTURES, "hero3_strip_%s.jpg" % name)
    sheet.save(out, quality=88)
    print("STRIP %-8s %d rows -> %s" % (name, len(rows), out))
    return out


def main() -> None:
    for name in (sys.argv[1:] or ["walk", "run", "strafe", "back", "turn"]):
        build(name)


if __name__ == "__main__":
    main()
