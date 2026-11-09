"""Small numpy raster helpers shared by the cover look: value noise in 3D, a box blur, a box
downsample and the gutter dilation.

Split out of `coverlook.py` for length. They are all O(n) in their radius — a summed-area window rather
than a stencil — because the heavy low-pass runs at a radius of tens of texels on a 1 k x 1 k x 3
raster, where a stencil would be a hundred array adds per pass.
"""
from __future__ import annotations

import math
from typing import Tuple

import numpy as np


def _hash3(x: np.ndarray, y: np.ndarray, z: np.ndarray, seed: float) -> np.ndarray:
    h = np.sin(x * 127.1 + y * 311.7 + z * 74.7 + seed * 39.3) * 43758.5453
    return (h - np.floor(h)).astype(np.float32)


def vnoise(pos: np.ndarray, cell: float, seed: float) -> np.ndarray:
    """Trilinear value noise on the object-space position, one cell per `cell` metres.

    Three-dimensional rather than two so it crosses an island border without a seam: the field is a
    function of where the surface IS, not of how it was unwrapped.
    """
    q = pos / max(cell, 1e-4)
    i = np.floor(q)
    f = q - i
    f = f * f * (3.0 - 2.0 * f)
    out = np.zeros(pos.shape[:2], dtype=np.float32)
    for dz in (0.0, 1.0):
        for dy in (0.0, 1.0):
            for dx in (0.0, 1.0):
                w = ((f[..., 0] if dx else 1.0 - f[..., 0])
                     * (f[..., 1] if dy else 1.0 - f[..., 1])
                     * (f[..., 2] if dz else 1.0 - f[..., 2]))
                out += w * _hash3(i[..., 0] + dx, i[..., 1] + dy, i[..., 2] + dz, seed)
    return out


def _box1(a: np.ndarray, r: int, axis: int) -> np.ndarray:
    """One box blur pass along `axis`, O(n) in the radius (a summed-area window, not a stencil).

    The heavy low-pass runs at a radius of tens of texels on a 1 k x 1 k x 3 raster; a stencil would
    be a hundred array adds per pass and this is two.
    """
    n = a.shape[axis]
    pad = [(0, 0)] * a.ndim
    pad[axis] = (r, r)
    c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis)
    c = np.concatenate([np.zeros_like(np.take(c, [0], axis=axis)), c], axis=axis)
    hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
    lo = np.take(c, np.arange(0, n), axis=axis)
    return ((hi - lo) / float(2 * r + 1)).astype(np.float32)


def blur(a: np.ndarray, r: int) -> np.ndarray:
    """Separable box blur, `r` texels, three passes (a gaussian to a few percent)."""
    if r < 1:
        return a
    return _box1(_box1(_box1(_box1(_box1(_box1(a, r, 0), r, 1), r, 0), r, 1), r, 0), r, 1)


def downsample(a: np.ndarray, factor: int) -> np.ndarray:
    """Box-downsample a (H, W) or (H, W, C) raster by an integer factor."""
    if factor <= 1:
        return a
    h, w = a.shape[0] // factor, a.shape[1] // factor
    return a[:h * factor, :w * factor].reshape(h, factor, w, factor, *a.shape[2:]).mean(axis=(1, 3))


def pad(px: np.ndarray, cov: np.ndarray, texels: int) -> np.ndarray:
    """Grow the covered texels outward into the empty atlas, `texels` deep.

    **This is the whole artefact.** A packed layout of ~8 800 sliver islands leaves ~94 % of the atlas
    empty, and every gutter was BLACK. A 2-texel island minified to mip 3 averages 8x8 texels — mostly
    gutter — so the surface darkened along the island layout, which is the smeared streaks the first
    three r7 prototypes all still had. The albedo was flat per island the whole time; the mip chain was
    painting the gutters over it.

    Iterated 3-tap box dilation rather than one wide blur so the padding FOLLOWS the island it came
    from instead of averaging two neighbours together at a corner.
    """
    out = px
    grown = cov.copy()
    m = grown.astype(np.float32)[..., None]
    for _ in range(max(1, int(math.ceil(texels / 3.0)))):
        num = blur(out * m, 1)
        den = blur(m, 1)
        fill = num / np.maximum(den, 1e-4)
        hit = den[..., 0] > 1e-3
        out = np.where(grown[..., None], out, np.where(hit[..., None], fill, out))
        grown = grown | hit
        m = grown.astype(np.float32)[..., None]
    return out.astype(np.float32)
