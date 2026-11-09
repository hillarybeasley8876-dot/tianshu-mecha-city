#!/usr/bin/env python3
"""Contact sheet for one unit of the r4 capture batch, labelled with the command and the timestamp.

    tools/trailer/batch_sheet.py hud
    tools/trailer/batch_sheet.py feel --cols 8 --cell 420

Reads tmp/trailer/r4/results.json (written by batch_r4.py), takes every image the unit's runs
produced plus frames sampled out of every movie, and tiles them into
captures/batch_r4/<unit>_sheet.jpg. Movie frames are labelled with their time in the take; stills are
labelled with the command id, the file name and the wall-clock time the command finished.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "captures" / "batch_r4"
FONT = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
BG = (14, 14, 18)
PAD = 6
LABEL_H = 30
MOVIE_EVERY = 2.0
MOVIE_MAX = 12
BIG_EVERY = 120.0     # sampling step for a take too large to decode end to end
BIG_MAX = 3           # and only this many seeks: each one rescans an unindexed avi from the start


def tiles_for(row: dict, tmp: Path) -> list[tuple[str, Path]]:
    out: list[tuple[str, Path]] = []
    for rel in row["outputs"]:
        path = ROOT / rel
        # A sheet written while the batch ran is not a capture: it would tile a picture of a picture.
        if not path.exists() or OUT in path.parents:
            continue
        if path.suffix.lower() in (".jpg", ".jpeg", ".png"):
            out.append((f"{row['id']} {path.name} {row['at']}", path))
        elif path.suffix.lower() in (".avi", ".mp4", ".mkv"):
            out.extend(movie_frames(row, path, tmp))
    return out


def movie_frames(row: dict, path: Path, tmp: Path) -> list[tuple[str, Path]]:
    """Frames every MOVIE_EVERY seconds. A very large take is sampled at fixed offsets instead:
    decoding a 2 GB avi end to end would cost more than the whole sheet is worth."""
    d = tmp / path.stem
    d.mkdir(parents=True, exist_ok=True)
    big = path.stat().st_size > 1024 * 1024 * 1024
    if big:
        for n in range(BIG_MAX):
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(n * BIG_EVERY), "-i", str(path),
                            "-frames:v", "1", str(d / f"f_{n:03d}.png")], check=False)
    else:
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(path),
                        "-vf", f"fps=1/{MOVIE_EVERY}", "-fps_mode", "passthrough", str(d / "f_%03d.png")],
                       check=False)
    frames = sorted(d.glob("f_*.png"))[:BIG_MAX if big else MOVIE_MAX]
    step = BIG_EVERY if big else MOVIE_EVERY
    return [(f"{row['id']} {path.name} t={i * step:.1f}s {row['at']}", f)
            for i, f in enumerate(frames)]


def build(unit: str, rows: list[dict], cols: int, cell: int,
          extras: list[tuple[str, Path]] | None = None) -> Path:
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        tiles: list[tuple[str, Path]] = []
        for row in rows:
            tiles.extend(tiles_for(row, tmp))
        tiles.extend(extras or [])
        if not tiles:
            raise SystemExit(f"batch_sheet: {unit} produced no image")
        thumbs = []
        for label, path in tiles:
            im = Image.open(path).convert("RGB")
            im = im.resize((cell, max(1, round(im.height * cell / im.width))))
            thumbs.append((label, im))
        cw = cell
        ch = max(i.height for _, i in thumbs) + LABEL_H
        rows_n = (len(thumbs) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * (cw + PAD) + PAD, rows_n * (ch + PAD) + PAD), BG)
        draw = ImageDraw.Draw(sheet)
        font = ImageFont.truetype(FONT, 13)
        for n, (label, im) in enumerate(thumbs):
            x = PAD + (n % cols) * (cw + PAD)
            y = PAD + (n // cols) * (ch + PAD)
            sheet.paste(im, (x, y))
            draw.rectangle([x, y + ch - LABEL_H, x + cw, y + ch], fill=(0, 0, 0))
            draw.text((x + 4, y + ch - LABEL_H + 8), label[:64], font=font, fill=(230, 230, 235))
        OUT.mkdir(parents=True, exist_ok=True)
        out = OUT / f"{unit}_sheet.jpg"
        sheet.save(out, quality=84)
        print(f"wrote {out} {sheet.size} tiles={len(thumbs)}")
        return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("unit")
    ap.add_argument("--cols", type=int, default=6)
    ap.add_argument("--cell", type=int, default=460)
    ap.add_argument("--extra", action="append", default=[],
                    help="label=captures/path.jpg — a file the unit asked for that this run did not "
                         "re-shoot (it is labelled as such on the sheet)")
    args = ap.parse_args()
    results = json.loads((ROOT / "tmp/trailer/r4/results.json").read_text())
    rows = [r for r in results if r["unit"] == args.unit]
    if not rows:
        raise SystemExit(f"batch_sheet: no results for {args.unit}")
    extras = []
    for item in args.extra:
        label, _, rel = item.partition("=")
        path = ROOT / rel
        if not path.exists():
            print(f"batch_sheet: extra missing {rel}")
            continue
        extras.append((label, path))
    build(args.unit, rows, args.cols, args.cell, extras)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
