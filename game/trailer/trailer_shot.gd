extends Node3D
## Trailer shot scene (trailer unit). Wraps `res://main.tscn` so a movie run can do the three things
## the recorder cannot: render at 1920x1080, take the HUD (and the tutorial key prompts) off, and fly
## a cinematic camera that the game itself has no reason to own.
##
##   tools/godot.sh movie --movie=<abs.avi> --scene=res://trailer/shot.tscn \
##       --timeline=res://trailer/tl_<shot>.json --trailer-cam=res://trailer/cam_<shot>.json [game flags]
##
## Flags (all optional):
##   --trailer-cam=res://…   keyframed cinematic camera (JSON, see _load_cam); implies HUD off
##   --trailer-rig=res://…   camera-kit rig (JSON, see cam_rig.gd); a second --trailer-rig2= adds one
##   --trailer-log=<abs.csv> per-frame framing log from the rigs (the shot's evidence)
##   --trailer-pack=<r>,<type>:<n>,…  spawn the fight pack on a ring of r metres at world-ready, so the
##                           enemies are in the frame instead of 150–250 m away where --enemies puts
##                           them (the spawner snaps each one onto its navmesh)
##   --trailer-hud=0|1       force the combat HUD on/off (default: off for a cam shot, on otherwise)
##   --trailer-prompts=0|1   tutorial key prompts (default off: they read as a prototype)
##   --trailer-assist=res://… scripted reactions a timeline cannot time (see assist.gd)

const MAIN := "res://main.tscn"

var cam: Camera3D = null
var rigs: Array[TrailerCamRig] = []
var assist: TrailerAssist = null
var _keys: Array[Dictionary] = []
var _cam_len: float = 0.0
var _t: float = 0.0


func _ready() -> void:
	add_child((load(MAIN) as PackedScene).instantiate())
	_load_cam()
	_load_rigs()
	_load_assist()
	_apply_hud()


## `--trailer-assist=res://…` — the scripted reactions (perfect parry, execution, gatling vent) that a
## timeline cannot time — and `--trailer-mark=x,y,z[,radius]` — the arena wall that keeps a mech under
## a pack of 14 m mantises from being batted 100 m across the district mid-take. Either flag creates
## the assist; both can be used together. Armed only once the world is up, so no rule fires against a
## half-built scene.
func _load_assist() -> void:
	var path := Game.flag("trailer-assist", "")
	var mark := Game.flag("trailer-mark", "")
	if path == "" and mark == "":
		return
	assist = TrailerAssist.new()
	assist.name = "TrailerAssist"
	add_child(assist)
	if path != "":
		var data: Variant = JSON.parse_string(_spec_text(path))
		if not data is Dictionary:
			push_error("TrailerShot: %s is not an assist JSON object" % path)
			return
		assist.setup(data as Dictionary)
	if mark != "":
		var parts := mark.split(",", false)
		if parts.size() < 3:
			push_error("TrailerShot: --trailer-mark wants x,y,z[,radius[,drop]]")
			return
		assist.add_rule({"on": "mark", "pos": [parts[0], parts[1], parts[2]],
				"radius": parts[3] if parts.size() > 3 else 26.0,
				"drop": parts[4] if parts.size() > 4 else 22.0})


func _load_cam() -> void:
	var path := Game.flag("trailer-cam", "")
	if path == "":
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_error("TrailerShot: %s is not a camera JSON object" % path)
		return
	var d := data as Dictionary
	for k: Variant in (d.get("keys", []) as Array):
		_keys.append(_parse_key(k as Dictionary))
	if _keys.is_empty():
		push_error("TrailerShot: %s has no keys" % path)
		return
	_cam_len = float(_keys[-1]["t"])
	cam = Camera3D.new()
	cam.name = "TrailerCam"
	cam.near = 0.5
	cam.far = 6000.0
	add_child(cam)
	cam.make_current()
	_apply_key(0.0)


## A spec argument is either a `res://…json` path or the JSON itself. The showcase reel carries its
## twenty-one camera rigs inline in `showcase.json`, so a rig is one object in the shot list instead of
## a file nobody opens.
func _spec_text(v: String) -> String:
	if v.begins_with("{"):
		return v
	var text := FileAccess.get_file_as_string(v)
	if text == "":
		push_error("TrailerShot: cannot read %s" % v)
	return text


## Camera-kit rigs: one per --trailer-rig / --trailer-rig2 flag, each with its own time window, so a
## take can open on a rig, hand the view back to the game camera, and pick it up again later.
func _load_rigs() -> void:
	var log_base := Game.flag("trailer-log", "")
	for i in 2:
		var path := Game.flag("trailer-rig" if i == 0 else "trailer-rig2", "")
		if path == "":
			continue
		var data: Variant = JSON.parse_string(_spec_text(path))
		if not data is Dictionary:
			push_error("TrailerShot: %s is not a rig JSON object" % path)
			continue
		var rig := TrailerCamRig.new()
		rig.name = "TrailerRig%d" % i
		add_child(rig)
		var log_path := log_base
		if log_path != "" and i > 0:
			log_path = log_path.get_basename() + "_%d.csv" % i
		rig.setup(data as Dictionary, log_path)
		rigs.append(rig)


func _parse_key(k: Dictionary) -> Dictionary:
	return {
		"t": float(k.get("t", 0.0)),
		"pos": _vec(k["pos"]) if k.has("pos") else Vector3.INF,
		"pos_hero": _vec(k["pos_hero"]) if k.has("pos_hero") else Vector3.INF,
		"look": _vec(k["look"]) if k.has("look") else Vector3.INF,
		"look_hero": _vec(k["look_hero"]) if k.has("look_hero") else Vector3.INF,
		"fov": float(k.get("fov", 50.0)),
		"ease": float(k.get("ease", 1.0)),
	}


func _vec(v: Variant) -> Vector3:
	var a := v as Array
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


var _hud_want: bool = true
var _guard_t: float = 0.0
var _packed: bool = false


func _process(delta: float) -> void:
	_guard_t -= delta
	if _guard_t <= 0.0:
		_guard_t = 0.2
		_guard()
	if cam != null:
		_t += delta
		_apply_key(minf(_t, _cam_len))


## Keeps the HUD where the shot wants it and retires the tutorial key prompts. Both are re-asserted
## by the flow state machine (it calls `tutorial.begin()` when it enters the tutorial beat), so this
## is a poll rather than a one-shot. The pack is spawned here too, on the first poll after the world
## is built — the spawner only honours --enemies at that moment, and it puts them 150–250 m out.
func _guard() -> void:
	if Game.hud != null and Game.hud.visible != _hud_want:
		Game.hud.visible = _hud_want
	if not _packed and Game.world_built() and Game.player != null:
		_packed = true
		_pack()
		if assist != null:
			assist.arm()
	if Game.flag("trailer-prompts", "0") != "0":
		return
	var flow := find_child("GameFlow", true, false)
	var tut: Variant = flow.get(&"tutorial") if flow != null else null
	if tut is Node and bool((tut as Node).get(&"active")) and (tut as Node).has_method(&"finish"):
		(tut as Node).call(&"finish")


## `--trailer-pack=<radius>,<type>:<n>,<type>:<n>` — the fight pack on a ring around the hero, each
## monster snapped onto its own navmesh by the spawner's public spawn().
func _pack() -> void:
	var spec := Game.flag("trailer-pack", "")
	if spec == "":
		return
	var spawner := find_child("EnemySpawner", true, false)
	if spawner == null:
		push_error("TrailerShot: --trailer-pack needs the enemies unit (do not pass --stub=enemies)")
		return
	var parts := spec.split(",", false)
	var radius := float(parts[0])
	var types: Array[String] = []
	for entry: String in parts.slice(1):
		var t := entry.split(":")
		for i in (int(t[1]) if t.size() > 1 else 1):
			types.append(t[0])
	var centre := Game.player.global_position
	# `--trailer-pack-arc=<centre_deg>,<width_deg>` narrows the ring to a wedge. The lens sits at a
	# known bearing, so the pack is placed on the FAR side of the hero (centre = bearing + 180): a
	# 14 m mantis that closes from the camera's own side walks into the lens and fills the frame
	# (m1_ripper pass 4, t=8-11 s). The framing metric cannot catch it -- MASK_SIGHT excludes enemies
	# by design -- so this is a placement rule, not a measurement.
	var arc := Game.flag("trailer-pack-arc", "").split(",", false)
	var mid := deg_to_rad(float(arc[0])) if arc.size() > 0 else 0.0
	var width := deg_to_rad(float(arc[1])) if arc.size() > 1 else 0.0
	var made := 0
	for i in types.size():
		var a := TAU * float(i) / float(maxi(types.size(), 1))
		if arc.size() > 1:
			a = mid + (float(i) / float(maxi(types.size() - 1, 1)) - 0.5) * width
		var want := centre + Vector3(cos(a), 0.0, sin(a)) * radius
		var xf := Transform3D(Basis.looking_at((centre - want).normalized(), Vector3.UP), want)
		var e: Node3D = spawner.call(&"spawn", StringName(types[i]), xf)
		if e == null:
			push_error("TrailerShot: the spawner refused a '%s'" % types[i])
			continue
		made += 1
		if i == 0:
			print("PACK %s at (%.0f,%.0f,%.0f) d=%.0f" % [types[i], e.global_position.x,
					e.global_position.y, e.global_position.z, e.global_position.distance_to(centre)])
	print("PACK %d/%d spawned on a %.0f m %s around (%.0f,%.0f,%.0f)" % [made, types.size(), radius,
			"arc %.0f+/-%.0f deg" % [rad_to_deg(mid), rad_to_deg(width) * 0.5] if arc.size() > 1
			else "ring", centre.x, centre.y, centre.z])


## A key resolves to a world position and a world look-at point. `pos`/`look` are absolute;
## `pos_hero`/`look_hero` are offsets from the hero (PlayerMech's origin = capsule centre, ≈ 8 m above
## the feet), so a chase cam or a low angle that tracks a falling mech is one key. A key with neither
## inherits the previous key's resolved value. `ease` 0 = linear, 1 = smoothstep on the segment.
func _apply_key(t: float) -> void:
	var i := 0
	while i < _keys.size() - 1 and float(_keys[i + 1]["t"]) <= t:
		i += 1
	var a := _keys[i]
	var b: Dictionary = _keys[mini(i + 1, _keys.size() - 1)]
	var span := float(b["t"]) - float(a["t"])
	var u := 0.0 if span <= 0.0 else clampf((t - float(a["t"])) / span, 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u) if float(a["ease"]) > 0.5 else u
	var hero := Game.player.global_position if Game.player != null else Vector3.ZERO
	var pos := _resolve(a, "pos", "pos_hero", hero).lerp(_resolve(b, "pos", "pos_hero", hero), u)
	var look := _resolve(a, "look", "look_hero", hero).lerp(_resolve(b, "look", "look_hero", hero), u)
	cam.global_position = pos
	cam.fov = lerpf(float(a["fov"]), float(b["fov"]), u)
	if look.distance_squared_to(pos) > 0.01:
		cam.look_at(look, Vector3.UP)


func _resolve(key: Dictionary, abs_name: String, hero_name: String, hero: Vector3) -> Vector3:
	var v: Vector3 = key[abs_name]
	if v != Vector3.INF:
		return v
	var h: Vector3 = key[hero_name]
	return hero + h if h != Vector3.INF else Vector3.ZERO


func _apply_hud() -> void:
	_hud_want = Game.flag("trailer-hud", "0" if cam != null else "1") != "0"
	set_process(true)
