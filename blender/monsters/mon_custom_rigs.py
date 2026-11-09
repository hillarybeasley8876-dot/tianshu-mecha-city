"""Armatures for the two monsters Tripo could not rig (monster-assets).

Both are fitted to the already-oriented, already-scaled mesh (facing +Y, metres) by binning the
mesh into slabs and taking centroids. Precision is not critical: the bones only have to sit inside
each limb, because the actual weights come from a heat solve on a manifold voxel proxy
(`mon_rig.rig_from_proxy`).
"""
import numpy as np

from monsters import mon_rig
from monsters.mon_rig import build_armature, slab_centroids

#: leg chains, spine, neck/launcher, sac — briefs/monster-assets.md "Spitter"
SPITTER_BONES = 4 * 3 + 3 + 2 + 1
#: 2 wings x 3, spine 3, neck/head 2, tail 3, legs 2 x 2 — same brief, "Harrier"
HARRIER_BONES = 2 * 3 + 3 + 2 + 3 + 2 * 2


def _main_axis(pts: np.ndarray) -> int:
    """The axis the points spread along most (0 = x, 1 = y, 2 = z)."""
    return int(np.argmax(pts.max(axis=0) - pts.min(axis=0)))


def _edges(lo: float, hi: float, bones: int) -> np.ndarray:
    """Slab edges producing exactly `bones` centroids (n bones need n+1 centroids, so n+2 edges)."""
    return np.linspace(lo, hi, bones + 2)


def _chain(prefix: str, line: np.ndarray, parent: str, connect_from: int = 1) -> list:
    spec = []
    for i in range(len(line) - 1):
        spec.append(("%s_%d" % (prefix, i), line[i], line[i + 1], parent, i >= connect_from))
        parent = "%s_%d" % (prefix, i)
    return spec


def _limb_line(pts: np.ndarray, axis: int, bones: int, anchor: float) -> np.ndarray:
    """Slab centroids along `axis`, ordered from the limb's root (nearest `anchor`) outwards.

    `slab_centroids` bins between *ascending* edges; passing descending ones makes every slab empty,
    and the empty-slab fallback then collapses the whole limb onto one point — which is how the
    spitter's legs and the harrier's legs and tail came out as zero-length bones (found by the
    stride measurement: their feet never moved). `build_armature` now refuses degenerate bones."""
    edges = np.linspace(pts[:, axis].min(), pts[:, axis].max(), bones + 2)
    line = slab_centroids(pts, axis, edges)
    far_min = abs(pts[:, axis].min() - anchor) > abs(pts[:, axis].max() - anchor)
    return line if far_min else line[::-1]


def spitter_rig(mesh):
    """Quadruped artillery: 4 legs x 3 bones, spine 3, neck + launcher, sac."""
    pts = mon_rig._world_verts(mesh)
    lo, hi = pts.min(axis=0), pts.max(axis=0)
    h = hi[2] - lo[2]
    leg_top = lo[2] + 0.46 * h
    legs, body = pts[pts[:, 2] < leg_top], pts[pts[:, 2] >= leg_top]
    centre = body.mean(axis=0)
    spec = [("Root", centre - [0, 0, 0.25 * h], centre, None, False)]

    spine_y = _edges(centre[1] - 0.30 * (hi[1] - lo[1]), centre[1] + 0.16 * (hi[1] - lo[1]), 3)
    spine = slab_centroids(body, 1, spine_y)
    spec += _chain("Spine", spine, "Root", connect_from=0)

    front = body[body[:, 1] > spine_y[-2]]
    if len(front) > 40:
        neck = slab_centroids(front, 1, _edges(spine_y[-1], hi[1], 2))
        spec += _chain("Launcher", neck, "Spine_2", connect_from=0)

    sac_pts = body[(body[:, 2] > hi[2] - 0.22 * h) & (body[:, 1] < centre[1])]
    if len(sac_pts) > 20:
        base = np.array([centre[0], sac_pts[:, 1].mean(), sac_pts[:, 2].min()])
        spec.append(("Sac", base, sac_pts.mean(axis=0), "Spine_0", False))

    for sx, sy, name in ((-1, 1, "LegFL"), (1, 1, "LegFR"), (-1, -1, "LegBL"), (1, -1, "LegBR")):
        sel = legs[(np.sign(legs[:, 0] - centre[0]) == sx) & (np.sign(legs[:, 1] - centre[1]) == sy)]
        if len(sel) < 20:
            continue
        spec += _chain(name, _limb_line(sel, 2, 3, leg_top), "Root", connect_from=1)
    return build_armature("SpitterRig", spec), spec


def harrier_rig(mesh):
    """Flyer: 2 wings x 3 bones, spine 3, neck + head, tail 3, 2 legs x 2."""
    pts = mon_rig._world_verts(mesh)
    lo, hi = pts.min(axis=0), pts.max(axis=0)
    span = hi[0] - lo[0]
    root_x = lo[0] + 0.30 * span
    core = pts[np.abs(pts[:, 0] - (lo[0] + hi[0]) * 0.5) < (root_x - lo[0])]
    centre = core.mean(axis=0)
    spec = [("Root", centre - [0, 0, 0.1 * (hi[2] - lo[2])], centre, None, False)]

    spine_y = _edges(centre[1] - 0.18 * (hi[1] - lo[1]), centre[1] + 0.22 * (hi[1] - lo[1]), 3)
    spec += _chain("Spine", slab_centroids(core, 1, spine_y), "Root", connect_from=0)

    head_pts = core[core[:, 1] > spine_y[-2]]
    if len(head_pts) > 20:
        spec += _chain("Head", slab_centroids(head_pts, 1, _edges(spine_y[-1], hi[1], 2)),
                       "Spine_2", connect_from=0)

    rear = core[core[:, 1] < spine_y[1]]
    if len(rear) > 20:
        axis = _main_axis(rear)
        spec += _chain("Tail", _limb_line(rear, axis, 3, centre[axis]), "Spine_0", connect_from=0)

    low = core[core[:, 2] < centre[2] - 0.12 * (hi[2] - lo[2])]
    for sx, name in ((-1, "LegL"), (1, "LegR")):
        sel = low[np.sign(low[:, 0] - centre[0]) == sx]
        if len(sel) < 12:
            continue
        spec += _chain(name, _limb_line(sel, 2, 2, centre[2]), "Root", connect_from=1)

    for sx, name in ((-1, "WingL"), (1, "WingR")):
        side = lo[0] if sx < 0 else hi[0]
        sel = pts[np.sign(pts[:, 0] - centre[0]) == sx]
        sel = sel[np.abs(sel[:, 0] - centre[0]) > (root_x - lo[0])]
        if len(sel) < 40:
            continue
        edges = _edges(centre[0] + sx * (root_x - lo[0]) * 0.6, side, 3)
        edges = np.sort(edges)
        line = slab_centroids(sel, 0, edges)
        if sx < 0:
            line = line[::-1]
        spec += _chain(name, line, "Spine_2", connect_from=1)
    return build_armature("HarrierRig", spec), spec
