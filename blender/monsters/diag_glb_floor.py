"""What the shipped .glb *file* says about a clip's lowest point (monster-assets, lead r6).

Every other way to ask this question goes through an importer: `probe_floor` asks Godot, and the
build's gate used to load the GLB back into Blender. For the juggernaut's `charge_run` those two
disagreed by 0.6 m and neither could settle it. This reads the container itself — nodes, skins,
inverse bind matrices, animation samplers — skins the mesh with plain numpy, and prints the answer
the file actually encodes, with the per-frame lowest vertex and the joint that carries it. It agrees
with Godot to the millimetre, so it is what `mon_ground.round_trip` now corrects against.

No bpy: run it with the system python3 (numpy only), so it costs nothing next to a Blender boot.

    python3 blender/monsters/diag_glb_floor.py --glb=game/enemies/models/juggernaut/juggernaut.glb \
        --clip=charge_run --frames
    python3 blender/monsters/diag_glb_floor.py --glb=… --all --hz=30
    python3 blender/monsters/diag_glb_floor.py --glb=… --all --support=L_ToeBase,R_ToeBase
"""
from __future__ import annotations

import argparse
import os
import sys

import numpy as np

# Runnable straight from the shell (`python3 blender/monsters/diag_glb_floor.py …`) as well as
# importable as `monsters.diag_glb_floor` from Blender, so the package root goes on the path.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Re-exported so callers have one import for "read the shipped file": `mon_ground.round_trip` and
# `diag_roundtrip` both use `glbfile.read_glb` / `.accessor`.
from monsters.glb_file import accessor, buffers, read_glb  # noqa: F401

# --- node transforms -----------------------------------------------------------------------------


def trs_matrix(translation, rotation, scale) -> np.ndarray:
    """Column-major-agnostic 4x4 from a glTF TRS (rotation is a xyzw quaternion)."""
    x, y, z, w = rotation
    n = (x * x + y * y + z * z + w * w) ** 0.5 or 1.0
    x, y, z, w = x / n, y / n, z / n, w / n
    rot = np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])
    out = np.eye(4)
    out[:3, :3] = rot * np.asarray(scale)[None, :]
    out[:3, 3] = translation
    return out


def node_locals(gltf: dict) -> list:
    """Each node's rest local matrix."""
    out = []
    for node in gltf.get("nodes", []):
        if "matrix" in node:
            out.append(np.array(node["matrix"], dtype=float).reshape(4, 4).T)
        else:
            out.append(trs_matrix(node.get("translation", [0, 0, 0]),
                                  node.get("rotation", [0, 0, 0, 1]),
                                  node.get("scale", [1, 1, 1])))
    return out


def parents_of(gltf: dict) -> list:
    out = [-1] * len(gltf.get("nodes", []))
    for i, node in enumerate(gltf.get("nodes", [])):
        for child in node.get("children", []):
            out[child] = i
    return out


def globals_from(locals_: list, parents: list, order: list) -> np.ndarray:
    """(n, 4, 4) world matrices, resolving parents before children."""
    out = np.tile(np.eye(4), (len(locals_), 1, 1))
    for i in order:
        out[i] = out[parents[i]] @ locals_[i] if parents[i] >= 0 else locals_[i]
    return out


def topo_order(parents: list) -> list:
    order, seen = [], set()

    def visit(i: int) -> None:
        if i in seen:
            return
        seen.add(i)
        if parents[i] >= 0:
            visit(parents[i])
        order.append(i)

    for i in range(len(parents)):
        visit(i)
    return order


# --- animation -----------------------------------------------------------------------------------

def animation_tracks(gltf: dict, bufs: list, anim: dict) -> dict:
    """{node index: {path: (times, values, interpolation)}} for one glTF animation."""
    out: dict = {}
    for channel in anim.get("channels", []):
        sampler = anim["samplers"][channel["sampler"]]
        times = accessor(gltf, bufs, sampler["input"])[:, 0].astype(float)
        values = accessor(gltf, bufs, sampler["output"]).astype(float)
        interp = sampler.get("interpolation", "LINEAR")
        if interp == "CUBICSPLINE":
            values = values[1::3]
        out.setdefault(channel["target"]["node"], {})[channel["target"]["path"]] = (
            times, values, interp)
    return out


def sample_track(times: np.ndarray, values: np.ndarray, interp: str, t: float) -> np.ndarray:
    """One track's value at time `t`, matching glTF semantics (STEP holds, LINEAR lerps/slerps)."""
    if len(times) == 1 or t <= times[0]:
        return values[0]
    if t >= times[-1]:
        return values[-1]
    i = int(np.searchsorted(times, t, side="right")) - 1
    if interp == "STEP":
        return values[i]
    span = times[i + 1] - times[i]
    u = 0.0 if span <= 0 else (t - times[i]) / span
    a, b = values[i], values[i + 1]
    if a.shape[0] == 4:  # quaternion: shortest-arc slerp, as both importers do
        if float(np.dot(a, b)) < 0.0:
            b = -b
        dot = float(np.clip(np.dot(a, b), -1.0, 1.0))
        if dot > 0.9995:
            out = a + (b - a) * u
            return out / (np.linalg.norm(out) or 1.0)
        theta = np.arccos(dot)
        s = np.sin(theta)
        return (a * np.sin((1 - u) * theta) + b * np.sin(u * theta)) / s
    return a + (b - a) * u


def sample_locals(rest: list, tracks: dict, t: float) -> list:
    """Every node's local matrix at time `t`."""
    out = list(rest)
    for node, paths in tracks.items():
        translation, rotation, scale = [0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 1.0], [1.0, 1.0, 1.0]
        base = rest[node]
        if "translation" in paths or "rotation" in paths or "scale" in paths:
            # recover the rest TRS so an unanimated channel keeps its authored value
            translation = list(base[:3, 3])
            scale = list(np.linalg.norm(base[:3, :3], axis=0))
            rot3 = base[:3, :3] / np.where(np.array(scale) == 0, 1.0, scale)[None, :]
            rotation = _quat_from_matrix(rot3)
        if "translation" in paths:
            translation = sample_track(*paths["translation"], t=t)
        if "rotation" in paths:
            rotation = sample_track(*paths["rotation"], t=t)
        if "scale" in paths:
            scale = sample_track(*paths["scale"], t=t)
        out[node] = trs_matrix(translation, rotation, scale)
    return out


def _quat_from_matrix(m: np.ndarray) -> list:
    """xyzw quaternion from a rotation matrix (Shepperd's method, numerically safe branches)."""
    trace = m[0, 0] + m[1, 1] + m[2, 2]
    if trace > 0.0:
        s = (trace + 1.0) ** 0.5 * 2.0
        q = [(m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, 0.25 * s]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = (1.0 + m[0, 0] - m[1, 1] - m[2, 2]) ** 0.5 * 2.0
        q = [0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s]
    elif m[1, 1] > m[2, 2]:
        s = (1.0 + m[1, 1] - m[0, 0] - m[2, 2]) ** 0.5 * 2.0
        q = [(m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s]
    else:
        s = (1.0 + m[2, 2] - m[0, 0] - m[1, 1]) ** 0.5 * 2.0
        q = [(m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s, (m[1, 0] - m[0, 1]) / s]
    return q


# --- skinning ------------------------------------------------------------------------------------

class Skin:
    """One skinned primitive: rest positions, up to four joint influences, and the joint list.

    A rigged export carries LOD0 and LOD1 as two skinned nodes sharing one skin. The *largest* is
    LOD0, and picking it by vertex count rather than by node order means the measurement does not
    silently change when the exporter reorders the meshes."""

    def __init__(self, gltf: dict, bufs: list, node: int = -1) -> None:
        self.names = [n.get("name", "?") for n in gltf.get("nodes", [])]
        self.parents = parents_of(gltf)
        self.rest = node_locals(gltf)
        self.order = topo_order(self.parents)
        if node < 0:
            skinned = [i for i, n in enumerate(gltf["nodes"]) if "skin" in n and "mesh" in n]
            if not skinned:
                raise RuntimeError("diag_glb_floor: the file has no skinned mesh")
            node = max(skinned, key=lambda i: accessor(
                gltf, bufs, gltf["meshes"][gltf["nodes"][i]["mesh"]]["primitives"][0]
                ["attributes"]["POSITION"]).shape[0])
        self.mesh_node = node
        self.skin = gltf["skins"][gltf["nodes"][node]["skin"]]
        self.joints = list(self.skin["joints"])
        ibm = accessor(gltf, bufs, self.skin["inverseBindMatrices"]).astype(float)
        self.ibm = ibm.reshape(-1, 4, 4).transpose(0, 2, 1)
        prim = gltf["meshes"][gltf["nodes"][node]["mesh"]]["primitives"][0]
        attrs = prim["attributes"]
        self.pos = accessor(gltf, bufs, attrs["POSITION"]).astype(float)
        self.jidx = accessor(gltf, bufs, attrs["JOINTS_0"]).astype(int)
        self.jw = accessor(gltf, bufs, attrs["WEIGHTS_0"]).astype(float)
        total = self.jw.sum(axis=1, keepdims=True)
        self.jw = self.jw / np.where(total <= 0.0, 1.0, total)
        self.tris = (accessor(gltf, bufs, prim["indices"]).astype(int).reshape(-1, 3)
                     if "indices" in prim else
                     np.arange(len(self.pos)).reshape(-1, 3))
        self.keep = self._non_bridge()

    def joint_hops(self, a: int, b: int) -> int:
        """Bone-tree distance between two joints, in the glTF node hierarchy."""
        chain, n = [], self.joints[a]
        while n >= 0:
            chain.append(n)
            n = self.parents[n]
        steps, n = 0, self.joints[b]
        while n >= 0:
            if n in chain:
                return chain.index(n) + steps
            n = self.parents[n]
            steps += 1
        return 99

    def _non_bridge(self) -> np.ndarray:
        """Vertex mask with bridge-triangle vertices removed — the rule `probe_floor.gd` uses, so
        the two numbers compare. A bridge joins joints more than three hops apart."""
        dominant = self.jidx[np.arange(len(self.pos)), self.jw.argmax(axis=1)]
        bad = np.zeros(len(self.pos), dtype=bool)
        cache: dict = {}
        for tri in self.tris:
            for e in range(3):
                a, b = int(dominant[tri[e]]), int(dominant[tri[(e + 1) % 3]])
                if a == b:
                    continue
                key = (min(a, b), max(a, b))
                if key not in cache:
                    cache[key] = self.joint_hops(key[0], key[1])
                if cache[key] > 3:
                    bad[tri] = True
                    break
        return ~bad

    def support_joints(self, names, hops: int = 3) -> set:
        """Joint indices that can bear the body's weight: the named contact bones and everything
        within `hops` of them *up* the tree — a leg, from the toe to the knee.

        A hand claw or a tail is not support. Pinning the global lowest point instead lifts the
        whole animal whenever one of those swings past the feet, which trades a sink for a float and
        fixes neither."""
        wanted = {self.joints.index(self.names.index(n)) for n in names
                  if n in self.names and self.names.index(n) in self.joints}
        out = set(wanted)
        for start in wanted:
            node, up = self.joints[start], 0
            while up < hops and self.parents[node] >= 0:
                node = self.parents[node]
                up += 1
                if node in self.joints:
                    out.add(self.joints.index(node))
        return out

    def pose(self, tracks: dict, t: float) -> np.ndarray:
        """World-space skinned positions at time `t`: sum(w * globalJoint * IBM * v)."""
        globals_ = globals_from(sample_locals(self.rest, tracks, t), self.parents, self.order)
        mats = globals_[np.array(self.joints)] @ self.ibm
        homo = np.concatenate([self.pos, np.ones((len(self.pos), 1))], axis=1)
        posed = np.einsum("vkab,vb->vka", mats[self.jidx], homo)[:, :, :3]
        return (posed * self.jw[:, :, None]).sum(axis=1)


def clip_names(gltf: dict) -> list:
    return [a.get("name", "animation_%d" % i) for i, a in enumerate(gltf.get("animations", []))]


# --- report --------------------------------------------------------------------------------------

def measure(skin: Skin, tracks: dict, length: float, hz: float, support=frozenset()) -> dict:
    """Per-frame lowest point over the clip, with the joint that carries it.

    `support` restricts the measurement to vertices whose dominant joint is in that set — the legs,
    as opposed to a hand claw or a tail that happens to swing lower than them. A clip can only be
    planted on its support: pinning the global minimum instead lifts the whole body whenever an arm
    or a tail dips past the feet, which trades a sink for a float."""
    steps = max(int(np.ceil(length * hz)), 1)
    dominant = skin.jidx[np.arange(len(skin.pos)), skin.jw.argmax(axis=1)]
    keep = np.nonzero(skin.keep)[0]
    if len(support):
        keep = keep[np.isin(dominant[keep], list(support))]
    rows = []
    for s in range(steps):
        t = length * s / steps
        posed = skin.pose(tracks, t)
        low = float(posed[keep, 1].min())
        who = int(keep[int(np.argmin(posed[keep, 1]))])
        rows.append((t, low, skin.names[skin.joints[int(dominant[who])]]))
    lows = np.array([r[1] for r in rows])
    return {"rows": rows, "low": float(lows.min()), "high": float(lows.max()),
            "worst_t": rows[int(np.argmin(lows))][0], "steps": steps, "verts": len(keep)}


def main(argv: list) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--glb", required=True)
    parser.add_argument("--clip", default="")
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--hz", type=float, default=30.0)
    parser.add_argument("--frames", action="store_true", help="print every sampled frame")
    parser.add_argument("--support", default="", help="comma-separated bones that carry the body")
    args = parser.parse_args(argv)

    gltf, binary = read_glb(args.glb)
    bufs = buffers(gltf, binary)
    skin = Skin(gltf, bufs)
    names = clip_names(gltf)
    print("GLB %s" % args.glb)
    print("  nodes %d  joints %d  verts %d  tris %d  bridge verts %d  clips %d"
          % (len(gltf["nodes"]), len(skin.joints), len(skin.pos), len(skin.tris),
             int((~skin.keep).sum()), len(names)))
    roots = [i for i, p in enumerate(skin.parents) if p < 0]
    for r in roots:
        print("  root node %d '%s' rest translation %s scale %s"
              % (r, skin.names[r], np.round(skin.rest[r][:3, 3], 4).tolist(),
                 np.round(np.linalg.norm(skin.rest[r][:3, :3], axis=0), 4).tolist()))
    wanted = names if args.all else [n for n in names if args.clip in n]
    if not wanted:
        print("  no clip matches '%s'; have %s" % (args.clip, names))
        return 1
    for name in wanted:
        anim = gltf["animations"][names.index(name)]
        tracks = animation_tracks(gltf, bufs, anim)
        length = max(float(accessor(gltf, bufs, s["input"])[:, 0].max())
                     for s in anim["samplers"])
        support = skin.support_joints([n for n in args.support.split(',') if n])
        got = measure(skin, tracks, length, args.hz, support)
        print("FLOORFILE %-14s len %5.2f s | lowest %+.3f m @ %.2f s | highest per-frame %+.3f m"
              " | animated nodes %d | verts %d" % (name, length, got["low"], got["worst_t"],
                                        got["high"], len(tracks), got["verts"]))
        if args.frames:
            for t, low, who in got["rows"]:
                print("    t %5.3f  lowest %+.3f m  joint %s" % (t, low, who))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
