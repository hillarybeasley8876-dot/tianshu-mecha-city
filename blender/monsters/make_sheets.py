"""Tile rendered pose strips into the review contact sheets (monster-assets).

    tools/blender.sh run blender/monsters/render_models.py -- --type=mantis --clips=slash_1 --frames=6
    python3 blender/monsters/make_sheets.py --out=captures/monsters_attack_strips.jpg \
        --cell=380 --cols=6 ripper:bite mantis:slash_1 spitter:fire harrier:dive \
        juggernaut:ground_slam titan:stomp

Reads the PNGs `render_models.py` wrote to tmp/monster-assets/render/<type>_<clip>_<i>.png, one row
per `type:clip` argument, and writes a single JPEG. Plain python3 — no Blender needed.
"""
import argparse
import glob
import os
import sys

from PIL import Image

TMP = os.path.expanduser("~/m/mecha-city/tmp/monster-assets/render")
ROOT = os.path.expanduser("~/m/mecha-city")


def row_frames(entry: str, folder: str, ext: str) -> list:
    """Every frame image for one `<name>:<prefix>` entry, in frame order.

    Blender renders are addressed as `type:clip` (files `<type>_<clip>_<i>.png`); Godot captures
    from `tools/godot.sh drive --out=<prefix>` are addressed as `label:<prefix>` under --dir."""
    _name, prefix = entry.split(":")
    files = sorted(glob.glob(os.path.join(folder, "%s_*.%s" % (prefix, ext))),
                   key=lambda p: int(p.rsplit("_", 1)[1].split(".")[0]))
    if not files:
        print("SHEET skip %s: no frames in %s" % (entry, folder))
    return files


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("entries", nargs="+", help="type:clip pairs, one per row")
    p.add_argument("--out", required=True)
    p.add_argument("--cell", type=int, default=380)
    p.add_argument("--cols", type=int, default=6)
    p.add_argument("--quality", type=int, default=72)
    p.add_argument("--dir", default=TMP, help="folder holding the frames")
    p.add_argument("--ext", default="png", help="frame extension (png for renders, jpg for captures)")
    args = p.parse_args()
    folder = os.path.expanduser(args.dir)
    rows = [(e, row_frames(e, folder, args.ext)) for e in args.entries]
    rows = [(e, f) for e, f in rows if f]
    if not rows:
        print("SHEET nothing to tile")
        sys.exit(1)
    cols = max(min(args.cols, max(len(f) for _, f in rows)), 1)
    cell = args.cell
    sheet = Image.new("RGB", (cell * cols, cell * len(rows)), (32, 36, 40))
    for r, (_entry, files) in enumerate(rows):
        for c, path in enumerate(files[:cols]):
            im = Image.open(path).convert("RGB")
            im.thumbnail((cell, cell))
            sheet.paste(im, (c * cell + (cell - im.width) // 2, r * cell + (cell - im.height) // 2))
    out = args.out if os.path.isabs(args.out) else os.path.join(ROOT, args.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sheet.save(out, quality=args.quality)
    print("SHEET %s  %d rows x %d cols" % (out, len(rows), cols))


main()
