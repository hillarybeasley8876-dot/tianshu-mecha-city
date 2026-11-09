"""The lead's r6 MUST-FIX 1 gate, measured on the SHIPPED glb: a flat wall must shade as one value.

    python3 tools/citykit/normalqa.py game/world/kit/t01/t01.glb ...

`meshqa.py` answers "is the surface flat" (geometry). This answers the question the player actually
sees: **inside one planar region, does the shading term vary?** A wall can be geometrically perfect
and still render as a patchwork of light and dark wedges, because the shading normal is an average
taken across the region's border and over the collapse's slivers — that is what the lead photographed
at T1fac and A4st (`captures/lead_r6pre_st_*`).

The measurement:

1. rebuild the model's planar regions from the shipped triangles with the same rule `planar.flatten()`
   used (welded neighbours, coplanar within `REGION_DEG`, one connected blob per region);
2. for a fixed sun direction `L`, evaluate `dot(N, L)` at every VERTEX of every triangle in the region,
   using the NORMAL attribute the glb actually carries;
3. report, per region, `(max - min) / |mean|` — the shading spread — and aggregate it area-weighted.

The lead's gate is **under 2 %**. Regions smaller than `MIN_AREA` are reported separately rather than
folded in: a 0.5 m^2 patch of wall between two balconies cannot show a wedge and would only dilute the
number.
"""
from __future__ import annotations

import sys
from typing import Dict, List, Tuple

import numpy as np

from meshqa import load

#: Two welded triangles belong to one planar region when their normals agree this closely. 12 deg
#: is "a viewer reads these as one plane": wide enough to hold a wall the reconstruction left a few
#: degrees of wobble on, far too tight to cross a corner, a cornice or a balcony return.
REGION_DEG = 12.0
#: ... and the region has to be worth measuring, in square metres of surface.
MIN_AREA = 4.0
#: The gate, as a percentage of the region's own mean shading term.
GATE_PCT = 2.0
#: ... and in absolute terms, as a fraction of the full `dot(N, L)` range. This is the number that
#: catches a wedge on a wall the sun grazes, where the relative gate is meaningless.
GATE_ABS = 0.03
#: A region whose mean shading term is below this is not lit by the key light; it is measured by the
#: absolute gate only (see `spread`).
LIT_MIN = 0.25
#: The share of LIT WALL AREA that must be inside the 2 % gate. The mean is reported but not gated: a
#: tail of 2 m2 patches between two balconies can pull a mean anywhere and the eye reads area.
AREA_OK = 95.0
#: A grazing dusk sun, roughly the city's key light. The spread is a property of the normals, not of
#: this vector, but a sun that grazes the wall is the worst case and the one the lead shot in.
SUN = np.array([0.42, -0.36, 0.83])


def regions(tris: np.ndarray) -> Tuple[np.ndarray, np.ndarray, Dict[int, int]]:
    """Label every triangle with a planar region id (-1 for none).

    Two triangles join when they share a welded edge and their normals are within `REGION_DEG`. This
    is a stricter test than `planar.flatten()`'s assignment (which allows 25 deg and 0.6 m), so it
    measures the region the flattening pass actually PRODUCED rather than the one it hoped for.
    """
    g = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    area = 0.5 * np.linalg.norm(g, axis=1)
    g = g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-12)
    flat = tris.reshape(-1, 3)
    _, inv = np.unique(np.round(flat, 3), axis=0, return_inverse=True)
    faces = inv.reshape(-1, 3)
    edges: Dict[Tuple[int, int], List[int]] = {}
    for i, (a, b, c) in enumerate(faces):
        for u, v in ((a, b), (b, c), (c, a)):
            edges.setdefault((min(u, v), max(u, v)), []).append(i)
    cos_r = np.cos(np.radians(REGION_DEG))
    parent = list(range(len(tris)))

    def find(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for pair in edges.values():
        if len(pair) != 2:
            continue
        i, j = pair
        # NOT abs(): the two faces of a 20 cm balcony slab are exactly antiparallel and share an edge
        # at the slab's rim. Merging them makes one "region" whose shading term runs from +0.5 to -0.5
        # and reports a 200 % spread on a surface that is perfectly flat.
        if float(g[i].dot(g[j])) < cos_r:
            continue
        a, b = find(i), find(j)
        if a != b:
            parent[a] = b
    label = np.array([find(i) for i in range(len(tris))])
    return label, area, {int(k): int(v) for k, v in zip(*np.unique(label, return_counts=True))}


def corner_range(norms: np.ndarray, area: np.ndarray) -> Tuple[float, float]:
    """Per-TRIANGLE corner range of `dot(N, L)` — the region-free half of the gate.

    A triangle whose three corners carry three different normals is shaded as a gradient across
    itself, which is the wedge the lead photographed. No region definition is involved, so this number
    cannot be made to look good by choosing the regions carefully. Returns (area-weighted mean,
    95th percentile by area).
    """
    if not np.any(np.abs(norms) > 1e-9):
        return 0.0, 0.0
    n = norms / np.maximum(np.linalg.norm(norms, axis=2, keepdims=True), 1e-12)
    term = (n * SUN[None, None, :]).sum(2)
    rng = term.max(axis=1) - term.min(axis=1)
    w = area / max(area.sum(), 1e-12)
    order = np.argsort(rng)
    cw = np.cumsum(w[order])
    p95 = float(rng[order][int(np.searchsorted(cw, 0.95))])
    return float((rng * w).sum()), p95


def spread(tris: np.ndarray, norms: np.ndarray, label: np.ndarray,
           area: np.ndarray) -> List[dict]:
    """Per-region shading spread: (max - min) of `dot(N, L)` over the region's corners.

    Two numbers, because they answer different questions:

    * `spread_pct` is the lead's gate — `(max - min) / |mean|`, in percent. It is only meaningful
      where the sun actually lights the wall: a wall the sun grazes has a mean near zero, so a
      hundredth of absolute variation is a huge RELATIVE number on a surface that is dark either way.
      Regions with `|mean| < LIT_MIN` are therefore excluded from the gate and counted separately.
    * `spread_abs` is the same range in absolute terms, which is what the eye reads on any wall
      whatever its orientation, and is the number that catches a wedge on a shadowed facade.
    """
    if not np.any(np.abs(norms) > 1e-9):
        return []
    ln = np.linalg.norm(norms, axis=2, keepdims=True)
    n = norms / np.maximum(ln, 1e-12)
    term = (n * SUN[None, None, :]).sum(2)          # (tri, 3) — one value per triangle corner
    out: List[dict] = []
    for rid in np.unique(label):
        sel = label == rid
        a = float(area[sel].sum())
        if a < MIN_AREA:
            continue
        vals = term[sel].reshape(-1)
        mean = float(vals.mean())
        rng = float(vals.max() - vals.min())
        out.append({"id": int(rid), "area": a, "tris": int(sel.sum()), "mean": mean,
                    "spread_abs": rng,
                    "spread_pct": (100.0 * rng / abs(mean)) if abs(mean) >= LIT_MIN else float("nan")})
    out.sort(key=lambda r: -r["area"])
    return out


def report(path: str, top: int = 5) -> dict:
    tris, norms = load(path)
    if len(tris) == 0:
        return {"path": path, "regions": 0, "area_pct": 0.0, "worst": 0.0, "wmean": 0.0,
                "absmean": 0.0, "lit_area_pct": 0.0, "top": []}
    label, area, _counts = regions(tris)
    regs = spread(tris, norms, label, area)
    total = float(area.sum())
    covered = sum(r["area"] for r in regs)
    if not regs:
        return {"path": path, "regions": 0, "area_pct": 0.0, "worst": 0.0, "wmean": 0.0,
                "absmean": 0.0, "lit_area_pct": 0.0, "top": []}
    lit = [r for r in regs if r["spread_pct"] == r["spread_pct"]]      # not NaN
    lit_area = sum(r["area"] for r in lit)
    wmean = (sum(r["spread_pct"] * r["area"] for r in lit) / lit_area) if lit_area else 0.0
    ok_area = sum(r["area"] for r in lit if r["spread_pct"] <= GATE_PCT)
    absmean = sum(r["spread_abs"] * r["area"] for r in regs) / max(covered, 1e-9)
    cmean, cp95 = corner_range(norms, area)
    return {"path": path, "regions": len(regs), "area_pct": 100.0 * covered / max(total, 1e-9),
            "worst": max((r["spread_pct"] for r in lit), default=0.0), "wmean": wmean,
            "absmean": absmean, "lit_area_pct": 100.0 * lit_area / max(total, 1e-9),
            "area_ok": 100.0 * ok_area / max(lit_area, 1e-9),
            "corner_mean": cmean, "corner_p95": cp95, "top": regs[:top]}


def main(argv: List[str]) -> int:
    paths = [a for a in argv if not a.startswith("-")]
    if not paths:
        print(__doc__)
        return 2
    print("%-16s %5s %6s %5s %7s %7s %7s %7s %7s   %s"
          % ("glb", "regs", "area%", "lit%", "ok%", "wmean%", "absmean", "corner", "c95",
             "worst regions (area m2 / spread %)"))
    bad = 0
    for p in paths:
        try:
            r = report(p)
        except (OSError, ValueError, KeyError, IndexError) as exc:
            print("%-24s  FAILED: %s" % (p.split("/")[-1], exc))
            bad += 1
            continue
        worst = sorted((w for w in r["top"] if w["spread_pct"] == w["spread_pct"]),
                       key=lambda x: -x["spread_pct"])[:3]
        print("%-16s %5d %6.1f %5.1f %7.1f %7.2f %7.4f %7.4f %7.4f   %s"
              % (p.split("/")[-1], r["regions"], r["area_pct"], r["lit_area_pct"], r["area_ok"],
                 r["wmean"], r["absmean"], r["corner_mean"], r["corner_p95"],
                 "  ".join("%.0fm2/%.2f%%" % (w["area"], w["spread_pct"]) for w in worst)))
        # The gate is on the AREA inside it, not on the mean: a tail of 2 m2 patches between two
        # balconies can pull a mean anywhere, and the eye reads area.
        if r["area_ok"] < AREA_OK or r["absmean"] > GATE_ABS:
            bad += 1
    print("gate: >= %.0f%% of lit wall area inside the %.1f%% spread, and <= %.2f absolute"
          "  ->  %s" % (AREA_OK, GATE_PCT, GATE_ABS, "PASS" if bad == 0 else "%d OVER" % bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
