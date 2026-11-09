"""The cover kit's palette, taken from the model's own CONCEPT image (lead r8 §1 and §2).

**Why the atlas's colour has to go.** The lead's probe measured k07's shipped albedo at a stored mean
of (0.37, 0.32, 0.26) and k02's at (0.41, 0.35, 0.28): both tan, against concepts that are white and
light grey. A Tripo atlas is warm-biased everywhere, so keeping its hue — which is what r7 did, on
purpose, because the r6 band grade had made twelve concepts read as one brown — keeps every model tan.
The palette has to come from the concept.

**What is transferred, and what is not.** Reinhard's transfer matches the mean AND the standard
deviation of a channel. In Lab:

* **a and b (chroma) are transferred fully.** Chroma in the concept is albedo — the machine really is
  painted that colour — so both statistics mean something.
* **L is NOT transferred, deliberately.** The concept's L standard deviation is 18-27, and almost all
  of that is the studio render's own LIGHTING, not its albedo. Transferring it would paint the
  render's key light into the texture, and it would make no difference anyway: `coverlook.levels()`
  then fits the model's p50 and p97 onto the lead's band, which is a monotone remap of the whole value
  distribution — any earlier L shift is discarded except through the ordering.

**Value comes from the lead's table, not from the concept** (`CLASS_BAND` below), because the concept
is a lit render and the table is albedo. Stored sRGB, from r8 §1:

| class | stored sRGB | what it is |
|---|---|---|
| paint | 0.72-0.80 | white or light grey paint: the k02 tanks, the k07 tank and fins, the k03 crates, the k06 container, the k12 silo |
| steel | 0.25-0.40 | steel frames and dark parts |
| concrete | 0.50-0.60 | concrete |
| wood | 0.40-0.55 | the k08 drums |

Which class a model is, is art direction read off its concept by eye (`CLASS_OF`), not a measurement:
a concept's median value is a mixture of its lit and shadowed sides and says nothing reliable about
albedo. The measured half of this module is the chroma and the accent clusters.
"""
from __future__ import annotations

import json
import os
from typing import Dict, List, Tuple

import numpy as np

ROOT = os.path.expanduser("~/m/mecha-city")
JOBS = os.path.join(ROOT, "art", "tripo", "jobs.json")

#: The lead's r8 §1 table, stored sRGB (lo is the model's p50 target, hi its p97 target).
CLASS_BAND: Dict[str, Tuple[float, float]] = {
    "paint": (0.72, 0.80),
    "steel": (0.25, 0.40),
    "concrete": (0.50, 0.60),
    "wood": (0.40, 0.55),
}
#: Which surface each cover model is mostly made of, read off its concept. See the module docstring
#: for why this is a table and not a measurement.
CLASS_OF: Dict[str, str] = {
    "k01": "paint",      # bone-white armour plate over a bronze machine
    "k02": "paint",      # white tanks on a dark steel cradle
    "k03": "paint",      # light grey crates, dark banding
    "k04": "concrete",   # precast barriers, hazard chevrons drawn by `hazard.py`
    "k05": "steel",      # dark steel plates; khaki sandbags and a red banner are accents
    "k06": "paint",      # white cab and container
    "k07": "paint",      # light grey tank and fins; hazard plinth drawn by `hazard.py`
    "k08": "wood",       # wooden drums; the black cable is a dark accent
    "k09": "steel",      # dark LED screens and lattice over concrete rubble
    "k10": "paint",      # white hoarding panels under blue posters
    "k11": "concrete",   # broken concrete slabs
    "k12": "concrete",   # white silo and grey culvert rings
}
#: A concept pixel above this saturation is an ACCENT (a logo band, an insulator, hazard yellow)
#: rather than part of the painted body, and is protected separately in `coverlook.accent_levels`.
ACCENT_SAT = 0.25
#: The concept's background is a flat light grey; a pixel further than this from the border median is
#: object. 0.055 rather than anything tighter because the backdrops carry a faint vignette.
BG_TOL = 0.055
#: Hue bins for the accent clusters, degrees. 30 deg is fine enough to keep red away from hazard
#: yellow and coarse enough that one logo does not split across a boundary.
HUE_BIN = 30.0
MIN_ACCENT_W = 0.004
#: A near-black pixel's "hue" is noise — its saturation is high and its value is 0.01, and matching a
#: real yellow part to it would paint that part black. Clusters below this value are dropped.
MIN_ACCENT_V = 0.08
#: How far an accent texel is pulled onto its concept cluster's chroma. 1.0 would paste the concept's
#: swatch on and lose the model's own variation; 0.6 keeps the insulator reading as painted metal.
ACCENT_PULL = 0.60

_M_RGB2XYZ = np.array([[0.4124, 0.3576, 0.1805],
                       [0.2126, 0.7152, 0.0722],
                       [0.0193, 0.1192, 0.9505]], dtype=np.float32)
_M_XYZ2RGB = np.linalg.inv(_M_RGB2XYZ.astype(np.float64)).astype(np.float32)
_WHITE = np.array([0.95047, 1.0, 1.08883], dtype=np.float32)


def concept_path(aid: str) -> str:
    """The image that model was actually generated FROM — the registry, not a naming convention.

    Three of the twelve (k04, k10, k11) came from their second candidate, so assuming `-1-1` would
    transfer the wrong palette onto a third of the kit.
    """
    with open(JOBS) as fh:
        jobs = json.load(fh)
    row = jobs.get("kit_" + aid)
    if row is None or not row.get("image"):
        raise KeyError("no Tripo job recorded for kit_%s in %s" % (aid, JOBS))
    return str(row["image"])


def _read(path: str) -> np.ndarray:
    """(H, W, 3) of STORED sRGB values. PIL outside Blender, `bpy` inside it."""
    try:
        from PIL import Image
    except ImportError:
        import bpy
        img = bpy.data.images.load(path, check_existing=False)
        img.colorspace_settings.name = "Non-Color"
        buf = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
        img.pixels.foreach_get(buf)
        px = buf.reshape(img.size[1], img.size[0], 4)[::-1, :, :3].copy()
        bpy.data.images.remove(img)
        return px
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0


def _srgb_to_lin(c: np.ndarray) -> np.ndarray:
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4).astype(np.float32)


def _lin_to_srgb(c: np.ndarray) -> np.ndarray:
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055).astype(np.float32)


def rgb_to_lab(rgb: np.ndarray) -> np.ndarray:
    """sRGB (stored) -> CIE Lab, D65. The last axis may be 3 on any shape."""
    xyz = _srgb_to_lin(rgb.astype(np.float32)) @ _M_RGB2XYZ.T
    t = xyz / _WHITE
    f = np.where(t > 0.008856, np.cbrt(np.maximum(t, 0.0)), 7.787 * t + 16.0 / 116.0)
    return np.stack([116.0 * f[..., 1] - 16.0,
                     500.0 * (f[..., 0] - f[..., 1]),
                     200.0 * (f[..., 1] - f[..., 2])], axis=-1).astype(np.float32)


def lab_to_rgb(lab: np.ndarray) -> np.ndarray:
    fy = (lab[..., 0] + 16.0) / 116.0
    fx = fy + lab[..., 1] / 500.0
    fz = fy - lab[..., 2] / 200.0
    f = np.stack([fx, fy, fz], axis=-1)
    t = np.where(f > 0.206893, f ** 3, (f - 16.0 / 116.0) / 7.787)
    return _lin_to_srgb((t * _WHITE) @ _M_XYZ2RGB.T)


def hue_of(rgb: np.ndarray) -> np.ndarray:
    """Hue in degrees from a plain RGB triple. The same formula `emit_mask._hue` uses, so a band
    classified as hazard yellow here is the same band there."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = rgb.max(axis=-1), rgb.min(axis=-1)
    d = np.maximum(mx - mn, 1e-6)
    h = np.where(mx == r, ((g - b) / d) % 6.0, np.where(mx == g, (b - r) / d + 2.0, (r - g) / d + 4.0))
    return (h * 60.0) % 360.0


def sat_of(rgb: np.ndarray) -> np.ndarray:
    mx = rgb.max(axis=-1)
    return np.where(mx > 1e-5, (mx - rgb.min(axis=-1)) / np.maximum(mx, 1e-5), 0.0)


def object_mask(px: np.ndarray) -> np.ndarray:
    """The object in a concept render: everything that is not the flat light-grey backdrop.

    The backdrop colour is the median of the image border, which is backdrop on every one of these
    images (the object never touches the frame). Erode-then-dilate rather than a bare threshold so a
    single antialiased edge pixel or a dust speck does not enter the statistics.
    """
    h, w = px.shape[:2]
    border = np.concatenate([px[0], px[-1], px[:, 0], px[:, -1]], axis=0)
    bg = np.median(border, axis=0)
    m = np.abs(px - bg).max(axis=-1) > BG_TOL

    def neighbourhood(a: np.ndarray) -> np.ndarray:
        p = np.pad(a, 1)
        return sum(p[i:i + h, j:j + w] for i in range(3) for j in range(3))

    m = neighbourhood(m.astype(np.int32)) >= 6      # erode: drop specks and lone edge pixels
    return neighbourhood(m.astype(np.int32)) >= 1   # dilate back


def measure(aid: str) -> Dict[str, object]:
    """The palette of one cover model: its class band, its chroma statistics and its accent clusters.

    Everything is measured on the OBJECT pixels of the concept only — the backdrop is 50-80 % of these
    images and its grey would otherwise set the chroma mean to exactly neutral, which is the same
    nothing-happens failure as keeping the atlas's hue.
    """
    path = concept_path(aid)
    px = _read(path)
    m = object_mask(px)
    if m.sum() < 256:
        raise ValueError("concept %s: the object mask covers %d pixels" % (path, int(m.sum())))
    obj = px[m]
    lab = rgb_to_lab(obj)
    sat = sat_of(obj)
    base = sat < ACCENT_SAT
    if base.sum() < 64:
        base = np.ones_like(base)
    pal: Dict[str, object] = {
        "id": aid,
        "image": os.path.basename(path),
        "class": CLASS_OF.get(aid, "steel"),
        "cover_pct": round(100.0 * float(m.mean()), 2),
        "ab_mean": [round(float(v), 3) for v in lab[base][:, 1:].mean(axis=0)],
        "ab_std": [round(float(v), 3) for v in lab[base][:, 1:].std(axis=0)],
        "base_v": round(float(np.median(obj[base].max(axis=-1))), 4),
    }
    pal["band"] = list(CLASS_BAND[str(pal["class"])])
    pal["accents"] = _accents(obj, sat, ~base)
    return pal


def _accents(obj: np.ndarray, sat: np.ndarray, acc: np.ndarray) -> List[Dict[str, float]]:
    """The concept's saturated clusters: hue bin -> median chroma, saturation, value and weight.

    These are what `coverlook.accent_levels` protects. Without them the lead's §1 levels lift a dark
    red insulator to the same 0.72-0.80 as the white tank it sits on, and the model loses every
    colour its concept had.
    """
    if acc.sum() < 32:
        return []
    hue = hue_of(obj)
    bins = (hue[acc] // HUE_BIN).astype(np.int32)
    lab = rgb_to_lab(obj[acc])
    out: List[Dict[str, float]] = []
    for k in np.unique(bins):
        sel = bins == k
        w = float(sel.mean()) * float(acc.mean())
        val = float(np.median(obj[acc][sel].max(axis=-1)))
        if w < MIN_ACCENT_W or val < MIN_ACCENT_V:
            continue
        out.append({"hue": round(float(np.median(hue[acc][sel])), 1),
                    "a": round(float(np.median(lab[sel][:, 1])), 3),
                    "b": round(float(np.median(lab[sel][:, 2])), 3),
                    "sat": round(float(np.median(sat[acc][sel])), 3),
                    "val": round(val, 4),
                    "w": round(w, 4)})
    out.sort(key=lambda c: -c["w"])
    return out[:4]


def reinhard(face_rgb: np.ndarray, pal: Dict[str, object]) -> Tuple[np.ndarray, Dict[str, float]]:
    """Transfer the concept's CHROMA onto the model's low-passed per-face colour (lead r8 §2.1).

    Affine in (a, b), matching both the mean and the standard deviation of the concept's own body
    pixels. L is left alone — see the module docstring. Faces whose saturation is over `ACCENT_SAT`
    are additionally pulled onto their nearest concept cluster (`ACCENT_PULL`), which is what keeps a
    red insulator red rather than merely warm.
    """
    lab = rgb_to_lab(face_rgb)
    ref_mean = np.array(pal["ab_mean"], dtype=np.float32)
    ref_std = np.maximum(np.array(pal["ab_std"], dtype=np.float32), 0.5)
    src_mean = lab[:, 1:].mean(axis=0)
    src_std = np.maximum(lab[:, 1:].std(axis=0), 0.5)
    out = lab.copy()
    out[:, 1:] = (lab[:, 1:] - src_mean) * (ref_std / src_std) + ref_mean

    clusters = list(pal.get("accents") or [])
    sat = sat_of(face_rgb)
    acc = sat > ACCENT_SAT
    pulled = 0.0
    if clusters and acc.any():
        hue = hue_of(face_rgb)
        ch = np.array([c["hue"] for c in clusters], dtype=np.float32)
        d = np.abs((hue[:, None] - ch[None, :] + 180.0) % 360.0 - 180.0)
        near = np.argmin(d, axis=1)
        for i, c in enumerate(clusters):
            sel = acc & (near == i)
            if not sel.any():
                continue
            tgt = np.array([c["a"], c["b"]], dtype=np.float32)
            out[sel, 1:] += (tgt[None, :] - out[sel, 1:]) * ACCENT_PULL
            pulled += float(sel.mean())
    rgb = np.clip(lab_to_rgb(out), 0.0, 1.0)
    stats = {"ab_mean": [round(float(v), 3) for v in src_mean],
             "ab_std": [round(float(v), 3) for v in src_std],
             "ab_ref": [round(float(v), 3) for v in ref_mean],
             "accent_pct": round(100.0 * float(acc.mean()), 2),
             "accent_pull_pct": round(100.0 * pulled, 2)}
    return rgb, stats
