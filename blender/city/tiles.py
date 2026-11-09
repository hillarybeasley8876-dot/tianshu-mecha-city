"""Tiling and export (city-build).

Geometry is cut into 200 m tiles; inside a tile it is cut again into <= 60 m chunks so a mesh
never lands in all four sun-shadow splits (godot-tech 4.3). Each chunk emits one object per
material role (so a chunk is 1-4 draw calls, not one per surface) and each tile emits one
`-colonly` and one `-occonly` object. Tiles export as .glb, one file per tile.
"""
import os

import bmesh
import bpy
from mathutils import Vector

from lib import export, uv
from kit import builder, roles

TILE = 200.0     ## export granularity
CHUNK = 60.0     ## shadow-split granularity
Z_CHUNK = 120.0  ## vertical cut, so a 240 m tower is two pieces, not four


def tile_key(x, y, half):
    return (int((x + half) // TILE), int((y + half) // TILE))


def chunk_key(x, y, z, half):
    return (int((x + half) // CHUNK), int((y + half) // CHUNK), int(z // Z_CHUNK))


def _bisect(bm, co, no, keep_inner):
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-5,
                           plane_co=co, plane_no=no, clear_outer=keep_inner,
                           clear_inner=not keep_inner)


def center(bm):
    """Median of the face centres (BMesh has no centre of its own)."""
    n = len(bm.faces)
    if n == 0:
        return Vector((0.0, 0.0, 0.0))
    acc = Vector((0.0, 0.0, 0.0))
    for f in bm.faces:
        acc += f.calc_center_median()
    return acc / n


def split(bm, half):
    """Cut a bmesh into <= CHUNK plan pieces and <= Z_CHUNK tall pieces.
    Returns [(tile, chunk key, bmesh)]."""
    pieces = [bm]
    for axis, extent in ((0, CHUNK), (1, CHUNK), (2, Z_CHUNK)):
        nxt = []
        for piece in pieces:
            nxt.extend(_split_axis(piece, axis, extent, half if axis < 2 else 0.0))
        pieces = nxt
    out = []
    for piece in pieces:
        if not len(piece.faces):
            piece.free()
            continue
        c = center(piece)
        out.append((tile_key(c.x, c.y, half), chunk_key(c.x, c.y, c.z, half), piece))
    return out


def _split_axis(bm, axis, extent, origin):
    """Repeatedly cut one axis at `extent` intervals until the piece fits."""
    out = []
    stack = [bm]
    while stack:
        piece = stack.pop()
        lo = min(v.co[axis] for v in piece.verts)
        hi = max(v.co[axis] for v in piece.verts)
        if hi - lo <= extent * 1.001:
            out.append(piece)
            continue
        base = origin if origin else 0.0
        cut = base + (int((lo - base) // extent) + 1) * extent
        if cut <= lo + 1e-4 or cut >= hi - 1e-4:
            out.append(piece)
            continue
        no = Vector((0.0, 0.0, 0.0))
        no[axis] = 1.0
        co = Vector((0.0, 0.0, 0.0))
        co[axis] = cut
        outer = piece.copy()
        _bisect(piece, co, no, True)
        _bisect(outer, co, no, False)
        if len(piece.faces):
            stack.append(piece)
        else:
            piece.free()
        if len(outer.faces):
            stack.append(outer)
        else:
            outer.free()
    return out


class TileSet:
    """Accumulates render chunks and collision/occluder proxies per 200 m tile."""

    def __init__(self, half):
        self.half = half
        self.render = {}   ## tile -> {chunk key -> {role index -> bmesh}}
        self.col = {}      ## tile -> bmesh
        self.col_lm = {}   ## tile -> bmesh (landmark collision: collides, never HLOD)
        self.occ = {}      ## tile -> bmesh
        self.props = {}    ## tile -> bmesh (Layers.PROPS decoration)
        self.curtain = {}  ## tile -> bmesh (map-edge no-fly curtain: collides, never HLOD)

    def add_kit(self, kit, prefix=""):
        """Chunk a finished render Kit into the tile set. Returns the chunk count.

        `prefix` goes in front of every exported chunk name, which is how `city.gd` tells a
        landmark chunk (`lm_t3_1_c...`) from an ordinary one and gives it a 2 km range instead of
        the 450 m detail cut (reviews/city-build-r8.md item 1).
        """
        bm = kit.merged()
        if bm is None:
            return 0
        n = 0
        for tile, key, piece in split(bm, self.half):
            per_chunk = self.render.setdefault(tile, {}).setdefault((prefix,) + key, {})
            for mat_index, faces in _by_material(piece).items():
                target = per_chunk.setdefault(mat_index, bmesh.new())
                _append_faces(target, faces)
            n += 1
            piece.free()
        return n

    def add_solids(self, solids, landmark=False):
        """Collision and occluder proxies, bucketed by the tile their faces sit in.

        A landmark's collision goes to `self.col_lm` so it still collides (it is merged back into
        the same `-colonly` object on export) but `hlod_meshes()` never sees it: at 561 m the
        Spire was being drawn as its own HLOD collision mass, a lavender pixel-block trumpet.
        """
        col_store = self.col_lm if landmark else self.col
        for src, store in ((solids.col, col_store), (solids.occ, self.occ),
                           (solids.props, self.props), (solids.curtain, self.curtain)):
            bm = src.merged()
            if bm is None:
                continue
            buckets = {}
            for f in bm.faces:
                c = f.calc_center_median()
                buckets.setdefault(tile_key(c.x, c.y, self.half), []).append(f)
            for tile, faces in buckets.items():
                _append_faces(store.setdefault(tile, bmesh.new()), faces)
            bm.free()

    def hlod_meshes(self):
        """A copy of every tile's collision mass, for the distant stand-in mesh.

        `self.curtain` and `self.col_lm` are deliberately absent: the map-edge no-fly curtain is
        four 1 400 x 260 m cards with no render mesh, and merged into a proxy they read as a flat
        wall filling the frame from every vista (city-art r3); the landmark mass would double-draw
        the Spire as a box over the landmark's own render chunks (r8 item 1)."""
        out = {}
        for tile, src in self.col.items():
            out[tile] = src.copy()
        return out

    def tiles(self):
        return sorted(set(self.render) | set(self.col) | set(self.col_lm) | set(self.occ)
                      | set(self.props) | set(self.curtain))


def _by_material(bm):
    groups = {}
    for f in bm.faces:
        groups.setdefault(f.material_index, []).append(f)
    return groups


def _merge(a, b):
    """One bmesh holding the faces of both, or whichever exists."""
    if a is None:
        return b
    if b is None:
        return a
    _append_faces(a, list(b.faces))
    b.free()
    return a


def _append_faces(dst, faces):
    remap = {}
    for f in faces:
        ring = []
        for v in f.verts:
            if v not in remap:
                remap[v] = dst.verts.new(v.co)
            ring.append(remap[v])
        try:
            nf = dst.faces.new(ring)
            nf.material_index = f.material_index
        except ValueError:
            pass


def _emit(name, bm, col, materials, single_index=None, windows=False):
    """One object per (chunk, role) or per proxy. `single_index` keeps only that material slot,
    so a merged-per-material object carries one primitive, not twelve."""
    if bm is None or not len(bm.faces):
        if bm is not None:
            bm.free()
        return None
    slots = materials
    if single_index is not None:
        for f in bm.faces:
            f.material_index = 0
        slots = [materials[single_index]]
    else:
        # Collision/occluder proxies carry n-gons; triangulate so the exporter can build
        # tangents (it warns and ships an empty attribute otherwise).
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
    obj = builder.object_from_bmesh(name, bm, col, slots)
    uv.box_uv(obj, 1.0)
    if windows:
        builder.tag_windows(obj.data)
    obj.data.calc_loop_triangles()
    return obj


def export_tiles(tiles, out_dir, materials, report):
    """Write one .glb per tile. Returns {tile: path}."""
    os.makedirs(out_dir, exist_ok=True)
    store_hlod = tiles.hlod_meshes()
    paths = {}
    col = bpy.context.scene.collection
    for tile in tiles.tiles():
        tx, ty = tile
        objs = []
        for chunk, groups in sorted(tiles.render.get(tile, {}).items()):
            for mat_index, bm in sorted(groups.items()):
                role = roles.ROLE_ORDER[mat_index]
                name = "%st%d_%d_c%d_%d_%d_%s" % (chunk[0], tx, ty, chunk[1], chunk[2], chunk[3],
                                                  role.replace("mc_", ""))
                obj = _emit(name, bm, col, materials, single_index=mat_index,
                            windows=(role == "mc_window"))
                if obj is not None:
                    objs.append(obj)
        # The HLOD proxy is the tile's own collision mass: one cheap mesh that stands in for
        # every chunk beyond the swap distance (ART.md 6 / godot-tech 4.4).
        hlod = store_hlod.get(tile)
        if hlod is not None:
            obj = _emit("t%d_%d_hlod" % (tx, ty), hlod, col, [materials[1]], single_index=0)
            if obj is not None:
                objs.append(obj)
        # The no-fly curtain and the landmark mass ride in the same -colonly object as the rest of
        # the collision (they are ordinary WORLD collision); they are just kept out of the HLOD
        # proxy above.
        col_bm = _merge(_merge(tiles.col.get(tile), tiles.curtain.get(tile)),
                        tiles.col_lm.get(tile))
        for suffix, store in (("-colonly", {tile: col_bm}), ("-occonly", tiles.occ),
                              ("_props-colonly", tiles.props)):
            obj = _emit("t%d_%d%s" % (tx, ty, suffix), store.get(tile), col, materials)
            if obj is not None:
                objs.append(obj)
        if not objs:
            continue
        path = os.path.join(out_dir, "tile_%d_%d.glb" % (tx, ty))
        export.export_glb(path, objects=objs)
        tris = sum(len(o.data.loop_triangles) for o in objs)
        size = os.path.getsize(path)
        report.append((os.path.basename(path), len(objs), tris, size))
        paths[tile] = path
        for obj in objs:
            bpy.data.objects.remove(obj, do_unlink=True)
    return paths
