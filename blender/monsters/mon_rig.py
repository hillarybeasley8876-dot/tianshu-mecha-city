"""Rig surgery and custom armatures for the HUSK monsters (monster-assets).

Three jobs (lead note, monster-assets):
  1. collapse the Tripo humanoid's 30 finger joints into 3 claw bones per hand (mantis scythes,
     juggernaut and titan claws) — 15 bones a hand animate nothing a player can read;
  2. give the titan the tail and jaw Tripo's biped rig has no bones for;
  3. build armatures from scratch for the spitter and the harrier, which Tripo refused to rig.

Weights are never solved by heat on a Tripo shell (they are often non-manifold and the solve fails);
heat runs on a voxel-remeshed manifold proxy and the result is Data Transferred back.
"""
import bpy
import numpy as np
from mathutils import Matrix, Vector

#: how far the tail's root blend reaches along the surface, as a fraction of the tail's length.
#: Wide enough that the per-edge step in Tail_0's share stays under the stretch gate.
TAIL_BLEND_FRAC = 0.14
#: which finger chains fold into which claw, per hand side
CLAW_OF_FINGER = {"Thumb": 0, "Index": 1, "Mid": 1, "Ring": 2, "Pinky": 2}
SIDES = ("L", "R")


def purge_bone_fcurves(action, bone_names: set) -> int:
    """Drop the animation channels of bones that no longer exist (keeps the GLB clean)."""
    gone = 0
    for fc in list(_all_fcurves(action)):
        for name in bone_names:
            if 'pose.bones["%s"]' % name in fc.data_path:
                _remove_fcurve(action, fc)
                gone += 1
                break
    return gone


def _all_fcurves(action) -> list:
    try:
        return list(action.fcurves)
    except AttributeError:
        out = []
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    out.extend(bag.fcurves)
        return out


def _remove_fcurve(action, fc) -> None:
    try:
        action.fcurves.remove(fc)
        return
    except AttributeError:
        pass
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                if fc in list(bag.fcurves):
                    bag.fcurves.remove(fc)
                    return


def group_weights(obj) -> dict:
    """name -> {vertex index: weight} for every vertex group on the mesh."""
    out = {vg.index: {} for vg in obj.vertex_groups}
    names = {vg.index: vg.name for vg in obj.vertex_groups}
    for v in obj.data.vertices:
        for ge in v.groups:
            if ge.weight > 1e-4:
                out[ge.group][v.index] = ge.weight
    return {names[i]: w for i, w in out.items()}


def set_weights(obj, weights: dict) -> None:
    """Replace every vertex group with `weights` (name -> {vertex index: weight}), normalised to 1."""
    for vg in list(obj.vertex_groups):
        obj.vertex_groups.remove(vg)
    groups = {name: obj.vertex_groups.new(name=name) for name in weights}
    for name, per_vert in weights.items():
        vg = groups[name]
        for idx, w in per_vert.items():
            if w > 1e-4:
                vg.add([idx], min(1.0, float(w)), "REPLACE")
    normalise(obj)


def normalise(obj) -> None:
    """Make each vertex's weights sum to 1 (skinning breaks if they do not)."""
    totals = np.zeros(len(obj.data.vertices), dtype=np.float64)
    entries = []
    for v in obj.data.vertices:
        for ge in v.groups:
            if ge.weight > 1e-4:
                totals[v.index] += ge.weight
                entries.append((v.index, ge.group, ge.weight))
    if not entries:
        return
    scale = np.where(totals > 1e-6, 1.0 / np.maximum(totals, 1e-6), 0.0)
    lookup = {vg.index: vg for vg in obj.vertex_groups}
    for idx, gi, w in entries:
        lookup[gi].add([idx], float(w * scale[idx]), "REPLACE")


# --- 1. finger chains -> 3 claws per hand -------------------------------------------------------

def collapse_claws(arm, mesh, actions: list) -> dict:
    """Replace each hand's five finger chains with three claw bones.

    Returns {'removed': [...], 'claws': [...]} so the build report can show the bone saving."""
    plan = {}
    for side in SIDES:
        for finger, claw in CLAW_OF_FINGER.items():
            chain = ["%s_%s%d" % (side, finger, i) for i in (1, 2, 3)]
            if not all(b in arm.data.bones for b in chain):
                continue
            plan.setdefault((side, claw), []).append(chain)
    if not plan:
        return {"removed": [], "claws": []}
    weights = group_weights(mesh)
    merged, removed, claws = {}, [], []
    for (side, claw), chains in sorted(plan.items()):
        name = "%s_Claw%d" % (side, claw + 1)
        per_vert = {}
        for chain in chains:
            for bone in chain:
                removed.append(bone)
                for idx, w in weights.pop(bone, {}).items():
                    per_vert[idx] = per_vert.get(idx, 0.0) + w
        merged[name] = per_vert
        heads = [arm.data.bones[c[0]].head_local for c in chains]
        tails = [arm.data.bones[c[-1]].tail_local for c in chains]
        claws.append((name, "%s_Hand" % side,
                      sum(heads, Vector()) / len(heads), sum(tails, Vector()) / len(tails)))
    weights.update(merged)
    set_weights(mesh, weights)
    _edit_bones(arm, lambda ebs: _apply_claws(ebs, claws, removed))
    gone = set(removed)
    for action in actions:
        purge_bone_fcurves(action, gone)
    return {"removed": removed, "claws": [c[0] for c in claws]}


def _apply_claws(edit_bones, claws: list, removed: list) -> None:
    for bone in removed:
        if bone in edit_bones:
            edit_bones.remove(edit_bones[bone])
    for name, parent, head, tail in claws:
        bone = edit_bones.new(name)
        bone.head, bone.tail = head, tail
        bone.parent = edit_bones.get(parent)
        bone.use_connect = False


def _edit_bones(arm, fn) -> None:
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    fn(arm.data.edit_bones)
    bpy.ops.object.mode_set(mode="OBJECT")


def rename_bone(arm, old: str, new: str, actions: list) -> bool:
    """Rename a bone and every animation channel that drives it."""
    if old not in arm.data.bones:
        return False
    _edit_bones(arm, lambda ebs: setattr(ebs[old], "name", new))
    mesh_groups = [o for o in bpy.data.objects if o.type == "MESH"]
    for obj in mesh_groups:
        vg = obj.vertex_groups.get(old)
        if vg is not None:
            vg.name = new
    for action in actions:
        for fc in _all_fcurves(action):
            if 'pose.bones["%s"]' % old in fc.data_path:
                fc.data_path = fc.data_path.replace('pose.bones["%s"]' % old,
                                                    'pose.bones["%s"]' % new)
    return True


# --- 2. the titan's tail and jaw ------------------------------------------------------------------

def _world_verts(mesh) -> np.ndarray:
    mw = mesh.matrix_world
    return np.array([[c for c in (mw @ v.co)] for v in mesh.data.vertices], dtype=float)


def _polyline_param(points: np.ndarray, line: np.ndarray) -> np.ndarray:
    """For each point, its fractional position along a polyline (0..len(line)-1)."""
    a, b = line[:-1], line[1:]
    ab = b - a
    denom = np.maximum((ab * ab).sum(axis=1), 1e-9)
    out = np.zeros(len(points))
    best = np.full(len(points), np.inf)
    for i in range(len(a)):
        t = np.clip(((points - a[i]) * ab[i]).sum(axis=1) / denom[i], 0.0, 1.0)
        proj = a[i] + t[:, None] * ab[i]
        d = np.linalg.norm(points - proj, axis=1)
        closer = d < best
        best = np.where(closer, d, best)
        out = np.where(closer, i + t, out)
    return out


def _fit_chain(points: np.ndarray, bones: int, y_hi: float) -> np.ndarray:
    """`bones + 1` node positions along a tail: the mean of each equal-width slab of −Y."""
    edges = np.linspace(y_hi, points[:, 1].min(), bones + 1)
    line = []
    for i in range(bones + 1):
        lo, hi = (edges[i + 1], edges[i]) if i < bones else (edges[-1], edges[-1])
        sel = points[(points[:, 1] >= lo) & (points[:, 1] < hi)] if i < bones else \
            points[points[:, 1] <= edges[-1] + 1e-6]
        line.append(sel.mean(axis=0) if len(sel) else (line[-1] if line else points.mean(axis=0)))
    return np.array(line)


def tail_mask(mesh, arm, pelvis: Vector, bones: int, ratio: float = 1.0,
              radius_frac: float = 0.12, passes: int = 4) -> tuple:
    """The vertices that really are tail: nearer the fitted chain than to any other bone, behind the
    pelvis, and connected to the tail tip.

    Lead r5 item 1: the old test was a plane `root_gap` behind the pelvis. On the titan that plane
    sits at y = 17.8 while its feet are at y = 16.7, so 60 % of LOD0 — calves, forearms, toes — came
    back carrying tail weights and the skin tore in every clip. Distance to the chain decides it
    instead, and the mesh's own connectivity stops the region leaking into the body."""
    from monsters import mon_skin

    pts = _world_verts(mesh)
    # a previous tail chain must not compete with the one being fitted (a rebuild re-runs this)
    body_bones = [b for b in arm.data.bones if not b.name.startswith("Tail_")]
    seg = mon_skin.segments_of(arm, body_bones)
    graph = mon_skin.csr_adjacency(mesh.data)
    lo, hi = pts.min(axis=0), pts.max(axis=0)
    radius = radius_frac * float(np.linalg.norm(hi - lo))
    tip = int(np.argmin(pts[:, 1]))
    line = np.array([[pelvis.x, pelvis.y, pelvis.z], pts[tip]])
    mask = np.zeros(len(pts), dtype=bool)
    for _ in range(passes):
        d_chain, _ = mon_skin.polyline_distance(pts, line)
        d_other = mon_skin.distance_to_segments(pts, seg).min(axis=1)
        allowed = (d_chain < ratio * np.maximum(d_other, 1e-6)) & (d_chain < radius) \
            & (pts[:, 1] <= pelvis.y)
        mask = mon_skin.flood_from(tip, allowed, graph)
        if mask.sum() < bones * 8:
            break
        line = _fit_chain(pts[mask], bones, float(pts[mask][:, 1].max()))
    return mask, line, pts


def add_tail(arm, mesh, bones: int = 6, parent: str = "Pelvis") -> dict:
    """Fit a bone chain to the tail hanging behind the pelvis and skin the tail to it.

    Called after the model has been oriented (facing +Y). Returns a report dict with the chain
    length and how many vertices moved."""
    pel = arm.matrix_world @ arm.data.bones[parent].head_local
    mask, line, pts = tail_mask(mesh, arm, pel, bones)
    if mask.sum() < bones * 8:
        raise RuntimeError("add_tail: only %d tail vertices found" % int(mask.sum()))
    names = ["Tail_%d" % i for i in range(bones)]
    _edit_bones(arm, lambda ebs: _make_chain(ebs, names, line, parent))

    idx_tail = np.nonzero(mask)[0]
    t = _polyline_param(pts[idx_tail], line)
    weights = group_weights(mesh)
    blend_verts = 0
    # the tail's old weights (Tripo had no tail bones, so they land on legs and spine) are wrong:
    # drop them and write the chain weights instead.
    for name in weights:
        for idx in idx_tail:
            weights[name].pop(int(idx), None)
    for k in range(bones + 1):
        target = names[min(k, bones - 1)]
        share = np.clip(1.0 - np.abs(t - k), 0.0, 1.0)
        for idx, w in zip(idx_tail, share):
            if w > 1e-3:
                weights.setdefault(target, {})[int(idx)] = float(w)
    length = float(np.linalg.norm(np.diff(line, axis=0), axis=1).sum())
    # The blend band at the root, measured as geodesic distance from the tail's first segment along
    # the mesh, so the tail's share falls to zero over `band_m` metres of *surface* instead of over
    # two rings. A two-ring step tore the root: 0.33 of Tail_0 on a pelvis vertex is half a metre of
    # displacement across a 0.15 m edge (lead r5 item 1). The body's own weights are kept and scaled
    # down by the ramp — overwriting them left those vertices with nothing but Tail_0.
    band_m = TAIL_BLEND_FRAC * length
    root_mask = np.zeros(len(pts), dtype=bool)
    root_mask[idx_tail[t <= 1.5]] = True
    for idx, share in _blend_band(mesh, root_mask, band_m):
        blend_verts += 1
        for name in list(weights):
            w = weights[name].get(idx)
            if w is not None:
                weights[name][idx] = w * (1.0 - share)
        weights.setdefault(names[0], {})[idx] = \
            max(weights.get(names[0], {}).get(idx, 0.0), share)
    set_weights(mesh, weights)
    return {"bones": names, "length": round(length, 3), "tail_verts": int(len(idx_tail)),
            "blend_verts": int(blend_verts), "root": [round(float(c), 3) for c in line[0]]}


def _blend_band(mesh, mask: np.ndarray, band_m: float) -> list:
    """(vertex, share) for every vertex within `band_m` metres of `mask` along the mesh surface.

    Dijkstra over the edge graph with edge lengths as costs, seeded from the whole region, so the
    share falls off with real surface distance rather than with ring count."""
    import heapq

    from monsters import mon_skin

    starts, nbr, counts = mon_skin.csr_adjacency(mesh.data)
    pts = _world_verts(mesh)
    best = np.full(len(pts), np.inf)
    heap = []
    for v in np.nonzero(mask)[0]:
        best[v] = 0.0
        heap.append((0.0, int(v)))
    heapq.heapify(heap)
    while heap:
        d, v = heapq.heappop(heap)
        if d > best[v] or d > band_m:
            continue
        for u in nbr[starts[v]:starts[v] + counts[v]]:
            step = float(np.linalg.norm(pts[u] - pts[v]))
            if d + step < best[u]:
                best[u] = d + step
                heapq.heappush(heap, (d + step, int(u)))
    out = []
    for v in np.nonzero((best > 0.0) & (best <= band_m))[0]:
        out.append((int(v), float(np.clip(1.0 - best[v] / max(band_m, 1e-6), 0.0, 1.0))))
    return out


def _make_chain(edit_bones, names: list, line: np.ndarray, parent: str) -> None:
    prev = edit_bones.get(parent)
    for i, name in enumerate(names):
        bone = edit_bones.new(name)
        bone.head = Vector((float(c) for c in line[i]))
        bone.tail = Vector((float(c) for c in line[i + 1]))
        bone.parent = prev
        bone.use_connect = prev is not None and i > 0
        prev = bone


def add_jaw(arm, mesh, head: str = "Head", jaw: str = "Jaw", source: str = "FacialBone") -> dict:
    """Give the skull a jaw bone and move the lower front of the head onto it.

    Tripo's biped rig has a stub `FacialBone` in about the right place, so it is renamed rather than
    invented; the vertices that actually form the lower jaw are then re-weighted onto it."""
    rename_bone(arm, source, jaw, list(bpy.data.actions))
    if jaw not in arm.data.bones:
        raise RuntimeError("add_jaw: no %s bone and no %s to rename" % (jaw, source))
    hb = arm.data.bones[head]
    origin = arm.matrix_world @ hb.head_local
    length = max((arm.matrix_world @ hb.tail_local - origin).length, 1e-3)
    _edit_bones(arm, lambda ebs: _place_jaw(ebs, jaw, head, origin, length))

    pts = _world_verts(mesh)
    weights = group_weights(mesh)
    dominant = np.full(len(pts), "", dtype=object)
    best = np.zeros(len(pts))
    for name in (head, jaw):
        for idx, w in weights.get(name, {}).items():
            if w > best[idx]:
                best[idx], dominant[idx] = w, name
    cand = np.array([d in (head, jaw) for d in dominant])
    front = np.clip((pts[:, 1] - origin.y) / (0.35 * length), 0.0, 1.0)
    below = np.clip((origin.z - pts[:, 2]) / (0.45 * length), 0.0, 1.0)
    share = np.where(cand, np.minimum(front, below), 0.0)
    moved = 0
    for idx in np.nonzero(share > 0.05)[0]:
        i, w = int(idx), float(share[idx])
        take = (weights.get(head, {}).get(i, 0.0) + weights.get(jaw, {}).get(i, 0.0)) * w
        if take <= 1e-4:
            continue
        for name in (head, jaw):
            if i in weights.get(name, {}):
                weights[name][i] *= (1.0 - w)
        weights.setdefault(jaw, {})[i] = weights.get(jaw, {}).get(i, 0.0) * (1.0 - w) + take
        moved += 1
    set_weights(mesh, weights)
    return {"jaw": jaw, "verts": moved, "origin": [round(float(c), 3) for c in origin]}


def _place_jaw(edit_bones, jaw: str, head: str, origin: Vector, length: float) -> None:
    bone = edit_bones[jaw]
    bone.head = origin
    bone.tail = origin + Vector((0.0, 0.85 * length, -0.25 * length))
    bone.parent = edit_bones.get(head)
    bone.use_connect = False


# --- 3. armatures built from scratch (spitter, harrier) -------------------------------------------

def slab_centroids(pts: np.ndarray, axis: int, edges: np.ndarray) -> np.ndarray:
    """Centroid of the points inside each slab along `axis`, in slab order.

    Empty slabs are filled by interpolating (or extrapolating) between the nearest slabs that do
    have points, stepped along `axis`. Copying a neighbour's centroid instead — which is what this
    used to do — puts two centroids on the same point and produces a zero-length bone, which is how
    the harrier's wing roots and one of its legs came out degenerate."""
    out = []
    for i in range(len(edges) - 1):
        sel = pts[(pts[:, axis] >= edges[i]) & (pts[:, axis] < edges[i + 1])]
        out.append(sel.mean(axis=0) if len(sel) else None)
    known = [i for i, c in enumerate(out) if c is not None]
    if not known:
        return np.repeat(pts.mean(axis=0)[None, :], len(out), axis=0)
    step = float(edges[-1] - edges[0]) / max(len(out), 1)
    for i, c in enumerate(out):
        if c is not None:
            continue
        before = max([k for k in known if k < i], default=None)
        after = min([k for k in known if k > i], default=None)
        if before is not None and after is not None:
            out[i] = out[before] + (out[after] - out[before]) * ((i - before) / (after - before))
            continue
        anchor, away = (before, step) if before is not None else (after, -step)
        out[i] = out[anchor].copy()
        out[i][axis] += away * abs(i - anchor)
    return np.array(out)


def build_armature(name: str, spec: list):
    """Create an armature from [(bone, head, tail, parent, connect)] in world space."""
    arm_data = bpy.data.armatures.new(name)
    arm = bpy.data.objects.new(name, arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for bone_name, head, tail, parent, connect in spec:
        bone = arm_data.edit_bones.new(bone_name)
        bone.head = Vector((float(c) for c in head))
        bone.tail = Vector((float(c) for c in tail))
        if parent:
            bone.parent = arm_data.edit_bones.get(parent)
            bone.use_connect = bool(connect)
    bpy.ops.object.mode_set(mode="OBJECT")
    degenerate = [b.name for b in arm_data.bones if b.length < 1e-4]
    if degenerate:
        raise RuntimeError("%s: zero-length bones %s — a fitted limb collapsed onto one point "
                           "(mon_custom_rigs._limb_line bins between ascending edges)"
                           % (name, ", ".join(degenerate)))
    return arm


def rig_from_proxy(mesh, arm, voxel_frac: float = 0.012) -> dict:
    """Skin `mesh` to `arm`: heat-solve on a manifold voxel proxy, then Data Transfer back.

    Heat weighting fails outright on the Tripo shells (non-manifold), which is why the solve runs on
    a voxel remesh and only the result is transferred (lead note, monster-assets)."""
    from monsters import mon_lib, mon_skin

    lo, hi = mon_lib.mesh_bounds(mesh)
    voxel = max((hi - lo).length * voxel_frac, 1e-3)
    proxy = mon_lib.voxel_proxy(mesh, voxel, "%s_proxy" % mesh.name)
    ok = mon_lib.heat_weight(proxy, arm)
    tris = mon_lib.tri_count(proxy)
    if not ok:
        raise RuntimeError("rig_from_proxy: heat weighting failed on the voxel proxy of %s" % mesh.name)
    # the proxy and the mesh are different tessellations of the same shell, so the weights travel
    # along the mesh's own surface (lead r5 item 1) instead of by nearest face in 3-space.
    xfer = mon_skin.transfer_surface(proxy, mesh)
    rms = mon_lib.surface_rms(mon_lib.sample_points(proxy, 4000), mesh)
    normalise(mesh)
    bpy.data.objects.remove(proxy, do_unlink=True)
    return {"voxel": round(voxel, 4), "proxy_tris": tris, "groups": xfer["groups"],
            "proxy_to_mesh_rms": round(rms, 4), "xfer": xfer}


def bind_mesh(mesh, arm) -> None:
    """Parent the mesh to the armature with ONE Armature modifier (weights already on the mesh).

    Idempotent on purpose: the build calls it before and after the model is placed, and a second
    Armature modifier would apply the skinning twice — which tears the mesh apart."""
    mesh.parent = arm
    mesh.matrix_parent_inverse = arm.matrix_world.inverted()
    mod = next((m for m in mesh.modifiers if m.type == "ARMATURE"), None)
    if mod is None:
        mod = mesh.modifiers.new("Armature", "ARMATURE")
    mod.object = arm




