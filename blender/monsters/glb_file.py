"""Reading a glTF/GLB container (monster-assets).

The container half of `diag_glb_floor`: chunk parsing, buffers and accessors. Nothing here knows
what a monster is — it turns a `.glb` into numpy arrays, which is what lets the floor measurement run
on the system python3 with no Blender and no Godot.

    from monsters.glb_file import read_glb, buffers, accessor
"""
from __future__ import annotations

import json
import struct

import numpy as np

#: glTF componentType -> (numpy dtype, byte size)
COMPONENT = {
    5120: (np.int8, 1), 5121: (np.uint8, 1), 5122: (np.int16, 2),
    5123: (np.uint16, 2), 5125: (np.uint32, 4), 5126: (np.float32, 4),
}
#: glTF accessor type -> components per element
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
#: glTF chunk types
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942


def read_glb(path: str) -> tuple:
    """(gltf JSON, binary chunk bytes) for a .glb, or (JSON, b"") for a .gltf."""
    with open(path, "rb") as handle:
        blob = handle.read()
    if blob[:4] != b"glTF":
        return json.loads(blob.decode("utf-8")), b""
    _magic, _version, total = struct.unpack_from("<III", blob, 0)
    offset, js, binary = 12, None, b""
    while offset < min(total, len(blob)):
        length, kind = struct.unpack_from("<II", blob, offset)
        payload = blob[offset + 8:offset + 8 + length]
        if kind == CHUNK_JSON:
            js = json.loads(payload.decode("utf-8"))
        elif kind == CHUNK_BIN:
            binary = payload
        offset += 8 + length
    if js is None:
        raise RuntimeError("glb_file: %s has no JSON chunk" % path)
    return js, binary


def buffers(gltf: dict, binary: bytes) -> list:
    """Every buffer's bytes, in `gltf["buffers"]` order (the GLB chunk is buffer 0)."""
    import base64

    out = []
    for buf in gltf.get("buffers", []):
        if "uri" not in buf:
            out.append(binary)
            continue
        uri = buf["uri"]
        out.append(base64.b64decode(uri.split(",", 1)[1]) if uri.startswith("data:") else b"")
    return out


def accessor(gltf: dict, bufs: list, index: int) -> np.ndarray:
    """One accessor as a (count, ncomp) array. Sparse accessors are not used by our exports; a
    sparse one raises rather than silently reading the wrong vertices."""
    acc = gltf["accessors"][index]
    if "sparse" in acc:
        raise RuntimeError("glb_file: sparse accessor %d is not supported" % index)
    dtype, size = COMPONENT[acc["componentType"]]
    ncomp = NCOMP[acc["type"]]
    count = acc["count"]
    if "bufferView" not in acc:
        return np.zeros((count, ncomp), dtype=dtype)
    view = gltf["bufferViews"][acc["bufferView"]]
    base = bufs[view.get("buffer", 0)]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = view.get("byteStride", 0) or ncomp * size
    raw = np.frombuffer(base, dtype=np.uint8)
    if stride == ncomp * size:
        return np.frombuffer(base, dtype=dtype, count=count * ncomp,
                             offset=start).reshape(count, ncomp)
    rows = np.lib.stride_tricks.as_strided(
        raw[start:start + stride * count], shape=(count, ncomp * size), strides=(stride, 1))
    return np.ascontiguousarray(rows).view(dtype).reshape(count, ncomp)
