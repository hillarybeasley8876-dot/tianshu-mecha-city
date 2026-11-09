class_name FlowCheckpoint
extends RefCounted
## One respawn point (SPEC §7.1: the start, every destroyed spire, every boss phase). A checkpoint is
## pure data — GameFlow owns what restoring it means — so it can be built, compared and serialised in
## a test without a scene.

var id: StringName = &"start"
var at: Transform3D = Transform3D.IDENTITY
var flow_state: StringName = &"district"
var spires_down: Array[StringName] = []
## The arenas the player had already finished when this was written. A respawn restores the set, so a
## cleared yard or hive arena never fights again (r5 brief item 6).
var arenas_done: Array[StringName] = []
var elapsed: float = 0.0
var boss_phase: int = 0
var stats: Dictionary = {}


static func make(id_: StringName, at_: Transform3D, state: StringName, spires: Array[StringName],
		elapsed_: float = 0.0, phase: int = 0, stats_: Dictionary = {},
		arenas: Array[StringName] = []) -> FlowCheckpoint:
	var cp := FlowCheckpoint.new()
	cp.id = id_
	cp.at = at_
	cp.flow_state = state
	cp.spires_down = spires.duplicate()
	cp.arenas_done = arenas.duplicate()
	cp.elapsed = elapsed_
	cp.boss_phase = phase
	cp.stats = stats_.duplicate()
	return cp


func to_dict() -> Dictionary:
	return {"id": String(id), "pos": [at.origin.x, at.origin.y, at.origin.z],
			"yaw": rad_to_deg(at.basis.get_euler().y), "state": String(flow_state),
			"spires": spires_down.map(func(s: StringName) -> String: return String(s)),
			"arenas": arenas_done.map(func(s: StringName) -> String: return String(s)),
			"elapsed": elapsed, "phase": boss_phase}


static func from_dict(d: Dictionary) -> FlowCheckpoint:
	var pos := d.get("pos", [0.0, 0.0, 0.0]) as Array
	return make(StringName(d.get("id", "start")),
			Transform3D(Basis(Vector3.UP, deg_to_rad(float(d.get("yaw", 0.0)))),
					Vector3(float(pos[0]), float(pos[1]), float(pos[2]))),
			StringName(d.get("state", "district")), _names(d.get("spires", [])),
			float(d.get("elapsed", 0.0)), int(d.get("phase", 0)), {},
			_names(d.get("arenas", [])))


static func _names(raw: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	for s: String in raw as Array:
		out.append(StringName(s))
	return out
