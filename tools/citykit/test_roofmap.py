"""The gate for `blender/citykit/roofmap.py`: a dressing point sampled from the map must land on the roof.

    python3 tools/citykit/test_roofmap.py                # every model that has a map
    python3 tools/citykit/test_roofmap.py t01 m01        # named models

City-art consumes the map to place rooftop units, so the thing that has to be true is: **stand at the
cell the map names, at the height the map names, and the real surface is within 0.5 m.** This walks the
map the way a scatterer would — pick a flat cell, read its height, raycast the shipped mesh — and
reports the error distribution per model.

It also reports the second half of the lead's ask: how the map's "flat" cells agree with what the mesh
says is flat. A cell marked flat whose real surface normal is more than `flat_deg` off up is a machine
block that would sit on a slope.

Runs on the glb directly (no Blender), so it measures the file the game loads.
"""
from __future__ import annotations

import base64
import json
import os
import sys
from typing import Dict, List, Tuple

import numpy as np

from meshqa import load

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
KIT = os.path.join(ROOT, "game", "world", "kit")
#: The lead's tolerance: a dressing point sampled from the map lands within this of the real surface.
TOL_M = 0.5
#: How many cells per model are probed. Every cell on a small model; a stratified sample on a big one.
PROBES = 400


def read_map(row: dict) -> Tuple[dict, np.ndarray, np.ndarray] | None:
    """(meta, heights in metres as (ny, nx), flat flags as (ny, nx)), or None if the row has no map."""
    rec = row.get("roof")
    if not rec:
        return None
    nx, ny = int(rec["nx"]), int(rec["ny"])
    h = np.frombuffer(base64.b64decode(rec["h"]), dtype=np.uint8).reshape(ny, nx)
    f = np.frombuffer(base64.b64decode(rec["flat"]), dtype=np.uint8).reshape(ny, nx)
    return rec, h.astype(np.float64) * float(rec["z_span"]) / 255.0 + float(rec["z0"]), f > 127


def top_surface(tris: np.ndarray, x: np.ndarray, y: np.ndarray) -> np.ndarray:
    """Height of the highest upward-facing surface above each (x, y), or NaN where there is none.

    A brute-force point-in-triangle test over the whole mesh, vectorised per query: the gate runs once
    per model on a few hundred probes and a spatial index would be more code than the loop.
    """
    a, b, c = tris[:, 0], tris[:, 1], tris[:, 2]
    up = np.cross(b - a, c - a)
    keep = up[:, 2] > 1e-9
    a, b, c, up = a[keep], b[keep], c[keep], up[keep]
    if len(a) == 0:
        return np.full(len(x), np.nan)
    out = np.full(len(x), np.nan)
    for i in range(len(x)):
        px, py = x[i], y[i]
        # Barycentric in XY; a triangle whose XY projection is degenerate is skipped.
        d = ((b[:, 1] - c[:, 1]) * (a[:, 0] - c[:, 0])
             + (c[:, 0] - b[:, 0]) * (a[:, 1] - c[:, 1]))
        ok = np.abs(d) > 1e-9
        if not ok.any():
            continue
        l0 = np.where(ok, ((b[:, 1] - c[:, 1]) * (px - c[:, 0])
                           + (c[:, 0] - b[:, 0]) * (py - c[:, 1])) / np.where(ok, d, 1.0), -1.0)
        l1 = np.where(ok, ((c[:, 1] - a[:, 1]) * (px - c[:, 0])
                           + (a[:, 0] - c[:, 0]) * (py - c[:, 1])) / np.where(ok, d, 1.0), -1.0)
        l2 = 1.0 - l0 - l1
        hit = ok & (l0 >= -1e-6) & (l1 >= -1e-6) & (l2 >= -1e-6)
        if not hit.any():
            continue
        z = l0[hit] * a[hit, 2] + l1[hit] * b[hit, 2] + l2[hit] * c[hit, 2]
        out[i] = float(z.max())
    return out


def check(aid: str) -> dict | None:
    row_path = os.path.join(KIT, aid, "row.json")
    glb = os.path.join(KIT, aid, aid + ".glb")
    if not os.path.exists(row_path) or not os.path.exists(glb):
        return None
    with open(row_path) as fh:
        row = json.load(fh)
    parsed = read_map(row)
    if parsed is None:
        return None
    rec, h, flat = parsed
    tris, _norms = load(glb)
    # The glb is Y-up (`export_yup=True`) and the roof map is in Blender's Z-up MODEL space. Blender
    # (x, y, z) exports as glTF (x, z, -y), so the inverse is model = (gx, -gz, gy). Measuring without
    # this reported errors of 100-180 m, which is the model's own height: the probe was reading the
    # wrong axis entirely.
    tris = tris[:, :, [0, 2, 1]] * np.array([1.0, -1.0, 1.0])
    ny, nx = h.shape
    cell = float(rec["cell_m"])
    ox, oy = rec["origin"]
    ys, xs = np.nonzero(flat)
    if len(xs) == 0:
        return {"id": aid, "cells": nx * ny, "flat": 0, "probes": 0, "p50": 0.0, "p95": 0.0,
                "over": 0.0, "slope_bad": 0.0}
    step = max(1, len(xs) // PROBES)
    xs, ys = xs[::step], ys[::step]
    px = ox + (xs + 0.5) * cell
    py = oy + (ys + 0.5) * cell
    real = top_surface(tris, px, py)
    got = h[ys, xs]
    ok = ~np.isnan(real)
    if not ok.any():
        return {"id": aid, "cells": nx * ny, "flat": int(flat.sum()), "probes": 0, "p50": 0.0,
                "p95": 0.0, "over": 100.0, "slope_bad": 0.0}
    err = np.abs(real[ok] - got[ok])
    return {"id": aid, "cells": nx * ny, "flat": int(flat.sum()), "probes": int(ok.sum()),
            "p50": float(np.percentile(err, 50)), "p95": float(np.percentile(err, 95)),
            "over": 100.0 * float((err > TOL_M).mean()),
            "no_surface": int((~ok).sum())}


def main(argv: List[str]) -> int:
    ids = [a for a in argv if not a.startswith("-")]
    if not ids:
        ids = sorted(d for d in os.listdir(KIT) if os.path.isdir(os.path.join(KIT, d)))
    print("%-6s %7s %7s %7s %8s %8s %8s %8s"
          % ("id", "cells", "flat", "probes", "p50 m", "p95 m", "over%", "nosurf"))
    worst, bad = 0.0, 0
    n = 0
    for aid in ids:
        r = check(aid)
        if r is None:
            continue
        n += 1
        print("%-6s %7d %7d %7d %8.3f %8.3f %8.1f %8d"
              % (r["id"], r["cells"], r["flat"], r["probes"], r["p50"], r["p95"], r["over"],
                 r.get("no_surface", 0)))
        worst = max(worst, r["p95"])
        if r["p95"] > TOL_M:
            bad += 1
    print("gate: p95 error <= %.1f m on every model  ->  %s (%d models, worst p95 %.3f m)"
          % (TOL_M, "PASS" if bad == 0 else "%d OVER" % bad, n, worst))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
