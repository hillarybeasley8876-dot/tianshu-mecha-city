#!/usr/bin/env python3
"""mech-move r8 item 10: the death capture sheet (d1_dead_page | d2_walked_page, plus the close-up).

Verbatim the sheet script in status/mech-move.md "Captures needed" item 3, moved out of the heredoc
so tools/trailer/batch_r4.py can run it as one step.
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CAP = ROOT / "captures"


def load(name: str) -> Image.Image:
    return Image.open(CAP / f"mech-move_death_{name}.jpg")


def main() -> int:
    pages = [load("d1_dead_page"), load("d2_walked_page")]
    close = load("d2_walked_closeup")
    w = max(i.width for i in pages)
    h = max(i.height for i in pages)
    pad = 8
    wide = w * 2 + pad
    close = close.resize((wide, round(close.height * wide / close.width)))
    sheet = Image.new("RGB", (wide + pad * 2, h + close.height + pad * 3), (10, 10, 12))
    for n, i in enumerate(pages):
        sheet.paste(i, (pad + n * (w + pad), pad))
    sheet.paste(close, (pad, h + pad * 2))
    out = CAP / "mech-move_death_sheet.jpg"
    sheet.save(out, quality=88)
    print("wrote", out, sheet.size)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
