#!/usr/bin/env python3
"""The lead's wedge gate: low-pass both crops (gaussian sigma = 12 px) and compare luminance std.

    tools/citykit/wedge.py captures/r7probe_A5deck_shipped.jpg captures/r7probe_A5deck_plainalbedo.jpg

The shipped crop's std must be at most `GATE` (1.5) times the plain-albedo twin's. A facade GRID is
high-frequency and does not count against this — the sigma-12 low-pass removes it — but the wedges do.
The crop is the near third of the frame, which is where the player stands.
"""
from __future__ import annotations

import subprocess
import sys
import tempfile

import numpy as np

SIGMA = 12.0
GATE = 1.5
#: The near third of the frame: x from 0.30 to 0.72, y from 0.28 to 0.80 of the image.
CROP = (0.30, 0.28, 0.72, 0.80)


def load(path: str) -> np.ndarray:
    out = tempfile.NamedTemporaryFile(suffix=".png", delete=False).name
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", path, out], check=True)
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", out, "-f", "rawvideo", "-pix_fmt", "gray",
                          "-"], check=True, capture_output=True).stdout
    probe = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=width,height",
                            "-of", "csv=p=0", out], check=True, capture_output=True, text=True)
    w, h = (int(v) for v in probe.stdout.strip().split(",")[:2])
    return np.frombuffer(raw, dtype=np.uint8).reshape(h, w).astype(np.float32) / 255.0


def blur(a: np.ndarray, sigma: float) -> np.ndarray:
    r = max(1, int(round(sigma)))
    out = a
    for axis in (0, 1):
        for _ in range(3):
            acc = out
            for s in range(1, r + 1):
                acc = acc + np.roll(out, s, axis) + np.roll(out, -s, axis)
            out = acc / float(2 * r + 1)
    return out


def stat(path: str) -> float:
    a = load(path)
    h, w = a.shape
    x0, y0, x1, y1 = CROP
    crop = a[int(y0 * h):int(y1 * h), int(x0 * w):int(x1 * w)]
    return float(blur(crop, SIGMA).std())


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    ship, plain = stat(sys.argv[1]), stat(sys.argv[2])
    ratio = ship / max(plain, 1e-6)
    print("WEDGE shipped sigma-%d std %.5f   plain-albedo %.5f   ratio %.2f  gate <= %.1f  %s"
          % (int(SIGMA), ship, plain, ratio, GATE, "PASS" if ratio <= GATE else "FAIL"))
    return 0 if ratio <= GATE else 1


if __name__ == "__main__":
    sys.exit(main())
