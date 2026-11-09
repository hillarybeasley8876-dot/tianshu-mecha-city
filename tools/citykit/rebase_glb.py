"""Put every shipped kit and prop glb's pivot at its footprint's base centre, and check that it is.

  python3 tools/citykit/rebase_glb.py --check     # the gate: exit 1 if any glb is not based
  python3 tools/citykit/rebase_glb.py --apply     # move the vertices of every glb that is not
  ... [--set kit|props|all]                       # default all

`game/world/kit/kit_placer.gd` and `game/world/props/prop_scatter.gd` both take the MESH out of a glb
(the node is dropped) and draw it with its origin on the placement's base; `tools/citykit/assign.py`
fits heights, stacks cover and hangs fasciae on the same assumption. Through 11-03 every glb shipped
with its mesh centred on its own middle -- `fit_native` (blender/citykit/process.py) and `normalise`
(blender/props/process_prop.py) moved the origin, then a later `apply_transforms` baked it back -- so
all 8 477 kit instances and every prop drew sunk by about half their height, and the roof dressing
floated over the real roofs.

A kit family (the detail glb, its `_lod` and its `_far`) moves by ONE vector, measured on the detail
mesh, so the tiers stay registered with each other through the visibility-range swaps. A prop glb also
loses the node translation the scatter never read, so the scene and the mesh agree.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import struct
import sys
from typing import Dict, List, Tuple

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
KIT_DIR = os.path.join(ROOT, "game", "world", "kit")
KIT_JSON = os.path.join(KIT_DIR, "kit.json")
PROP_DIR = os.path.join(ROOT, "game", "world", "props", "meshes")
## Holograms float by design and are placed by their centre (prop_scatter.gd `_spawn_holograms`).
HOLOGRAMS = ("koi_dragon",)
GLTF_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942
FLOAT = 5126
## How far the base and the footprint centre may sit from the origin, in metres.
TOLERANCE = 0.05


def read_glb(path: str) -> Tuple[dict, bytearray]:
    data = open(path, "rb").read()
    magic, _version, length = struct.unpack_from("<III", data, 0)
    if magic != GLTF_MAGIC:
        raise ValueError("%s is not a glb" % path)
    off = 12
    doc = None
    blob = bytearray()
    while off < length:
        size, kind = struct.unpack_from("<II", data, off)
        off += 8
        chunk = data[off:off + size]
        off += size
        if kind == CHUNK_JSON:
            doc = json.loads(chunk)
        elif kind == CHUNK_BIN:
            blob = bytearray(chunk)
    if doc is None:
        raise ValueError("%s has no JSON chunk" % path)
    return doc, blob


def write_glb(path: str, doc: dict, blob: bytearray) -> None:
    text = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    text += b" " * (-len(text) % 4)
    body = bytes(blob) + b"\0" * (-len(blob) % 4)
    total = 12 + 8 + len(text) + 8 + len(body)
    out = struct.pack("<III", GLTF_MAGIC, 2, total) + struct.pack("<II", len(text), CHUNK_JSON) + text \
        + struct.pack("<II", len(body), CHUNK_BIN) + body
    tmp = path + ".rebase_tmp"
    with open(tmp, "wb") as f:
        f.write(out)
    os.replace(tmp, path)


def node_translation(doc: dict, path: str) -> np.ndarray:
    """The translation on the mesh node. Rotation or scale would make mesh space differ from model
    space in a way a translation of the vertices cannot fix, so those are refused."""
    out = np.zeros(3)
    for node in doc.get("nodes", []):
        if "mesh" not in node:
            continue
        if any(k in node for k in ("matrix", "rotation", "scale")):
            raise ValueError("%s: node %r rotates or scales its mesh" % (path, node.get("name")))
        out = np.array(node.get("translation", [0.0, 0.0, 0.0]), dtype=np.float64)
    return out


def positions(doc: dict, blob: bytearray) -> List[Tuple[dict, np.ndarray]]:
    """Every POSITION accessor once, as a writable strided view into the BIN chunk."""
    out: List[Tuple[dict, np.ndarray]] = []
    seen = set()
    for mesh in doc.get("meshes", []):
        for prim in mesh.get("primitives", []):
            index = prim.get("attributes", {}).get("POSITION")
            if index is None:
                continue
            acc = doc["accessors"][index]
            key = (acc["bufferView"], acc.get("byteOffset", 0))
            if key in seen:
                continue
            seen.add(key)
            if acc["componentType"] != FLOAT or acc["type"] != "VEC3" or acc.get("sparse"):
                raise ValueError("POSITION accessor %d is not a dense float VEC3" % index)
            view = doc["bufferViews"][acc["bufferView"]]
            start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
            stride = view.get("byteStride", 12)
            arr = np.ndarray(shape=(acc["count"], 3), dtype="<f4", buffer=blob, offset=start,
                             strides=(stride, 4))
            out.append((acc, arr))
    return out


def bounds(path: str) -> Tuple[np.ndarray, np.ndarray]:
    """The box of the MESH, in mesh space: what the placers draw."""
    doc, blob = read_glb(path)
    node_translation(doc, path)
    views = positions(doc, blob)
    lo = np.min([arr.min(axis=0) for _, arr in views], axis=0).astype(np.float64)
    hi = np.max([arr.max(axis=0) for _, arr in views], axis=0).astype(np.float64)
    return lo, hi


def base_offset(path: str) -> np.ndarray:
    """The move that puts the footprint's base centre on the origin (glTF is Y-up)."""
    lo, hi = bounds(path)
    return np.array([-(lo[0] + hi[0]) * 0.5, -lo[1], -(lo[2] + hi[2]) * 0.5])


def move(path: str, offset: np.ndarray) -> None:
    """Move the vertices by `offset` and drop any node translation."""
    doc, blob = read_glb(path)
    node_translation(doc, path)
    for acc, arr in positions(doc, blob):
        arr += offset.astype(np.float32)
        acc["min"] = [float(v) for v in arr.min(axis=0)]
        acc["max"] = [float(v) for v in arr.max(axis=0)]
    for node in doc.get("nodes", []):
        if "mesh" in node:
            node.pop("translation", None)
    write_glb(path, doc, blob)


def kit_families() -> Dict[str, List[str]]:
    """model id -> [detail, lod, far] glb paths that exist, detail first."""
    kit = json.load(open(KIT_JSON))
    out: Dict[str, List[str]] = {}
    for row in kit.get("models", []):
        mid = str(row["id"])
        paths = [os.path.join(KIT_DIR, str(row.get("glb", "%s/%s.glb" % (mid, mid))))]
        for tier in ("lod", "far"):
            if isinstance(row.get(tier), dict) and row[tier].get("glb"):
                paths.append(os.path.join(KIT_DIR, str(row[tier]["glb"])))
        out[mid] = [p for p in paths if os.path.exists(p)]
        if not out[mid] or out[mid][0] != paths[0]:
            raise FileNotFoundError("%s: detail glb %s is missing" % (mid, paths[0]))
    return out


def prop_families() -> Dict[str, List[str]]:
    out: Dict[str, List[str]] = {}
    for path in sorted(glob.glob(os.path.join(PROP_DIR, "*.glb"))):
        name = os.path.basename(path)[:-4]
        if name not in HOLOGRAMS:
            out["prop:" + name] = [path]
    return out


def _tiers_registered(mid: str, paths: List[str]) -> int:
    """The tiers must stay registered with the detail mesh they swap with: inside its box, not sunk
    under its base. A collapse can push a vertex out a little (k07's far is 1.2 m wider) or lose a thin
    base (m05's far starts 10 m up); a pivot error is half the model's height."""
    bad = 0
    d_lo, d_hi = bounds(paths[0])
    slack = np.maximum(1.5, 0.1 * (d_hi - d_lo))
    for p in paths[1:]:
        lo, hi = bounds(p)
        if lo[1] < -1.0 or np.any(lo < d_lo - slack) or np.any(hi > d_hi + slack):
            print("FAIL %-4s %s: y %+.2f..%+.2f against the detail's %+.2f..%+.2f"
                  % (mid, os.path.basename(p), lo[1], hi[1], d_lo[1], d_hi[1]))
            bad += 1
    return bad


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--apply", action="store_true")
    ap.add_argument("--set", choices=("kit", "props", "all"), default="all")
    args = ap.parse_args()
    families: Dict[str, List[str]] = {}
    if args.set in ("kit", "all"):
        families.update(kit_families())
    if args.set in ("props", "all"):
        families.update(prop_families())
    bad = 0
    for mid, paths in sorted(families.items()):
        offset = base_offset(paths[0])
        stray = float(np.max(np.abs(node_translation(read_glb(paths[0])[0], paths[0]))))
        if float(np.max(np.abs(offset))) <= TOLERANCE and stray <= TOLERANCE:
            bad += _tiers_registered(mid, paths)
            continue
        if args.check:
            print("FAIL %-20s pivot %.2f m off its base centre (base y %+.2f m), node translation %.2f m"
                  % (mid, float(np.max(np.abs(offset))), -offset[1], stray))
            bad += 1
            continue
        for p in paths:
            move(p, offset)
        print("MOVED %-20s by (%+.2f, %+.2f, %+.2f) m: %s" % (mid, offset[0], offset[1], offset[2],
              ", ".join(os.path.basename(p) for p in paths)))
    if args.check:
        print("PASS" if bad == 0 else "FAILED %d models" % bad)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
