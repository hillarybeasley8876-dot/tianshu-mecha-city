"""glTF material for a kit building: Tripo albedo + ORM + normal, palette-graded, plus the signage
emission mask.

One material per model (ART.md §6: merge static geometry). The texture set is graded by `grade.py`
before export — roughness floored, albedo pulled onto the ART.md palette — because the raw Tripo maps
are glossy and near-white and read as crumpled foil at dusk (lead r3). The baked emission is signage
only — lit windows come from McKitSkin, which finds the dark panes in this albedo and lights them per
floor cell, so the grade deliberately leaves the dark pane band alone.
"""
from __future__ import annotations

from typing import Optional

import bpy
import numpy as np

import emit_mask
import facade_tex
import grade

#: McKitSkin scales this by `emission_scale` 0.6. Lowered from 2.4 in r6: at 2.4 the baked signage was
#: the brightest thing on a facade and, where the classifier over-reached (see `emit_mask`), it WAS the
#: facade. 1.5 keeps a neon strip reading as neon against a 0.22-linear wall.
EMISSION_STRENGTH = 1.5
#: Normal-map strength on the exported glTF (`normalTexture.scale`, which `McKitSkin` hands straight to
#: `mc_kit`'s `normal_strength`). A Tripo normal map is baked from the same confetti atlas as the
#: albedo, so at 0.06-0.49 m per texel its detail is sub-texel geometry noise, not surface: at 1.0 it
#: put a specular sparkle on every near cover piece (lead r6 MUST-FIX 2, A5deck / A6garden). 0.45 keeps
#: the large-scale relief a riveted tank or a tiled roof actually has and drops the micro-normal term.
NORMAL_STRENGTH = 0.45
#: Roughness written over the repainted texels, where the ORM is flattened (see `grade.flatten_over`).
#: Painted concrete and painted steel at dusk: matte enough that a grazing sun does not find a gloss
#: term to sparkle on, and matched to `grade.ROUGH_FLOOR` so the two halves of one wall agree.
WALL_ROUGH = 0.62


def resize(tex: int) -> None:
    """Cap the imported texture set: albedo/normal at `tex`, the packed maps at half that."""
    for img in bpy.data.images:
        if img.size[0] <= 0 or img.size[0] <= (tex if img.name.startswith("Color") else tex // 2):
            continue
        side = tex if img.name.startswith("Color") else max(tex // 2, 256)
        img.scale(side, side)


def _images_by_kind() -> dict:
    """{kind: image} for the imported Tripo set. `Color` and `ORM` are found by name prefix; the
    normal map is NOT — Tripo names it `NormalGL_<uuid>` and the prefix map never matched it, which is
    why the r5 pass believed it had replaced the normal map and had not (see `_normal_node`)."""
    out: dict = {}
    for img in bpy.data.images:
        if img.size[0] <= 0:
            continue
        head = img.name.split("_")[0]
        out.setdefault("Normal" if head.startswith("Normal") else head, img)
    return out


def _normal_node(nt):
    """The material's existing Normal Map node and its image, or (None, None).

    `kitmat.build()` REUSES the imported Tripo material rather than making a new one, so its node tree
    — including the NormalGL texture Tripo linked — is still wired up. Finding the node is the only
    reliable way to reach that image: `_images_by_kind()` keys on the name prefix and Tripo's normal
    map is `NormalGL_<uuid>`, so `imgs.get("Normal")` returned None through r5 and the normal map
    shipped at Tripo's own strength, untouched, under every repainted wall (lead r6 MUST-FIX 1/2).
    """
    for node in nt.nodes:
        if node.type != "NORMAL_MAP" or not node.inputs["Color"].is_linked:
            continue
        src = node.inputs["Color"].links[0].from_node
        if src.type == "TEX_IMAGE" and src.image is not None and src.image.size[0] > 0:
            return node, src.image
    return None, None


def _tex_node(nt, img, x: float, y: float):
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image, node.location = img, (x, y)
    return node


def build(obj: bpy.types.Object, tex: int, band: str = "street", aid: str = "kit",
          win_mask=None, mask_side: int = 0, walls=None, tops=None,
          signage: bool = True) -> dict:
    """Rewire `obj`'s single material and return the emission-mask + grade stats.

    `win_mask` / `mask_side` are `panes.build()`'s window mask: the geometry-derived pane grid that
    replaces r3's darkest-percentile carve (lead r4 MUST-FIX 2). It travels separately from the glTF
    material — Godot reads it as `McKitSkin`'s `win_mask` — but the albedo is darkened through it here
    so the glass reads as glass in daylight too.

    `walls` / `tops` are `wallgroup`'s face groups: every near-vertical and near-horizontal face on the
    model. They are what the facade repaint covers (lead r6 MUST-FIX 1 and 3).
    """
    resize(tex)
    mat = obj.data.materials[0] if obj.data.materials else bpy.data.materials.new("kit_body")
    mat.name = "kit_body"
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    imgs = _images_by_kind()

    colour: Optional[bpy.types.Image] = imgs.get("Color")
    if colour is None:
        print("  WARN no albedo texture on %s" % obj.name)
        return {"neon_pct": 0.0, "interior_pct": 0.0}

    # Order matters. The emission mask is read from the ORIGINAL albedo (neon signs and lit shopfronts
    # must stay bright and saturated); the glass weight is too (it is what keeps dark panes out of the
    # grade so `mc_kit` still finds its windows). The grade then returns FRESH image datablocks loaded
    # from the JPEGs it wrote — the exporter byte-copies those and re-encodes a dirty buffer at 8x the
    # size (see `grade._write_jpeg`), so the nodes below must point at the returned images, not `imgs`.
    mask, stats = emit_mask.build(colour, tex, signage)
    glass = grade.glass_weight(colour)
    used = grade.used_mask(obj, (grade.MEASURE_PX, colour.size[0]))
    # MUST-FIX 1 and 3 (lead r6): every wall is repainted with a world-scaled, texel-aware facade
    # field. r5 painted a grid whose lines came out 0.3-1.2 texels wide on every building — invisible
    # on the towers, aliased into black/white speckle on the props — and only inside the strictly
    # planar regions, so most of every facade kept the Tripo blotches.
    fstats, painted = facade_tex.repaint(obj, colour, walls or [], band, tops or [])
    stats.update(fstats)
    # MUST-FIX 1 (lead r6): the emission mask is read from the ORIGINAL albedo, where a Tripo wall is
    # near-white, so `emit_mask` classified whole facades as lit interior and shipped them at
    # `EMISSION_STRENGTH` 2.4. That — not the albedo — is what made the near walls at T1fac and A4st
    # read as large pale peach-to-white planes: the albedo pass measures 0.10-0.25 linear on the same
    # texels (`captures/kit/wall_t01_alb.png` next to `wall_t01.png`). A repainted wall is not a light
    # source; the lit windows come from `mc_kit`'s window layer through the pane mask, not from here.
    mask, stats["emit_masked_pct"] = grade.flatten_over(mask, painted, (0.0, 0.0, 0.0))
    colour, ga = grade.albedo(colour, band, used, aid, win_mask, mask_side, painted)
    stats.update(ga)
    orm_img: Optional[bpy.types.Image] = imgs.get("ORM")
    if orm_img is not None:
        orm_img, go = grade.orm(orm_img, glass, (imgs["Color"].size[0], imgs["Color"].size[1]), aid)
        stats.update(go)
    # MUST-FIX 1 and 2 (lead r6): the normal map and the ORM are baked from the same confetti atlas as
    # the albedo, through the same stretched UV islands. Under a repainted wall they are a smeared
    # bump-and-gloss field that has nothing to do with the new albedo — the grazing-sun gate render was
    # dominated by soft wedges that follow the atlas, and the near cover pieces sparkled at 1K. Both
    # are flattened over exactly the repainted texels; the model's own relief survives on real detail.
    nmap, normal = _normal_node(nt)
    if normal is not None:
        normal, stats["normal_flat_pct"] = grade.flatten_over(normal, painted, (0.5, 0.5, 1.0),
                                                              aid, "normal")
        src = nmap.inputs["Color"].links[0].from_node
        src.image = normal
    if orm_img is not None:
        orm_img, stats["orm_flat_pct"] = grade.flatten_over(orm_img, painted,
                                                            (1.0, WALL_ROUGH, 0.0), aid, "orm")

    if orm_img is not None:
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        sep.location = (-380, -200)
        nt.links.new(_tex_node(nt, orm_img, -620, -200).outputs["Color"], sep.inputs["Color"])
        nt.links.new(sep.outputs[1], bsdf.inputs["Roughness"])
        nt.links.new(sep.outputs[2], bsdf.inputs["Metallic"])
    else:
        for key, slot in (("Roughness", "Roughness"), ("Metallic", "Metallic")):
            if key in imgs:
                nt.links.new(_tex_node(nt, imgs[key], -620, -420).outputs["Color"], bsdf.inputs[slot])
    if nmap is not None:
        nmap.inputs["Strength"].default_value = NORMAL_STRENGTH
    elif normal is not None:
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nmap.location = (-380, -520)
        nmap.inputs["Strength"].default_value = NORMAL_STRENGTH
        nt.links.new(_tex_node(nt, normal, -620, -620).outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])

    nt.links.new(_tex_node(nt, colour, -620, 40).outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Emission Strength"].default_value = EMISSION_STRENGTH
    nt.links.new(_tex_node(nt, mask, -620, 260).outputs["Color"], bsdf.inputs["Emission Color"])
    return stats


def build_cover(obj: bpy.types.Object, imgs: dict, aid: str = "kit") -> dict:
    """Wire a `covertex.build()` texture set onto `obj` and return the material stats.

    Deliberately NOT `build()`: the cover band gets its albedo, ORM and normal from the re-bake, so
    the facade repaint, the band grade and the emission classifier have nothing left to do — and each
    of them would actively undo it (the grade's `target / median` gain is what flattened twelve
    concepts into one brown, and the emission classifier is what lit k07's hazard band as neon).

    Emission is a BLACK texture rather than an absent one: `McMaterials.kit()` only reads
    `src.emission_*` when `emission_enabled`, and the window layer falls back to "find the dark texels
    in the albedo" when it is handed no mask at all — which on a grimy, seam-lined prop would light
    the seams. Black means off, unambiguously.
    """
    mat = obj.data.materials[0] if obj.data.materials else bpy.data.materials.new("kit_body")
    mat.name = "kit_body"
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    mat.use_nodes = True
    nt = mat.node_tree
    for node in list(nt.nodes):
        if node.type not in ("BSDF_PRINCIPLED", "OUTPUT_MATERIAL"):
            nt.nodes.remove(node)
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    colour, orm_img, normal = imgs.get("Color"), imgs.get("ORM"), imgs.get("Normal")
    if colour is None:
        print("  WARN cover %s has no baked albedo" % aid)
        return {"cover_material": 0}
    nt.links.new(_tex_node(nt, colour, -620, 40).outputs["Color"], bsdf.inputs["Base Color"])
    if orm_img is not None:
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        sep.location = (-380, -200)
        nt.links.new(_tex_node(nt, orm_img, -620, -200).outputs["Color"], sep.inputs["Color"])
        nt.links.new(sep.outputs[1], bsdf.inputs["Roughness"])
        nt.links.new(sep.outputs[2], bsdf.inputs["Metallic"])
    if normal is not None:
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nmap.location = (-380, -520)
        nmap.inputs["Strength"].default_value = NORMAL_STRENGTH
        nt.links.new(_tex_node(nt, normal, -620, -620).outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    black = bpy.data.images.get("kit_emit_black") or bpy.data.images.new(
        "kit_emit_black", 8, 8, alpha=False)
    black.pixels.foreach_set(np.zeros(8 * 8 * 4, dtype=np.float32))
    nt.links.new(_tex_node(nt, black, -620, 260).outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 0.0
    return {"cover_material": 1, "emit_off": 1, "neon_pct": 0.0, "interior_pct": 0.0}
