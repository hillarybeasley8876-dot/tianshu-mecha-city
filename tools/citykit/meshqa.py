"""Measure what actually ships: a glb's flat-surface share and its shading-normal deviation.

    python3 tools/citykit/meshqa.py game/world/kit/t01/t01.glb ...

The lead's r4 gate, on the EXPORT rather than on what a bmesh op reported:

* **truly flat** — a triangle counts only if every welded neighbour (sharing an edge after welding
  positions to 1 mm) lies within `FLAT_DEG` of its own plane. A wall that is one plane has all of
  its triangles in; a wobbly reconstruction has almost none, whatever the operator claimed.
* **shading deviation** — area-weighted angle between the stored NORMAL attribute and the geometric
  face normal. This is the "crumpled black chrome" number: a mesh decimated after its normals were
  built keeps normals that no longer belong to any face it has.

Reads the glb directly (no Blender), so it measures the file the game loads.
"""
from __future__ import annotations

import json
import struct
import sys
from typing import Dict, List, Tuple

import numpy as np

#: A triangle is "truly flat" when no welded neighbour deviates more than this from its plane.
FLAT_DEG = 1.0
#: Shading normal more than this far off the face it sits on is a visible crease artefact.
BENT_DEG = 30.0
_COMP = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}
_N = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def _chunks(blob: bytes) -> Tuple[dict, bytes]:
    off, js, binb = 12, None, b""
    while off < len(blob):
        ln, typ = struct.unpack_from("<II", blob, off)
        off += 8
        chunk = blob[off:off + ln]
        off += ln
        if typ == 0x4E4F534A:
            js = json.loads(chunk)
        elif typ == 0x004E4942:
            binb = chunk
    if js is None:
        raise ValueError("no JSON chunk")
    return js, binb


def load(path: str) -> Tuple[np.ndarray, np.ndarray]:
    """(triangles Nx3x3, vertex normals Nx3x3). Normals are zeros when the glb carries none."""
    js, binb = _chunks(open(path, "rb").read())

    def acc(i: int) -> np.ndarray:
        a = js["accessors"][i]
        bv = js["bufferViews"][a["bufferView"]]
        n = _N[a["type"]]
        start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        raw = np.frombuffer(binb, dtype=_COMP[a["componentType"]], count=a["count"] * n,
                            offset=start)
        return raw.reshape(a["count"], n).astype(np.float64)

    pos: List[np.ndarray] = []
    nor: List[np.ndarray] = []
    for mesh in js["meshes"]:
        for prim in mesh["primitives"]:
            idx = acc(prim["indices"]).reshape(-1).astype(np.int64)
            pos.append(acc(prim["attributes"]["POSITION"])[idx].reshape(-1, 3, 3))
            if "NORMAL" in prim["attributes"]:
                nor.append(acc(prim["attributes"]["NORMAL"])[idx].reshape(-1, 3, 3))
    tris = np.concatenate(pos)
    norms = np.concatenate(nor) if len(nor) == len(pos) else np.zeros_like(tris)
    return tris, norms


def flat_share(tris: np.ndarray) -> Tuple[float, float, int]:
    """(share of area whose every welded neighbour is within 1 deg, within 3 deg, triangle count)."""
    flat = tris.reshape(-1, 3)
    _, inv = np.unique(np.round(flat, 3), axis=0, return_inverse=True)
    faces = inv.reshape(-1, 3)
    g = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    area = 0.5 * np.linalg.norm(g, axis=1)
    g = g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-12)
    edges: Dict[Tuple[int, int], List[int]] = {}
    for i, (a, b, c) in enumerate(faces):
        for u, v in ((a, b), (b, c), (c, a)):
            edges.setdefault((min(u, v), max(u, v)), []).append(i)
    worst = np.zeros(len(tris))
    for pair in edges.values():
        if len(pair) != 2:
            continue
        i, j = pair
        ang = np.degrees(np.arccos(np.clip(float(g[i].dot(g[j])), -1.0, 1.0)))
        worst[i] = max(worst[i], ang)
        worst[j] = max(worst[j], ang)
    w = area / max(area.sum(), 1e-12)
    return (100.0 * float(w[worst < 1.0].sum()), 100.0 * float(w[worst < 3.0].sum()), len(tris))


def shading_dev(tris: np.ndarray, norms: np.ndarray) -> Tuple[float, float, float]:
    """(area-weighted mean angle between the shading normal and the face, % of area over BENT_DEG,
    % of area whose shading normal opposes the face)."""
    g = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    area = 0.5 * np.linalg.norm(g, axis=1)
    g = g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-12)
    vn = norms.mean(axis=1)
    ln = np.linalg.norm(vn, axis=1, keepdims=True)
    if float(ln.max()) < 1e-9:
        return 0.0, 0.0, 0.0
    vn = vn / np.maximum(ln, 1e-12)
    dot = (g * vn).sum(1)
    ang = np.degrees(np.arccos(np.clip(np.abs(dot), 0.0, 1.0)))
    w = area / max(area.sum(), 1e-12)
    # A shading normal that opposes the winding is a worse fault than a bent one, so it is reported
    # apart rather than folded into the angle (where |dot| would hide it as 0 degrees).
    return (float((ang * w).sum()), 100.0 * float(w[ang > BENT_DEG].sum()),
            100.0 * float(w[dot < 0.0].sum()))


def report(path: str) -> dict:
    tris, norms = load(path)
    flat1, flat3, n = flat_share(tris)
    mean, bent, flipped = shading_dev(tris, norms)
    return {"path": path, "tris": n, "flat1": flat1, "flat3": flat3, "dev_mean": mean,
            "dev_over": bent, "flipped": flipped}


def main(argv: List[str]) -> int:
    paths = [a for a in argv if not a.startswith("-")]
    if not paths:
        print(__doc__)
        return 2
    print("%-34s %7s  %7s %7s  %8s %8s %7s"
          % ("glb", "tris", "flat1%", "flat3%", "dev deg", ">30deg%", "flip%"))
    for p in paths:
        try:
            r = report(p)
        except (OSError, ValueError, KeyError, IndexError) as exc:
            print("%-34s  FAILED: %s" % (p.split("/")[-1], exc))
            continue
        print("%-34s %7d  %7.1f %7.1f  %8.1f %8.1f %7.1f"
              % (p.split("/")[-1], r["tris"], r["flat1"], r["flat3"], r["dev_mean"], r["dev_over"],
                 r["flipped"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
