"""Segment the Tianshu hero into rigid armour pieces (hero-v3, brief step 1).

    tools/blender.sh run blender/hero3/segment.py -- [--stop-after=body|label|report|split|cap]

  body   frame the textured mesh: face +Y, feet at z = 0, 16.0 m to the helm top, origin between the
         feet (measured from the two leg clusters, NOT the bounding box -- the drone fan would skew it)
  label  transfer one part id per body face from hero3_a1p (the two Tripo models are natively
         aligned: same image, same pose; the fit is verified, not assumed)
  report per-part anatomy in the 16 m frame -- this is what picks the cut planes
  split  planar cuts at the joints the parts do not already separate; one bone per piece
  cap    fill + inset every opening in dark metal so no hollow shell shows

Deterministic throughout. Each stage writes a GLB into tmp/hero-v3 so it can be looked at.
"""
import argparse
import json
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender/hero3"))
sys.path.insert(0, os.path.expanduser("~/m/mecha-city/blender"))
import hero3_bones  # noqa: E402
import hero3_cap  # noqa: E402
import hero3_lib as H  # noqa: E402
from lib import common  # noqa: E402

BODY_GLB = "art/tripo/hero3_a1/model.glb"
PARTS_GLB = "art/tripo/hero3_a1p/model.glb"
## Decimate ONCE, before the cut, and never again: decimating each plate afterwards moves its
## boundary independently of its neighbour's, so the shared cut line opens into a gap a few
## centimetres wide and the inner core shows through every seam (lead review r1: the magenta bleed).
WORK_TRIS = 110000       ## the caps add ~70k, so the plates land on the 160k LOD0 budget
LABEL_SAMPLES = 12000    ## per part, deterministic even stride
LEG_ZONE = 0.40          ## fraction of the height that counts as "legs" when centring laterally
ALIGN_MAX_SCALE = 0.03   ## the part model may only be re-scaled this far from the body
LOD0_TRIS = 160000      ## the brief's LOD0 budget for the whole armour set
LOD1_TRIS = 60000       ## LOD1
STAGES = ["body", "label", "report", "split", "cap"]


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:]
    p = argparse.ArgumentParser()
    p.add_argument("--stop-after", default="cap", choices=STAGES)
    p.add_argument("--body", default=BODY_GLB)
    p.add_argument("--parts", default=PARTS_GLB)
    p.add_argument("--debug", action="store_true",
                   help="flat-colour the pieces by bone for the label sheet")
    return p.parse_args(argv)


def reached(stage: str, args) -> bool:
    return STAGES.index(stage) <= STAGES.index(args.stop_after)


def face_centres(obj) -> np.ndarray:
    """(n, 3) world-space face centres."""
    out = np.empty(len(obj.data.polygons) * 3)
    obj.data.polygons.foreach_get("center", out)
    out = out.reshape(-1, 3)
    if obj.matrix_world != Matrix.Identity(4):
        out = np.array([list(obj.matrix_world @ Vector(p)) for p in out])
    return out


# --- stage: body ------------------------------------------------------------------------------------

def stage_body(body, parts):
    """Face +Y, ground the feet, scale so the helm top is 16.0 m, origin between the feet.

    Tripo authored the mesh facing +X with Y as the left/right axis (measured: the two legs and the
    two arms separate along Y, the toes point +X), so a +90 deg yaw puts it on the contract's +Y
    facing. The helm, not the bounding box, sets the height -- the drone fan reaches out sideways.
    The SAME transform goes onto the part model: the two Tripo jobs are natively in one frame."""
    for obj in [body] + parts:
        H.transform_mesh(obj, H.yaw(90.0))
    lo, _ = H.bbox(body)
    ground = Matrix.Translation(Vector((0.0, 0.0, -lo.z)))
    for obj in [body] + parts:
        H.transform_mesh(obj, ground)
    height = float(face_centres(body)[:, 2].max())
    scale = Matrix.Scale(H.HERO_HEIGHT_M / height, 4)
    for obj in [body] + parts:
        H.transform_mesh(obj, scale)
    frame = stage_frame(body)
    for obj in [body] + parts:
        H.transform_mesh(obj, frame)
    print("BODY framed: +Y facing, provisional scale %.2f, ground %.3f, frame %s, tris %d" % (
        H.HERO_HEIGHT_M / height, lo.z, [round(v, 3) for v in frame.translation],
        H.tri_count(body)))
    return body


def stage_final_scale(body, parts, labels: np.ndarray) -> None:
    """Scale so the CREST is at 16.0 m (CONTRACTS §2), measured on the labelled head piece.

    The bounding box measures the drone mast, which rises past the head, and a plain distance-to-axis
    test still catches the mast tip where it leans over the spine. The head is found instead as the
    piece holding the most geometry on the axis above the shoulders -- a crest is a solid mass, the
    mast is a 0.3 m bar. The scale is uniform about the origin, so the feet stay grounded and the
    origin stays between them."""
    centres = face_centres(body)
    on_axis = (np.hypot(centres[:, 0], centres[:, 1]) < 1.0) & (centres[:, 2] > 12.0)
    scores = [int((on_axis & (labels == pid)).sum()) for pid in range(len(parts))]
    head = int(np.argmax(scores))
    helm = float(centres[labels == head][:, 2].max())
    print("HELM piece %s (scores %s) top %.3f m, bbox top %.3f m -> scale %.4f" % (
        parts[head].name, scores, helm, centres[:, 2].max(), H.HERO_HEIGHT_M / helm))
    if max(scores) < 500:
        raise RuntimeError("helm: no piece holds the axis above the shoulders (scores %s)" % scores)
    fit = Matrix.Scale(H.HERO_HEIGHT_M / helm, 4)
    for obj in [body] + parts:
        H.transform_mesh(obj, fit)


def stage_frame(body) -> Matrix:
    """The translation that puts the model origin between the feet, on the ground.

    Both axes come from the ground contact patch, which is literally what "origin between the feet"
    means and is the footprint the PlayerMech capsule stands on. A bounding-box centre would sit half
    a drone-fan off the spine; the pelvis band would sit forward, pulled by the tassets."""
    pts = H.sample_points(body, 120000)
    low = pts[pts[:, 2] < 0.15]
    if len(low) < 200:
        raise RuntimeError("frame: only %d points on the ground" % len(low))
    lateral = float(_two_means(low[:, 0]))
    fore = float(low[:, 1].mean())
    print("FRAME contact %d pts, lateral centre %.3f m, fore/aft %.3f m, patch y[%.2f %.2f]" % (
        len(low), lateral, fore, low[:, 1].min(), low[:, 1].max()))
    return Matrix.Translation(Vector((-lateral, -fore, 0.0)))


def _two_means(values: np.ndarray, iterations: int = 24) -> float:
    """Midpoint of a deterministic 2-means split (seeds at the extremes). Returns the centre."""
    a, b = float(values.min()), float(values.max())
    for _ in range(iterations):
        mid = (a + b) / 2.0
        left, right = values[values < mid], values[values >= mid]
        if len(left) == 0 or len(right) == 0:
            break
        new_a, new_b = float(left.mean()), float(right.mean())
        if abs(new_a - a) < 1e-6 and abs(new_b - b) < 1e-6:
            a, b = new_a, new_b
            break
        a, b = new_a, new_b
    print("FRAME leg clusters at %.3f m and %.3f m" % (a, b))
    return (a + b) / 2.0


# --- stage: label -----------------------------------------------------------------------------------

def stage_align(body, parts) -> None:
    """Verify (and, only if it clearly helps, refine) the part model's fit onto the body.

    Both Tripo jobs come from the same image in the same pose and land in the same frame, so the fit
    starts at identity. A similarity ICP may only be accepted when it lowers the RMS and stays within
    ALIGN_MAX_SCALE of 1.0 -- an unconstrained fit happily shrinks the parts into the torso and then
    every label is wrong in a way no screenshot shows."""
    dst = H.sample_points(body, 40000)
    src = np.concatenate([H.sample_n(o, 1500) for o in parts])
    tree = H.kdtree_of(dst)
    probe = Vector()
    base = float(np.sqrt(np.mean([
        tree.find(Vector((float(p[0]), float(p[1]), float(p[2]))))[2] ** 2 for p in src])))
    m, rms = H.fit_similarity(src, dst, 8)
    scale = m.to_scale().x
    if rms < base and abs(scale - 1.0) < ALIGN_MAX_SCALE:
        for obj in parts:
            H.transform_mesh(obj, m)
        print("ALIGN refined: rms %.4f -> %.4f m, scale %.4f" % (base, rms, scale))
    else:
        print("ALIGN kept identity: rms %.4f m (refine gave %.4f at scale %.4f, rejected)" % (
            base, rms, scale))


def stage_label(body, parts) -> np.ndarray:
    """One part id per body face: the nearest part sample to the face centre."""
    samples, tags = [], []
    for pid, obj in enumerate(parts):
        samples.append(H.sample_n(obj, LABEL_SAMPLES))
        tags.extend([pid] * LABEL_SAMPLES)
    pts = np.concatenate(samples)
    tags = np.array(tags)
    print("LABEL kdtree over %d samples from %d parts" % (len(pts), len(parts)))
    tree = H.kdtree_of(pts)
    centres = face_centres(body)
    out = np.empty(len(centres), dtype=np.int32)
    probe = Vector()
    for i, c in enumerate(centres):
        probe[0], probe[1], probe[2] = c[0], c[1], c[2]
        out[i] = tags[tree.find(probe)[1]]
    counts = np.bincount(out, minlength=len(parts))
    for pid, obj in enumerate(parts):
        print("LABEL %-18s faces=%-8d (%.1f%%)" % (obj.name, counts[pid],
                                                   100.0 * counts[pid] / len(out)))
    return out


# --- stage: report ----------------------------------------------------------------------------------

def stage_report(body, parts, labels: np.ndarray) -> dict:
    """Per-part anatomy in the 16 m frame -- the numbers the cut planes are chosen from."""
    centres = face_centres(body)
    rows = []
    for pid, obj in enumerate(parts):
        sel = centres[labels == pid]
        if len(sel) == 0:
            print("PART %-18s EMPTY" % obj.name)
            continue
        lo, hi = sel.min(axis=0), sel.max(axis=0)
        rows.append({"id": pid, "name": obj.name, "faces": int(len(sel)),
                     "lo": [round(float(v), 2) for v in lo], "hi": [round(float(v), 2) for v in hi],
                     "mid": [round(float(v), 2) for v in (lo + hi) / 2.0]})
        print("PART %-18s faces=%-7d x[%6.2f %6.2f] y[%6.2f %6.2f] z[%6.2f %6.2f]" % (
            obj.name, len(sel), lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]))
    return {"parts": rows}


# --- stage: split -----------------------------------------------------------------------------------

def seg_distance(points: np.ndarray, head, tail) -> np.ndarray:
    """Distance from each point to the bone segment head->tail."""
    a = np.array(head, dtype=float)
    b = np.array(tail, dtype=float)
    ab = b - a
    length2 = float(ab @ ab)
    if length2 < 1e-9:
        return np.linalg.norm(points - a, axis=1)
    t = np.clip((points - a) @ ab / length2, 0.0, 1.0)
    return np.linalg.norm(points - (a + t[:, None] * ab), axis=1)


def cut_planes(bones: dict, chain: list) -> list:
    """(joint, normal) for every boundary in a bone chain: the plane PERPENDICULAR to the chain at
    that joint. The normal bisects the two bone directions, so for a straight limb the plane is
    exactly perpendicular to the bone -- the cut the brief asks for."""
    out = []
    for i in range(len(chain) - 1):
        a, b = bones[chain[i]], bones[chain[i + 1]]
        da = np.array(a["tail"]) - np.array(a["head"])
        db = np.array(b["tail"]) - np.array(b["head"])
        da /= max(np.linalg.norm(da), 1e-9)
        db /= max(np.linalg.norm(db), 1e-9)
        n = da + db
        n /= max(np.linalg.norm(n), 1e-9)
        out.append((np.array(a["tail"], dtype=float), n))
    return out


def assign_bones(body, parts, labels: np.ndarray) -> tuple:
    """One bone per face: the labelled part picks the chain, the joint cut planes pick the bone.

    A face starts on the chain's first bone and is handed on each time it is on the far side of that
    joint's plane, so every boundary between two pieces is one flat cut square to the bone."""
    bones = hero3_bones.bone_map()
    centres = face_centres(body)
    out = np.full(len(centres), -1, dtype=np.int32)
    names = sorted(bones)
    index = {name: i for i, name in enumerate(names)}
    residual = np.zeros(len(centres))
    for pid, obj in enumerate(parts):
        region = "tripo_part_" + obj.name.replace("Seg_p", "")
        chain = hero3_bones.REGION_CHAIN.get(region)
        single = hero3_bones.REGION_SINGLE.get(region)
        if chain is None and single is None:
            print("ASSIGN %-14s no region rule, skipped" % region)
            continue
        mask = labels == pid
        pts = centres[mask]
        if single is not None:
            out[mask] = index[single]
            residual[mask] = seg_distance(pts, bones[single]["head"], bones[single]["tail"])
            continue
        chosen = np.full(len(pts), index[chain[0]], dtype=np.int32)
        todo = np.ones(len(pts), dtype=bool)
        planes = cut_planes(bones, chain)
        for i in reversed(range(len(planes))):
            joint, normal = planes[i]
            past = ((pts - joint) @ normal > 0.0) & todo
            chosen[past] = index[chain[i + 1]]
            todo &= ~past
        out[mask] = chosen
        residual[mask] = np.min([seg_distance(pts, bones[b]["head"], bones[b]["tail"])
                                 for b in chain], axis=0)
        for bone in chain:
            print("ASSIGN %-14s -> %-12s %6d faces" % (
                region, bone, int((chosen == index[bone]).sum())))
    unassigned = int((out < 0).sum())
    if unassigned:
        print("ASSIGN WARNING %d faces have no bone (they will be dropped)" % unassigned)
    print("ASSIGN bind residual: mean %.2f m, p95 %.2f m, max %.2f m" % (
        residual.mean(), float(np.percentile(residual, 95)), residual.max()))
    return out, names, residual


def split_by_bone(body, bone_ids: np.ndarray, names: list, colour: bool = True) -> list:
    """One mesh object per bone, in the final 16 m frame."""
    out = []
    for bid, bone in enumerate(names):
        faces = np.nonzero(bone_ids == bid)[0]
        if len(faces) < 12:
            if len(faces):
                print("PIECE %-12s only %d faces, merged away" % (bone, len(faces)))
            continue
        piece = H.extract_faces(body, faces.tolist())
        piece.name = "H3_%s" % bone
        if colour:
            piece.data.materials.clear()
            piece.data.materials.append(H.flat_material("Dbg%s" % bone, debug_colour(bid)))
            for poly in piece.data.polygons:
                poly.material_index = 0
        lo, hi = H.bbox(piece)
        print("PIECE %-12s %7d faces  x[%6.2f %6.2f] y[%6.2f %6.2f] z[%6.2f %6.2f]" % (
            bone, len(faces), lo.x, hi.x, lo.y, hi.y, lo.z, hi.z))
        out.append(piece)
    return out


## 16 hues, evenly spaced and fully saturated: the label sheet has to be readable at a glance.
def debug_colour(pid: int) -> tuple:
    import colorsys

    return colorsys.hsv_to_rgb((pid * 0.6180339887) % 1.0, 0.85, 0.95)


def decimate_to_budget(pieces: list, budget: int) -> int:
    """Collapse-decimate the whole set to `budget` triangles, each piece paying its own share.

    NOT used on the cut plates any more (see WORK_TRIS): per-plate decimation breaks the shared cut
    boundary. Kept for the LOD pass and for any future prop that is decimated as separate objects."""
    tris = {obj.name: H.tri_count(obj) for obj in pieces}
    total = sum(tris.values())
    out = 0
    for obj in pieces:
        share = max(200, int(budget * tris[obj.name] / total))
        out += H.decimate(obj, share)
    print("DECIMATE %d pieces %d -> %d tris (budget %d)" % (len(pieces), total, out, budget))
    return out


def main() -> None:
    args = parse_args()
    common.reset()
    bpy.context.scene.render.fps = 60
    body = H.only_mesh(H.load_glb(args.body), "body")
    body.name = "Hero3Body"
    parts = sorted([o for o in H.load_glb(args.parts) if o.type == "MESH"], key=lambda o: o.name)
    print("PARTS %d kept: %s" % (len(parts), ", ".join(o.name for o in parts)))
    stage_body(body, parts)
    H.decimate(body, WORK_TRIS)
    print("BODY work tris %d" % H.tri_count(body))
    stage_align(body, parts)
    for obj in parts:
        obj.name = "Seg_" + obj.name.replace("tripo_part_", "p")
    labels = stage_label(body, parts)
    stage_final_scale(body, parts, labels)
    report = stage_report(body, parts, labels)
    os.makedirs(H.TMP, exist_ok=True)
    with open(os.path.join(H.TMP, "parts_report.json"), "w") as fh:
        json.dump(report, fh, indent=1)
    if not reached("split", args):
        H.export_glb(os.path.join(H.TMP, "stage_label.glb"), [body] + parts, animations=False)
        return
    bone_ids, names, _ = assign_bones(body, parts, labels)
    pieces = split_by_bone(body, bone_ids, names, colour=args.debug)
    decimate_to_budget(pieces, LOD0_TRIS)
    H.export_glb(os.path.join(H.TMP, "stage_split.glb"), pieces, animations=False)
    if reached("cap", args):
        hero3_cap.cap_pieces(pieces)
        H.export_glb(os.path.join(H.TMP, "stage_cap.glb"), pieces, animations=False)
    report["bones"] = names
    with open(os.path.join(H.TMP, "parts_report.json"), "w") as fh:
        json.dump(report, fh, indent=1)


if __name__ == "__main__":
    main()
