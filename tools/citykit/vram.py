#!/usr/bin/env python3
"""Report the kit's texture VRAM: what the models and their window masks cost resident.

    python3 tools/citykit/vram.py            # the kit
    python3 tools/citykit/vram.py --all      # every texture under game/

Godot imports these lossless (`compress/mode=0`), so a texture's resident size is its pixel count
times its channel count times 4/3 for the mip chain. The channel count is read off the source file
rather than the `.ctex`: a JPEG and an opaque PNG are both RGB8, and a mask with an alpha channel
would be RGBA8. This is an upper bound on the truth by at most the alpha channel, and it is the same
arithmetic for every round, which is what makes the numbers comparable across r3 and r4.
"""
from __future__ import annotations

import os
import sys

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "game"))
IMAGE_EXT = (".jpg", ".jpeg", ".png", ".webp")
MIPS = 4.0 / 3.0


def cost(path: str) -> tuple[int, int]:
    """(pixels, bytes resident) for one image."""
    try:
        with Image.open(path) as im:
            w, h = im.size
            bands = len(im.getbands())
    except (OSError, ValueError):
        return 0, 0
    # Godot's lossless import keeps the source's channel count: an 8-bit grey PNG becomes FORMAT_L8
    # (1 byte/texel), a JPEG or an opaque RGB PNG becomes RGB8, anything with alpha becomes RGBA8.
    channels = bands if bands in (1, 2, 3, 4) else 4
    return w * h, int(w * h * channels * MIPS)


def walk(root: str, label: str) -> tuple[int, int, int]:
    px = by = n = 0
    for dirpath, _, files in os.walk(root):
        if ".godot" in dirpath:
            continue
        for f in files:
            if not f.lower().endswith(IMAGE_EXT) or f.endswith(".import"):
                continue
            p, b = cost(os.path.join(dirpath, f))
            px += p
            by += b
            n += 1
    print("%-10s %5d images  %8.1f Mpx  %7.0f MB resident (with mipmaps)"
          % (label, n, px / 1e6, by / 1e6))
    return px, by, n


def main() -> int:
    if "--all" in sys.argv:
        walk(ROOT, "project")
        return 0
    walk(os.path.join(ROOT, "world", "kit"), "kit")
    for sub in ("world", "player", "flow"):
        p = os.path.join(ROOT, sub)
        if os.path.isdir(p):
            walk(p, sub)
    return 0


if __name__ == "__main__":
    sys.exit(main())
