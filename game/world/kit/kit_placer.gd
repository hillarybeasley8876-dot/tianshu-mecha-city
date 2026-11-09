extends Node3D
## city-kit — places the Tripo architecture kit over the structures city-build left unrendered.
##
## `city.gd` instances `kit_placer.tscn` and calls `setup(city, layout)` when the build ran skinned
## (briefs/city-kit.md step 6). Everything positional comes from `data/map/kit_assign.json`, copied
## next to the models as `res://world/kit/kit_assign.json` by `tools/citykit/assign.py`; the model
## index is `kit.json`. Nothing enumerates `res://` — the index names every path, which is what the
## exported build needs (godot-tech §8: no DirAccess on `res://`).
##
## One MultiMeshInstance3D per (model, 200 m tile): a 40-model kit over 391 buildings is ~150 nodes,
## not 391. Each batch carries one `McMaterials.kit()` material, so the whole city adds a handful of
## materials. Detail ends at 450 m, where city-build's per-tile HLOD proxy (built from the collision
## mass, which skinning never touches) takes over at 430 m — the same swap the blockout uses.
##
## Coordinates: `kit_assign.json` is in Blender map space (X east, Y north, Z up) like
## `data/map/city_layout.json`; `city.to_godot()` converts, and the yaw is numerically the same angle
## about the up axis (Blender +Z CCW == Godot +Y).

const ASSIGN_PATH := "res://world/kit/kit_assign.json"
const KIT_PATH := "res://world/kit/kit.json"
const TILE := 200.0
## The far band's batch grid. r9 measured the alternative — ONE map-wide batch per model, which cuts
## KitPlacer from 105 draws to 69 at the A1 spawn — and rejected it: a MultiMeshInstance3D is culled by
## its whole AABB, so a map-wide batch is never culled and the far band submits 0.9 M primitives that
## four tiled batches reject with the tile. 69 draws / 6.80 M prims measured 20 fps against 105 draws /
## 5.92 M prims at 29 fps. The 800 m grid stays.
const TILE_FAR := 800.0
const DETAIL_END := 450.0
## r2 item 2: the decimated kit mesh takes over where the detail batch ends and holds the skyline
## out to 1 600 m, which is past every vista. City-build's box proxy is NOT hidden for it — that
## proxy is the only render of the decks, viaducts and ground past 450 m too (see ## Requests).
const FAR_BEGIN := 450.0
## 1 100 m, not 1 600: the far band is 41 % of the kit's triangles at the A1 spawn and the collapse
## has a hard per-mesh floor (f01 will not go below 12.5 k however hard it is pushed), so reach is
## the only lever left. Past ~900 m city-art's skyline ring is the horizon anyway.
const FAR_END := 1100.0
## r9 item 1: the 96-box skyline ring. Every one of those boxes is between 0 and 400 m from something
## the player can stand on (measured against the layout's streets, buildings and arenas), so a
## `visibility_range_begin` above zero would leave a hole where city-build dropped the box; the ring is
## therefore drawn from the camera outwards. The END has to cover the farthest pairing — a ring tower
## 1 229 m out seen from the opposite map corner is ~2 220 m — and 3 000 m leaves margin for the
## high roof cameras without ever reaching the far plane.
const RING_BEGIN := 0.0
const RING_END := 3000.0
## The ring's own batch grid. It is coarser than the far band's 800 m because the ring boxes sit on an
## annulus 740-1 229 m out: on an 800 m grid they land in five buckets per axis, so a 12-model ring
## makes ~60 batches where a 1 600 m grid makes ~30. See `_push` for the rest of the measurement.
const RING_TILE := 1600.0
## Map half-extent, for the tile key `far_lod` rows are written with (blender/city/tiles.py).
const MAP_HALF := 700.0
## Where an arena cover piece swaps from its 12 k-triangle detail mesh to its LOD. The player fights
## beside this geometry, so the near tier is the one that has to survive a grazing sun (lead r4
## MUST-FIX 2); 150 m is the lead's number and covers an arena from its middle.
const COVER_NEAR := 150.0
const KIT_OPTS := {"base_y": 0.0}  ## models are metre-scale with the pivot at the footprint base

var _city: Node = null
var _meshes: Dictionary = {}
var _lods: Dictionary = {}
var _fars: Dictionary = {}
## model id -> the window mask Blender stamped (`<id>/<id>_win.png`), for models that have one.
var _wins: Dictionary = {}
var _win_tex: Dictionary = {}
## 200 m tile ids whose HLOD proxy stands down for the far LOD (kit_assign.json `far_lod`).
var _far_tiles: Dictionary = {}
## Models whose far mesh failed the silhouette gate and therefore draw no far batch.
var _gate_failed: PackedStringArray = []
var _batches := 0
var _placed := 0
var _skipped := 0
## Every batch this placer built, so city-art's settle pass can move the pieces onto the surface the
## player sees. The LISTS are the source of truth, not the MultiMesh: `get_instance_transform` returns
## identity under the dummy renderer a head-less test runs on, so reading them back would silently
## settle nothing.
var _built: Array[Dictionary] = []


## Entry point called by `city.gd`. Safe to call with a city that has no `to_godot`.
##
## `assign` overrides the shipped assignment file. It exists for the cover line-up scene
## (`world/kit/tests/kit_lineup.tscn`), which needs the real kit materials and the real dusk
## environment on one instance of every cover model — including the ones the assigner never places —
## without editing `kit_assign.json` for a screenshot.
func setup(city: Node, _layout: Dictionary = {}, assign: Dictionary = {}) -> void:
	_city = city
	var rows := assign if not assign.is_empty() else _read_json(ASSIGN_PATH)
	var kit := _read_json(KIT_PATH)
	if rows.is_empty() or kit.is_empty():
		push_error("KitPlacer: %s or %s is missing/empty — the skinned city has no architecture"
				% [ASSIGN_PATH, KIT_PATH])
		return
	var sizes := {}
	for m in kit.get("models", []):
		sizes[String(m.get("id", ""))] = m.get("size", [1.0, 1.0, 1.0])
	# Pieces are placed by the thousand (6 600 railings alone), so they take the cheap second glb the
	# Blender pass writes for them; buildings always take the full-detail one, and their far batch
	# takes the decimated one — but only for models that passed the silhouette gate
	# (blender/citykit/fargate.py). A far mesh that tears is worse than the box proxy behind it, so a
	# failed model simply draws no far batch and its tile keeps city-build's proxy.
	for m in kit.get("models", []):
		var mid := String(m.get("id", ""))
		if m.has("lod"):
			_lods[mid] = String((m["lod"] as Dictionary).get("glb", ""))
		if m.has("win"):
			_wins[mid] = String(m["win"])
		if m.has("far"):
			var far_row: Dictionary = m["far"]
			var gate: Dictionary = far_row.get("gate", {})
			if gate.is_empty() or bool(gate.get("pass", true)):
				_fars[mid] = String(far_row.get("glb", ""))
			else:
				_gate_failed.append(mid)
	# The far band is drawn ONLY where city-build's HLOD proxy stands down for it (the `far_lod`
	# rows). Anywhere else the proxy is already the far representation, and drawing both was 1.5 M
	# primitives of overlap at the A1 spawn for a picture no better than either alone.
	for row in rows.get("far_lod", []):
		_far_tiles[String(row.get("id", ""))] = true
	var groups := {}
	for row in rows.get("buildings", []):
		_add_placement(groups, sizes, row, "detail")
		if _far_tiles.has(_tile_of(row)):
			_add_placement(groups, sizes, row, "far")
	for row in rows.get("cover", []):
		_add_cover(groups, sizes, row)
	for row in rows.get("pieces", []):
		_add_piece(groups, sizes, row)
	for row in rows.get("ring", []):
		_add_ring(groups, sizes, row)
	_build(groups)
	print("KitPlacer: %d models in %d batches, %d instances (%d rows skipped)"
			% [_meshes.size(), _batches, _placed, _skipped])
	if not _gate_failed.is_empty():
		print("KitPlacer: %d models failed the far silhouette gate and draw no far batch: %s"
				% [_gate_failed.size(), ", ".join(_gate_failed)])

# --------------------------------------------------------------------- input
func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("KitPlacer: %s is not a JSON object" % path)
		return {}
	return parsed as Dictionary


func _to_godot(p: Variant) -> Vector3:
	if _city != null and _city.has_method("to_godot"):
		return _city.call("to_godot", p) as Vector3
	var v: Array = p as Array
	return Vector3(float(v[0]), float(v[2]), -float(v[1]))


## "t3_4" for a building row, from the same key city-build's tiles.py and far.py use. A tiled row's
## copies can straddle a boundary, so every piece is tested, not just the row's own centre.
func _tile_of(row: Dictionary) -> String:
	var parts: Array = row.get("pieces", [])
	var p: Array = parts[0].get("pos", row.get("pos", [0, 0, 0])) if not parts.is_empty() \
			else row.get("pos", [0, 0, 0])
	return "t%d_%d" % [int(floor((float(p[0]) + MAP_HALF) / TILE)),
			int(floor((float(p[1]) + MAP_HALF) / TILE))]


func _add_placement(groups: Dictionary, sizes: Dictionary, row: Dictionary,
		tier: String = "detail") -> void:
	var model := String(row.get("model", ""))
	if not sizes.has(model):
		_skipped += 1
		return
	if tier == "far" and not _fars.has(model):
		return
	# A tiled row (r2 item 3) is one layout building answered by 2-3 copies end to end; every other
	# row is a single transform at its own `pos`.
	var parts: Array = row.get("pieces", [])
	if parts.is_empty():
		parts = [{"pos": row.get("pos", [0, 0, 0]), "yaw": row.get("yaw", 0.0),
				"scale": row.get("scale", [1.0, 1.0, 1.0])}]
	for part in parts:
		var p: Dictionary = part
		var s: Array = p.get("scale", [1.0, 1.0, 1.0])
		_push(groups, model, _basis(float(p.get("yaw", 0.0)),
				Vector3(float(s[0]), float(s[2]), float(s[1])),
				_to_godot(p.get("pos", [0, 0, 0]))), tier)


## One arena cover box: 1-27 copies of the same cluster, tiled along the box and stacked up it, each
## scaled uniformly (tools/citykit/cover.py).
##
## Every piece is pushed TWICE, into a near batch and a far batch, and Godot's visibility ranges swap
## between them at COVER_NEAR. The player fights beside this geometry, so inside 150 m it is the
## 12 k-triangle detail mesh; past that it is the LOD. Both batches exist as nodes but only one of
## each pair is ever in the frustum, so the swap costs memory and no draws (lead r4 MUST-FIX 2).
func _add_cover(groups: Dictionary, sizes: Dictionary, row: Dictionary) -> void:
	var model := String(row.get("model", ""))
	if not sizes.has(model):
		_skipped += 1
		return
	for p in row.get("pieces", []):
		var piece: Dictionary = p
		var s: Array = piece.get("scale", [1.0, 1.0, 1.0])
		var t := _basis(float(piece.get("yaw", 0.0)),
				Vector3(float(s[0]), float(s[2]), float(s[1])),
				_to_godot(piece.get("pos", [0, 0, 0])))
		_push(groups, model, t, "cover_near")
		if _lods.has(model):
			_push(groups, model, t, "cover_far")


## One skyline-ring box (r9 item 1). A ring row is always a single transform at its own `pos` — the
## assigner never tiles one — and it always draws the model's FAR glb, so a model whose far mesh failed
## the silhouette gate simply draws nothing and city-build's box stays dropped. That case is counted
## in `_skipped` rather than silently leaving a hole in the horizon.
func _add_ring(groups: Dictionary, sizes: Dictionary, row: Dictionary) -> void:
	var model := String(row.get("model", ""))
	if not sizes.has(model) or not _fars.has(model):
		_skipped += 1
		return
	var s: Array = row.get("scale", [1.0, 1.0, 1.0])
	_push(groups, model, _basis(float(row.get("yaw", 0.0)),
			Vector3(float(s[0]), float(s[2]), float(s[1])),
			_to_godot(row.get("pos", [0, 0, 0]))), "ring")


func _add_piece(groups: Dictionary, sizes: Dictionary, row: Dictionary) -> void:
	var model := String(row.get("model", ""))
	if not sizes.has(model):
		_skipped += 1
		return
	var segs: Array = row.get("segments", [])
	if segs.is_empty():
		_add_placement(groups, sizes, row, "lod")
		return
	var size: Array = sizes[model]
	for seg in segs:
		_push(groups, model, _segment(size, seg as Dictionary), "lod")


## A straight, tileable segment: the model's long horizontal axis runs along the segment, scaled to
## its length. Blender Y is Godot Z after the glTF Y-up export, hence the axis test on `size`.
func _segment(size: Array, seg: Dictionary) -> Transform3D:
	var yaw := float(seg.get("yaw", 0.0))
	var scale := Vector3.ONE
	var s: Variant = seg.get("scale", null)
	if s is Array:
		var a: Array = s
		scale = Vector3(float(a[0]), float(a[2]), float(a[1]))
	else:
		var length := float(seg.get("len", 0.0))
		var sx: float = maxf(float(size[0]), 0.01)
		var sy: float = maxf(float(size[1]), 0.01)
		if length > 0.0:
			if sy >= sx:
				scale = Vector3(1.0, 1.0, length / sy)
			else:
				scale = Vector3(length / sx, 1.0, 1.0)
				yaw += 90.0
	return _basis(yaw, scale, _to_godot(seg.get("pos", [0, 0, 0])))


## Scale in the MODEL's own frame, then turn: `kit_assign.json` and `_segment` give the scale per model
## axis. `Basis.scaled()` would scale the world axes after the turn instead, which at any yaw that is
## not a multiple of 180 deg stretches the wrong axis or shears the model (11-03: 189 of 384 buildings
## missed part of their footprint, and the roof dressing over the missing part hung in the air).
func _basis(yaw_deg: float, scale: Vector3, origin: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)).scaled_local(scale), origin)


func _push(groups: Dictionary, model: String, t: Transform3D, tier: String) -> void:
	# Every tier is batched on a grid, the ring included. A map-wide ring batch reads better on paper
	# (one draw per model for 96 instances) but a MultiMeshInstance3D is culled by its whole AABB, so it
	# is never culled and the whole 0.5 M-triangle horizon is submitted from a street corner where a
	# sliver of it is visible: measured at the A1 spawn, map-wide batches cost 5.92 M primitives against
	# 5.14 M on a grid, for six fewer draws.
	var tile := RING_TILE if tier == "ring" else (TILE_FAR if tier == "far" else TILE)
	# Centred, so a tile really is one bucket: floor(-800 / 800) is -1 while floor(800 / 800) is 1,
	# which silently splits every batch that crosses the origin into an east one and a west one.
	var key := "%s|%s|%d|%d" % [model, tier, int(floor((t.origin.x + tile * 0.5) / tile)),
			int(floor((t.origin.z + tile * 0.5) / tile))]
	if not groups.has(key):
		groups[key] = {"model": model, "tier": tier, "list": [] as Array[Transform3D]}
	(groups[key]["list"] as Array).append(t)


# -------------------------------------------------------------------- output
func _mesh_for(model: String, tier: String) -> Mesh:
	var rel := "%s/%s.glb" % [model, model]
	if tier == "lod" or tier == "cover_far":
		if _lods.has(model):
			rel = String(_lods[model])
	elif (tier == "far" or tier == "ring") and _fars.has(model):
		rel = String(_fars[model])
	var key := "%s|%s" % [model, tier]
	if _meshes.has(key):
		return _meshes[key]
	var path := "res://world/kit/" + rel
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("KitPlacer: cannot load %s" % path)
		_meshes[key] = null
		return null
	var node := packed.instantiate()
	var mesh := _first_mesh(node)
	node.free()
	_meshes[key] = mesh
	return mesh


func _first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return (node as MeshInstance3D).mesh
	for child in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null


func _build(groups: Dictionary) -> void:
	for key in groups:
		var batch: Dictionary = groups[key]
		var model := String(batch["model"])
		var tier := String(batch["tier"])
		var list: Array = batch["list"]
		var mesh := _mesh_for(model, tier)
		if mesh == null or list.is_empty():
			_skipped += list.size()
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i] as Transform3D)
		var mi := MultiMeshInstance3D.new()
		mi.name = "kit_%s" % key.replace("|", "_")
		mi.multimesh = mm
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if tier == "far":
			# A 1 500-triangle mesh 500 m away casts nothing anyone can see, and the shadow pass is
			# where a skyline's draw count goes.
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_begin = FAR_BEGIN
			mi.visibility_range_end = FAR_END
		elif tier == "ring":
			# The horizon band. Shadows off for the same reason as `far`, and the range covers the
			# whole map (see RING_BEGIN / RING_END).
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_begin = RING_BEGIN
			mi.visibility_range_end = RING_END
		elif tier == "cover_near":
			# The player stands behind this. Shadows on, detail mesh, and only out to the swap.
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mi.visibility_range_end = COVER_NEAR
		elif tier == "cover_far":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_begin = COVER_NEAR
			mi.visibility_range_end = DETAIL_END
		elif tier == "detail":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mi.visibility_range_end = DETAIL_END
		else:
			# Pieces (railings, fasciae, stalls, cover) are 3.5 M of the 5.4 M triangles in frame at
			# the A1 spawn, and the shadow pass draws every one of them a second time. A railing's
			# shadow is not worth 30 fps; the buildings keep theirs.
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = DETAIL_END
		mi.material_override = _kit_material(mesh, model)
		add_child(mi)
		_built.append({"node": mi, "mesh": mesh, "list": list, "tier": tier, "model": model,
				"name": String(mi.name), "index": _built.size()})
		_batches += 1
		_placed += list.size()


## The batches whose instances are RENDERED near the player and can therefore be a surface something
## else stands on — or be settled onto one themselves. `far` and `cover_far` draw past 450 m / 150 m
## and are the same geometry at a lower tier, so they follow their near twin rather than being
## settled twice.
func near_batches() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for batch in _built:
		if String(batch["tier"]) in ["detail", "lod", "cover_near"]:
			out.append(batch)
	return out


## Re-uploads a batch after the settle pass rewrote its list. An emptied batch is hidden rather than
## left as a zero-instance MultiMesh, which Godot still submits.
func upload(batch: Dictionary, list: Array[Transform3D]) -> void:
	var node := batch.get("node") as MultiMeshInstance3D
	if node == null:
		push_error("KitPlacer: upload called with a batch that has no node")
		return
	if list.is_empty():
		node.multimesh.instance_count = 0
		node.visible = false
		batch["list"] = [] as Array[Transform3D]
		return
	var mm := node.multimesh
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, list[i])
	batch["list"] = list


## One skinned material per model (cached inside `McKitSkin`), so a model on twelve tiles is one
## material. A model whose imported material is missing keeps Godot's default rather than going grey.
##
## The window mask is the point of r4: `McKitSkin` finds panes by albedo darkness unless it is handed
## an explicit mask, and on a Tripo atlas the darkest texels are crevices and seam noise, not windows
## (lead r4 MUST-FIX 2). `blender/citykit/panes.py` stamps a metric grid of 2.0 x 2.4 m rectangles onto
## the flattened vertical walls and writes it here, so every lit texel is a real window.
func _kit_material(mesh: Mesh, model: String) -> Material:
	if mesh.get_surface_count() == 0:
		return null
	var src := mesh.surface_get_material(0)
	if src is BaseMaterial3D:
		var opts := KIT_OPTS.duplicate()
		var mask := _win_mask(model)
		if mask != null:
			opts["win_mask"] = mask
		return McMaterials.kit(src as BaseMaterial3D, opts)
	push_warning("KitPlacer: no BaseMaterial3D on the first surface; using it as imported")
	return src


## The mask texture for a model, loaded once. Missing file is reported, not silently skipped: a model
## that loses its mask loses every lit window it has.
func _win_mask(model: String) -> Texture2D:
	if _win_tex.has(model):
		return _win_tex[model]
	var tex: Texture2D = null
	if _wins.has(model):
		var path := "res://world/kit/" + String(_wins[model])
		tex = load(path) as Texture2D
		if tex == null:
			push_error("KitPlacer: cannot load the window mask %s" % path)
	_win_tex[model] = tex
	return tex
