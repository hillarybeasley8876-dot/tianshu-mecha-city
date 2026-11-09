#!/usr/bin/env python3
"""Title / end-card plates for the trailer, rendered with PIL.

This ffmpeg has no `drawtext` and no libass, so text is drawn here and composited by ffmpeg's
`overlay`. CJK comes from /System/Library/Fonts/Hiragino Sans GB.ttc (the font the brief names);
Latin from the same face so a mixed line keeps one baseline.
"""
from __future__ import annotations

import subprocess
from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

CJK = "/System/Library/Fonts/Hiragino Sans GB.ttc"
W, H = 1920, 1080


@dataclass
class Title:
    """One plate: `lines` are (text, style) with style in main|sub|small|tiny."""
    at: float
    dur: float
    lines: list[tuple[str, str]]
    fade: float = 0.5
    y: int = -1                      # -1 = centre the block
    x: int = W // 2
    align: str = "center"
    letter_space: int = 0
    shadow: bool = True
    rule: bool = False             ## draw the cyan accent bar left of the block (lower third)


STYLES: dict[str, tuple[int, tuple[int, int, int], int]] = {
    # name: (size, colour, tracking)
    "main": (150, (255, 255, 255), 26),
    "sub": (54, (232, 238, 245), 10),
    "small": (36, (200, 212, 226), 6),
    "tiny": (28, (150, 165, 182), 4),
    # lower third (showcase reel): the verb's in-game name, then its key on the dim second line
    "lower": (46, (244, 248, 252), 4),
    "lowerkey": (30, (140, 214, 232), 6),
    "cardno": (34, (150, 200, 224), 14),
    "card": (118, (255, 255, 255), 22),
    "cardsub": (40, (206, 220, 234), 10),
}

## The lower third sits this far from the left edge and this far above the bottom (px, 1920x1080).
LOWER_X, LOWER_Y = 104, 872
ACCENT = (96, 208, 232)


def _font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(CJK, size)


def _text_w(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont, track: int) -> int:
    w = int(draw.textlength(text, font=font))
    return w + track * max(0, len(text) - 1)


def _draw_tracked(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str,
                  font: ImageFont.FreeTypeFont, fill, track: int) -> None:
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill)
        x += int(draw.textlength(ch, font=font)) + track


def render_title(t: Title, out: Path) -> Path:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    heights, widths = [], []
    for text, style in t.lines:
        size, _c, track = STYLES[style]
        f = _font(size)
        widths.append(_text_w(draw, text, f, track))
        heights.append(int(f.size * 1.45))
    total = sum(heights)
    y = t.y if t.y >= 0 else (H - total) // 2
    if t.rule:
        draw.rectangle([t.x - 26, y + 4, t.x - 20, y + total - 6], fill=ACCENT + (235,))
        draw.rectangle([t.x - 34, y + 4, t.x - 30, y + total - 6], fill=ACCENT + (110,))
    for (text, style), w, h in zip(t.lines, widths, heights):
        size, colour, track = STYLES[style]
        f = _font(size)
        x = t.x - w // 2 if t.align == "center" else t.x
        if t.shadow:
            _draw_tracked(draw, (x + 3, y + 4), text, f, (0, 0, 0, 190), track)
        _draw_tracked(draw, (x, y), text, f, colour + (255,), track)
        y += h
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    return out


def lower_third(label: str, key: str = "", detail: str = "") -> Title:
    """The showcase reel's per-segment label: the verb's in-game name, its key, what it does."""
    lines: list[tuple[str, str]] = [(label, "lower")]
    sub = "   ".join(p for p in (f"[{key}]" if key else "", detail) if p)
    if sub:
        lines.append((sub, "lowerkey"))
    return Title(at=0.0, dur=1.0, lines=lines, y=LOWER_Y, x=LOWER_X, align="left",
                 fade=0.35, rule=True)


def render_card(lines: list[tuple[str, str]], bg: Path | None, out: Path,
                blur: int = 14, darken: float = 0.42) -> Path:
    """A full-frame chapter card: a blurred, darkened still from the chapter behind the title.

    A card is a picture, not an overlay, so the reel gets a real beat between chapters instead of
    text floating over moving footage.
    """
    if bg is not None and bg.exists():
        img = Image.open(bg).convert("RGB").resize((W, H), Image.LANCZOS)
        img = img.filter(ImageFilter.GaussianBlur(blur))
        img = Image.blend(Image.new("RGB", (W, H), (4, 6, 10)), img, darken)
    else:
        img = Image.new("RGB", (W, H), (6, 8, 12))
    draw = ImageDraw.Draw(img)
    heights = [int(_font(STYLES[s][0]).size * 1.5) for _t, s in lines]
    y = (H - sum(heights)) // 2
    for (text, style), h in zip(lines, heights):
        size, colour, track = STYLES[style]
        f = _font(size)
        w = _text_w(draw, text, f, track)
        _draw_tracked(draw, ((W - w) // 2 + 3, y + 4), text, f, (0, 0, 0), track)
        _draw_tracked(draw, ((W - w) // 2, y), text, f, colour, track)
        y += h
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    return out


def render_titles(titles: list[Title], outdir: Path) -> list[tuple[Title, Path]]:
    outdir.mkdir(parents=True, exist_ok=True)
    return [(t, render_title(t, outdir / f"title_{i:02d}.png")) for i, t in enumerate(titles)]
