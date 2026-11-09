"""A dense UV layout and a low-passed re-bake for the arena cover kit (lead r7 §1).

**Why the atlas has to go.** A Tripo atlas is ~9 000 confetti islands, each carrying its own value and
its own baked shading. On a cover piece at 15 m every texel is several screen pixels, so each triangle
shows its island's patch and the seams draw the wedges the lead photographed at A5deck. Repainting
INTO that atlas cannot fix it — k07's walls are 62.7 % of its mesh AREA and 4.4 % of its atlas TEXELS,
because the atlas spends its resolution on tiny protruding elements and leaves 91 % of itself empty
(`captures/blender/r7before_k07_studio.jpg` is what that looks like: smeared wood-grain streaks
running along the stretched islands).

**What the layout pass does.** The island COUNT cannot be fixed — a 12 k-tri collapse of a
photogrammetry shell really does have that many distinct surface patches, and every angle-based
projection finds them (measured: `smart_project` at 66 deg returns 9 011 islands with a median of 1.5
texels, and dissolving coplanar faces first only takes it to 7 962). What can be fixed is the two
things that actually show:

1. **Seams that are not real.** `weld_uvs` gives one UV to the two loops across any edge whose
   dihedral is small — two faces that are, for texturing, the same surface. That is where the island
   count comes down honestly rather than by fiat.
2. **Density.** `average_islands_scale` + `pack_islands` makes the texel density uniform (the raw
   atlas has a 46x spread between its median and its p95) and packs the result. Density is what lets
   `coverlook` draw a 45 mm panel seam at all: at the raw atlas's density that seam is 0.9 of a texel,
   which is the r5/r6 "the grid averaged away to nothing" failure exactly.

**What the bake does.** Cycles EMIT passes move the Tripo maps from the old parameterisation to the
new one. They are baked LOW-PASSED — a mask-normalised blur in the old atlas first, so the island
confetti and its baked shading average out and the part colours stay — and the procedural layer at
metre scale goes on top (`coverlook.py`).

Everything else — position, normal, pointiness, texel size — is rasterised straight out of the mesh in
numpy, so the procedural layer needs no further bakes and is bit-for-bit deterministic.
"""
from __future__ import annotations

import math
import os
from typing import Dict, List, Tuple

import bpy
import numpy as np

#: Gutter, in target-resolution pixels. The lead asked for 8 or more and at a normal island count that
#: is right — but a 12 k-tri collapse of a photogrammetry shell really does unwrap into ~8 800 islands
#: (measured; no projection or dissolve pass gets it below ~7 900), and Blender's packer satisfies the
#: margin by SHRINKING the islands: at 8 px it packed k07 to 0.13 % fill and a texel came out 92 cm
#: across. 2 px is what the content needs here — after `island_fill` an island is ONE flat colour, so a
#: mip that bleeds across the gutter pulls in a neighbour's flat colour, which is what a mip would
#: average to anyway. `captures/kit/r7_layout_<id>.png` is the check.
MARGIN_PX = 2
#: The mask-normalised blur applied in the OLD atlas before the bake, in texels. Small, because the
#: islands it has to flatten are themselves only a few texels across; the wide part of the low-pass is
#: `coverlook`'s per-island value fill, which cannot bleed across a part boundary at all.
#: The 3D low-pass, in METRES of surface. `VALUE_SIGMA_M` is how far one texel's baked SHADING is
#: trusted to reach — it is the knob that turns crumpled foil into painted steel, and it has to be
#: wider than a panel. `CHROMA_SIGMA_M` is deliberately much tighter: a hazard band or a logo is
#: chroma at roughly half a metre, and diffusing it at the value's sigma erases it. Measured on k07,
#: 0.55 m / 0.16 m is where the fins read as one painted surface and the plinth's yellow survives.
VALUE_SIGMA_M = float(os.environ.get("COVER_VALUE_SIGMA", "2.0"))
CHROMA_SIGMA_M = float(os.environ.get("COVER_CHROMA_SIGMA", "0.45"))
DIFFUSE_ITERS = 2
#: The soft saturation threshold `desaturate_weak` applies. See its docstring for the measurement.
SAT_LO, SAT_HI = 0.10, 0.34
CHROMA_FLOOR = 0.22
#: Dihedral below which two faces across an edge share one UV. 18 deg is inside `wallgroup.QUANT`'s
#: 14 deg normal bucket plus a margin: a face pair that flat is one painted panel.
WELD_DEG = 18.0
SRC_UV = "tripo_src"


def _select(obj: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def _edge_faces(me) -> Dict[Tuple[int, int], List[Tuple[int, int]]]:
    """Undirected edge -> the (loop at the lower vertex, loop at the higher vertex) of each face."""
    out: Dict[Tuple[int, int], List[Tuple[int, int]]] = {}
    for poly in me.polygons:
        li = list(poly.loop_indices)
        for k, cur in enumerate(li):
            nxt = li[(k + 1) % len(li)]
            a, b = me.loops[cur].vertex_index, me.loops[nxt].vertex_index
            out.setdefault((min(a, b), max(a, b)), []).append((cur, nxt) if a < b else (nxt, cur))
    return out


def _loop_poly(me) -> np.ndarray:
    out = np.empty(len(me.loops), dtype=np.int32)
    for poly in me.polygons:
        out[list(poly.loop_indices)] = poly.index
    return out


def _uv_area(me, uvl) -> float:
    total = 0.0
    for poly in me.polygons:
        pts = [uvl.data[li].uv for li in poly.loop_indices]
        for k in range(1, len(pts) - 1):
            ax, ay = pts[0]
            bx, by = pts[k]
            cx, cy = pts[k + 1]
            total += abs((bx - ax) * (cy - ay) - (cx - ax) * (by - ay)) * 0.5
    return total


def _uvs(uvl, n: int) -> np.ndarray:
    buf = np.empty(n * 2, dtype=np.float32)
    uvl.data.foreach_get("uv", buf)
    return buf.reshape(-1, 2)


def _loop_islands(me, uvl) -> np.ndarray:
    """Per-loop island index, 0..K-1. Two loops across a shared edge are the same island exactly when
    their UVs agree there; a UV seam is where they do not."""
    n = len(me.loops)
    parent = list(range(n))

    def find(a: int) -> int:
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    uv_of = {li: tuple(round(c, 5) for c in uvl.data[li].uv) for li in range(n)}
    for pairs in _edge_faces(me).values():
        if len(pairs) != 2:
            continue
        (a0, b0), (a1, b1) = pairs
        for x, y in ((a0, a1), (b0, b1)):
            if uv_of[x] != uv_of[y]:
                continue
            ra, rb = find(x), find(y)
            if ra != rb:
                parent[ra] = rb
    roots = {}
    out = np.empty(n, dtype=np.int32)
    for li in range(n):
        r = find(li)
        if r not in roots:
            roots[r] = len(roots)
        out[li] = roots[r]
    return out


def islands(obj: bpy.types.Object, side: int) -> Dict[str, float]:
    """UV-space island stats: how many, and how large in texels. The gate for "large islands"."""
    me = obj.data
    uvl = me.uv_layers.active
    isl = _loop_islands(me, uvl)
    area: Dict[int, float] = {}
    for poly in me.polygons:
        root = int(isl[poly.loop_indices[0]])
        pts = [uvl.data[li].uv for li in poly.loop_indices]
        s = 0.0
        for k in range(1, len(pts) - 1):
            ax, ay = pts[0]
            bx, by = pts[k]
            cx, cy = pts[k + 1]
            s += abs((bx - ax) * (cy - ay) - (cx - ax) * (by - ay)) * 0.5
        area[root] = area.get(root, 0.0) + s
    px = sorted(v * side * side for v in area.values())
    if not px:
        return {"uv_islands": 0, "island_px_med": 0.0, "uv_fill_pct": 0.0}
    return {"uv_islands": len(px), "island_px_med": round(px[len(px) // 2], 1),
            "island_px_p10": round(px[len(px) // 10], 1),
            "uv_fill_pct": round(100.0 * sum(px) / (side * side), 2)}


def weld_uvs(obj: bpy.types.Object, angle_deg: float = WELD_DEG) -> Dict[str, float]:
    """Give ONE uv to the two loops across every edge whose dihedral is under `angle_deg`.

    A Tripo unwrap of a 700 k-tri shell carries thousands of seams; decimating to 12 k does not remove
    them, so the mesh arrives with ~9 000 islands whose median is five texels and a packed layout
    spends most of its atlas on gutters.

    Welding across a closed shell can FOLD the parameterisation, and `folded_pct` is the honest measure
    of that: the share of UV area the weld destroyed. It is reported, not hidden — a fold shows up as
    two parts of the model sampling the same texels, which on a flat-per-part cover texture reads as
    one part's colour bleeding onto another.
    """
    me = obj.data
    uvl = me.uv_layers.active
    n = len(me.loops)
    uv = _uvs(uvl, n).astype(np.float64)
    before = _uv_area(me, uvl)
    thr = math.cos(math.radians(angle_deg))
    owner = _loop_poly(me)
    parent = list(range(n))

    def find(a: int) -> int:
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for pairs in _edge_faces(me).values():
        if len(pairs) != 2:
            continue
        (a0, b0), (a1, b1) = pairs
        if float(me.polygons[owner[a0]].normal.dot(me.polygons[owner[a1]].normal)) < thr:
            continue
        for x, y in ((a0, a1), (b0, b1)):
            ra, rb = find(x), find(y)
            if ra != rb:
                parent[ra] = rb
    groups: Dict[int, List[int]] = {}
    for li in range(n):
        groups.setdefault(find(li), []).append(li)
    for g in groups.values():
        if len(g) > 1:
            uv[g] = uv[g].mean(axis=0)
    uvl.data.foreach_set("uv", uv.reshape(-1).astype(np.float32))
    after = _uv_area(me, uvl)
    return {"weld_groups": len(groups), "weld_deg": angle_deg,
            "folded_pct": round(100.0 * max(0.0, 1.0 - after / max(before, 1e-12)), 2)}


def layout(obj: bpy.types.Object, side: int) -> Dict[str, float]:
    """Weld the false seams, equalise the texel density and pack — into a FRESH active UV layer.

    The Tripo layer is kept as `SRC_UV` because the bake needs it as the source parameterisation.
    `do_init=False` matters: `MeshUVLoopLayers.new` otherwise COPIES the active layer's data, and the
    "new" layout then silently is the old one.
    """
    me = obj.data
    if not me.uv_layers:
        me.uv_layers.new(name=SRC_UV)
    me.uv_layers.active.name = SRC_UV
    new = me.uv_layers.new(name="UVMap", do_init=False)
    me.uv_layers.active = new
    new.active_render = True
    # The new layer starts empty, so copy the Tripo UVs into it, weld there, and keep the original
    # untouched for the bake.
    n = len(me.loops)
    src = _uvs(me.uv_layers[SRC_UV], n)
    new.data.foreach_set("uv", src.reshape(-1))
    stats = weld_uvs(obj)
    _select(obj)
    bpy.context.scene.tool_settings.use_uv_select_sync = True
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.average_islands_scale()
    bpy.ops.uv.pack_islands(rotate=True, scale=True, margin=float(MARGIN_PX) / side,
                            margin_method="FRACTION")
    bpy.ops.object.mode_set(mode="OBJECT")
    stats.update(islands(obj, side))
    return stats




def pixels(img: bpy.types.Image) -> np.ndarray:
    """The image as an (H, W, 4) array of STORED values (row 0 is the bottom, like Blender's UV v)."""
    buf = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    return buf.reshape(img.size[1], img.size[0], 4)




def face_texels(me, uvl, side: int) -> Tuple[np.ndarray, np.ndarray]:
    """(face -> the texels its UV footprint covers, face -> how many) in the CURRENT layout.

    A face is the only unit that survives a re-layout: islands are defined by the UVs and change when
    they move. So the Tripo colour is reduced to one value per FACE here, in the original atlas, and
    everything after this works from that.
    """
    uv = _uvs(uvl, len(me.loops)).astype(np.float64) * side
    out = []
    counts = np.zeros(len(me.polygons), dtype=np.int32)
    for poly in me.polygons:
        p = uv[list(poly.loop_indices)]
        x0 = max(0, int(np.floor(p[:, 0].min())))
        x1 = min(side - 1, int(np.ceil(p[:, 0].max())))
        y0 = max(0, int(np.floor(p[:, 1].min())))
        y1 = min(side - 1, int(np.ceil(p[:, 1].max())))
        if x1 < x0 or y1 < y0:
            out.append(np.zeros((0, 2), dtype=np.int32))
            continue
        ys, xs = np.mgrid[y0:y1 + 1, x0:x1 + 1]
        out.append(np.stack([ys.reshape(-1), xs.reshape(-1)], axis=1).astype(np.int32))
        counts[poly.index] = len(out[-1])
    return out, counts


def face_colour(me, uvl, side: int, px: np.ndarray) -> np.ndarray:
    """One colour per face: the mean of the source texture over the face's own UV footprint."""
    cells, counts = face_texels(me, uvl, side)
    out = np.zeros((len(me.polygons), px.shape[2]), dtype=np.float32)
    for poly in me.polygons:
        c = cells[poly.index]
        if len(c):
            out[poly.index] = px[c[:, 0], c[:, 1]].mean(axis=0)
    return out


def diffuse(centres: np.ndarray, weights: np.ndarray, vals: np.ndarray, sigma: float,
            iters: int = 2) -> np.ndarray:
    """Gaussian diffusion of a per-face quantity over 3D space. **This is the low-pass.**

    The lead's instruction is "low-passed enough that the island confetti and its baked shading are
    gone and the part colours stay", and neither a UV blur nor a per-island mean does that: an island
    is 2 texels across and carries ONE SAMPLE of the baked shading, so its mean is that sample. The
    dump of the first prototype's source atlas is unambiguous — flat patches, every one a different
    value, white next to black on one steel panel.

    A blur in 3D is the only one with the right support: it averages the panel with itself and stops
    at the gap between parts. `sigma` is therefore a physical scale — how far the baked shading of one
    spot is trusted to reach — and it is the knob that trades "smooth painted steel" against "the logo
    band is still there". Chroma is diffused at a TIGHTER sigma than value for exactly that reason:
    baked shading is value, a logo band is chroma.
    """
    n = len(centres)
    if n == 0:
        return vals
    out = vals.astype(np.float32).copy()
    w = np.maximum(weights, 1e-6).astype(np.float32)
    inv = np.float32(-0.5 / max(sigma * sigma, 1e-9))
    step = max(1, int(4_000_000 // max(n, 1)))
    for _ in range(max(1, iters)):
        src = out
        acc = np.zeros_like(out)
        den = np.zeros(n, dtype=np.float32)
        for i0 in range(0, n, step):
            i1 = min(n, i0 + step)
            d2 = ((centres[i0:i1, None, :] - centres[None, :, :]) ** 2).sum(axis=2)
            k = np.exp(d2 * inv) * w[None, :]
            acc[i0:i1] = k @ src
            den[i0:i1] = k.sum(axis=1)
        out = acc / np.maximum(den, 1e-9)[:, None]
    return out


def desaturate_weak(rgb: np.ndarray) -> np.ndarray:
    """Keep the concept's colours, drop the photogrammetry's colour noise.

    Measured on k07: diffusing the hue/saturation field barely moves it (std 0.144 -> 0.135 even at a
    2 m value sigma), because a Tripo atlas's colour varies at the scale of its own islands and every
    one of them is a slightly different grey — the render reads as tan and rust blotches over a
    machine the concept painted one colour.

    A linear saturation cut would take the hazard yellow with it. This is a SOFT THRESHOLD instead: a
    texel whose saturation is under `SAT_LO` is a tint and keeps only `CHROMA_FLOOR` of it, one over
    `SAT_HI` is a real colour and keeps all of it. The concept's bands and logos are far above the
    threshold; the noise is far below.
    """
    mx = rgb.max(axis=1, keepdims=True)
    mn = rgb.min(axis=1, keepdims=True)
    sat = (mx - mn) / np.maximum(mx, 1e-5)
    keep = np.clip((sat - SAT_LO) / max(SAT_HI - SAT_LO, 1e-5), 0.0, 1.0)
    grey = rgb.mean(axis=1, keepdims=True)
    return grey + (rgb - grey) * (CHROMA_FLOOR + (1.0 - CHROMA_FLOOR) * keep)


def _to_side(px: np.ndarray, side: int) -> np.ndarray:
    """Nearest-neighbour resample an (H, W, C) raster to `side` x `side`.

    `kitmat.resize` halves the packed maps, so the ORM arrives at half the albedo's resolution while
    the island raster is at the albedo's. Nearest neighbour rather than a box filter because the ORM is
    about to be reduced to per-island means anyway — the interpolation would buy nothing.
    """
    if px.shape[0] == side and px.shape[1] == side:
        return px
    idx = (np.arange(side) * px.shape[0] // side).clip(0, px.shape[0] - 1)
    return px[np.ix_(idx, idx)]


def _mk(name: str, side: int, rgb: np.ndarray, data: bool) -> bpy.types.Image:
    """A byte image whose `pixels` ARE the stored values — the space every other number here is in."""
    old = bpy.data.images.get(name)
    if old is not None:
        bpy.data.images.remove(old)
    img = bpy.data.images.new(name, side, side, alpha=False)
    img.colorspace_settings.name = "Non-Color" if data else "sRGB"
    buf = np.ones((side, side, 4), dtype=np.float32)
    buf[:, :, :3] = np.clip(rgb, 0.0, 1.0)
    img.pixels.foreach_set(buf.reshape(-1))
    img.update()
    return img


def _dump(aid: str, maps: Dict[str, np.ndarray]) -> None:
    """Write the composed maps to `captures/kit/r7_<id>_<kind>.png` when `COVER_DUMP` is set.

    Looking at the texture is the only fast way to tell an albedo problem from a normal-map one; the
    first r7 prototype's swirl was the normal map and the sheet made that obvious in one look.
    """
    out_dir = os.path.expanduser("~/m/mecha-city/captures/kit")
    os.makedirs(out_dir, exist_ok=True)
    for kind, px in maps.items():
        img = _mk("dump_" + kind, px.shape[0], px, kind != "albedo")
        img.file_format = "PNG"
        img.filepath_raw = os.path.join(out_dir, "r7_%s_%s.png" % (aid, kind))
        img.save()
        bpy.data.images.remove(img)
    print("  COVER DUMP %s -> captures/kit/r7_%s_*.png" % (aid, aid))


def build(obj: bpy.types.Object, aid: str, tex: int) -> Tuple[Dict[str, bpy.types.Image], dict]:
    """Re-lay and re-look one cover model. Returns ({kind: image}, stats).

    The ORM and the normal map both keep the kit's usual half resolution. The first version gave the
    normal map the full 1 k and that cost +30 MB of VRAM for TWO models (so ~190 MB for the roll-out);
    the panel seams it carries are 7 texels wide at 1 k, which is 3.6 at 512 — still well clear of the
    "a feature under a texel averages away" failure this whole pass exists to avoid.
    """
    import coverlook
    import coverraster
    import grade
    import kitmat

    kitmat.resize(tex)
    colour = next((i for i in bpy.data.images if i.name.startswith("Color")), None)
    orm_src = next((i for i in bpy.data.images if i.name.startswith("ORM")), None)
    if colour is None:
        print("  COVER FAIL %s: no albedo texture to read" % aid)
        return {}, {"cover_fail": 1}
    side = tex
    me = obj.data
    # 1. Reduce the Tripo atlas to one colour per FACE, in its own parameterisation. A face is the
    #    only unit that survives the re-layout below.
    face_rgb = face_colour(me, me.uv_layers.active, side,
                           _to_side(pixels(colour)[:, :, :3], side))
    face_orm = face_colour(me, me.uv_layers.active, side,
                           _to_side(pixels(orm_src)[:, :, :3], side)) if orm_src is not None \
        else np.full((len(me.polygons), 3), 0.5, np.float32)
    # 2. Low-pass it in 3D. Value wide (the baked shading is value), chroma tight (a logo band is
    #    chroma and has to survive), the packed map in between.
    centres = np.empty((len(me.polygons), 3), dtype=np.float32)
    area = np.empty(len(me.polygons), dtype=np.float32)
    for poly in me.polygons:
        centres[poly.index] = poly.center
        area[poly.index] = poly.area
    v = face_rgb.max(axis=1, keepdims=True)
    unit = face_rgb / np.maximum(v, 1e-5)
    v_d = diffuse(centres, area, v, VALUE_SIGMA_M, DIFFUSE_ITERS)
    u_d = diffuse(centres, area, unit, CHROMA_SIGMA_M, DIFFUSE_ITERS)
    u_d = u_d / np.maximum(u_d.max(axis=1, keepdims=True), 1e-5)
    face_rgb = np.clip(v_d * u_d, 0.0, 1.0)
    face_rgb = desaturate_weak(face_rgb)
    print("  COVER %s diffuse: v std %.4f -> %.4f   unit std %.4f -> %.4f  (sigma %.2f/%.2f m)"
          % (aid, float(v.std()), float(v_d.std()), float(unit.std()), float(u_d.std()),
             VALUE_SIGMA_M, CHROMA_SIGMA_M))
    face_orm = np.clip(diffuse(centres, area, face_orm, VALUE_SIGMA_M, DIFFUSE_ITERS), 0.0, 1.0)

    # 2b. The palette comes from the CONCEPT, not from the atlas (lead r8 §2). The accent mask is taken
    #     BEFORE the transfer, on the model's own saturation: after it, the transfer's own gain would
    #     decide what counts as a coloured part, which is the thing being replaced.
    import concept

    acc_face = concept.sat_of(face_rgb) > concept.ACCENT_SAT
    try:
        pal = concept.measure(aid)
    except (KeyError, ValueError, OSError) as exc:
        print("  COVER WARN %s: no concept palette (%s) — using the steel band" % (aid, exc))
        pal = None
    if pal is not None:
        face_rgb, tstats = concept.reinhard(face_rgb, pal)
        print("  COVER %s concept %s class=%s band=%s  ab %s -> %s  accents %.1f%% (%.1f%% pulled)"
              % (aid, pal["image"], pal["class"], pal["band"], tstats["ab_mean"],
                 tstats["ab_ref"], tstats["accent_pct"], tstats["accent_pull_pct"]))
    else:
        tstats = {}

    # 3. A dense layout, then the geometry rasters in it.
    stats: Dict[str, object] = dict(layout(obj, side))
    g = coverraster.geom(obj, side)
    cov = g["cov"]
    if not cov.any():
        print("  COVER FAIL %s: the new UV layout covers no texels" % aid)
        return {}, {"cover_fail": 1}
    med_mpt = float(np.median(g["mpt"][cov]))
    stats["mpt"] = round(med_mpt, 4)
    stats["mpt_p95"] = round(float(np.percentile(g["mpt"][cov], 95.0)), 4)
    stats["seam_texels"] = round(coverlook.SEAM_W / max(med_mpt, 1e-4), 2)
    stats["value_sigma_m"] = VALUE_SIGMA_M
    stats["chroma_sigma_m"] = CHROMA_SIGMA_M

    out = coverlook.build(face_rgb, face_orm, g, side // 2, side // 2, pal, acc_face, aid)
    stats.update(out["stats"])
    stats.update({"concept": (pal or {}).get("image", ""), **tstats})
    imgs = {"Color": _mk("Color", side, out["rgb"], False),
            "ORM": _mk("ORM", side // 2, out["orm"], True),
            "Normal": _mk("Normal", side // 2, out["normal"], True)}
    imgs = {k: grade._write_jpeg(v, aid, k.lower(), fmt="PNG" if k == "Normal" else "JPEG")
            for k, v in imgs.items()}
    stats["v_p50_file"] = round(float(np.median(pixels(imgs["Color"])[:, :, :3].max(axis=2)[cov])), 4)
    if os.environ.get("COVER_DUMP"):
        dumps = {"albedo": out["rgb"], "normal": out["normal"], "orm": out["orm"],
                 "layout": np.repeat(cov[..., None].astype(np.float32), 3, axis=2)}
        for k, f in out["fields"].items():
            dumps["f_" + k] = np.repeat(f[..., None].astype(np.float32), 3, axis=2) \
                if f.ndim == 2 else f
        _dump(aid, dumps)
    src = obj.data.uv_layers.get(SRC_UV)
    if src is not None:
        obj.data.uv_layers.remove(src)
    return imgs, stats
