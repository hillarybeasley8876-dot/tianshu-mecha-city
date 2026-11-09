"""Emissive mask + weak-point detection for the HUSK monsters (monster-assets).

ART.md §2: the monsters are charcoal chitin with **acid-green #9BFF3A veins** and **violet #B04CFF
weak points**. The Tripo albedos already contain both (verified on all seven, status file), so the
mask is derived from the albedo instead of being painted by hand:

  * a pixel that is strongly green-dominant becomes acid emission,
  * a pixel that is strongly red+blue-dominant becomes violet emission,
  * everything else is black.

The violet part is then projected back through the UVs onto the mesh to find where the weak-point
cores physically are, so `weak_*` sockets land on the real glow instead of a guess.
"""
import bpy
import numpy as np

MASK_PX = 2048
ACID = (0x9B / 255.0, 0xFF / 255.0, 0x3A / 255.0)
VIOLET = (0xB0 / 255.0, 0x4C / 255.0, 0xFF / 255.0)
#: Emission strength written into the GLB material. Neutral 1.0: the *look* energy is a per-type
#: number in `mon_types.LOOK` and lands in `<type>_rig.json`, because the hive's veins and the
#: ripper's veins want very different strengths and a baked 3.0 made the trunk a lime blob (look r1).
EMISSION_ENERGY = 1.0

#: Mask cleanup (look r1). The hue test alone lit every texel of a vein at full value, so the vein's
#: dark edge glowed as hot as its core and hundreds of 2-px specks became sub-pixel sparkle at 80 m.
#: Gate the coverage by albedo luminance (hot centres, dark edges), erode the result so only cores
#: survive, and drop what is left as an isolated blob.
LUMA_GATE = (0.25, 0.75)
ERODE_PX = 2
MIN_BLOB_PX = 40
#: Blob sizes are counted on a quarter-scale copy: a speck test does not need full resolution and
#: the label propagation below is 16x cheaper at 512 px.
BLOB_SCALE = 4

#: ART.md §1 chitin #1B2430 has a linear luminance of 0.016. The measured *texture* median of a
#: Tripo monster is 0.19-0.30 linear — four stops of mid-grey — but the lead's per-type gains
#: (ripper 0.5, hive 0.22, harrier 0.25) put the on-screen median at 0.066-0.095, because AO and
#: the dusk key knock it down again. GRADE_TARGET is that on-screen number: `gain = TARGET/median`
#: reproduces the lead's gains per type to within a quarter of a stop while staying measured.
GRADE_TARGET = 0.08
GRADE_CLAMP = (0.15, 0.90)


def albedo_image(material):
    """The base-colour image of a Tripo material, or None."""
    if material is None or not material.node_tree:
        return None
    for node in material.node_tree.nodes:
        if node.type == "TEX_IMAGE" and node.image is not None:
            name = node.image.name.lower()
            if "color" in name or "basecolor" in name or "diffuse" in name:
                return node.image
    for node in material.node_tree.nodes:
        if node.type == "TEX_IMAGE" and node.image is not None:
            return node.image
    return None


def _pixels(img) -> np.ndarray:
    """(h, w, 4) float32 view of an image, bottom-up like Blender's buffer (scene-linear)."""
    w, h = img.size
    buf = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    return buf.reshape(h, w, 4)


def to_srgb(a: np.ndarray) -> np.ndarray:
    """Scene-linear -> sRGB. `Image.pixels` is linear, but the thresholds below were chosen against
    the sRGB values an artist sees, so the mask is classified in sRGB and written back as linear."""
    a = np.clip(a, 0.0, 1.0)
    return np.where(a <= 0.0031308, a * 12.92, 1.055 * np.power(a, 1.0 / 2.4) - 0.055)


def to_linear(a: np.ndarray) -> np.ndarray:
    """sRGB -> scene-linear (the inverse, for writing the mask back into an image)."""
    a = np.clip(a, 0.0, 1.0)
    return np.where(a <= 0.04045, a / 12.92, np.power((a + 0.055) / 1.055, 2.4))


def classify(rgb: np.ndarray) -> tuple:
    """Return (acid, violet) coverage maps in 0..1 from an (h, w, 3) sRGB array.

    Both classes demand real brightness as well as hue: the carapace scales have a faint green
    sheen everywhere, and lighting the whole silhouette acid-green destroys the dark-corruption read
    (ART.md §1). Only pixels bright and saturated enough to read as a light source pass."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = np.maximum(np.maximum(r, g), b) + 1e-5
    acid = (np.clip((g - 0.28) / 0.30, 0.0, 1.0)
            * np.clip((g / mx - 0.40) / 0.16, 0.0, 1.0)
            * np.clip((g - b) / 0.13, 0.0, 1.0))
    violet = (np.clip((b - 0.22) / 0.24, 0.0, 1.0)
              * np.clip((np.minimum(r, b) - g) / 0.09, 0.0, 1.0)
              * np.clip((r - 0.09) / 0.18, 0.0, 1.0))
    return acid, violet


def smoothstep(edge0: float, edge1: float, x: np.ndarray) -> np.ndarray:
    """Hermite ramp between two edges (numpy has no smoothstep)."""
    t = np.clip((x - edge0) / max(edge1 - edge0, 1e-6), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def erode(mask: np.ndarray, steps: int) -> np.ndarray:
    """4-neighbour min filter, `steps` times: a coverage map shrunk by ~`steps` px, soft edges."""
    out = mask
    for _ in range(max(0, steps)):
        out = np.minimum.reduce([out,
                                 np.roll(out, 1, axis=0), np.roll(out, -1, axis=0),
                                 np.roll(out, 1, axis=1), np.roll(out, -1, axis=1)])
    return out


def drop_specks(mask: np.ndarray, min_px: int) -> np.ndarray:
    """Zero every connected component of `mask > 0` smaller than `min_px` pixels.

    Labels are propagated by repeated max over the 4-neighbourhood (no scipy in Blender's Python),
    on a `BLOB_SCALE`-times smaller copy: a speck test does not need the full mask resolution."""
    if min_px <= 0:
        return mask
    hot = mask > 1e-4
    if not hot.any():
        return mask
    s = BLOB_SCALE
    small = hot[::s, ::s]
    labels = np.where(small, np.arange(small.size, dtype=np.int32).reshape(small.shape), 0)
    for _ in range(4 * max(small.shape)):
        prev = labels
        labels = np.maximum.reduce([labels,
                                    np.roll(labels, 1, axis=0) * np.roll(small, 1, axis=0),
                                    np.roll(labels, -1, axis=0) * np.roll(small, -1, axis=0),
                                    np.roll(labels, 1, axis=1) * np.roll(small, 1, axis=1),
                                    np.roll(labels, -1, axis=1) * np.roll(small, -1, axis=1)])
        labels *= small
        if np.array_equal(labels, prev):
            break
    counts = np.bincount(labels.ravel())
    keep = counts >= max(1, min_px // (s * s))
    keep[0] = False
    alive = keep[labels]
    out = mask.copy()
    out[~np.repeat(np.repeat(alive, s, axis=0), s, axis=1)[:mask.shape[0], :mask.shape[1]]] = 0.0
    return out


def clean_coverage(mask: np.ndarray, erode_px: int = ERODE_PX) -> np.ndarray:
    """Erode to the vein cores, then drop what is left as an isolated speck.

    The violet weak-point cores pass `erode_px=0`: they are gameplay sockets (`weak_*`, the enemies
    unit hangs a Hurtbox on each), and shaving two pixels off a core can drop the whole cluster
    under the face floor and delete a weak point. Specks still go."""
    return drop_specks(erode(mask, erode_px), MIN_BLOB_PX)


def build_mask(material, name: str) -> tuple:
    """Create the emission image for a material. Returns (image, acid_map, violet_map)."""
    src = albedo_image(material)
    if src is None:
        raise RuntimeError("%s: material has no base colour image" % name)
    work = src.copy()
    if max(work.size) > MASK_PX:
        s = MASK_PX / max(work.size)
        work.scale(max(1, int(work.size[0] * s)), max(1, int(work.size[1] * s)))
    px = _pixels(work)
    rgb = to_srgb(px[..., :3])
    acid, violet = classify(rgb)
    luma = rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722
    gate = smoothstep(LUMA_GATE[0], LUMA_GATE[1], luma)
    raw_acid, raw_violet = float((acid > 0.5).mean()), float((violet > 0.5).mean())
    acid = clean_coverage(acid * gate)
    violet = clean_coverage(violet * gate, erode_px=0)
    out = np.zeros_like(px)
    for ch in range(3):
        out[..., ch] = to_linear(acid * ACID[ch] + violet * VIOLET[ch])
    out[..., 3] = 1.0
    img = bpy.data.images.new("EM_%s" % name, width=work.size[0], height=work.size[1], alpha=False)
    img.pixels.foreach_set(out.ravel())
    img.file_format = "PNG"
    img.pack()
    print("EMIT %-11s %dx%d  acid %.2f%% -> %.2f%%, violet %.2f%% -> %.2f%%"
          % (name, img.size[0], img.size[1], 100.0 * raw_acid, 100.0 * float((acid > 0.5).mean()),
             100.0 * raw_violet, 100.0 * float((violet > 0.5).mean())))
    bpy.data.images.remove(work)
    return img, acid, violet


#: Resolution of the UV-usage raster the albedo grade is measured on.
MEASURE_PX = 256


def median_luma(obj, material) -> float:
    """Median scene-linear luminance of the albedo over the texels the mesh really uses.

    The grade the Godot shader needs to land this type on ART.md's #1B2430 chitin (lead look r1).
    Measured over the UV shells, not the whole image: the empty half of a texture atlas says nothing
    about how bright the monster is on screen."""
    src = albedo_image(material)
    if src is None:
        raise RuntimeError("median_luma: material has no base colour image")
    work = src.copy()
    work.scale(MEASURE_PX, MEASURE_PX)
    px = _pixels(work)
    bpy.data.images.remove(work)
    luma = px[..., 0] * 0.2126 + px[..., 1] * 0.7152 + px[..., 2] * 0.0722
    used = rasterize_faces(obj, range(len(obj.data.polygons)), MEASURE_PX) > 0.5
    if not used.any():
        print("LUMA %s: no UVs — grading on the whole image" % obj.name)
        return float(np.median(luma))
    return float(np.median(luma[used]))


def wire_emission(material, mask_img) -> None:
    """Plug the mask into the Principled BSDF's emission at EMISSION_ENERGY."""
    nt = material.node_tree
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        raise RuntimeError("wire_emission: %s has no Principled BSDF" % material.name)
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image = mask_img
    node.location = (bsdf.location.x - 400, bsdf.location.y - 500)
    nt.links.new(node.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = EMISSION_ENERGY


# --- weak points ---------------------------------------------------------------------------------

def _face_uv_scores(obj, violet: np.ndarray) -> np.ndarray:
    """Violet coverage under each face's UV centroid. Faces without UVs score 0."""
    me = obj.data
    if not me.uv_layers:
        return np.zeros(len(me.polygons), dtype=np.float32)
    uv = me.uv_layers.active.data
    h, w = violet.shape
    out = np.zeros(len(me.polygons), dtype=np.float32)
    for i, poly in enumerate(me.polygons):
        u = sum(uv[li].uv[0] for li in poly.loop_indices) / len(poly.loop_indices)
        v = sum(uv[li].uv[1] for li in poly.loop_indices) / len(poly.loop_indices)
        x = min(w - 1, max(0, int(u * w)))
        y = min(h - 1, max(0, int(v * h)))
        out[i] = violet[y, x]
    return out


def dilate(mask: np.ndarray, steps: int) -> np.ndarray:
    """4-neighbour max filter, `steps` times — the inverse of `erode`."""
    out = mask
    for _ in range(max(0, steps)):
        out = np.maximum.reduce([out,
                                 np.roll(out, 1, axis=0), np.roll(out, -1, axis=0),
                                 np.roll(out, 1, axis=1), np.roll(out, -1, axis=1)])
    return out


def write_mask_png(path: str, channels: list) -> None:
    """Write up to four coverage maps as one RGBA PNG (channel i = channels[i]), bottom-up like
    every other Blender image buffer, so UV space lines up with the emission mask."""
    h, w = channels[0].shape
    rgba = np.zeros((h, w, 4), dtype=np.float32)
    for i in range(4):
        rgba[..., i] = channels[i] if i < len(channels) else 0.0
    img = bpy.data.images.new("PODS", width=w, height=h, alpha=True)
    img.pixels.foreach_set(rgba.ravel())
    img.file_format = "PNG"
    img.filepath_raw = path
    img.save()
    bpy.data.images.remove(img)
    print("PODMASK %s %dx%d cover %s" % (path, w, h,
          [round(float(c.mean()), 5) for c in rgba.transpose(2, 0, 1)]))


def rasterize_faces(obj, faces, size: int) -> np.ndarray:
    """UV-space coverage (size x size) of a face set: 1 inside a face, 0 outside, soft at edges.

    Used for the hive's pod mask, where the shader needs to know which bulb a texel belongs to."""
    me = obj.data
    out = np.zeros((size, size), dtype=np.float32)
    if not me.uv_layers:
        return out
    uv = me.uv_layers.active.data
    for fi in faces:
        loops = list(me.polygons[fi].loop_indices)
        pts = np.array([[uv[li].uv[0], uv[li].uv[1]] for li in loops], dtype=np.float64)
        for k in range(1, len(pts) - 1):
            _fill_triangle(out, pts[0], pts[k], pts[k + 1])
    return out


def _fill_triangle(out: np.ndarray, a, b, c) -> None:
    """Barycentric fill of one UV triangle into a coverage map, in pixels."""
    size = out.shape[0]
    p = np.array([a, b, c]) * size
    lo = np.clip(np.floor(p.min(axis=0)).astype(int), 0, size - 1)
    hi = np.clip(np.ceil(p.max(axis=0)).astype(int) + 1, 1, size)
    if hi[0] <= lo[0] or hi[1] <= lo[1]:
        return
    xs = np.arange(lo[0], hi[0]) + 0.5
    ys = np.arange(lo[1], hi[1]) + 0.5
    gx, gy = np.meshgrid(xs, ys)
    d = ((p[1][1] - p[2][1]) * (p[0][0] - p[2][0]) + (p[2][0] - p[1][0]) * (p[0][1] - p[2][1]))
    if abs(d) < 1e-9:
        return
    w0 = ((p[1][1] - p[2][1]) * (gx - p[2][0]) + (p[2][0] - p[1][0]) * (gy - p[2][1])) / d
    w1 = ((p[2][1] - p[0][1]) * (gx - p[2][0]) + (p[0][0] - p[2][0]) * (gy - p[2][1])) / d
    w2 = 1.0 - w0 - w1
    inside = np.minimum(np.minimum(w0, w1), w2)
    block = out[lo[1]:hi[1], lo[0]:hi[0]]
    np.maximum(block, np.clip(inside * size * 0.5, 0.0, 1.0).astype(np.float32), out=block)


def find_weak_points(obj, violet: np.ndarray, radius_frac: float = 0.10, max_points: int = 4,
                     min_faces: int = 12) -> list:
    """The violet cores, without the face lists `cluster_mask` returns (those are build-time only)."""
    return [{k: v for k, v in c.items() if k != "face_idx"}
            for c in cluster_mask(obj, violet, radius_frac, max_points, min_faces)]


def cluster_mask(obj, mask: np.ndarray, radius_frac: float = 0.10, max_points: int = 4,
                 min_faces: int = 12) -> list:
    """Cluster the lit faces of a coverage map into at most `max_points` world-space cores.

    Greedy, deterministic: the highest-scoring unclaimed face seeds a cluster, every lit face
    within `radius_frac * model size` joins it, and the cluster centre is the score-weighted mean.
    Returns [{'pos': [x, y, z], 'score': float, 'faces': int, 'face_idx': [int]}] strongest first."""
    me = obj.data
    scores = _face_uv_scores(obj, mask)
    hot = np.nonzero(scores > 0.45)[0]
    if len(hot) < min_faces:
        return []
    mw = obj.matrix_world
    centres = np.array([[c for c in (mw @ me.polygons[i].center)] for i in hot])
    weights = scores[hot]
    size = float(np.linalg.norm(centres.max(axis=0) - centres.min(axis=0)))
    radius = max(size * radius_frac, 1e-3)
    taken = np.zeros(len(hot), dtype=bool)
    clusters = []
    for _ in range(max_points):
        masked = np.where(taken, -1.0, weights)
        seed = int(np.argmax(masked))
        if masked[seed] <= 0.0:
            break
        near = np.nonzero(np.linalg.norm(centres - centres[seed], axis=1) <= radius)[0]
        near = near[~taken[near]]
        if len(near) < min_faces:
            taken[seed] = True
            continue
        w = weights[near]
        pos = (centres[near] * w[:, None]).sum(axis=0) / w.sum()
        clusters.append({"pos": [round(float(c), 4) for c in pos],
                         "score": round(float(w.mean()), 4), "faces": int(len(near)),
                         "face_idx": [int(hot[i]) for i in near]})
        taken[near] = True
    clusters.sort(key=lambda c: -c["faces"])
    return clusters

