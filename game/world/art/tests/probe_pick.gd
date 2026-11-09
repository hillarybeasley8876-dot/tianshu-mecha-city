extends Node
## Diagnostic: what is the bright thing at this pixel? (city-art r14)
##
## The value probe found a 14-degree white blob in the T1fac street frame that is NOT the sun — the sun
## is 90 degrees off that camera's bearing — and is NOT sky, because it is absent from the bare-sky B
## frame. This raycasts the camera's own rays through a list of pixels and prints what they hit.
##
##   tools/godot.sh test res://world/art/tests/probe_pick.gd -- \
##     --pick-cam=T1fac --pick-px=0.56,0.13 --pick-px=0.50,0.20

const CITY_SCENE := "res://world/city.tscn"
const CAMS := "res://world/art/tests/cams_value.json"

var _city: Node3D


func _ready() -> void:
	_city = (load(CITY_SCENE) as PackedScene).instantiate() as Node3D
	add_child(_city)
	for i in 6:
		await get_tree().physics_frame
	var spec := Game.flag("pick-cam", "T1fac")
	var cam_spec := _camera(spec)
	if cam_spec.is_empty():
		push_error("probe_pick: no camera named '%s' in %s" % [spec, CAMS])
		get_tree().quit(1)
		return
	var cam := Camera3D.new()
	cam.near = 0.05
	cam.far = 6000.0
	cam.fov = float(cam_spec.get("fov", 60.0))
	add_child(cam)
	var pos: Array = cam_spec["pos"]
	var look: Array = cam_spec["look"]
	cam.position = Vector3(pos[0], pos[1], pos[2])
	cam.look_at(Vector3(look[0], look[1], look[2]), Vector3.UP)
	cam.current = true
	await get_tree().process_frame
	var names := Game.flag("pick-names", "")
	if not names.is_empty():
		_list(names)
		get_tree().quit(0)
		return
	var near := Game.flag("pick-near", "")
	if not near.is_empty():
		_near(near)
		get_tree().quit(0)
		return
	var state := get_viewport().world_3d.direct_space_state
	for entry in Game.flag("pick-px", "0.5,0.5").split(";", false):
		var uv := entry.split(",")
		var ndc := Vector2(float(uv[0]), float(uv[1]))
		var from := cam.project_ray_origin(ndc)
		var to := from + cam.project_ray_normal(ndc) * 6000.0
		var hit := state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD))
		var what := "sky / no collider"
		if not hit.is_empty():
			var node := hit.get("collider") as Node
			what = "%s (%s) at %s" % [node.name, node.get_path(), hit.get("position")]
		print("PICK %s uv=%s -> %s" % [spec, ndc, what])
	get_tree().quit(0)


## r16b §4: every visual instance whose AABB centre is within `r` of a point — `--pick-near=x,y,z:r`.
## The bright panel that clips 8 % of the A3st frame has NO collider, so a ray cannot name it; this
## lists what is standing where it is instead.
func _near(spec: String) -> void:
	var parts := spec.split(":")
	var p := parts[0].split(",")
	var at := Vector3(float(p[0]), float(p[1]), float(p[2]))
	var r := float(parts[1]) if parts.size() > 1 else 30.0
	var stack: Array[Node] = [_city]
	var hits := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is VisualInstance3D:
			var box := (n as VisualInstance3D).get_aabb()
			var centre: Vector3 = (n as Node3D).global_transform * box.get_center()
			if centre.distance_to(at) <= r:
				hits += 1
				print("NEAR %s type=%s centre=%s size=%s" % [n.name, n.get_class(), centre, box.size])
		stack.append_array(n.get_children())
	print("NEAR %d visuals within %.0f m of %s" % [hits, r, at])


## Every node whose name contains the fragment, with its material's role — the crown in V3/V7 has no
## collider, so a ray cannot name it and hiding by fragment needs the name first.
func _list(fragment: String) -> void:
	var stack: Array[Node] = [_city]
	var hits := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var near := n is Node3D and (n as Node3D).global_position.y > 180.0 \
			and Vector2((n as Node3D).global_position.x, (n as Node3D).global_position.z).length() < 260.0
		if fragment == "*" or String(n.name).contains(fragment):
			if fragment != "*" or near:
				hits += 1
				print("NAME %s type=%s pos=%s" % [n.name, n.get_class(),
					n.global_position if n is Node3D else Vector3.ZERO])
		if n is MeshInstance3D and (fragment == "*" or String(n.name).contains(fragment)):
			var mi := n as MeshInstance3D
			for i in mi.mesh.get_surface_count() if mi.mesh != null else 0:
				var sm := mi.mesh.surface_get_material(i)
				print("NAME   surface %d of %s = %s" % [i, mi.name,
					sm.resource_name if sm != null else "(null)"])
		stack.append_array(n.get_children())
	print("NAME %d nodes match '%s'" % [hits, fragment])


func _camera(name: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAMS))
	for c: Dictionary in (parsed as Array):
		if String(c["name"]) == name:
			return c
	return {}
