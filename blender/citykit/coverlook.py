"""The arena cover kit's look: a procedural layer at metre scale over the low-passed Tripo bake, with
a palette taken from the CONCEPT (lead r7 §1, re-graded by r8 §1-§3).

The order matters, and the reason it does is the whole diagnosis:

* **Value comes from a HEAVY low-pass, chroma from a LIGHT one** (`covertex.diffuse`). A Tripo island
  carries its own baked shading, and that shading is what the lead photographed as wedges — it is a
  VALUE artefact, so it needs a blur wide enough to flatten a whole island (measured in METRES, not
  texels, because an island's size in texels depends on how the atlas happened to be packed). A logo
  band is CHROMA and is diffused far more tightly, or it smears into the grey around it.
* **Colour comes from the concept, value from the lead's table.** `concept.reinhard` transfers the
  concept's Lab chroma onto the low-passed bake — r7 kept the atlas's hue on purpose, and the atlas is
  warm-biased everywhere, so every model shipped tan (measured: k07 at stored (0.37, 0.32, 0.26)).
  The VALUE is then fitted onto `concept.CLASS_BAND`, which is the lead's r8 §1 table in stored sRGB:
  white paint 0.72-0.80, concrete 0.50-0.60, wood 0.40-0.55, steel 0.25-0.40. r7 read that table as
  sRGB when it is linear albedo, and shipped a white tank at 0.21 linear — mid-grey under a dusk sun.
* **Accents are exempt from the band.** A saturated face is matched to a concept accent cluster by hue
  and levelled onto THAT cluster's value, so a dark red insulator stays dark red on a white tank.
* **The band is a range, so the value is compressed into it** (`soft_band`). The two-point fit is
  monotone and preserves structure — including the structure of a bake shadow too large for any
  diffusion to flatten, which is what left near-black smears across k07's tank.
* **Procedural last.** Panel seams and bays, edge wear on convex edges, grime toward the base, all at
  metre scale from `coverraster.geom`'s rasters, then the hazard bands (`hazard.py`) drawn straight
  over the top — a 0.5 m band cannot survive a 0.45 m chroma blur, so it is painted, not preserved.

All of it is numpy on rasters, so it is deterministic and needs no further bakes.
"""
from __future__ import annotations

import math
import os
from typing import Dict, List, Optional, Tuple

import numpy as np

from raster import blur, downsample, pad, vnoise

#: Fallback value band, in the SAME units every other number in this pipeline is measured in
#: (`grade._pixels` on a byte sRGB image = the stored sRGB value), for a model with no concept row.
#: A real cover model takes its band from `concept.CLASS_BAND` — the lead's r8 §1 table. This is the
#: steel row of that table, which is the safe middle for an unclassified prop.
MID_V, HI_V = 0.25, 0.40
GAMMA_CLAMP = (0.45, 1.80)
GAIN_CLAMP = (0.15, 6.0)
#: The heavy low-pass, in METRES of surface. A Tripo island's own baked shading is a gradient over
#: roughly this much of the model, so this is the radius that flattens it; anything smaller leaves the
#: wedges and anything much larger merges neighbouring parts.
HEAVY_M = 0.22
LIGHT_M = 0.035
#: How much of the light copy's chroma is added back. Slightly over 1 because the heavy blur also
#: desaturates whatever it touches.
CHROMA_GAIN = 1.15

#: Panel seam pitch and width in metres. The width is a REQUEST: `lines` floors it at one texel, and
#: the real density here is 121 mm per texel on k07 (measured on the shipped glb), so the narrowest
#: seam that can be drawn at all is ~260 mm. At r7's 1.20 m pitch that floor turned the "seam" into a
#: broad 30 %-deep modulation over a third of the surface — the soft dark diagonal smudges the studio
#: render showed and `COVER_STAGE=levels` proved were the seam layer and nothing else. The pitch is
#: therefore 2.4 m, which is a plausible panel size AND puts the line at 11 % of its own period.
SEAM_M, SEAM_W = 2.40, 0.100
BAY_M, BAY_W = 7.20, 0.180        # the coarser structural joint
SEAM_DARK, BAY_DARK = 0.14, 0.10  # how much value each takes out
SEAM_DEPTH, BAY_DEPTH = 0.020, 0.038   # metres, for the normal map
HAZARD_ROUGH = 0.42               # a painted hazard band is glossier than what it is painted on
GRIME_H = 2.4                     # metres of base grime
GRIME_DARK = 0.22
WEAR_LIFT = 0.35                  # how far a worn convex edge lightens
#: How far outside the lead's band a texel may sit before `soft_band` compresses it, and how hard the
#: knee bites. Both are small on purpose: the lead's band is a RANGE, and the wider the shipped range
#: the more high-frequency contrast the cover adds over a plain albedo — which is exactly what
#: `tools/citykit/wedge.py` gates at 1.5x. At slack 0.10 / knee 0.25 the A5deck wedge measured 1.73;
#: the mean is unchanged by this, only the spread.
BAND_SLACK = 0.05
BAND_KNEE = 0.15
WEAR_METAL, WEAR_ROUGH = 0.42, 0.34
#: The remap the baked ORM green is pulled into. Narrow on purpose: a Tripo ORM carries its bake's
#: own large-scale gloss variation, and at (0.48, 0.88) that showed up in the studio render as soft
#: dark diagonal creases across k07's flat tank panels — with a FLAT material the same glb renders
#: clean, which is what localised it to the maps. A painted machine is uniformly semi-gloss.
BASE_ROUGH = (0.52, 0.70)
SLOPE_CLAMP = 1.6                 # tangent-space slope cap; island borders have no valid gradient
NOISE_SEED = 17.0
#: How far the composed albedo is dilated into the empty atlas, in texels. See `pad` — this is the
#: difference between a flat painted panel and the smeared streaks the first prototypes shipped.
PAD_PX = 16


def _luma(rgb: np.ndarray) -> np.ndarray:
    return (rgb * np.array([0.2126, 0.7152, 0.0722], np.float32)).sum(axis=2)


def levels(v: np.ndarray, cov: np.ndarray, lo: float, hi: float
           ) -> Tuple[np.ndarray, Dict[str, float]]:
    """The two-point fit as a per-texel SCALE on `v = max(rgb)`, plus the numbers for the row.

    `lo` and `hi` are the lead's r8 §1 band for the model's surface class, in STORED sRGB — the same
    units every other number in this pipeline is measured in (`grade._pixels` on a byte sRGB image).
    r7 fitted p50 -> 0.20 and p97 -> 0.50 here, reading the lead's "painted white steel at 0.45-0.55"
    as sRGB; it is LINEAR albedo, so 0.50 sRGB is 0.21 linear and a white tank shipped mid-grey. The
    bands now come from `concept.CLASS_BAND`.
    """
    sel = v[cov]
    if sel.size < 16:
        return np.ones_like(v), {"fit": 0}
    p50 = float(np.percentile(sel, 50.0))
    p97 = float(np.percentile(sel, 97.0))
    if p50 <= 1e-4 or p97 <= p50 * 1.02:
        return np.ones_like(v), {"p50": round(p50, 4), "p97": round(p97, 4), "fit": 0}
    g = float(np.clip(np.log(hi / lo) / np.log(p97 / p50), *GAMMA_CLAMP))
    a = float(np.clip(lo / (p50 ** g), *GAIN_CLAMP))
    scale = np.where(v > 1e-5, a * np.power(np.maximum(v, 1e-5), g) / np.maximum(v, 1e-5), 0.0)
    return scale.astype(np.float32), {"p50": round(p50, 4), "p97": round(p97, 4),
                                      "gamma": round(g, 3), "gain": round(a, 3), "fit": 1}


def accent_gain(v: np.ndarray, sel: np.ndarray, target: float) -> np.ndarray:
    """A flat gain that puts one accent group's MEDIAN value on its concept cluster's value.

    A gain rather than the base's two-point fit: an accent is a small, flat, painted region (a logo
    band, an insulator, hazard yellow) and there is no value structure inside it worth preserving —
    but there IS a structure worth not destroying, because the same cluster's texels are spread over
    the whole model. Lifting a dark red insulator to the white tank's 0.72-0.80 is what this exists
    to prevent (lead r8 §2.2).
    """
    vals = v[sel]
    if vals.size < 12:
        return np.ones_like(v)
    med = float(np.median(vals))
    if med <= 1e-4:
        return np.ones_like(v)
    return np.full_like(v, float(np.clip(target / med, *GAIN_CLAMP)))


def plane_axes(pos: np.ndarray, nrm: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
    """Per-texel (u, v) in METRES along the two axes least aligned with the surface normal.

    The same trick `lib.uv.box_uv` uses, evaluated per texel: the face's dominant normal axis is
    dropped and the other two position components become its plane coordinates. It is continuous
    across a whole axis-aligned region, which is what a panel seam has to be.
    """
    order = np.argsort(-np.abs(nrm), axis=2)
    u = np.take_along_axis(pos, order[..., 1:2], axis=2)[..., 0]
    v = np.take_along_axis(pos, order[..., 2:3], axis=2)[..., 0]
    return u, v


def lines(x: np.ndarray, period: float, width: float, mpt: np.ndarray) -> np.ndarray:
    """A soft line every `period` metres along `x`, never narrower than one texel.

    The `max(width/2, mpt)` floor is the lesson from r5/r6: a 0.16 m storey line came out 0.3 texels
    wide on a Tripo atlas and averaged away to nothing. A feature narrower than a texel cannot be
    drawn, so it is drawn one texel wide instead.
    """
    d = np.abs(((x / period + 0.5) % 1.0) - 0.5) * period
    half = np.maximum(width * 0.5, mpt * 1.1)
    soft = np.maximum(mpt * 0.8, 1e-4)
    return np.clip((half + soft - d) / np.maximum(2.0 * soft, 1e-5), 0.0, 1.0)


def accent_scale(rgb: np.ndarray, v: np.ndarray, acc: np.ndarray, cov: np.ndarray,
                 clusters: List[Dict[str, float]]) -> Tuple[np.ndarray, Dict[str, float]]:
    """The per-texel scale for the ACCENT texels: each group onto its own concept cluster's value.

    A model accent is matched to a concept cluster by HUE, which survives the trip between a
    photogrammetry atlas and a studio render in a way a nearest-RGB match does not — the two differ
    by exactly the warm bias this whole pass exists to remove.

    Without this, `levels` lifts a dark red insulator onto the same 0.72-0.80 as the white tank it is
    bolted to and the model loses every colour its concept had (lead r8 §2.2).
    """
    import concept

    scale = np.ones_like(v)
    sel_all = acc & cov
    stats: Dict[str, float] = {"accent_pct": round(100.0 * float(sel_all.mean()), 2),
                               "accent_groups": 0}
    if not clusters or not sel_all.any():
        return scale, stats
    hue = concept.hue_of(rgb)
    ch = np.array([float(c["hue"]) for c in clusters], dtype=np.float32)
    d = np.abs((hue[..., None] - ch[None, None, :] + 180.0) % 360.0 - 180.0)
    near = np.argmin(d, axis=2)
    for i, c in enumerate(clusters):
        sel = sel_all & (near == i)
        if int(sel.sum()) < 12:
            continue
        scale = np.where(sel, accent_gain(v, sel, float(c["val"])), scale)
        stats["accent_groups"] = int(stats["accent_groups"]) + 1
        stats["acc%d_pct" % i] = round(100.0 * float(sel.mean()), 2)
        stats["acc%d_val" % i] = round(float(c["val"]), 3)
    return scale, stats


def soft_band(v: np.ndarray, lo: float, hi: float, knee: float = BAND_KNEE) -> np.ndarray:
    """Compress the value into the lead's band instead of letting a dark patch stay dark.

    The two-point fit is monotone, so it preserves STRUCTURE — including the structure of the Tripo
    bake's own large-scale shading, and a 2 m diffusion cannot flatten a shadow that covers half a
    16 m machine. On k07 that left near-black smears across a tank the concept paints one light grey.

    This is the other half of r8 §1: the table is a RANGE, so the value is pulled into it. A knee
    rather than a clip, because a clip turns every over-range texel into the same value and the
    gradient inside a face — which the lead accepted in r7 — disappears with it. `BAND_SLACK` is how
    far outside the band a texel may still sit before the knee engages.
    """
    top = hi + BAND_SLACK
    bot = max(lo - BAND_SLACK, 0.02)
    return np.where(v > top, top + (v - top) * knee,
                    np.where(v < bot, bot - (bot - v) * knee, v)).astype(np.float32)


def build(face_rgb: np.ndarray, face_orm: np.ndarray, g: Dict[str, np.ndarray],
          orm_side: int, nrm_side: int, pal: Optional[Dict[str, object]] = None,
          acc_face: Optional[np.ndarray] = None, aid: str = "") -> Dict[str, object]:
    """Compose the cover's albedo / ORM / normal from the diffused per-face colour and the rasters.

    `face_rgb` / `face_orm` are already low-passed in 3D by `covertex.diffuse` and colour-transferred
    onto the concept by `concept.reinhard`, so there is no blur here at all — every texel takes its
    own face's value, the levels fit sets its class band, and the procedural layer goes on top.
    """
    import hazard

    cov, fid = g["cov"], g["fid"]
    pos, mpt = g["pos"], np.maximum(g["mpt"], 1e-4)
    side = cov.shape[0]
    safe = np.maximum(fid, 0)
    alb = face_rgb[safe]
    orm = face_orm[safe]
    band = tuple(pal["band"]) if pal else (MID_V, HI_V)
    acc = (acc_face[safe] if acc_face is not None
           else np.zeros(fid.shape, dtype=bool))
    v = alb.max(axis=2)
    scale, fit = levels(v, cov & ~acc, float(band[0]), float(band[1]))
    ascale, astats = accent_scale(alb, v, acc, cov, list((pal or {}).get("accents") or []))
    scale = np.where(acc, ascale, scale)
    rgb = np.clip(alb * scale[..., None], 0.0, 1.0)
    # The band is a RANGE (lead r8 §1), so the base value is compressed into it. Accents are exempt:
    # a dark red insulator is supposed to be outside the white tank's band.
    base = ~acc
    vb = soft_band(rgb.max(axis=2), float(band[0]), float(band[1]))
    rgb = np.where(base[..., None], rgb * (vb / np.maximum(rgb.max(axis=2), 1e-5))[..., None], rgb)
    rgb = np.clip(rgb, 0.0, 1.0)
    diag = {"alb_v_std": round(float(alb.max(axis=2)[cov].std()), 4),
            "alb_v_p05": round(float(np.percentile(alb.max(axis=2)[cov], 5.0)), 4),
            "alb_v_p95": round(float(np.percentile(alb.max(axis=2)[cov], 95.0)), 4),
            "band": [round(float(band[0]), 3), round(float(band[1]), 3)],
            "class": str((pal or {}).get("class", "steel"))}

    u, vv = plane_axes(pos, g["nrm"])
    seam = np.maximum(lines(u, SEAM_M, SEAM_W, mpt), lines(vv, SEAM_M, SEAM_W, mpt))
    bay = np.maximum(lines(u, BAY_M, BAY_W, mpt), lines(vv, BAY_M, BAY_W, mpt))
    grain = vnoise(pos, 0.45, NOISE_SEED)
    coarse = vnoise(pos, 3.10, NOISE_SEED + 5.0)
    wear = np.clip(g["wear"], 0.0, 1.0) * np.clip(0.35 + 1.3 * grain, 0.0, 1.0)
    z = pos[..., 2]
    z0 = float(z[cov].min()) if cov.any() else 0.0
    grime = np.clip(1.0 - (z - z0) / GRIME_H, 0.0, 1.0) ** 1.6
    grime = np.clip(grime * np.clip(0.30 + 1.5 * blur(coarse, 2), 0.0, 1.2), 0.0, 1.0)

    stage = os.environ.get("COVER_STAGE", "")
    if stage != "levels":
        rgb = rgb * (1.0 - SEAM_DARK * seam - BAY_DARK * bay)[..., None]
    if stage not in ("levels", "seam"):
        ceil = float(band[1]) + BAND_SLACK
        rgb = rgb + (np.minimum(rgb * 1.85 + 0.05, ceil) - rgb) * (WEAR_LIFT * wear)[..., None]
        rgb = rgb * (1.0 - GRIME_DARK * grime)[..., None]
    rgb, hz, hz_stats = hazard.draw(rgb, pos, g["nrm"], cov, mpt, u, vv, aid)
    rgb = pad(rgb, cov, PAD_PX)

    fields = {"seam": seam, "bay": bay, "wear": wear, "grime": grime, "hazard": hz}
    packed, normal = orm_normal(orm, fields, mpt, grain, fid, orm_side, nrm_side, side)
    stats = {"fit": fit, **astats, **hz_stats, **diag,
             "seam_pct": round(100.0 * float((seam > 0.5)[cov].mean()), 2) if cov.any() else 0.0,
             "wear_pct": round(100.0 * float((wear > 0.4)[cov].mean()), 2) if cov.any() else 0.0,
             "grime_pct": round(100.0 * float((grime > 0.4)[cov].mean()), 2) if cov.any() else 0.0,
             "cover_pct": round(100.0 * float(cov.mean()), 2)}
    if cov.any():
        val = rgb.max(axis=2)[cov]
        stats["v_p50"] = round(float(np.percentile(val, 50.0)), 4)
        stats["v_p97"] = round(float(np.percentile(val, 97.0)), 4)
        stats["luma_p50"] = round(float(np.percentile(_luma(rgb)[cov], 50.0)), 4)
    return {"rgb": np.clip(rgb, 0.0, 1.0), "orm": packed, "normal": normal, "stats": stats,
            "fields": {"seam": seam, "bay": bay, "wear": wear, "grime": grime, "hazard": hz,
                       "flat": np.clip(alb, 0.0, 1.0)}}


def island_gradient(h: np.ndarray, fid: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
    """Forward differences of `h` that only reach inside ONE FACE.

    `np.gradient` across a face border differences two unrelated heights, and on this kit that is most
    texels: a 12 k-tri prop over 6 % of a 1 k atlas means nearly every texel has a border neighbour.
    Every one of those produced a full-scale slope, and the clamped result is the swirl of light and
    dark facets the first r7 prototype still had — the normal map, not the albedo.
    """
    gy = np.zeros_like(h)
    gx = np.zeros_like(h)
    same_y = fid[1:, :] == fid[:-1, :]
    same_x = fid[:, 1:] == fid[:, :-1]
    gy[:-1, :] = np.where(same_y, h[1:, :] - h[:-1, :], 0.0)
    gx[:, :-1] = np.where(same_x, h[:, 1:] - h[:, :-1], 0.0)
    return gy, gx


def orm_normal(orm: np.ndarray, f: Dict[str, np.ndarray], mpt: np.ndarray, grain: np.ndarray,
               fid: np.ndarray, orm_side: int, nrm_side: int,
               side: int) -> Tuple[np.ndarray, np.ndarray]:
    """The packed ORM and the tangent-space normal map, both from the same procedural fields.

    The normal is computed from a HEIGHT in metres divided by `mpt`, which is why it needs no bake:
    `covertex.geom` reports each texel's metres-per-texel from the UV->3D Jacobian, so a 12 mm seam is
    a 12 mm seam on an island that got 20 texels and on one that got 400. The slopes are clamped
    because a texel on a face BORDER has no valid neighbour to difference against.
    """
    seam, bay, wear, grime = f["seam"], f["bay"], f["wear"], f["grime"]
    hz = f.get("hazard")
    rough = BASE_ROUGH[0] + (BASE_ROUGH[1] - BASE_ROUGH[0]) * np.clip(orm[..., 1], 0.0, 1.0)
    metal = np.minimum(orm[..., 2], 0.35)
    rough = np.clip(rough + 0.12 * seam + 0.10 * bay, 0.0, 1.0)
    rough = rough * (1.0 - wear) + WEAR_ROUGH * wear
    rough = rough * (1.0 - grime) + 0.92 * grime
    metal = metal * (1.0 - wear) + WEAR_METAL * wear
    if hz is not None:
        # A painted hazard band is glossier than the concrete or the weathered steel under it, and it
        # is PAINT: it carries none of the panel relief, so the seam and bay depth are cancelled
        # inside it rather than showing through the stripes.
        rough = rough * (1.0 - hz) + HAZARD_ROUGH * hz
        metal = metal * (1.0 - hz)
    packed = np.stack([np.ones_like(rough), np.clip(rough, 0.05, 1.0), np.clip(metal, 0.0, 1.0)],
                      axis=-1)

    relief = (1.0 - hz) if hz is not None else 1.0
    height = (-SEAM_DEPTH * seam - BAY_DEPTH * bay + 0.004 * wear
              + 0.0025 * (grain - 0.5) - 0.003 * grime) * relief
    gy, gx = island_gradient(height, fid)
    sx = downsample(np.clip(gx / mpt, -SLOPE_CLAMP, SLOPE_CLAMP), side // nrm_side)
    sy = downsample(np.clip(gy / mpt, -SLOPE_CLAMP, SLOPE_CLAMP), side // nrm_side)
    packed = downsample(packed, side // orm_side)
    n = np.stack([-sx, -sy, np.ones_like(sx)], axis=-1)
    n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-6)
    return np.clip(packed, 0.0, 1.0), np.clip(n * 0.5 + 0.5, 0.0, 1.0)
