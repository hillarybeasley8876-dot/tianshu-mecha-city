class_name TrailerCamRig
extends Camera3D
## The trailer camera kit (trailer unit, lead brief trailer-r2 §2): five script-driven rigs that take
## the view from the game camera for the length of a shot and hand it back afterwards.
##
##   orbit  circles the hero — radius, height, rate (deg/s), start bearing
##   crane  rises or descends at a fixed bearing, looking at the hero
##   chase  a lagged follow at a fixed offset in the hero's own frame (behind or beside)
##   low    at deck level looking up at the mech
##   wide   locked off: a fixed camera that frames the hero and the enemies together
##
## Every rig looks at the hero through a framing offset (so the mech can sit off-centre) and holds a
## frame-height floor: when the mech would read smaller than `min_bbox` of the frame the camera closes
## the distance until it does. Every frame it logs what the viewer can actually see —
## TrailerFraming's bbox / blocked / foes — and fails the take when the mech is hidden, too small, or
## the fight is off screen for longer than the brief allows.
##
## Spec is JSON (see game/trailer/rig_*.json):
##   {"rig":"orbit", "from":0.0, "to":6.0, "kind":"combat", "subject":"hero",
##    "radius":46, "height":12, "rate":14, "start":225, "look":[0,0,0], "frame":[0,0],
##    "fov":50, "min_bbox":0.3, "height_m":16}
##
## `subject` is what the rig frames AND what the framing metrics measure: "hero" (the default) or the
## name of a node in the scene, which is how the boss take frames the Brood Titan instead of the mech.
## `height_m` is the subject's world height, used for the bbox and the chest ray (16 m for the hero).

const PASS_BLOCKED := 0.2   ## s the subject may stay hidden behind scenery
const PASS_LOW := 0.3       ## s the subject may read under MIN_BBOX in a hero shot
const PASS_NOFOE := 0.5     ## s a combat shot may show no enemy
const MIN_BBOX := 0.25
const MIN_DIST := 22.0      ## m — the floor never walks the camera into the subject
const CLOSE_RATE := 6.0     ## 1/s — how fast the frame-height floor corrects
## Bearings the blocked-repair tries, in order, as an offset from the rig's own (0 = keep it).
const REPAIR_SWEEP: Array[float] = [0.0, 18.0, -18.0, 36.0, -36.0, 54.0, -54.0, 72.0, -72.0,
		90.0, -90.0, 115.0, -115.0, 140.0, -140.0, 180.0]
const REPAIR_RATE := 3.0    ## 1/s — how fast the lens swings to a clear bearing (the default)
## A rig can raise it with `"repair_rate"`. The Brood Titan CHARGES: its lens has to clear a Crown fin
## that crosses the frame in under a second, and at 3/s the swing arrives after the fin already has.
var _repair_rate: float = REPAIR_RATE

var spec: Dictionary = {}
var kind: StringName = &"hero"
var id: String = "rig"

var _from: float = 0.0
var _to: float = 1.0e9
var _t: float = 0.0
var _live: bool = false
var _game_cam: Camera3D = null
var _look_off: Vector3 = Vector3.ZERO
var _frame_off: Vector2 = Vector2.ZERO
var _min_bbox: float = MIN_BBOX
var _subject_name: String = "hero"
var _subject: Node3D = null
var _height: float = 16.0
var _warned: bool = false
var _last_pos: Vector3 = Vector3.ZERO
var _have_last: bool = false
var _close: float = 1.0
var _repair: float = 0.0            ## deg the lens is swung off its rig bearing to clear scenery
var _repair_want: float = 0.0
var _chase_pos: Vector3 = Vector3.ZERO
var _chase_look: Vector3 = Vector3.ZERO
var _chase_init: bool = false

var _log: FileAccess = null
var _frames: int = 0
var _blocked_run: float = 0.0
var _low_run: float = 0.0
var _nofoe_run: float = 0.0
var _blocked_max: float = 0.0
var _low_max: float = 0.0
var _nofoe_max: float = 0.0
var _bbox_min: float = 1.0
var _foes_min: int = 99
var _reported: bool = false


func setup(s: Dictionary, log_path: String = "") -> void:
	spec = s
	id = String(s.get("id", s.get("rig", "rig")))
	kind = StringName(s.get("kind", "hero"))
	_from = float(s.get("from", 0.0))
	_to = float(s.get("to", 1.0e9))
	_look_off = _vec(s.get("look", [0.0, 0.0, 0.0]))
	_frame_off = Vector2(float((s.get("frame", [0.0, 0.0]) as Array)[0]),
			float((s.get("frame", [0.0, 0.0]) as Array)[1]))
	_min_bbox = float(s.get("min_bbox", MIN_BBOX))
	_repair_rate = float(s.get("repair_rate", REPAIR_RATE))
	_subject_name = String(s.get("subject", "hero"))
	_height = float(s.get("height_m", 16.0))
	fov = float(s.get("fov", 50.0))
	near = 0.5
	far = 6000.0
	if log_path != "":
		_log = FileAccess.open(log_path, FileAccess.WRITE)
		if _log == null:
			push_error("TrailerCamRig: cannot write %s" % log_path)
		else:
			_log.store_line("# rig=%s kind=%s subject=%s min_bbox=%.2f"
					% [id, kind, _subject_name, _min_bbox])
			_log.store_line("t,bbox,blocked,foes,x,y,z")


## The game camera, found once: the rigs hand the view back to it when their window closes.
func _find_game_cam() -> Camera3D:
	if _game_cam != null and is_instance_valid(_game_cam):
		return _game_cam
	var rig := Game.camera_rig
	if rig == null:
		return null
	for n: Node in rig.find_children("*", "Camera3D", true, false):
		_game_cam = n as Camera3D
		break
	return _game_cam


func _process(delta: float) -> void:
	_t += delta
	var want := _t >= _from and _t < _to
	if want != _live:
		if want:
			make_current()
		else:
			_hand_back()
		_live = want
	if not _live:
		return
	_place(delta)
	_judge(delta)


func _hand_back() -> void:
	current = false
	var cam := _find_game_cam()
	if cam != null:
		cam.make_current()
	_report()


## Where this rig wants to be at time `_t`, before the frame-height floor has its say.
func _target() -> Array:
	var hero := _hero()
	var u := clampf((_t - _from) / maxf(_to - _from, 0.001), 0.0, 1.0)
	match String(spec.get("rig", "wide")):
		"orbit":
			var a := deg_to_rad(float(spec.get("start", 225.0)) + float(spec.get("rate", 0.0)) * (_t - _from))
			return [hero + Vector3(cos(a), 0.0, sin(a)) * float(spec.get("radius", 46.0))
					+ Vector3.UP * float(spec.get("height", 12.0)), hero]
		"crane":
			var b := deg_to_rad(float(spec.get("az", 225.0)))
			var h := lerpf(float(spec.get("from_h", 6.0)), float(spec.get("to_h", 40.0)), u)
			return [hero + Vector3(cos(b), 0.0, sin(b)) * float(spec.get("dist", 50.0)) + Vector3.UP * h, hero]
		"low":
			var c := deg_to_rad(float(spec.get("az", 225.0)))
			return [hero + Vector3(cos(c), 0.0, sin(c)) * float(spec.get("dist", 42.0))
					+ Vector3.UP * float(spec.get("height", -6.0)), hero + Vector3.UP * 4.0]
		"chase":
			var off := _vec(spec.get("offset", [0.0, 14.0, 46.0]))
			var basis := Basis()
			var s_node := _subj()
			if s_node != null:
				basis = s_node.global_transform.basis
			return [hero + basis * off, hero]
		_:
			return [_vec(spec.get("pos", [0.0, 0.0, 0.0])) if spec.has("pos")
					else hero + _vec(spec.get("pos_hero", [0.0, 20.0, -60.0])),
				_vec(spec.get("look_at", [0.0, 0.0, 0.0])) if spec.has("look_at") else hero]


## Place the camera: the rig's own position, the frame-height floor, then the look-at with its
## framing offset (frame.x = metres right, frame.y = metres up, so the mech sits off-centre).
func _place(delta: float) -> void:
	var t := _target()
	var pos: Vector3 = t[0]
	var look: Vector3 = t[1] + _look_off
	var lag := float(spec.get("lag", 0.0))
	if String(spec.get("rig", "wide")) == "chase" and lag > 0.0:
		if not _chase_init:
			_chase_pos = pos
			_chase_look = look
			_chase_init = true
		var k := 1.0 - exp(-delta / lag)
		_chase_pos = _chase_pos.lerp(pos, k)
		_chase_look = _chase_look.lerp(look, k)
		pos = _chase_pos
		look = _chase_look
	var b := TrailerFraming.bbox_fraction(self, _hero(), _height)
	var want := 1.0
	if b > 0.001 and b < _min_bbox:
		want = clampf(b / _min_bbox, 0.35, 1.0)
	_close = lerpf(_close, want, clampf(delta * CLOSE_RATE, 0.0, 1.0))
	if _close < 0.999:
		var d := pos.distance_to(look)
		pos = look + (pos - look).normalized() * maxf(d * _close, MIN_DIST)
	pos = _swing_clear(pos, look, delta)
	global_position = pos
	var dir := (look - pos).normalized()
	var right := dir.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.01:
		right = Vector3.RIGHT
	var up := right.cross(dir).normalized()
	var aim := look + right * _frame_off.x + up * _frame_off.y
	if aim.distance_squared_to(pos) > 0.01:
		look_at(aim, Vector3.UP)


## Blocked repair: a rig is placed from a measurement taken with the hero standing on its mark, and the
## hero then walks, dashes or flies — so the lens that was clear at the mark is regularly behind a
## parapet, a canopy or a truss a few seconds later. Rather than re-tune every rig, the lens swings
## around the subject (keeping its distance and height) until the chest ray is clear, and swings back
## when the rig's own bearing clears again. It is a camera operator stepping sideways, not a cut: the
## move is rate-limited and the bearing is smoothed.
##
## Measured need: on the showcase reel this is the difference between `blocked 2.9 s` and `blocked
## 0.0 s` on the same take (g4_flight, g5_dodge), and the r2b boss take was blocked for 28.4 s of 31.
func _swing_clear(pos: Vector3, look: Vector3, delta: float) -> Vector3:
	var subject := _subj()
	if subject == null:
		return pos
	var chest := subject.global_position + Vector3.UP * (_height * 0.35)
	if not _sight_blocked(pos, chest, subject):
		_repair_want = 0.0
	else:
		var arm := Vector3(pos.x - look.x, 0.0, pos.z - look.z)
		var radius := arm.length()
		if radius < 0.01:
			return pos
		var base := atan2(arm.z, arm.x)
		_repair_want = _repair
		for deg: float in REPAIR_SWEEP:
			var a := base + deg_to_rad(deg)
			var probe := Vector3(look.x + cos(a) * radius, pos.y, look.z + sin(a) * radius)
			if not _sight_blocked(probe, chest, subject):
				_repair_want = deg
				break
	_repair = lerpf(_repair, _repair_want, clampf(delta * _repair_rate, 0.0, 1.0))
	if absf(_repair) < 0.05:
		return pos
	var arm2 := Vector3(pos.x - look.x, 0.0, pos.z - look.z)
	var a2 := atan2(arm2.z, arm2.x) + deg_to_rad(_repair)
	return Vector3(look.x + cos(a2) * arm2.length(), pos.y, look.z + sin(a2) * arm2.length())


func _sight_blocked(from: Vector3, to: Vector3, subject: Node3D) -> bool:
	var hit := TrailerFraming.sight_hit_at(from, to, subject)
	return not hit.is_empty()


## One frame of evidence: what reads, what is hidden, and whether the shot has failed yet.
func _judge(delta: float) -> void:
	var s := TrailerFraming.sample(self, false, _subj(), _height)
	var blocked := bool(s["blocked"])
	var bbox := float(s["bbox"])
	var foes := int(s["foes"])
	_frames += 1
	_bbox_min = minf(_bbox_min, bbox)
	_foes_min = mini(_foes_min, foes)
	_blocked_run = _blocked_run + delta if blocked else 0.0
	_low_run = _low_run + delta if bbox < _min_bbox else 0.0
	_nofoe_run = _nofoe_run + delta if foes == 0 else 0.0
	_blocked_max = maxf(_blocked_max, _blocked_run)
	_low_max = maxf(_low_max, _low_run)
	_nofoe_max = maxf(_nofoe_max, _nofoe_run)
	if _log != null:
		_log.store_line("%.3f,%.3f,%d,%d,%.1f,%.1f,%.1f" % [_t, bbox, int(blocked), foes,
				global_position.x, global_position.y, global_position.z])
	if _frames % 60 == 1:
		print("RIG %s t=%.1f bbox=%.2f foes=%d/%d alive cam=(%.0f,%.0f,%.0f)" % [id, _t, bbox, foes,
				TrailerFraming.enemy_count(), global_position.x, global_position.y, global_position.z])


## The verdict for this take. Printed once, when the rig's window closes or the scene goes away.
func _report() -> void:
	if _reported or _frames == 0:
		return
	_reported = true
	var bad: Array[String] = []
	if _blocked_max > PASS_BLOCKED:
		bad.append("blocked %.2fs" % _blocked_max)
	if kind == &"hero" and _low_max > PASS_LOW:
		bad.append("small %.2fs" % _low_max)
	if kind == &"combat" and _nofoe_max > PASS_NOFOE:
		bad.append("no enemy %.2fs" % _nofoe_max)
	print("RIG %s frames=%d bbox_min=%.2f foes_min=%d blocked_max=%.2f low_max=%.2f nofoe_max=%.2f %s"
		% [id, _frames, _bbox_min, _foes_min, _blocked_max, _low_max, _nofoe_max,
		"PASS" if bad.is_empty() else "FAIL " + ", ".join(bad)])


func _exit_tree() -> void:
	_report()
	if _log != null:
		_log.close()
		_log = null


## The node this rig frames and measures. "hero" is Game.player; anything else is looked up by name in
## the scene (the boss take frames the Brood Titan), resolved lazily because it spawns after the rig.
func _subj() -> Node3D:
	if _subject_name == "hero":
		return Game.player
	if _subject != null and is_instance_valid(_subject):
		return _subject
	# The rig is a leaf: search from the scene root, not from here.
	var root := get_tree().current_scene
	if root == null:
		root = get_parent()
	if root != null:
		_subject = root.find_child(_subject_name, true, false) as Node3D
	if _subject == null and Game.world != null:
		_subject = Game.world.find_child(_subject_name, true, false) as Node3D
	if _subject == null and not _warned:
		_warned = true
		push_warning("TrailerCamRig %s: no node named '%s' to frame" % [id, _subject_name])
	return _subject


## The subject's world position, or the last one seen while it is still spawning: a rig must never
## snap to the origin because its subject does not exist yet.
func _hero() -> Vector3:
	var n := _subj()
	if n != null:
		_last_pos = n.global_position
		_have_last = true
	return _last_pos if _have_last else Vector3.ZERO


func _vec(v: Variant) -> Vector3:
	var a := v as Array
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
