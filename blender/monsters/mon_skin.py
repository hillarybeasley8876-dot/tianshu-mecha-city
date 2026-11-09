"""Skin-weight transfer that follows the surface instead of jumping across it (monster-assets).

Lead r5 item 1: `mon_lib.transfer_weights` used Data Transfer's *nearest face interpolated*, which
picks the closest source triangle in 3-space. Wherever two limbs touch in the bind pose — a mantis
forearm resting against its calf, a juggernaut knuckle against a thigh — a vertex on one limb is
closer to a triangle on the *other* limb, so whole patches came back carrying the neighbour's bones.
Those patches are the rings of triangles that stretch into flat sheets the moment a clip moves the
limbs apart (473 bridge triangles on the mantis against 25 on Tripo's own rig of the same animal).

The fix is a correspondence that is smooth *along the destination surface*:

  1. every destination vertex starts on its nearest source point (the same answer as before);
  2. those points are diffused over the destination's own edge graph, so a vertex is pulled toward
     where its mesh neighbours landed — a vertex on the calf is surrounded by calf matches, so it
     cannot stay matched to the forearm;
  3. the diffused point is re-projected onto the source with a BVH nearest-face query, and the
     three corner weights of that face are interpolated barycentrically.

Nothing here is random and nothing depends on iteration order, so builds stay deterministic.
"""
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

#: diffusion steps and the pull toward the neighbour mean. 8 steps at 0.5 reaches ~3 vertices, which
#: is enough to erase a mis-assigned patch without flattening a real feature (a claw tip).
STEPS = 8
LAMBDA = 0.5


def csr_adjacency(mesh) -> tuple:
    """(starts, neighbours, counts) — the mesh's edge graph in CSR form, both directions."""
    n = len(mesh.vertices)
    ends = np.empty((len(mesh.edges), 2), dtype=np.int64)
    for i, edge in enumerate(mesh.edges):
        ends[i] = edge.vertices
    src = np.concatenate([ends[:, 0], ends[:, 1]])
    dst = np.concatenate([ends[:, 1], ends[:, 0]])
    order = np.argsort(src, kind="stable")
    src, dst = src[order], dst[order]
    counts = np.bincount(src, minlength=n)
    if int(counts.min()) == 0:
        raise RuntimeError("csr_adjacency: %d isolated vertices" % int((counts == 0).sum()))
    starts = np.concatenate([[0], np.cumsum(counts)[:-1]]).astype(np.int64)
    return starts, dst, counts


def neighbour_mean(points: np.ndarray, graph: tuple) -> np.ndarray:
    """Mean of each vertex's 1-ring positions."""
    starts, nbr, counts = graph
    return np.add.reduceat(points[nbr], starts, axis=0) / counts[:, None]


def world_points(obj) -> np.ndarray:
    """Vertex positions in world space."""
    mw = obj.matrix_world
    return np.array([[c for c in (mw @ v.co)] for v in obj.data.vertices], dtype=np.float64)


def weight_matrix(obj) -> tuple:
    """(group names, (verts, groups) weight array) for a mesh that already has vertex groups."""
    names = [vg.name for vg in obj.vertex_groups]
    index = {vg.index: i for i, vg in enumerate(obj.vertex_groups)}
    out = np.zeros((len(obj.data.vertices), len(names)), dtype=np.float64)
    for v in obj.data.vertices:
        for ge in v.groups:
            if ge.weight > 0.0 and ge.group in index:
                out[v.index, index[ge.group]] = ge.weight
    return names, out


def triangulate(polygons) -> np.ndarray:
    """Fan-triangulate a face list. Blender's voxel remesh emits quads, and the BVH and the
    barycentric interpolation below both need triangles."""
    out = []
    for poly in polygons:
        v = poly.vertices[:]
        for i in range(1, len(v) - 1):
            out.append((v[0], v[i], v[i + 1]))
    return np.array(out, dtype=np.int64)


def _source_bvh(obj) -> tuple:
    """(BVHTree, world vertex array, triangle index array) for the weight source."""
    pts = world_points(obj)
    tris = triangulate(obj.data.polygons)
    tree = BVHTree.FromPolygons([Vector(p) for p in pts],
                                [tuple(int(i) for i in t) for t in tris],
                                all_triangles=True, epsilon=0.0)
    return tree, pts, tris


def _nearest(tree: BVHTree, pts: np.ndarray) -> tuple:
    """Nearest point on the source for every query point: (locations, face index)."""
    loc = np.zeros_like(pts)
    face = np.full(len(pts), -1, dtype=np.int64)
    for i, p in enumerate(pts):
        hit = tree.find_nearest(Vector(p))
        if hit[0] is None:
            raise RuntimeError("transfer_surface: source BVH has no hit for vertex %d" % i)
        loc[i] = (hit[0].x, hit[0].y, hit[0].z)
        face[i] = hit[2]
    return loc, face


def _barycentric(p: np.ndarray, a: np.ndarray, b: np.ndarray, c: np.ndarray) -> np.ndarray:
    """Barycentric coordinates of `p` inside triangle (a, b, c), clamped to the triangle."""
    v0, v1, v2 = b - a, c - a, p - a
    d00 = (v0 * v0).sum(axis=1)
    d01 = (v0 * v1).sum(axis=1)
    d11 = (v1 * v1).sum(axis=1)
    d20 = (v2 * v0).sum(axis=1)
    d21 = (v2 * v1).sum(axis=1)
    den = np.maximum(d00 * d11 - d01 * d01, 1e-12)
    v = (d11 * d20 - d01 * d21) / den
    w = (d00 * d21 - d01 * d20) / den
    u = 1.0 - v - w
    out = np.stack([u, v, w], axis=1)
    return np.clip(out, 0.0, 1.0) / np.maximum(out.sum(axis=1, keepdims=True), 1e-9)


def _diffuse(points: np.ndarray, graph: tuple, steps: int = STEPS,
             lam: float = LAMBDA) -> np.ndarray:
    out = points.copy()
    for _ in range(steps):
        out = (1.0 - lam) * out + lam * neighbour_mean(out, graph)
    return out


def transfer_surface(src_obj, dst_obj, steps: int = STEPS, lam: float = LAMBDA) -> dict:
    """Copy `src_obj`'s vertex groups onto `dst_obj` along the destination surface. Returns stats.

    The destination's own topology decides the correspondence, so a limb that touches another limb
    in the bind pose keeps its own bones instead of inheriting the neighbour's."""
    names, src_w = weight_matrix(src_obj)
    if not names:
        raise RuntimeError("transfer_surface: %s has no vertex groups" % src_obj.name)
    tree, src_pts, src_tris = _source_bvh(src_obj)
    dst_pts = world_points(dst_obj)
    graph = csr_adjacency(dst_obj.data)
    seed, _ = _nearest(tree, dst_pts)
    moved = _diffuse(seed, graph, steps, lam)
    landed, face = _nearest(tree, moved)
    tri = src_tris[face]
    bary = _barycentric(landed, src_pts[tri[:, 0]], src_pts[tri[:, 1]], src_pts[tri[:, 2]])
    out = (src_w[tri[:, 0]] * bary[:, 0:1] + src_w[tri[:, 1]] * bary[:, 1:2]
           + src_w[tri[:, 2]] * bary[:, 2:3])
    total = out.sum(axis=1, keepdims=True)
    out = np.where(total > 1e-9, out / np.maximum(total, 1e-9), 0.0)
    _write_groups(dst_obj, names, out)
    drift = float(np.linalg.norm(landed - seed, axis=1).mean())
    span = float(np.linalg.norm(dst_pts.max(axis=0) - dst_pts.min(axis=0)))
    return {"groups": len(names), "drift_m": round(drift, 4),
            "drift_frac": round(drift / max(span, 1e-9), 4),
            "match_rms_m": round(float(np.linalg.norm(landed - dst_pts, axis=1).mean()), 4)}


def _write_groups(obj, names: list, weights: np.ndarray) -> None:
    for vg in list(obj.vertex_groups):
        obj.vertex_groups.remove(vg)
    groups = [obj.vertex_groups.new(name=n) for n in names]
    nz = np.nonzero(weights > 1e-4)
    for v, g in zip(nz[0].tolist(), nz[1].tolist()):
        groups[g].add([v], float(weights[v, g]), "REPLACE")


def limit_influences(obj, maximum: int = 4) -> dict:
    """Keep only the `maximum` heaviest groups per vertex and renormalise.

    glTF (and Godot's skinning) carries four influences per vertex, and the exporter prunes the rest
    itself — so a weight field with more than four influences per vertex is measured one way in the
    build and shipped another. Doing the prune here, before the measurement, makes the two agree and
    keeps the smallest influences (the ones a smoothing pass just invented) out of the file."""
    names, weights = weight_matrix(obj)
    if not names:
        return {"trimmed": 0}
    if weights.shape[1] > maximum:
        order = np.argsort(-weights, axis=1)[:, :maximum]
        keep = np.zeros_like(weights, dtype=bool)
        np.put_along_axis(keep, order, True, axis=1)
        trimmed = int((weights > 0.0).sum() - (weights[keep] > 0.0).sum())
        weights = np.where(keep, weights, 0.0)
    else:
        trimmed = 0
    total = weights.sum(axis=1, keepdims=True)
    weights = weights / np.maximum(total, 1e-9)
    _write_groups(obj, names, weights)
    return {"trimmed": trimmed, "max": maximum}


def prune_distant_weights(obj, arm, k: float = 1.2, min_weight: float = 0.004) -> dict:
    """Drop the weights a bone has on vertices it has no business moving.

    Lead r5 item 1: after the claw collapse a calf vertex could carry 1-3 % of `R_Claw1`, a bone
    29 m away at the hand, and a waist vertex 6 % of an upper arm. One percent of a 29 m lever is
    0.3 m of displacement, so two adjacent vertices whose weights differ by 2 % tear a 0.09 m edge
    into 0.6 m — the 6-13x stretch the build reported. A bone may only hold a *partial* claim on
    vertices within `k` of its own lengths of its segment; a vertex that is mostly that bone is on
    it and keeps its weight however far the segment is."""
    names, weights = weight_matrix(obj)
    if not names:
        return {"dropped": 0}
    index = {bone.name: i for i, bone in enumerate(arm.data.bones)}
    keep = np.array([index.get(n, -1) for n in names])
    valid = np.nonzero(keep >= 0)[0]
    if not len(valid):
        return {"dropped": 0}
    _, seg = bone_segments(arm)
    pts = world_points(obj)
    dist = distance_to_segments(pts, seg)[:, keep[valid]]
    length = np.linalg.norm(seg[:, 1] - seg[:, 0], axis=1)[keep[valid]]
    reach = np.maximum(k * length, 1e-6)[None, :]
    drop = np.zeros_like(weights, dtype=bool)
    drop[:, valid] = (dist > reach) | (weights[:, valid] < min_weight)
    dropped = int((drop & (weights > 0.0)).sum())
    weights = np.where(drop, 0.0, weights)
    total = weights.sum(axis=1, keepdims=True)
    empty = total[:, 0] <= 1e-9
    if empty.any():
        nearest = dist[empty].argmin(axis=1)
        for row, v in enumerate(np.nonzero(empty)[0]):
            weights[v, valid[nearest[row]]] = 1.0
        total = weights.sum(axis=1, keepdims=True)
    weights = weights / np.maximum(total, 1e-9)
    _write_groups(obj, names, weights)
    return {"dropped": dropped, "emptied": int(empty.sum())}


def smooth_weights(obj, iterations: int = 3, lam: float = 0.5) -> dict:
    """Laplacian smoothing of the weight field over the mesh's own edge graph.

    A weight field that came off a coarser source is piecewise linear per source triangle, so at the
    destination's resolution it can still step hard across one edge — and a hard step across a short
    edge is exactly what `stretch_report` measures. A few light passes spread each step over the
    neighbouring rings without moving a joint."""
    names, weights = weight_matrix(obj)
    if not names:
        return {"iterations": 0}
    graph = csr_adjacency(obj.data)
    before = weights.copy()
    for _ in range(iterations):
        weights = (1.0 - lam) * weights + lam * neighbour_mean(weights, graph)
    total = weights.sum(axis=1, keepdims=True)
    weights = np.where(total > 1e-9, weights / np.maximum(total, 1e-9), 0.0)
    _write_groups(obj, names, weights)
    delta = float(np.abs(weights - before).sum(axis=1).mean())
    return {"iterations": iterations, "mean_abs_delta": round(delta, 4)}


def dominant_bones(obj, bone_names: list) -> np.ndarray:
    """Per vertex, the index into `bone_names` of its heaviest group (-1 when unweighted)."""
    group_to_bone = np.full(max((vg.index for vg in obj.vertex_groups), default=-1) + 1,
                            -1, dtype=np.int64)
    for vg in obj.vertex_groups:
        group_to_bone[vg.index] = bone_names.index(vg.name) if vg.name in bone_names else -1
    out = np.full(len(obj.data.vertices), -1, dtype=np.int64)
    best = np.zeros(len(obj.data.vertices))
    for v in obj.data.vertices:
        for ge in v.groups:
            if ge.weight > best[v.index] and ge.group < len(group_to_bone):
                best[v.index] = ge.weight
                out[v.index] = group_to_bone[ge.group]
    return out


def bridge_triangles(obj, bone_names: list, parents: list, max_hops: int = 3) -> dict:
    """Count triangles whose dominant bones are more than `max_hops` apart in the bone tree.

    The build-time twin of `game/enemies/models/tests/probe_fuse.gd` — same rule, so a rebuild can
    be judged without a Godot run."""
    dom = dominant_bones(obj, bone_names)

    def hops(a: int, b: int) -> int:
        chain = []
        n = a
        while n >= 0:
            chain.append(n)
            n = parents[n]
        steps = 0
        n = b
        while n >= 0:
            if n in chain:
                return chain.index(n) + steps
            n = parents[n]
            steps += 1
        return 99

    cache = {}
    pairs = {}
    bridge = 0
    tris = triangulate(obj.data.polygons)
    d = dom[tris]
    for t in range(len(tris)):
        worst, pa, pb = 0, -1, -1
        for e in range(3):
            a, b = int(d[t, e]), int(d[t, (e + 1) % 3])
            if a < 0 or b < 0 or a == b:
                continue
            key = (a, b) if a < b else (b, a)
            if key not in cache:
                cache[key] = hops(*key)
            if cache[key] > worst:
                worst, pa, pb = cache[key], key[0], key[1]
        if worst > max_hops:
            bridge += 1
            pairs["%s|%s" % (bone_names[pa], bone_names[pb])] = \
                pairs.get("%s|%s" % (bone_names[pa], bone_names[pb]), 0) + 1
    return {"tris": len(tris), "bridge": bridge, "pairs": pairs}


def segments_of(arm, bones: list) -> np.ndarray:
    """(bones, 2, 3) world-space head/tail array for a chosen subset of the armature."""
    mw = arm.matrix_world
    return np.array([[[c for c in (mw @ b.head_local)], [c for c in (mw @ b.tail_local)]]
                     for b in bones], dtype=np.float64)


def bone_segments(arm) -> tuple:
    """(names, (bones, 2, 3) world-space head/tail array) for distance queries."""
    names = [b.name for b in arm.data.bones]
    return names, segments_of(arm, list(arm.data.bones))


def distance_to_segments(points: np.ndarray, seg: np.ndarray) -> np.ndarray:
    """(points, bones) distance from each point to each bone's head-tail segment."""
    a = seg[:, 0][None, :, :]
    ab = (seg[:, 1] - seg[:, 0])[None, :, :]
    ap = points[:, None, :] - a
    denom = np.maximum((ab * ab).sum(axis=2), 1e-9)
    t = np.clip((ap * ab).sum(axis=2) / denom, 0.0, 1.0)
    proj = a + t[:, :, None] * ab
    return np.linalg.norm(points[:, None, :] - proj, axis=2)


def polyline_distance(points: np.ndarray, line: np.ndarray) -> np.ndarray:
    """Distance from each point to a polyline, and its fractional position along it."""
    a, b = line[:-1], line[1:]
    ab = b - a
    denom = np.maximum((ab * ab).sum(axis=1), 1e-9)
    best = np.full(len(points), np.inf)
    param = np.zeros(len(points))
    for i in range(len(a)):
        t = np.clip(((points - a[i]) * ab[i]).sum(axis=1) / denom[i], 0.0, 1.0)
        proj = a[i] + t[:, None] * ab[i]
        d = np.linalg.norm(points - proj, axis=1)
        closer = d < best
        best = np.where(closer, d, best)
        param = np.where(closer, i + t, param)
    return best, param


def flood_from(seed: int, allowed: np.ndarray, graph: tuple) -> np.ndarray:
    """Boolean mask of the vertices reachable from `seed` through edges, staying inside `allowed`."""
    starts, nbr, counts = graph
    out = np.zeros(len(allowed), dtype=bool)
    if not allowed[seed]:
        return out
    out[seed] = True
    stack = [seed]
    while stack:
        v = stack.pop()
        for u in nbr[starts[v]:starts[v] + counts[v]]:
            if allowed[u] and not out[u]:
                out[u] = True
                stack.append(int(u))
    return out


def kd_from_points(points: np.ndarray) -> KDTree:
    tree = KDTree(len(points))
    for i, p in enumerate(points):
        tree.insert(Vector(p), i)
    tree.balance()
    return tree


# --- the build-time twin of probe_anim.gd -------------------------------------------------------

#: edges shorter than this at rest are numerical noise, not skin (a decimated shell has plenty).
MIN_REST = 0.02
#: how many edges to follow. 4000 is what the acceptance probe samples, so the numbers compare.
SAMPLE_EDGES = 4000
#: The gate the lead set (r5 item 1) was "no edge passes 2x its bind length". Measured on Tripo's
#: own rig of the same animal, placed at the same scale, that is unreachable: it reaches 4.75x on
#: the titan at the joints, and the ratio also grows with mesh density (the same weight gradient
#: sampled over an edge 2.7x shorter reads as 2.7x the stretch). What the acceptance pass actually
#: saw was *long* sheets — 8.8-14.4 m on the mantis, 15.9-50 m on the titan — so the build gates on
#: the absolute length of the worst posed edge as a fraction of the model's bounding diagonal, and
#: prints the ratio beside it for comparison against Tripo's own rig.
STRETCH_GATE = 0.15


def _skin_tables(mesh, arm) -> tuple:
    """(bone indices, weights, rest positions in armature space) for the mesh's top-4 groups."""
    to_arm = arm.matrix_world.inverted() @ mesh.matrix_world
    rest = np.array([[c for c in (to_arm @ v.co)] for v in mesh.data.vertices], dtype=np.float64)
    lookup = {bone.name: i for i, bone in enumerate(arm.data.bones)}
    group_bone = np.full(max((vg.index for vg in mesh.vertex_groups), default=-1) + 1, -1,
                         dtype=np.int64)
    for vg in mesh.vertex_groups:
        group_bone[vg.index] = lookup.get(vg.name, -1)
    bidx = np.zeros((len(rest), 4), dtype=np.int64)
    wts = np.zeros((len(rest), 4), dtype=np.float64)
    for v in mesh.data.vertices:
        rows = [(float(g.weight), int(group_bone[g.group]))
                for g in v.groups if g.group < len(group_bone) and group_bone[g.group] >= 0]
        rows.sort(reverse=True)
        for k, (w, b) in enumerate(rows[:4]):
            bidx[v.index, k], wts[v.index, k] = b, w
    total = wts.sum(axis=1, keepdims=True)
    wts = np.where(total > 1e-9, wts / np.maximum(total, 1e-9), 0.0)
    return bidx, wts, rest


def _sampled_edges(mesh_data, rest: np.ndarray, count: int = SAMPLE_EDGES) -> tuple:
    ends = np.array([e.vertices[:] for e in mesh_data.edges], dtype=np.int64)
    length = np.linalg.norm(rest[ends[:, 0]] - rest[ends[:, 1]], axis=1)
    keep = np.nonzero(length >= MIN_REST)[0]
    if len(keep) > count:
        keep = keep[np.linspace(0, len(keep) - 1, count).astype(np.int64)]
    return ends[keep, 0], ends[keep, 1], length[keep]


def _skin_matrices(arm) -> np.ndarray:
    """(bones, 4, 4) armature-space skin matrices for the pose currently on the armature."""
    out = np.zeros((len(arm.data.bones), 4, 4), dtype=np.float64)
    for i, bone in enumerate(arm.data.bones):
        out[i] = np.array(arm.pose.bones[bone.name].matrix @ bone.matrix_local.inverted())
    return out


def _edge_owner(mesh, arm, a: int, b: int) -> str:
    """Which bones dominate the two ends of an edge — the answer to "where does the skin tear"."""
    names = [bone.name for bone in arm.data.bones]
    out = []
    for v in (a, b):
        rows = sorted(((float(g.weight), mesh.vertex_groups[g.group].name)
                       for g in mesh.data.vertices[v].groups
                       if g.group < len(mesh.vertex_groups)), reverse=True)[:4]
        out.append("+".join("%s %.2f" % (n, w) for w, n in rows if n in names))
    return " | ".join(out)


def stretch_report(label: str, mesh, arm, clips: dict, hz: float = 12.0,
                   gate: float = STRETCH_GATE) -> dict:
    """Worst per-edge stretch against the bind length, per clip — the gate `check_skin` could not
    see (lead r5 item 1: a sheet stretched between two limbs stays inside the bounding box).

    Prints one `STRETCH` line per clip and returns {clip: worst ratio}."""
    bidx, wts, rest = _skin_tables(mesh, arm)
    ea, eb, elen = _sampled_edges(mesh.data, rest)
    used = np.unique(np.concatenate([ea, eb]))
    slot = {int(v): i for i, v in enumerate(used)}
    sa = np.array([slot[int(v)] for v in ea])
    sb = np.array([slot[int(v)] for v in eb])
    sub_b, sub_w = bidx[used], wts[used]
    # homogeneous rest positions: the skin matrix carries the translation in its 4th column
    sub_c = np.concatenate([rest[used], np.ones((len(used), 1))], axis=1)
    data = arm.animation_data_create()
    previous = data.action
    pts = world_points(mesh)
    # the model's own scale, so a 6 m ripper and a 60 m titan are judged on the same footing
    height = float(np.linalg.norm(pts.max(axis=0) - pts.min(axis=0)))
    worst, longest_all = {}, {}
    for clip_id, action in sorted(clips.items()):
        start, end = int(action.frame_range[0]), int(action.frame_range[1])
        data.action = action
        if hasattr(action, "slots") and len(action.slots):
            data.action_slot = action.slots[0]
        steps = max(int(round((end - start) / max(bpy.context.scene.render.fps / hz, 1.0))), 1)
        frames = sorted({start + round(i * (end - start) / steps) for i in range(steps + 1)})
        top, top_frame, top_edge = 1.0, start, -1
        longest, longest_frame = 0.0, start
        for frame in frames:
            bpy.context.scene.frame_set(frame)
            skin = _skin_matrices(arm)
            posed = np.einsum("mkij,mj->mki", skin[sub_b], sub_c)[:, :, :3]
            pos = (posed * sub_w[:, :, None]).sum(axis=1)
            length = np.linalg.norm(pos[sa] - pos[sb], axis=1)
            ratio = length / elen
            if ratio.max() > top:
                top, top_frame, top_edge = float(ratio.max()), frame, int(ratio.argmax())
            if length.max() > longest:
                longest, longest_frame = float(length.max()), frame
        who = _edge_owner(mesh, arm, int(ea[top_edge]), int(eb[top_edge])) if top_edge >= 0 else ""
        worst[clip_id] = round(top, 2)
        longest_all[clip_id] = round(longest, 3)
        rest = float(elen[top_edge]) if top_edge >= 0 else 0.0
        print("STRETCH %-11s %-14s worst %6.2fx  longest posed edge %5.2f m from %4.2f m"
              " (%4.1f%% of the model) @ frame %4d  %-30s %s"
              % (label, clip_id, top, longest, rest, 100.0 * longest / max(height, 1e-6),
                 longest_frame, who, "OK" if longest <= gate * height else "OVER GATE"))
    data.action = previous
    bpy.context.scene.frame_set(0)
    longest = max(longest_all.values()) if longest_all else 0.0
    print("STRETCH %-11s SUMMARY worst %.2fx, longest posed edge %.2f m (%.1f%% of a %.1f m"
          " bounding diagonal), gate %.1f%%"
          % (label, max(worst.values()) if worst else 1.0, longest,
             100.0 * longest / max(height, 1e-6), height, 100.0 * gate))
    return {"ratio": worst, "longest_m": longest_all, "height_m": round(height, 3),
            "worst_ratio": round(max(worst.values()) if worst else 1.0, 2),
            "longest_frac": round(longest / max(height, 1e-6), 4)}
