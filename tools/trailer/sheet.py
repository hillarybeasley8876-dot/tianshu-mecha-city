#!/usr/bin/env python3
"""Contact sheet from a capture: one frame every N seconds, tiled and labelled with its timestamp.

    tools/trailer/sheet.py captures/trailer/shots/s04.avi -o captures/trailer/sheets/s04.jpg
    tools/trailer/sheet.py cut.mp4 --every 1.0 --cols 6 --start 12 --end 30
    tools/trailer/sheet.py --spec game/trailer/shots.json -o captures/trailer/sheets/v2a_shots.jpg

Used to judge a take without watching it (WORKER RULES: look at your own screenshots) and to
produce the per-shot sheets the brief's checkpoint 2 asks for. Frames come from ffmpeg; the tiling
and the labels are PIL, because the ffmpeg on this machine is built without `drawtext`.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
CELL_W = 480          # each tile is scaled to this width; 1920x1080 -> 480x270
PAD = 4
BG = (16, 16, 20)
FONT = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
CJK = "/System/Library/Fonts/Hiragino Sans GB.ttc"


def probe(src: Path) -> tuple[int, int, float]:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
         "stream=width,height,duration", "-of", "csv=p=0:s=x", str(src)],
        capture_output=True, text=True, check=True).stdout.strip()
    parts = out.split("x")
    if len(parts) < 3:
        raise SystemExit(f"sheet: cannot probe {src} ({out!r})")
    return int(parts[0]), int(parts[1]), float(parts[2])


def extract(src: Path, tmp: Path, start: float, end: float, every: float) -> list[Path]:
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-ss", str(start), "-to", str(end), "-i", str(src),
         "-vf", f"fps=1/{every},scale={CELL_W}:-2", "-fps_mode", "passthrough",
         str(tmp / "f_%04d.png")], check=True)
    return sorted(tmp.glob("f_*.png"))


def tile(frames: list[Path], out: Path, cols: int, every: float, start: float) -> None:
    first = Image.open(frames[0])
    cw, ch = first.size
    rows = (len(frames) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (cw + PAD) + PAD, rows * (ch + PAD) + PAD), BG)
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.truetype(FONT, 16)
    for i, path in enumerate(frames):
        x = PAD + (i % cols) * (cw + PAD)
        y = PAD + (i // cols) * (ch + PAD)
        sheet.paste(Image.open(path).convert("RGB"), (x, y))
        label = f"{start + i * every:.2f}s"
        draw.rectangle([x, y, x + 8 + 9 * len(label), y + 22], fill=(0, 0, 0))
        draw.text((x + 4, y + 3), label, font=font, fill=(255, 255, 255))
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out, quality=88)


def shots_sheet(spec: Path, out: Path, cols: int, at: float, cell: int = CELL_W) -> int:
    """One frame per shot of the edit, taken `at` of the way through each cut, straight from the take
    the cut uses — the "_shots.jpg" the lead reviews the camera work from. A shot that carries a
    `lower` label gets that label printed under its frame, so the sheet is the segment list."""
    doc = json.loads(spec.read_text())
    root = spec.parents[2]
    shots = doc["shots"]
    takedir = root / doc.get("dir", "captures/trailer/shots")
    tmp = Path(tempfile.mkdtemp(prefix="shotsheet_", dir=str(out.parent)))
    cells: list[tuple[str, Path]] = []
    try:
        for s in shots:
            src = takedir / f"{s['take']}.avi"
            if not src.exists():
                print(f"sheet: missing take {src.name} for {s['id']}", file=sys.stderr)
                continue
            t = float(s["in"]) + (float(s["out"]) - float(s["in"])) * at
            dst = tmp / f"{s['id']}.png"
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{t:.3f}", "-i", str(src),
                            "-frames:v", "1", "-vf", f"scale={cell}:-2", str(dst)], check=True)
            low = s.get("lower") or {}
            caption = f"{s['id']}  {t:.2f}s"
            if low:
                key = f"  [{low['key']}]" if low.get("key") else ""
                caption += "\n" + str(low.get("label", "")) + key
            cells.append((caption, dst))
        if not cells:
            raise SystemExit("sheet: no takes found")
        first = Image.open(cells[0][1])
        cw, ch = first.size
        cap_h = max(40, cell // 12)
        rows = (len(cells) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * (cw + PAD) + PAD,
                                  rows * (ch + cap_h + PAD) + PAD), BG)
        draw = ImageDraw.Draw(sheet)
        font = ImageFont.truetype(FONT, max(12, cell // 32))
        cjk = ImageFont.truetype(CJK, max(13, cell // 28))
        for i, (label, path) in enumerate(cells):
            x = PAD + (i % cols) * (cw + PAD)
            y = PAD + (i // cols) * (ch + cap_h + PAD)
            sheet.paste(Image.open(path).convert("RGB"), (x, y))
            lines = label.split("\n")
            draw.text((x + 4, y + ch + 2), lines[0], font=font, fill=(210, 214, 220))
            if len(lines) > 1:
                draw.text((x + 4, y + ch + cap_h // 2), lines[1], font=cjk, fill=(120, 205, 228))
        out.parent.mkdir(parents=True, exist_ok=True)
        sheet.save(out, quality=88)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print(f"sheet: {len(cells)} shots -> {out}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src", type=Path, nargs="?", default=None)
    ap.add_argument("-o", "--out", type=Path, default=None)
    ap.add_argument("--every", type=float, default=0.5, help="seconds between frames")
    ap.add_argument("--cols", type=int, default=6)
    ap.add_argument("--start", type=float, default=0.0)
    ap.add_argument("--end", type=float, default=-1.0)
    ap.add_argument("--spec", type=Path, default=None,
                    help="shots.json: one frame per shot of the edit instead of a time sweep")
    ap.add_argument("--at", type=float, default=0.5, help="where in each cut to grab the frame")
    ap.add_argument("--cell", type=int, default=CELL_W, help="tile width in px (review sheets go big)")
    args = ap.parse_args()

    if args.spec:
        out = args.out or (ROOT / "captures/trailer/sheets/shots.jpg")
        return shots_sheet(args.spec, out, args.cols, args.at, args.cell)
    if args.src is None:
        raise SystemExit("sheet: give a source file or --spec")

    src = args.src
    if not src.exists():
        raise SystemExit(f"sheet: no such file {src}")
    w, h, dur = probe(src)
    end = dur if args.end < 0 else min(args.end, dur)
    out = args.out or src.with_suffix(".jpg")

    tmp = Path(tempfile.mkdtemp(prefix="sheet_", dir=str(src.parent)))
    try:
        frames = extract(src, tmp, args.start, end, args.every)
        if not frames:
            raise SystemExit("sheet: ffmpeg produced no frames")
        tile(frames, out, args.cols, args.every, args.start)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print(f"sheet: {len(frames)} frames from {src.name} ({w}x{h}, {dur:.1f}s) -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
