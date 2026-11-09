extends Node
## Lead gate: does any dressing float above, or sink into, the surface that is meant to hold it?
##   tools/godot.sh run res://tools/float_audit.tscn 400
##
## Windowed on purpose: a MultiMesh keeps its instance transforms only on a real renderer, and almost
## all of the city's dressing is MultiMesh.
##
## The surface query is `ArtSurfaces` — the SAME class the load-time settle pass uses, so the gate
## cannot measure a world the game does not ship. Each dressing instance is dropped from 1 m over its
## TOP; the first support surface the ray meets is what holds it. `gap` = its lowest point minus that
## surface: positive floats, negative is buried.
##
## The gate is the FLOAT column: 0 instances floating more than 0.5 m in every resting category.
## Buried is reported and judged from close-ups (a pylon that meets a viaduct's underside is buried by
## design), so it does not fail the run.
##
## r10b added a THIRD section, STRUCTURE: city-kit's deck slabs, viaduct pylons, street skirts, market
## rows, railings, pipe racks and arena cover. Those are never settled — their transform comes from the
## same layout box as city-build's collider, so moving or dropping one would leave the collider behind.
## They are measured anyway and REPORTED by `kit_assign.json` row id, so an instance off its surface
## gets fixed in the rule that placed it (`tools/citykit/pieces.py`, `cover.py`) rather than patched at
## load. Cover is judged on its BOTTOM layer only: `cover.py` stacks copies bottom-up, so every layer
## above the first rests on the copy under it by construction.

const FLOAT_GATE := 0.5
const BURY_GATE := 0.5
## Kit tiers whose instances are rendered near the player and rest on something. `detail` is the
## architecture itself and `far`/`cover_far` are the same models at a lower tier — neither is dressing.
const JUDGED_TIERS: Array[String] = ["lod", "cover_near"]
## What is NOT judged, and why. Every line has to be defensible on its own.
const WHITELIST: Array[String] = [
	"kit u01/u02 — the deck and viaduct fasciae hang off a slab's outer face; nothing is under them",
	"kit detail tier — the buildings themselves; they stand on their own footprint",
	"kit far / cover_far — the same models at a lower tier, already judged in their near batch",
	"kit STRUCTURE (s01-s07, f03, cover k01-k12) — reported in the STRUCTURE section, never moved",
	"greeble mast_lamp — the aviation lamp hangs on its mast, 9.3 m up the pole, not on the roof",
	"signs, cables, cloth, scaffolds, holograms, plumes — suspended by design, not resting",
]

var _surfaces: ArtSurfaces = null
var _rows: Dictionary = {}           ## category -> Array[Dictionary]
var _structure: Array[Dictionary] = []  ## one row per judged structure instance
var _kit_rows: KitRows = null
var _decks: Dictionary = {}          ## deck id -> z / thickness / span / muted (see `KitRows`)
var _list := 30


func _ready() -> void:
	# Env, not a command-line flag: `tools/godot.sh run` has no pass-through for extra arguments, and
	# the wrapper is the lead's file. `FLOAT_LIST=40 tools/godot.sh run ...`
	_list = int(OS.get_environment("FLOAT_LIST")) if _list == 30 and \
			not OS.get_environment("FLOAT_LIST").is_empty() else _list
	var city := (load("res://world/city.tscn") as PackedScene).instantiate()
	add_child(city)
	for i in 4:
		await get_tree().process_frame
	_surfaces = ArtSurfaces.new()
	var kit := city.get_node_or_null(^"KitPlacer")
	var n := _surfaces.build(city, kit)
	print("FLOAT supports: %d surfaces in the physics world (%d ms)" % [n, _surfaces.built_ms])
	_kit_rows = KitRows.load_file()
	_decks = KitRows.load_decks()
	print("FLOAT kit rows: %d placed instances mapped back to kit_assign.json, %d decks read"
			% [_kit_rows.rows, _decks.size()])
	_audit(city)
	var bad := _report()
	_structure_report()
	get_tree().quit(1 if bad > 0 else 0)


# ------------------------------------------------------------------ dressing
func _audit(city: Node) -> void:
	var stack: Array[Node] = [city]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mmi := n as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null or mmi.multimesh.mesh == null \
				or not mmi.is_visible_in_tree():
			continue
		if _structure_audit(mmi):
			continue
		var category := _category(mmi)
		if category.is_empty():
			continue
		var bb := mmi.multimesh.mesh.get_aabb()
		var c := bb.get_center()
		# the centre and four points 40 % of the way to the corners: a thing half on a ledge is
		# held by the ledge, and a railing on a slab edge is held by the slab
		var feet := CitySettle._feet(bb)
		for i in mmi.multimesh.instance_count:
			var xf := mmi.global_transform * mmi.multimesh.get_instance_transform(i)
			var bottom := xf * feet[0]
			var top_y := (xf * Vector3(c.x, bb.end.y, c.z)).y
			var surface := NAN
			for foot in feet:
				var at := xf * foot
				var hit := _surfaces.top_below(Vector3(at.x, maxf(top_y, at.y) + 1.0, at.z))
				if not hit.is_empty() and (is_nan(surface) or float(hit["y"]) > surface):
					surface = float(hit["y"])
			var row: Array = _rows.get(category, [])
			row.append({"gap": bottom.y - surface if not is_nan(surface) else NAN, "at": bottom,
					"what": String(mmi.name), "top": top_y})
			_rows[category] = row


## True when this MultiMesh is city-kit STRUCTURE, which is measured into the STRUCTURE section and
## never gated. Cover copies above the bottom layer are skipped: they rest on the copy under them.
func _structure_audit(mmi: MultiMeshInstance3D) -> bool:
	var model := _kit_model(mmi)
	if model.is_empty() or CityArt.kit_role(model) not in ["structure", "cover"]:
		return false
	var bb := mmi.multimesh.mesh.get_aabb()
	var c := bb.get_center()
	var feet := CitySettle._feet(bb)
	for i in mmi.multimesh.instance_count:
		var xf := mmi.global_transform * mmi.multimesh.get_instance_transform(i)
		var row := _kit_rows.at(xf.origin)
		var layer := int(row.get("layer", 0))
		if String(row.get("kind", "")) == "cover" and layer > 0:
			continue
		var bottom := xf * feet[0]
		var top_y := (xf * Vector3(c.x, bb.end.y, c.z)).y
		var surface := NAN
		var under := "nothing"
		for foot in feet:
			var at := xf * foot
			var hit := _surfaces.top_below(Vector3(at.x, maxf(top_y, at.y) + 1.0, at.z))
			if not hit.is_empty() and (is_nan(surface) or float(hit["y"]) > surface):
				surface = float(hit["y"])
				under = "%s y %.1f" % [String(hit["kind"]), float(hit["y"])]
		var id := String(row.get("id", "?"))
		var deck: Dictionary = _decks.get(id, {})
		# The surface a structure row stands on is the LAYOUT's, not the renderer's, whenever the
		# layout declares one: a railing row is what makes city-build mute that deck's parapet render,
		# so there is no face at the polygon edge to measure against, and a skybridge or a canopy has
		# nothing under it by design. Everything else — cover, pylons, street skirts, market rows — is
		# judged against what is actually drawn, which is the whole point of the section.
		var judged := bottom.y - surface if not is_nan(surface) else NAN
		if not deck.is_empty() and not is_nan(float(deck["z"])):
			judged = bottom.y - float(deck["z"])
			under = "deck %s z %.1f (render: %s)" % [id, float(deck["z"]), under]
		_structure.append({"id": id, "kind": String(row.get("kind", "?")),
				"model": model, "gap": judged, "at": bottom, "under": under,
				"render": bottom.y - surface if not is_nan(surface) else NAN,
				"span": bool(deck.get("span", false)), "named": not row.is_empty()})
	return true


## The kit model of a KitPlacer MultiMesh, or "" when this is not one (or not a near tier).
func _kit_model(mmi: MultiMeshInstance3D) -> String:
	var parent := mmi.get_parent()
	if parent == null or String(parent.name) != "KitPlacer":
		return ""
	var parts := String(mmi.name).split("_")     # kit_<model>_<tier...>_<x>_<z>
	if parts.size() < 3:
		return ""
	# `kit_k01_cover_near_2_1` and `kit_s01_lod_1_-1`: the cover tier is two words.
	var near := parts[2] in JUDGED_TIERS \
			or (parts[2] == "cover" and parts.size() > 3 and parts[3] == "near")
	return String(parts[1]) if near else ""


## "kit:<model>", "prop:<name>", "greeble:<kind>" -- or "" for dressing that is not meant to rest on
## anything. Kit STRUCTURE is claimed by `_structure_audit` before this is ever called.
func _category(mmi: MultiMeshInstance3D) -> String:
	var parent := mmi.get_parent()
	var pname := String(parent.name) if parent != null else ""
	if pname == "KitPlacer":
		var model := _kit_model(mmi)
		return "kit:" + model if not model.is_empty() \
				and CityArt.kit_role(model) == "dressing" else ""
	if pname == "Dressing":
		var prop := String(mmi.name).get_slice("_", 0)
		return "" if prop in ["holo", "passage"] else "prop:" + prop
	if pname.begins_with("Greebles_"):
		# The aviation lamp rides 9.3 m up its mast — it hangs, it does not rest.
		return "" if String(mmi.name) == "mast_lamp" else "greeble:" + String(mmi.name)
	if pname == "Cargo":
		return "cargo"
	return ""


func _report() -> int:
	var floating_total := 0
	var worst_list: Array[Dictionary] = []
	var bury_list: Array[Dictionary] = []
	var air_list: Array[Dictionary] = []
	var names := _rows.keys()
	names.sort()
	print("FLOAT %-24s %6s %8s %8s %8s %8s %9s %8s" % ["category", "n", "float>.5", "float>3", "worst",
			"bury>.5", "worst", "no floor"])
	for category: String in names:
		var rows: Array = _rows[category]
		var floating := 0
		var high := 0
		var buried := 0
		var none := 0
		var worst_f := 0.0
		var worst_b := 0.0
		for r: Dictionary in rows:
			var gap := float(r["gap"])
			if is_nan(gap):
				none += 1
				air_list.append({"cat": category, "at": r["at"], "what": r["what"],
						"top": r["top"]})
				continue
			if gap > FLOAT_GATE:
				floating += 1
				worst_list.append({"gap": gap, "cat": category, "at": r["at"], "what": r["what"],
						"top": r["top"]})
			if gap > 3.0:
				high += 1
			if gap < -BURY_GATE:
				buried += 1
				bury_list.append({"gap": gap, "cat": category, "at": r["at"], "what": r["what"]})
			worst_f = maxf(worst_f, gap)
			worst_b = minf(worst_b, gap)
		floating_total += floating
		print("FLOAT %-24s %6d %8d %8d %7.1fm %8d %8.1fm %8d" % [category, rows.size(), floating, high,
				worst_f, buried, worst_b, none])
	worst_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["gap"]) > float(b["gap"]))
	for i in mini(_list, worst_list.size()):
		var w: Dictionary = worst_list[i]
		print("FLOATS %6.1f m  %-22s %-34s at %s" % [float(w["gap"]), w["cat"], w["what"], w["at"]])
	# Buried is reported, not gated: a pylon that meets a viaduct's underside is buried by design.
	# These are the worst ten, so they can be judged from a close-up instead of argued about.
	bury_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["gap"]) < float(b["gap"]))
	for i in mini(10, bury_list.size()):
		var b: Dictionary = bury_list[i]
		print("BURY  %6.1f m  %-22s %-34s at %s" % [float(b["gap"]), b["cat"], b["what"], b["at"]])
	# "no floor" is not a pass and not a fail on its own: it means the drop found NOTHING under the
	# item within DROP metres, which is either a real hole in the support set or an item standing
	# over one. The positions are printed so it can be judged rather than argued about.
	for i in mini(12, air_list.size()):
		var a: Dictionary = air_list[i]
		print("AIR    no support under %-22s %-30s base %s top %.1f"
				% [a["cat"], a["what"], a["at"], float(a["top"])])
	print("FLOAT whitelist (%d entries):" % WHITELIST.size())
	for line in WHITELIST:
		print("FLOAT   not judged: %s" % line)
	print("FLOAT %d instances floating more than %.1f m" % [floating_total, FLOAT_GATE])
	return floating_total


# ------------------------------------------------------------------ structure (reported, not gated)
## Every structure instance more than 0.5 m off the surface under it, named by its `kit_assign.json`
## row. This is the list the lead asked for: the fix belongs in the rule that placed the row, and a
## cover box's z belongs to city-layout because the collider has to move with the visual.
##
## A row the layout declares a SPAN (skybridge, canopy) is reported on its own line instead: nothing is
## under it by design, so what matters is that the row lands on something at its ends. A span with no
## supported instance at all is an offender like any other.
func _structure_report() -> void:
	var by_kind: Dictionary = {}
	var by_row: Dictionary = {}
	var unnamed := 0
	for r: Dictionary in _structure:
		if not bool(r["named"]):
			unnamed += 1
		var kind := String(r["kind"])
		var row: Dictionary = by_kind.get(kind, {"n": 0, "off": 0, "worst": 0.0, "none": 0})
		row["n"] = int(row["n"]) + 1
		var gap := float(r["gap"])
		if is_nan(gap):
			row["none"] = int(row["none"]) + 1
		else:
			row["worst"] = maxf(float(row["worst"]), gap)
			if gap > FLOAT_GATE:
				row["off"] = int(row["off"]) + 1
		by_kind[kind] = row
		var id := String(r["id"])
		var rows: Array = by_row.get(id, [])
		rows.append(r)
		by_row[id] = rows
	print("STRUCTURE %-16s %6s %8s %8s %9s" % ["kind", "judged", "off>.5", "no floor", "worst"])
	var kinds := by_kind.keys()
	kinds.sort()
	for kind: String in kinds:
		var row: Dictionary = by_kind[kind]
		print("STRUCTURE %-16s %6d %8d %8d %8.1fm" % [kind, int(row["n"]), int(row["off"]),
				int(row["none"]), float(row["worst"])])
	var off: Array[Dictionary] = []
	var ids := by_row.keys()
	ids.sort()
	for id: String in ids:
		var rows: Array = by_row[id]
		var supported := 0
		var worst: Dictionary = rows[0]
		for r: Dictionary in rows:
			if not is_nan(float(r["gap"])) and absf(float(r["gap"])) <= FLOAT_GATE:
				supported += 1
			if float(r["gap"]) > float(worst["gap"]):
				worst = r
		if bool(worst["span"]):
			print("SPAN    %-22s %-5s %3d instances, %d on a surface  worst %+.1f m  under: %s"
					% [id, worst["model"], rows.size(), supported, float(worst["gap"]),
					   worst["under"]])
			if supported > 0:
				continue          ## a declared span held at its ends: nothing to fix
		for r: Dictionary in rows:
			if float(r["gap"]) > FLOAT_GATE:
				off.append(r)
	off.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["gap"]) > float(b["gap"]))
	for r: Dictionary in off:
		print("STRUCT %+7.1f m  %-10s %-22s %-5s at %s  under: %s"
				% [float(r["gap"]), r["kind"], r["id"], r["model"], r["at"], r["under"]])
	# Nothing at all under it within 160 m is not the same as a gap: it is a hole in the support set.
	var air := 0
	for r: Dictionary in _structure:
		if is_nan(float(r["gap"])):
			air += 1
			if air <= 12:
				print("STRUCT   no floor  %-10s %-22s %-5s at %s"
						% [r["kind"], r["id"], r["model"], r["at"]])
	print("STRUCTURE %d of %d judged instances off their surface by more than %.1f m "
			% [off.size(), _structure.size(), FLOAT_GATE]
			+ "(reported, not gated); %d with no floor at all; %d could not be named from "
			% [air, unnamed] + "kit_assign.json")
