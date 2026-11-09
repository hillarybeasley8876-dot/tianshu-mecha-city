"""Palette + roughness grade for the kit's Tripo texture set (lead r3 MUST-FIX: "crumpled silver foil").

Three measured problems, three fixes, all applied to the texture pixels before export so the glTF
carries the graded maps (Godot's `mc_kit` keeps the model's own textures untouched by design):

1. **Glossy.** Tripo's ORM green medians sit at 0.10-0.36 (measured: t01 0.102, k02 0.192, k06 0.278).
   A glossy near-white surface mirrors the dusk sky in every facet, which IS the foil. Roughness is
   remapped into `[ROUGH_FLOOR, 1)` — a remap, not a `max()`, so a weathered 0.75 stays distinguishable
   from a painted 0.30 instead of both clamping to the same value.
2. **Pale.** Albedo medians run 0.27-0.66 scene-linear (u01 0.658 = sRGB 0.83, near-white). Each model
   is graded toward its band's target median from ART.md §2 (warm concrete #A9A196 = 0.396 linear) and
   tinted toward that band's hue, then its highlights are rolled off so a bright sheet stops being a
   bloom source.
3. **The window detector must not move.** `mc_kit` finds lit panes as albedo luminance in sRGB
   0.08-0.26 (`McKitSkin._copy_windows`). Darkening a model would push ordinary wall into that band and
   light the whole facade, so texels below GLASS_HI are blended back toward their original value: dark
   glass and neon stay exactly where they were, and only the pale surfaces move.

`report()` returns the before/after medians per model, in the shape monster-assets' `median_luma` used.
"""
from __future__ import annotations

import os
from typing import Dict, Optional, Tuple

import bpy
import numpy as np

#: Scratch folder for the graded textures between the pixel pass and the glTF export.
TEX_TMP = os.path.expanduser("~/m/mecha-city/tmp/city-kit/tex")

# Roughness is remapped into this floor .. 1.0. 0.55 is the lead's number: weathered concrete and
# painted steel, not a mirror.
ROUGH_FLOOR = 0.55
METAL_CAP = 0.30          # nothing in this kit is a polished metal prop except the odd pipe
# Albedo luminance (scene-linear) below which a texel is left alone. `mc_kit` finds its lit panes in
# sRGB 0.08-0.26 = linear 0.0064-0.0562 (`McKitSkin._copy_windows`), so the blend runs from inside that
# band out to 0.25: anything the shader could ever call a pane keeps its value, and only the pale
# surfaces — which are the actual problem, medians 0.27-0.66 — are graded. `pane_pct` below is the
# measurement that proves the detector did not move.
GLASS_LO, GLASS_HI = 0.005, 0.25
# `McKitSkin` pane band, as linear luminance. Reported before/after; a model whose pane fraction grows
# would light its whole facade at night, so it is the one number the grade must not move.
PANE_LO, PANE_HI = 0.0064, 0.0562
HI_START = 0.42           # linear luminance where the highlight rolloff starts
HI_KNEE = 1.6             # rolloff strength: out = s + (v-s) / (1 + k*(v-s))
GAIN_CLAMP = (0.30, 1.30)
SAT_CLAMP = (0.85, 1.60)
MEASURE_PX = 256

#: band -> (target median linear luma, tint sRGB, saturation gain). Targets are ART.md §2 read as
#: scene-linear: warm concrete #A9A196 = 0.396, brushed steel #8C939B = 0.26, terracotta #8E4A36 =
#: 0.11, rust/harbour darker still. They sit BELOW the palette value on purpose — a Tripo albedo has
#: its own lighting baked in, and the scene is dusk, so a model graded to the swatch reads pale.
BANDS: Dict[str, Tuple[float, Tuple[float, float, float], float]] = {
    "tower": (0.32, (0.92, 0.90, 0.86), 1.10),
    "megablock": (0.30, (0.94, 0.89, 0.82), 1.20),
    "midrise": (0.31, (0.94, 0.90, 0.84), 1.15),
    "civic": (0.34, (0.95, 0.92, 0.86), 1.10),
    "oldtown": (0.24, (0.98, 0.84, 0.72), 1.35),
    "harbor": (0.22, (0.96, 0.86, 0.74), 1.35),
    "foundry": (0.21, (0.94, 0.87, 0.78), 1.30),
    "street": (0.27, (0.95, 0.89, 0.80), 1.25),
    "structure": (0.28, (0.93, 0.90, 0.86), 1.15),
    # Lead r4 item 3: the cover kit is what the player fights next to, and at 0.22 it went nearly
    # black in the yard. ART.md's warm concrete #A9A196 is 0.396 linear; 0.34 is that band with the
    # baked-in lighting of a Tripo albedo allowed for.
    "cover": (0.34, (0.96, 0.90, 0.82), 1.25),
}
DEFAULT_BAND = (0.28, (0.94, 0.90, 0.84), 1.20)

#: `win_glass` from mc_kit_body.gdshaderinc (#131A22), normalised to luminance 1, and how far the
#: carved panes are pushed toward it.
GLASS_RGB = np.array([0.075, 0.098, 0.133], dtype=np.float32)
GLASS_RGB = GLASS_RGB / float(GLASS_RGB @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32))
#: How far a masked pane texel is pulled toward dark glass. 0.85 leaves a little of the Tripo
#: reflection in the pane, which is what stops a curtain wall reading as a black stencil.
PANE_MIX = 0.85

#: `assets.py` bands are about GEOMETRY (industrial / tileable), the grade bands are about PALETTE,
#: so an industrial hall in the harbour is rust and the same hall in the foundry is soot. Resolved
#: from the asset's own district rather than by adding a second band column to the asset table.
_INDUSTRIAL = {"D1": "harbor", "D6": "foundry", "D2": "harbor"}


def band_of(asset) -> str:
    """Grade band for an `assets.Asset`."""
    if asset.band == "industrial":
        for d in asset.districts:
            if d in _INDUSTRIAL:
                return _INDUSTRIAL[d]
        return "foundry"
    if asset.band == "tileable":
        return "structure"
    return asset.band if asset.band in BANDS else "street"


def _write_jpeg(img: bpy.types.Image, aid: str, kind: str, quality: int = 78,
                fmt: str = "JPEG"):
    """Save the graded pixels as a JPEG and return a FRESH image datablock loaded back from it.

    Why the reload: the glTF exporter byte-copies an image that is file-backed and UNMODIFIED ("Save
    PNGs as PNGs, JPEGs as JPEGs") and re-encodes anything else from its float buffer. Measured on t01,
    that re-encode produced a 13.0 MB "jpeg" for one 2K albedo where the same pixels written to disk
    first are 1.4 MB — 8x the VRAM for nothing. Saving and reloading hands the exporter a clean
    file-backed JPEG to copy. `tmp/city-kit/tex/` is scratch; only the glb ships.
    """
    ext = "png" if fmt == "PNG" else "jpg"
    out = os.path.join(TEX_TMP, "%s_%s.%s" % (aid, kind, ext))
    os.makedirs(TEX_TMP, exist_ok=True)
    bpy.context.scene.render.image_settings.quality = quality
    img.file_format = fmt
    img.filepath_raw = out
    img.save()
    fresh = bpy.data.images.load(out, check_existing=False)
    fresh.colorspace_settings.name = img.colorspace_settings.name
    fresh.name = "%s_%s_graded" % (aid, kind)
    return fresh


def _pixels(img: bpy.types.Image) -> np.ndarray:
    buf = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    return buf.reshape(-1, 4)


def _luma(px: np.ndarray) -> np.ndarray:
    return px[:, 0] * 0.2126 + px[:, 1] * 0.7152 + px[:, 2] * 0.0722


def _srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def used_mask(obj: bpy.types.Object, sides: Tuple[int, ...]) -> Dict[int, np.ndarray]:
    """Boolean rasters of the texels the mesh's UV shells actually cover, at each side in `sides`.

    Measured over the shells, not the whole atlas: an atlas that is half empty would drag the median
    toward whatever the padding colour is (the same reasoning as monsters' `median_luma`). Several
    sides come from ONE walk of the polygons — the 2K raster is what the pane percentile needs (a
    256 px downscale averages the window recesses away and the cut lands 50 % too high) and the 256 px
    one is what the median measurements index.
    """
    me = obj.data
    out = {s: np.zeros((s, s), dtype=bool) for s in sides}
    if not me.uv_layers:
        return {s: np.ones((s, s), dtype=bool) for s in sides}
    uv = me.uv_layers.active.data
    for poly in me.polygons:
        pts = [uv[li].uv for li in poly.loop_indices]
        for s, m in out.items():
            xs = [min(s - 1, max(0, int(p[0] * s))) for p in pts]
            ys = [min(s - 1, max(0, int(p[1] * s))) for p in pts]
            m[min(ys):max(ys) + 1, min(xs):max(xs) + 1] = True
    return {s: m.reshape(-1) for s, m in out.items()}


def _tint(tint_srgb: Tuple[float, float, float]) -> np.ndarray:
    """Tint as a linear RGB multiplier normalised to luminance 1, so it hues without brightening."""
    lin = np.array([_srgb_to_linear(c) for c in tint_srgb], dtype=np.float32)
    return lin / max(float(lin @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)), 1e-5)


def _downsample(px: np.ndarray, side: int, to: int = MEASURE_PX) -> np.ndarray:
    """Box-average an RGBA buffer down to `to` x `to`, returning RGB.

    Blender's own `Image.scale()` is NOT usable for the measurement: it needs a COPY, and `Image.copy()`
    on a packed glTF import re-reads the original file rather than the edited buffer, so every
    "after" number came back identical to "before" until this was done in numpy.
    """
    rgb = px[:, :3]
    step = side // to
    if step >= 1 and side % to == 0:
        return rgb.reshape(to, step, to, step, 3).mean(axis=(1, 3)).reshape(-1, 3)
    idx = (np.arange(to) * side // to).clip(0, side - 1)
    return rgb.reshape(side, side, 3)[np.ix_(idx, idx)].reshape(-1, 3)


def _median_luma(px: np.ndarray, side: int, used: np.ndarray) -> float:
    """Median linear luminance over the used texels of a MEASURE_PX reduction of `px`."""
    luma = _luma(np.concatenate([_downsample(px, side),
                                 np.ones((MEASURE_PX * MEASURE_PX, 1), np.float32)], axis=1))
    return float(np.median(luma[used] if used.any() else luma))


def _pane_pct(px: np.ndarray, side: int, used: np.ndarray) -> float:
    """Share of used texels inside `mc_kit`'s lit-pane luminance band — the window detector's input."""
    luma = _luma(np.concatenate([_downsample(px, side),
                                 np.ones((MEASURE_PX * MEASURE_PX, 1), np.float32)], axis=1))
    sel = luma[used] if used.any() else luma
    return round(100.0 * float(((sel >= PANE_LO) & (sel <= PANE_HI)).mean()), 2)


def albedo(img: bpy.types.Image, band: str, used: Dict[int, np.ndarray],
           aid: str, mask: Optional[np.ndarray] = None,
           mask_side: int = 0,
           pinned: Optional[np.ndarray] = None) -> Tuple[bpy.types.Image, dict]:
    """Grade the albedo in place. Returns the before/after medians for the row + the log line.

    `used` holds the UV-coverage rasters keyed by side: MEASURE_PX for the medians, the image's own
    side for the pane carve. `mask` is `panes.build()`'s window mask at `mask_side`, or None for a
    model with no facade (railings, cover, pipe racks) — those get no panes at all.

    `pinned` marks the texels `facade_tex.repaint()` has already set to the band's wall value. They are
    excluded from the median AND from the gain: the grade's job is to pull the Tripo atlas onto the
    palette, and applying its `target / median` gain to a wall that is already at 0.215 linear put it
    back at 0.32 — outside the 0.15-0.30 the lead asked for (r6 MUST-FIX 1). The pane carve below
    still runs over everything, because a pane is darker than any wall.
    """
    small = used[MEASURE_PX]
    side = img.size[0]
    target, tint_srgb, sat_gain = BANDS.get(band, DEFAULT_BAND)
    px = _pixels(img)
    rgb, luma = px[:, :3].copy(), _luma(px)
    free = _free(small, side, pinned)
    before = _median_luma(px, side, free)
    pane_before = _pane_pct(px, side, small)
    if before <= 1e-4:
        print("  GRADE skip albedo (black atlas)")
        return img, {"luma_before": before, "luma_after": before, "gain": 1.0,
                     "pane_before": pane_before, "pane_after": pane_before}

    gain = float(np.clip(target / before, *GAIN_CLAMP))
    graded = rgb * gain
    # Highlight rolloff: without it a 0.9-linear sheet stays a 0.9-linear sheet after a 0.7 gain and
    # still blooms at dusk. Compresses the top, leaves the mids alone.
    gl = _luma(np.concatenate([graded, np.ones((len(graded), 1), np.float32)], axis=1))
    over = np.maximum(gl - HI_START, 0.0)
    scale = np.where(over > 0.0, (HI_START + over / (1.0 + HI_KNEE * over)) / np.maximum(gl, 1e-5), 1.0)
    graded *= scale[:, None]
    # Saturation: k02's median is 0.043 — a grey. Push it toward the band's hue without going poster.
    gl = _luma(np.concatenate([graded, np.ones((len(graded), 1), np.float32)], axis=1))[:, None]
    graded = gl + (graded - gl) * float(np.clip(sat_gain, *SAT_CLAMP))
    graded *= _tint(tint_srgb)[None, :]
    graded = np.clip(graded, 0.0, 1.0)
    # Keep the pane band: blend back to the original where the texel is dark glass / neon / shadow.
    w = np.clip((luma - GLASS_LO) / max(GLASS_HI - GLASS_LO, 1e-5), 0.0, 1.0)[:, None]
    if pinned is not None:
        w = w * (1.0 - _upscale(pinned, side))[:, None]
    px[:, :3] = rgb * (1.0 - w) + graded * w
    img.pixels.foreach_set(px.reshape(-1))
    carve = darken_panes(img, mask, mask_side)
    px = _pixels(img)
    after = _median_luma(px, side, free)
    pane_after = _pane_pct(px, side, small)
    return _write_jpeg(img, aid, "albedo"), {
        "luma_before": round(before, 4), "luma_after": round(after, 4), "gain": round(gain, 3),
        "pane_before": pane_before, "pane_after": pane_after, "pane_carved": carve,
        "wall_luma": _median_luma(px, side, _pinned_only(small, side, pinned))}


def _upscale(mask: np.ndarray, side: int) -> np.ndarray:
    """Nearest-neighbour resample a square boolean raster to `side` x `side`, flattened."""
    m = mask.reshape(mask.shape[0], mask.shape[0])
    idx = (np.arange(side) * m.shape[0] // max(side, 1)).clip(0, m.shape[0] - 1)
    return m[np.ix_(idx, idx)].reshape(-1).astype(np.float32)


def _free(small: np.ndarray, side: int, pinned: Optional[np.ndarray]) -> np.ndarray:
    """The MEASURE_PX coverage raster minus the repainted texels — what the grade is allowed to move."""
    if pinned is None:
        return small
    return small & ~(_upscale(pinned, MEASURE_PX) > 0.5)


def _pinned_only(small: np.ndarray, side: int, pinned: Optional[np.ndarray]) -> np.ndarray:
    """The repainted texels that the mesh actually covers — the wall-value number the row reports."""
    if pinned is None:
        return np.zeros_like(small)
    return small & (_upscale(pinned, MEASURE_PX) > 0.5)


def flatten_over(img: bpy.types.Image, painted: np.ndarray, rgb: Tuple[float, float, float],
                 aid: str = "", kind: str = "", feather: int = 2) -> Tuple[bpy.types.Image, float]:
    """Replace `img`'s colour with `rgb` over the texels `facade_tex` repainted. Returns the share.

    **Why the normal map and the ORM have to follow the albedo (lead r6 MUST-FIX 1 and 2).** The
    repaint replaces the Tripo albedo with a world-scaled facade field — but the normal map and the
    ORM are baked from the SAME confetti atlas, through the SAME stretched UV islands. Leaving them
    there puts a smeared, high-frequency bump and gloss field under a clean albedo: measured on t01,
    the grazing-sun gate render (`captures/kit/wall_t01.png`) was dominated by soft light and dark
    wedges that follow the atlas's stretched islands, not the geometry, and the near cover pieces
    sparkled black and white at 1K. Flattening both over exactly the repainted texels removes the
    mismatch at its source; the model's own relief survives wherever the geometry is real detail.

    The edge is feathered by `feather` texels so the boundary is a gradient rather than a visible
    rectangle in the specular.
    """
    if painted is None or img is None or img.size[0] <= 0:
        return img, 0.0
    w, h = img.size
    m = _upscale(painted, max(w, h)).reshape(h, w) > 0.5
    if feather > 0:
        m = _dilate(m, feather)
    px = _pixels(img)
    target = np.array(rgb, dtype=np.float32)
    px[:, :3] = np.where(m.reshape(-1, 1), target[None, :], px[:, :3])
    img.pixels.foreach_set(px.reshape(-1))
    img.update()
    pct = round(100.0 * float(m.mean()), 2)
    # Re-save and reload, for the reason `_write_jpeg` exists: the exporter byte-copies a file-backed
    # UNMODIFIED image and re-encodes a dirty buffer at up to 8x the size.
    if aid and kind:
        # A normal map is 8-bit PNG, never JPEG: the ringing a JPEG puts on a flat (0.5, 0.5, 1.0)
        # field is a real tilt in the tangent frame, which is exactly the artefact this pass removes.
        return _write_jpeg(img, aid, kind, fmt="PNG" if kind == "normal" else "JPEG"), pct
    return img, pct


def _dilate(mask: np.ndarray, r: int) -> np.ndarray:
    """Grow a boolean raster by `r` texels in each direction (a separable max filter)."""
    out = mask.copy()
    for _ in range(r):
        out = (out | np.roll(out, 1, 0) | np.roll(out, -1, 0)
               | np.roll(out, 1, 1) | np.roll(out, -1, 1))
    return out


def darken_panes(img: bpy.types.Image, mask: Optional[np.ndarray], mask_side: int) -> float:
    """Pull the masked pane texels toward dark glass. Returns the fraction of the atlas darkened.

    **Why a mask and not a percentile (lead r4 MUST-FIX 2):** r3 took the darkest 7-17 % of each
    atlas, but on a Tripo atlas the darkest texels are crevices, AO creases and seam noise, not
    windows — the shader lit that noise at 1.7 gain and it read as reflections on chrome. `panes.py`
    now stamps a metric grid of 2.0 x 2.4 m rectangles onto the flattened vertical walls, so every
    pane is a real rectangle of a known size and nothing else can become one.

    The albedo is darkened as well as masked because the shader's own `window_mask()` falls back to
    albedo luminance when a model ships without the mask texture — and because a curtain wall has to
    look like glass in daylight too, not like painted-on white.
    """
    if mask is None or mask_side <= 0 or not mask.any():
        return 0.0
    w, h = img.size
    m = mask.reshape(mask_side, mask_side)
    ys = (np.arange(h) * mask_side // max(h, 1)).clip(0, mask_side - 1)
    xs = (np.arange(w) * mask_side // max(w, 1)).clip(0, mask_side - 1)
    mm = m[np.ix_(ys, xs)].reshape(-1, 1)
    px = _pixels(img)
    # GLASS_RGB is normalised to luminance 1, so this lands the pane inside `mc_kit`'s 0.0064-0.0562
    # lit-pane band without changing its hue away from `win_glass` (#131A22).
    target = (GLASS_RGB * (PANE_HI * 0.72))[None, :]
    px[:, :3] = px[:, :3] * (1.0 - mm * PANE_MIX) + target * (mm * PANE_MIX)
    img.pixels.foreach_set(px.reshape(-1))
    return round(100.0 * float((mm > 0.5).mean()), 2)


def orm(img: bpy.types.Image, glass: np.ndarray, glass_size: Tuple[int, int],
        aid: str) -> Tuple[bpy.types.Image, dict]:
    """Roughness floor + metallic cap, in place.

    `glass` is the per-texel keep-original weight measured on the ALBEDO, which is twice the ORM's
    resolution (`kitmat.resize` halves the packed maps), so it is nearest-neighbour resampled here
    rather than passed in at the wrong length.
    """
    px = _pixels(img)
    w, h = img.size
    gw, gh = glass_size
    g = glass.reshape(gh, gw)
    ys = (np.arange(h) * gh // max(h, 1)).clip(0, gh - 1)
    xs = (np.arange(w) * gw // max(w, 1)).clip(0, gw - 1)
    glass_px = g[np.ix_(ys, xs)].reshape(-1, 1)

    before_r = float(np.median(px[:, 1]))
    before_m = float(np.median(px[:, 2]))
    rough = ROUGH_FLOOR + (1.0 - ROUGH_FLOOR) * px[:, 1]
    metal = np.minimum(px[:, 2], METAL_CAP)
    px[:, 1:3] = np.concatenate([rough[:, None], metal[:, None]], axis=1) * glass_px \
        + px[:, 1:3] * (1.0 - glass_px)
    img.pixels.foreach_set(px.reshape(-1))
    return _write_jpeg(img, aid, "orm"), {
        "rough_before": round(before_r, 3), "rough_after": round(float(np.median(px[:, 1])), 3),
        "metal_before": round(before_m, 3), "metal_after": round(float(np.median(px[:, 2])), 3)}


def glass_weight(albedo_img: bpy.types.Image) -> np.ndarray:
    """0 where the albedo texel is dark glass / neon (leave the ORM alone), 1 on the pale surfaces."""
    luma = _luma(_pixels(albedo_img))
    return np.clip((luma - GLASS_LO) / max(GLASS_HI - GLASS_LO, 1e-5), 0.0, 1.0)
