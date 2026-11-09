#!/usr/bin/env python3
"""Derive the Tianshu emission / trim mask from the Tripo colour atlas (hero-v3 r7).

    python3 blender/hero3/hero3_emissive.py [--preview] [--uv=<dir>]

The shipped body material had no emission at all, so the concept's cyan seam lines were only albedo
pixels: on the shaded side of the mech they went black and the hero read as a silhouette in every
trailer shot (lead r7). Tripo bakes the lines into the albedo, so the mask is recovered from the
albedo by hue and written beside it:

    R  accent lines   steady cyan seams, the concept's armour piping
    G  vents          amber glow inside the head / chest UV islands, pulsed at runtime
    B  gold trim      so the shader can push metallic to 1.0 on the trim alone

Writes `game/player/model/hero3/hero3_Emission.png` (4K) and `hero3_lod1_Emission.png` (2K), plus a
`captures/hero3_emission_mask.jpg` contact sheet when --preview is given. `--uv` points at the
per-bone UV rasters from `hero3_uv.py`; without them the vent channel falls back to the amber hue
rule over the whole atlas.
"""
from __future__ import annotations

import argparse
import glob
import os
from typing import Dict, Optional, Tuple

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "game", "player", "model", "hero3")
CAPTURES = os.path.join(ROOT, "captures")
UV_DIR = os.path.join(ROOT, "tmp", "hero-v3", "uv")

## Measured on the 4K atlas: the seams sit at hue 187 +- 12, and the teal glow pools the Tripo bake
## leaves around the wider vents drop to V 0.24 before they stop reading as cyan. The bronze screws
## and the rust streaks that share the warm end sit at hue < 30, so the gold band starts at 33.
CYAN_HUE = (168.0, 206.0)
CYAN_SAT = 0.35
CYAN_VAL = 0.24
AMBER_HUE = (8.0, 46.0)
AMBER_SAT = 0.50
AMBER_VAL = 0.50
GOLD_HUE = (33.0, 60.0)
GOLD_SAT = 0.30
GOLD_VAL = 0.42
## Bones whose UV islands may carry a vent. Everything else is piping and trim.
VENT_BONES = ("Head", "Neck", "Spine01", "Spine02")
## The seams are 3-8 px wide at 4K; a close joins the gaps the JPEG left in them and an open drops
## the isolated specks the hue rule picks up inside the panel noise.
CLOSE_PX = {4096: 5, 2048: 3}
OPEN_PX = {4096: 3, 2048: 3}
SOFT_PX = {4096: 1.6, 2048: 1.0}


def hsv(rgb: np.ndarray) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Hue in degrees, saturation and value from a float [0, 1] RGB array."""
    mx = rgb.max(2)
    mn = rgb.min(2)
    d = mx - mn
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    hue = np.zeros_like(mx)
    live = d > 1e-6
    idx = (mx == r) & live
    hue[idx] = ((g - b)[idx] / d[idx]) % 6
    idx = (mx == g) & live
    hue[idx] = ((b - r)[idx] / d[idx]) + 2
    idx = (mx == b) & live
    hue[idx] = ((r - g)[idx] / d[idx]) + 4
    sat = np.where(mx > 0, d / np.maximum(mx, 1e-6), 0.0)
    return hue * 60.0, sat, mx


def band(hue: np.ndarray, sat: np.ndarray, val: np.ndarray, h: Tuple[float, float],
         s: float, v: float) -> np.ndarray:
    return (hue >= h[0]) & (hue <= h[1]) & (sat >= s) & (val >= v)


def clean(mask: np.ndarray, res: int) -> np.ndarray:
    """Close, open, then soften: a seam survives as one continuous line, speckle does not, and the
    1 px blur gives the shader a falloff instead of a hard-edged sticker."""
    img = Image.fromarray((mask * 255).astype(np.uint8))
    img = img.filter(ImageFilter.MaxFilter(CLOSE_PX.get(res, 3)))
    img = img.filter(ImageFilter.MinFilter(CLOSE_PX.get(res, 3)))
    img = img.filter(ImageFilter.MinFilter(OPEN_PX.get(res, 3)))
    img = img.filter(ImageFilter.MaxFilter(OPEN_PX.get(res, 3)))
    return np.asarray(img.filter(ImageFilter.GaussianBlur(SOFT_PX.get(res, 1.0))),
                      dtype=np.float32) / 255.0


def vent_regions(res: int, uv_dir: Optional[str]) -> Optional[np.ndarray]:
    """The union of the head / chest UV islands, resampled to `res`."""
    if not uv_dir or not os.path.isdir(uv_dir):
        return None
    out = None
    for bone in VENT_BONES:
        path = os.path.join(uv_dir, "uv_%s.png" % bone)
        if not os.path.exists(path):
            continue
        m = Image.open(path).convert("L").resize((res, res), Image.NEAREST)
        arr = np.asarray(m) > 127
        out = arr if out is None else (out | arr)
    return out


def build(color_path: str, res: int, uv_dir: Optional[str]) -> Tuple[np.ndarray, Dict[str, float]]:
    rgb = np.asarray(Image.open(color_path).convert("RGB"), dtype=np.float32) / 255.0
    if rgb.shape[0] != res:
        rgb = np.asarray(Image.fromarray((rgb * 255).astype(np.uint8)).resize((res, res)),
                         dtype=np.float32) / 255.0
    hue, sat, val = hsv(rgb)
    lines = clean(band(hue, sat, val, CYAN_HUE, CYAN_SAT, CYAN_VAL), res)
    gold = clean(band(hue, sat, val, GOLD_HUE, GOLD_SAT, GOLD_VAL), res)
    amber = band(hue, sat, val, AMBER_HUE, AMBER_SAT, AMBER_VAL)
    islands = vent_regions(res, uv_dir)
    vents = clean(amber & islands, res) if islands is not None else clean(amber, res)
    vents = np.clip(vents - lines, 0.0, 1.0)
    out = np.zeros((res, res, 3), dtype=np.uint8)
    for c, channel in enumerate((lines, vents, gold)):
        out[..., c] = np.clip(channel * 255.0, 0, 255).astype(np.uint8)
    stats = {"lines": float((lines > 0.5).mean()), "vents": float((vents > 0.5).mean()),
             "gold": float((gold > 0.5).mean())}
    return out, stats


def preview(masks: Dict[str, np.ndarray]) -> str:
    """One sheet per LOD: the atlas, the three channels and the mask laid over the atlas."""
    tiles = []
    for tag, (rgb, mask) in masks.items():
        small = np.asarray(Image.fromarray((rgb * 255).astype(np.uint8)).resize((512, 512)),
                           dtype=np.float32) / 255.0
        m = np.asarray(Image.fromarray(mask).resize((512, 512), Image.NEAREST), dtype=np.float32) / 255.0
        tiles.append(small)
        for c in range(3):
            tiles.append(np.repeat(m[..., c:c + 1], 3, axis=2))
        over = small * 0.45 + m * 0.55
        tiles.append(np.clip(over, 0.0, 1.0))
    cols = 5
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * 512, rows * 512), (16, 16, 20))
    for i, t in enumerate(tiles):
        sheet.paste(Image.fromarray((np.clip(t, 0, 1) * 255).astype(np.uint8)),
                    ((i % cols) * 512, (i // cols) * 512))
    path = os.path.join(CAPTURES, "hero3_emission_mask.jpg")
    sheet.resize((cols * 300, rows * 300)).save(path, quality=86)
    return path


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--uv", default=UV_DIR)
    args = ap.parse_args()
    os.makedirs(CAPTURES, exist_ok=True)
    built: Dict[str, Tuple[np.ndarray, np.ndarray]] = {}
    for tag, res in (("", 4096), ("lod1_", 2048)):
        hits = glob.glob(os.path.join(OUT_DIR, "hero3_%sColor_*.jpg" % tag))
        if not hits:
            raise SystemExit("hero3_emissive: no colour atlas for %s in %s" % (tag or "lod0", OUT_DIR))
        mask, stats = build(hits[0], res, args.uv)
        out = os.path.join(OUT_DIR, "hero3_%sEmission.png" % tag)
        Image.fromarray(mask).save(out)
        print("MASK %-24s %dx%d  lines %.3f%%  vents %.3f%%  gold %.3f%%"
              % (os.path.basename(out), res, res, stats["lines"] * 100, stats["vents"] * 100,
                 stats["gold"] * 100))
        if args.preview:
            rgb = np.asarray(Image.open(hits[0]).convert("RGB").resize((res, res)),
                             dtype=np.float32) / 255.0
            built[tag or "lod0"] = (rgb, mask)
    if built:
        print("PREVIEW %s" % preview(built))


if __name__ == "__main__":
    main()
