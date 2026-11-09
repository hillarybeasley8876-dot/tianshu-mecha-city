"""Pick each cover model's best-lit yaw, and build the r8 concept-fidelity sheet (lead r8 §4).

    python3 tools/citykit/fidelity_sheet.py --pick          # writes the per-model yaws into lineup.json
    python3 tools/citykit/fidelity_sheet.py --sheet         # captures/kit/r8_concept_fidelity.jpg

**Why a yaw pick at all.** The line-up is lit by one low dusk sun and every model stands at the same
yaw, so a model whose broad face happens to point away from the sun is photographed back-lit — which
says nothing about its albedo and would fail the lead's "every white object reads white" gate for a
lighting reason. Each model is therefore shot at several yaws and the sheet uses the brightest.

"Brightest" is the mean luminance of the middle 60 % of the frame, which is where the model is: a
front-lit pale model raises it and a back-lit silhouette lowers it. It is a proxy, and it is measured
rather than eyeballed so the choice is reproducible.

The sheet is twelve rows of concept | in-game at 15 m | in-game at 40 m, from the concept image the
Tripo job actually used (art/tripo/jobs.json — three of the twelve came from their second candidate).
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
from typing import Dict, List, Tuple

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LINEUP = os.path.join(ROOT, "game", "world", "kit", "tests", "lineup.json")
JOBS = os.path.join(ROOT, "art", "tripo", "jobs.json")
CAPTURES = os.path.join(ROOT, "captures")
SHEET = os.path.join(ROOT, "captures", "kit", "r8_concept_fidelity.jpg")
CELL = 300
#: The centre fraction of the frame the model occupies, used by the brightness pick.
CENTRE = 0.6


def models() -> List[str]:
    return list(json.load(open(LINEUP))["models"])


def brightness(path: str) -> float:
    """Mean luminance of the middle of the frame — how lit the model is, not how bright the sky is."""
    if not os.path.exists(path):
        return -1.0
    im = np.asarray(Image.open(path).convert("L"), dtype=np.float32) / 255.0
    h, w = im.shape
    dy, dx = int(h * (1.0 - CENTRE) * 0.5), int(w * (1.0 - CENTRE) * 0.5)
    return float(im[dy:h - dy, dx:w - dx].mean())


def pick(sets: List[str]) -> Dict[str, int]:
    """model -> the yaw whose 15 m shot is brightest, over the capture sets that exist."""
    out: Dict[str, int] = {}
    for m in models():
        best: Tuple[float, int] = (-1.0, 0)
        for tag in sets:
            yaw = int(tag.replace("r8yaw", "") or 0)
            v = brightness(os.path.join(CAPTURES, "%s_%s_15m.jpg" % (tag, m)))
            if v > best[0]:
                best = (v, yaw)
        out[m] = best[1]
    return out


def write_yaws(yaws: Dict[str, int]) -> None:
    spec = json.load(open(LINEUP))
    spec["yaws"] = [yaws[m] for m in spec["models"]]
    spec["yaw_note"] = ("per-model yaw chosen by tools/citykit/fidelity_sheet.py --pick: the brightest "
                        "of the yaws shot, so no model is judged back-lit")
    with open(LINEUP, "w") as fh:
        json.dump(spec, fh, indent=1)
    print("yaws: %s" % ", ".join("%s=%d" % kv for kv in yaws.items()))


def _cell(src: str, out: str) -> None:
    subprocess.run(["sips", "-Z", str(CELL), "-s", "format", "jpeg", "-s", "formatOptions", "78",
                    src, "--out", out], capture_output=True)


def sheet(prefix: str, halves: Tuple[Tuple[int, int], Tuple[int, int]]) -> None:
    """Two stacked sheets of six rows, because a 12-row one is too tall to read."""
    jobs = json.load(open(JOBS))
    tmp = os.path.join(ROOT, "tmp", "city-kit", "r8")
    os.makedirs(tmp, exist_ok=True)
    pad = ("scale=%d:%d:force_original_aspect_ratio=decrease,"
           "pad=%d:%d:(ow-iw)/2:(oh-ih)/2:color=0x1c1c1e" % (CELL, CELL, CELL, CELL))
    outs = []
    for half, (lo, hi) in enumerate(halves):
        cells: List[str] = []
        for m in models()[lo:hi]:
            for src, tag in ((jobs["kit_" + m]["image"], "c"),
                             (os.path.join(CAPTURES, "%s_%s_15m.jpg" % (prefix, m)), "15"),
                             (os.path.join(CAPTURES, "%s_%s_40m.jpg" % (prefix, m)), "40")):
                out = os.path.join(tmp, "S%d_%s_%s.jpg" % (half, m, tag))
                _cell(src, out)
                cells.append(out)
        n = len(cells)
        fc = "".join("[%d]%s[v%d];" % (k, pad, k) for k in range(n))
        layout = []
        for k in range(n):
            c, r = k % 3, k // 3
            x = "0" if c == 0 else ("w0" if c == 1 else "w0+w1")
            y = "0" if r == 0 else "+".join("h%d" % (3 * j) for j in range(r))
            layout.append("%s_%s" % (x, y))
        fc += "".join("[v%d]" % k for k in range(n))
        fc += "xstack=inputs=%d:layout=%s" % (n, "|".join(layout))
        out = os.path.join(tmp, "sheet%d.jpg" % half)
        subprocess.run(["ffmpeg", "-v", "error", "-y"] + sum([["-i", c] for c in cells], []) +
                       ["-filter_complex", fc, "-q:v", "4", out], capture_output=True)
        outs.append(out)
    subprocess.run(["ffmpeg", "-v", "error", "-y"] + sum([["-i", o] for o in outs], []) +
                   ["-filter_complex", "[0][1]hstack=inputs=2", "-q:v", "4", SHEET], capture_output=True)
    print("sheet -> %s (%d bytes)" % (SHEET, os.path.getsize(SHEET)))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--pick", action="store_true")
    ap.add_argument("--sheet", action="store_true")
    ap.add_argument("--prefix", default="r8lineup")
    args = ap.parse_args()
    if args.pick:
        sets = sorted({f.split("_")[0] for f in os.listdir(CAPTURES) if f.startswith("r8yaw")})
        print("yaw sets on disk: %s" % ", ".join(sets))
        write_yaws(pick(sets))
    if args.sheet:
        sheet(args.prefix, ((0, 6), (6, 12)))
