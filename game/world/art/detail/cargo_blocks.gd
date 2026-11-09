class_name CargoBlocks
extends Node3D
## Arena cover, dressed (city-art, look review 2026-11-02 item 3).
##
## city-build builds every arena cover piece as `kit.box(role)` plus a pale cap — a plain 17-34 m
## rectangular solid — and they are the closest geometry to the camera in the whole game. There are 360
## destructible ones and more permanent ones besides, and they were what made the user's screenshot read
## as building blocks.
##
## The box stays: it is the collider and it is not our file. Each piece gets a skin drawn at the same
## footprint, 2 cm proud, plus whatever breaks its silhouette:
##
## - **soft / destructible** cover becomes a stack of shipping containers. A container stack is almost
##   entirely a SURFACE — ISO pitch, corrugation, corner castings, per-container paint, rust bleeding
##   down, hazard bands — and all of that is pattern, so `mc_cargo` does it on ONE unit cube per slot.
##   Plus a few real containers perched off-grid on top, in proper columns, for the silhouette a flat
##   skin cannot give.
## - **hard** cover becomes a landscaped concrete wall: board-formed concrete, a chamfered coping and a
##   run of planter troughs with foliage along the top, which is what a Sky Garden arena actually is.
##
## Rows come from the DESIGN layout (`data/map/city_layout.json`), which is the only place that tags a
## piece `soft` and carries its rotation. The runtime layout's `breakable_cover` slots are the fallback
## when the design layout is absent; they cover the destructible pieces only.

const CARGO_SHADER := "res://world/art/shaders/mc_cargo.gdshader"
## The kit assignment city-kit writes and city-build reads. Read from inside the project: it used to be
## an absolute home path, so an exported build on any other machine found nothing here and every
## kit-owned cover piece was dressed twice (city-art r12 §3).
const KIT_ASSIGN := "res://world/kit/kit_assign.json"
const PROUD := 0.02            ## metres the skin sits outside the collider box
const CAP_H := 0.8             ## city-build's pale cap, which the skin has to swallow
const EXTRA_CHANCE := 0.66     ## share of stacks that carry perched containers
const EXTRA_MAX := 3           ## containers per column
## A soft piece at or under this height is too low for a slab skin to read as a stack: from above it is
## one flat plane, and the first pass shipped a red ribbed rug in the foreground of the canyon shot.
## These get separate containers laid on the top with real gaps between them instead.
const LOW_H := 8.0
const LOW_SPREAD := 3.2        ## metres of daylight a low stack keeps between two singles
const VISIBILITY_M := 900.0     ## arena cover is the closest geometry in the game; a 40 m stack is a
                               ## handful of pixels past this and mc_cargo costs more than it shows
const GROUP_TILES := 3         ## 3 x 3 city tiles (600 m) share one MultiMesh

## ISO 668 40 ft, in metres. Real sizes: a container at the wrong proportion is worse than none.
const BOX_L := 12.19
const BOX_W := 2.44
const BOX_H := 2.59

var soft_n: int = 0            ## destructible cover pieces, dressed as container stacks
var hard_n: int = 0            ## permanent cover pieces, dressed as landscaped walls
var extras: int = 0            ## perched containers
var low_n: int = 0             ## low soft pieces that got separate containers instead of a perch
var skipped_kit: int = 0       ## pieces left to city-kit's own Tripo cover model (one owner per piece)
var groups: int = 0

var _mat_cargo: ShaderMaterial = null
var _mat_perch: ShaderMaterial = null
## Every instance this layer placed, by kind -> Array[Transform3D]. The MultiMesh is the thing that gets
## drawn, but its transforms cannot be read back reliably (they come back as identity under the dummy
## renderer a head-less test runs on), so a test that wants to know WHERE something landed reads this.
var placed: Dictionary = {}
## Where the kit assignment is read from. A var, not a const, so a test can point the layer at a
## fixture and prove the FILE path works as well as the runtime `kit_skin.cover` list.
var kit_assign_path: String = KIT_ASSIGN


## `design` is data/map/city_layout.json, `layout` city-build's runtime layout. Returns the pieces
## dressed, so the count in a load line is the evidence that the layer ran.
func build(layout: Dictionary, design: Dictionary = {}, seed: int = 20261102) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var rows := _cover_rows(layout, design)
	if rows.is_empty():
		return 0
	var by_group: Dictionary = {}     # group key -> kind -> Array of [Transform3D, Color]
	for row in rows:
		var pos: Vector3 = row["pos"]
		var yaw: float = row["yaw"]
		var skin := row["size"] as Vector3 + Vector3(PROUD * 2.0, CAP_H + PROUD * 2.0, PROUD * 2.0)
		var org := Vector3(pos.x, pos.y + skin.y * 0.5, pos.z)
		var tint: Color = row["tint"]
		var basis := Basis(Vector3.UP, -deg_to_rad(yaw)).scaled_local(skin)
		if bool(row["soft"]):
			soft_n += 1
			_push(by_group, _key(pos), &"skin", Transform3D(basis, org), tint)
			if skin.y <= LOW_H + CAP_H + 0.5:
				low_n += 1
				_low_row(by_group, org, skin, yaw, tint, rng)
			else:
				_perch(by_group, org, skin, yaw, tint, rng)
		else:
			hard_n += 1
			_push(by_group, _key(pos), &"wall", Transform3D(basis, org), tint)
			_plant(by_group, org, skin, yaw, rng)
	for key in by_group:
		var node := Node3D.new()
		node.name = "Cover_" + String(key).replace(",", "_")
		add_child(node)
		groups += 1
		var group := by_group[key] as Dictionary
		for kind in group:
			_emit(node, kind, group[kind] as Array)
	return soft_n + hard_n


## One row per cover piece. The design layout wins: it is the only source that says `soft` and knows
## the rotation. The runtime `breakable_cover` slots are the fallback (and they are soft by definition).
##
## Pieces city-kit owns are dropped here (lead r7): `kit_assign.json` gives one arena cover piece a Tripo
## model and city-build then stops rendering its box, so a container skin on top would be a second,
## competing owner for the same volume. CargoBlocks dresses every piece that has no such row.
func _cover_rows(layout: Dictionary, design: Dictionary) -> Array[Dictionary]:
	var kit := _kit_owned(layout)
	var out: Array[Dictionary] = []
	var seen := 0                 ## cover pieces the design layout offered, kit-owned ones included
	for a in design.get("arenas", []):
		var arena := a as Dictionary
		var district := String(arena.get("district", arena.get("id", "")))
		var aid := String(arena.get("id", district))
		var index := 0
		for c in arena.get("cover", []):
			var piece := c as Dictionary
			var id := "%s#%d" % [aid, index]
			index += 1
			seen += 1
			if kit.has(id):
				skipped_kit += 1
				continue
			var ctr: Array = piece.get("center", [0.0, 0.0, 0.0])
			var sz: Array = piece.get("size", [8.0, 8.0, 8.0])
			# Map space is (x, y, base_z); Godot is (x, up, -y) and the collider box is centre-based.
			var pos := Vector3(float(ctr[0]), float(ctr[2]), -float(ctr[1]))
			out.append({
				"pos": pos,
				"size": Vector3(absf(float(sz[0])), absf(float(sz[2])), absf(float(sz[1]))),
				"yaw": float(piece.get("rot", 0.0)),
				"soft": bool(piece.get("soft", false)),
				"tint": _tint(pos, district),
			})
	if seen > 0:
		return out
	for s in layout.get("prop_slots", []):
		var slot := s as Dictionary
		var kind := String(slot.get("kind", ""))
		if kind != "breakable_cover" and kind != "arena_cover":
			continue
		var sid := String(slot.get("id", ""))
		if sid.is_empty():
			sid = "%s#%d" % [String(slot.get("arena", "")), int(slot.get("index", 0))]
		if kit.has(sid):
			skipped_kit += 1
			continue
		var p: Array = slot.get("pos", [0.0, 0.0, 0.0])
		var sz2: Array = slot.get("size", [8.0, 8.0, 8.0])
		var pos2 := Vector3(float(p[0]), float(p[2]), -float(p[1]))
		out.append({
			"pos": pos2,
			"size": Vector3(absf(float(sz2[0])), absf(float(sz2[2])), absf(float(sz2[1]))),
			"yaw": float(slot.get("yaw_deg", 0.0)),
			"soft": kind == "breakable_cover" or bool(slot.get("soft", false)),
			"tint": _tint(pos2, ""),
		})
	return out


## The cover pieces another unit owns, as `"<arena>#<index>"` ids. Two sources, unioned, because they
## answer different questions: `kit_assign.json` is what city-kit assigned (repo, may lead the build),
## and `layout.kit_skin.cover` is what city-build actually dropped the box for (inside res://, so it
## survives into an exported build where the repo file is gone). Missing either one is not an error.
func _kit_owned(layout: Dictionary) -> Dictionary:
	var ids: Dictionary = {}
	var assign := _read_json(kit_assign_path)
	for r in assign.get("cover", []):
		var row := r as Dictionary
		if String(row.get("kind", "cover")) == "cover":
			ids[String(row.get("id", ""))] = true
	var skin := layout.get("kit_skin", {}) as Dictionary
	for id in skin.get("cover", []):
		ids[String(id)] = true
	ids.erase("")
	return ids


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("CargoBlocks: %s could not be opened — no kit cover rows read" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return parsed as Dictionary
	push_warning("CargoBlocks: %s is not a JSON object" % path)
	return {}


## ART.md §4: faded rust and teal containers in the harbour, white-and-gold in the civic quarter. The
## shader reads COLOR.r as the district weight and COLOR.g as the piece's own seed.
static func _tint(pos: Vector3, district: String) -> Color:
	var civic := district.begins_with("D7") or district.begins_with("D5")
	return Color(1.0 if civic else 0.0, fmod(absf(pos.x) * 0.031 + absf(pos.z) * 0.017, 1.0), 0.0, 1.0)


## A low soft piece: the slab skin stays (city-build's box is under it and still renders, so the volume
## cannot be opened up), but the top face is what the camera sees from the canyon and a single flat
## plane reads as a rug. So the top carries 2-3 SEPARATE containers, all running along the piece's long
## axis and spread across it with metres of daylight between them, which is what a yard row looks like
## from above. Every one of them shows a door end to the long sides.
func _low_row(by_group: Dictionary, org: Vector3, skin: Vector3, yaw: float, tint: Color,
		rng: RandomNumberGenerator) -> void:
	var top := org.y + skin.y * 0.5
	var rot0 := -deg_to_rad(yaw)
	# Containers run along the longer plan axis; they are spread across the other one.
	var along_x := skin.x >= skin.z
	var across_m := (skin.z if along_x else skin.x) - 2.4
	var n := clampi(int(across_m / (BOX_W + LOW_SPREAD)), 2, 3)
	for i in range(n):
		var turned := rng.randf() < 0.22 and skin.x > BOX_L and skin.z > BOX_L
		var s := Vector3(BOX_W, BOX_H, BOX_L) if turned else Vector3(BOX_L, BOX_H, BOX_W)
		var rot := rot0 + (PI * 0.5 if turned else 0.0) + deg_to_rad(rng.randf_range(-6.0, 6.0))
		var t := ((float(i) + 0.5) / float(n) - 0.5) * across_m + rng.randf_range(-0.4, 0.4)
		var along := rng.randf_range(-0.16, 0.16) * (skin.x if along_x else skin.z)
		var off := (Vector2(along, t) if along_x else Vector2(t, along)).rotated(rot0)
		var lean := deg_to_rad(rng.randf_range(-2.0, 2.0))
		var xf := Transform3D(Basis(Vector3.UP, rot + lean).scaled_local(s),
			Vector3(org.x + off.x, top + s.y * 0.5, org.z + off.y))
		_push(by_group, _key(org), &"perch", xf,
			Color(tint.r, fmod(tint.g + rng.randf() * 0.61, 1.0), 1.0, 1.0))
		extras += 1


## Perched containers, in COLUMNS: one or two footprints on the stack's top face, each carrying one to
## three boxes that actually sit on each other. Scattering them independently is what put boxes in
## mid-air in the first pass.
func _perch(by_group: Dictionary, org: Vector3, skin: Vector3, yaw: float, tint: Color,
		rng: RandomNumberGenerator) -> void:
	if rng.randf() > EXTRA_CHANCE:
		return
	var top := org.y + skin.y * 0.5
	var rot0 := -deg_to_rad(yaw)
	for _c in range(rng.randi_range(1, 2)):
		var turned := rng.randf() < 0.30
		var s := Vector3(BOX_W, BOX_H, BOX_L) if turned else Vector3(BOX_L, BOX_H, BOX_W)
		var rot := rot0 + deg_to_rad(rng.randf_range(-13.0, 13.0)) + (PI * 0.5 if turned else 0.0)
		var off := Vector2(rng.randf_range(-0.32, 0.32) * skin.x,
			rng.randf_range(-0.32, 0.32) * skin.z).rotated(rot0)
		var n := rng.randi_range(1, EXTRA_MAX)
		for i in range(n):
			var lean := deg_to_rad(rng.randf_range(-2.5, 2.5))   # a stack is never perfectly plumb
			var xf := Transform3D(Basis(Vector3.UP, rot + lean).scaled_local(s),
				Vector3(org.x + off.x + i * 0.12, top + s.y * (0.5 + float(i)), org.z + off.y))
			_push(by_group, _key(org), &"perch", xf,
				Color(tint.r, fmod(tint.g + rng.randf() * 0.61, 1.0), 0.0, 1.0))
			extras += 1


## The hard cover's top: a chamfered coping ring and a run of planter troughs with foliage, which is
## what makes a 24 m concrete mass read as a garden terrace rather than a beige box.
func _plant(by_group: Dictionary, org: Vector3, skin: Vector3, yaw: float,
		rng: RandomNumberGenerator) -> void:
	var top := org.y + skin.y * 0.5
	var rot := -deg_to_rad(yaw)
	var n := clampi(int(maxf(skin.x, skin.z) / 7.0), 1, 6)
	for i in range(n):
		var t := (float(i) + 0.5) / float(n) - 0.5
		var along := Vector2(t * skin.x * 0.86, rng.randf_range(-0.3, 0.3) * skin.z).rotated(rot)
		var w := rng.randf_range(3.0, 5.5)
		var trough := Transform3D(Basis(Vector3.UP, rot).scaled_local(Vector3(w, 1.0, 2.2)),
			Vector3(org.x + along.x, top + 0.5, org.z + along.y))
		_push(by_group, _key(org), &"trough", trough, Color.WHITE)
		var bush := Transform3D(Basis(Vector3.UP, rot + rng.randf_range(-0.4, 0.4))
			.scaled_local(Vector3(w * 0.9, rng.randf_range(1.4, 2.8), 1.9)),
			Vector3(org.x + along.x, top + 1.4, org.z + along.y))
		_push(by_group, _key(org), &"foliage", bush, Color(rng.randf(), 0.0, 0.0, 1.0))
	# A lip just under the coping: the chamfer that stops the top edge reading as a cut.
	_push(by_group, _key(org), &"coping",
		Transform3D(Basis(Vector3.UP, rot).scaled_local(Vector3(skin.x + 0.9, 0.55, skin.z + 0.9)),
			Vector3(org.x, top - 0.1, org.z)), Color.WHITE)


func _push(by_group: Dictionary, key: StringName, kind: StringName, xf: Transform3D,
		tint: Color) -> void:
	if not by_group.has(key):
		by_group[key] = {}
	var group := by_group[key] as Dictionary
	if not group.has(kind):
		group[kind] = [] as Array[Array]
	(group[kind] as Array).append([xf, tint] as Array)
	if not placed.has(kind):
		placed[kind] = [] as Array[Transform3D]
	(placed[kind] as Array).append(xf)


static func _key(pos: Vector3) -> StringName:
	var gx := int(floor(pos.x / (200.0 * float(GROUP_TILES))))
	var gz := int(floor(pos.z / (200.0 * float(GROUP_TILES))))
	return StringName("%d,%d" % [gx, gz])


func _emit(parent: Node3D, kind: StringName, rows: Array) -> void:
	McMeshKit.multi(parent, kind, _mesh_for(kind), rows, _material_for(kind), VISIBILITY_M,
		kind == &"skin" or kind == &"wall")


## The skins and the perched containers are all unit cubes scaled per instance — `mc_cargo` reads each
## instance's own size out of MODEL_MATRIX, so one mesh serves every footprint. The rest are prototypes.
func _mesh_for(kind: StringName) -> Mesh:
	if kind == &"skin" or kind == &"wall" or kind == &"perch":
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE
		return cube
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		&"trough":
			McMeshKit.box(st, Vector3.ZERO, Vector3(1.0, 1.0, 1.0))
		&"foliage":
			# A lumpy cluster, not a box: `mc_foliage` can break the VALUE of a mass but not its
			# silhouette, and a green slab on a coping reads worse than no planting at all.
			McMeshKit.box(st, Vector3(0.0, -0.22, 0.0), Vector3(0.94, 0.36, 0.90))
			McMeshKit.box(st, Vector3(-0.20, 0.04, 0.10), Vector3(0.62, 0.46, 0.58))
			McMeshKit.box(st, Vector3(0.24, 0.10, -0.14), Vector3(0.55, 0.52, 0.50))
			McMeshKit.box(st, Vector3(0.02, 0.24, 0.18), Vector3(0.48, 0.40, 0.44))
			McMeshKit.box(st, Vector3(-0.12, 0.30, -0.16), Vector3(0.36, 0.34, 0.34))
			McMeshKit.box(st, Vector3(0.30, -0.06, 0.26), Vector3(0.30, 0.28, 0.28))
		&"coping":
			McMeshKit.box(st, Vector3.ZERO, Vector3(1.0, 1.0, 1.0))
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
	return mesh


func _material_for(kind: StringName) -> Material:
	match kind:
		&"skin":
			return _cargo_material(true)
		&"perch":
			return _cargo_material(false)
		&"wall":
			# Lead r7: a 24 m board-formed wall is the largest flat value in an arena, so it carries the
			# shutter boards (0.62 m), the form-tie cone holes on a 0.92 m grid and a recessed reveal
			# every 4.8 m — the marks a real pour leaves, not more props. The generic panel joint is off
			# here: with the reveal dividing the pour, a second 2.4 m grid made it read as tiling.
			return McMaterials.surface_variant(&"mc_concrete",
				{"panel_m": 0.0, "grime": 0.50, "facade": 0.0, "tile_m": 3.2,
				"board_m": 0.62, "form_tie_m": 0.92, "reveal_m": 4.8, "reveal_depth": 0.65,
				"grime_height": 3.0})
		&"trough", &"coping":
			return McMaterials.surface_variant(&"mc_stone",
				{"panel_m": 1.2, "grime": 0.30, "facade": 0.0})
		&"foliage":
			return McMaterials.foliage()
	return McMaterials.get_material(&"mc_concrete")


## One material per role, registered so the haze and wetness pushes reach it like every other city
## surface. A perched container is a single box: less rust and a tighter rib pitch read correctly at
## that size, and a full-size pitch would draw one cell across its whole side.
func _cargo_material(big: bool) -> ShaderMaterial:
	if big and _mat_cargo != null:
		return _mat_cargo
	if not big and _mat_perch != null:
		return _mat_perch
	var mat := ShaderMaterial.new()
	mat.shader = load(CARGO_SHADER) as Shader
	mat.set_shader_parameter(&"rib_pitch", 0.30 if big else 0.24)
	mat.set_shader_parameter(&"rust_amount", 0.50 if big else 0.28)
	McMaterials.register(mat)
	if big:
		_mat_cargo = mat
	else:
		_mat_perch = mat
	return mat
