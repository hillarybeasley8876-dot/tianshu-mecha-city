extends Node
## hero-v3 gates for lead r4 items 1, 4 and 5 -- the clip player's three "let go" rules and the idle.
##   tools/godot.sh test res://player/model/hero3/tests/test_hero3_release.gd
##
##   * **item 1** every one-shot clip, at the blends the GAME uses (0.05 / 0.06 / 0.08), has
##     `playing()` false within `length + blend + 1 tick`, and the bones it owned are back on the
##     gait and the posture. `stop()` releases a loop or a hold clip inside the same window.
##   * **item 4** every chain the game makes, cut in at the EARLIEST cancel frame `melee_table.gd`
##     allows: the hand's one-frame move over the chain's first three frames is no faster than the
##     faster clip's own fastest frame.
##   * **item 5** 4 s standing still, with no clip and with an upper clip: no foot or toe bone moves
##     more than 0.05 m and no applied foot roll changes by more than 1 degree in a tick.

const SCENE := "res://player/model/hero3/hero3_model.tscn"
const DT := 1.0 / 60.0
## The blends the game actually passes: melee_system 0.06, the play_action default 0.08, guard 0.05.
const BLENDS: Array[float] = [0.05, 0.06, 0.08]
const IDLE_SECONDS := 4.0
const IDLE_MOVE_GATE := 0.05
const IDLE_ROLL_GATE_DEG := 1.0
## The chains the game makes. Cut frames are not listed here: a melee link is cut at the earliest
## frame `melee_table.gd` allows, and anything else is swept every 4 frames (see `_cut_frames`).
const CHAINS: Array = [
	[&"melee_l1", &"melee_l2", &"melee_l3"],
	[&"air_l1", &"air_l2"],
	[&"guard_up", &"return_cut"],
	[&"guard_up", &"parry", &"guard_up"],
	[&"guard_up", &"catch_hold", &"catch_release"],
	[&"charge_r", &"fire_r"],
]

var failures: Array[String] = []
var _table: GDScript
var _model: Node3D
var _clips: Hero3ClipPlayer
var _gait: Hero3Gait
var _skel: Skeleton3D
## clip -> its own fastest one-frame hand move, measured solo. Filled by `_solo_fastest`.
var _solo: Dictionary = {}


func _ready() -> void:
	_table = load("res://combat/melee/melee_table.gd")
	_model = (load(SCENE) as PackedScene).instantiate()
	_model.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_model)
	_clips = _model.clips
	_gait = _model.gait
	_skel = _gait.skeleton
	_release_gate()
	_stop_gate()
	_chain_gate()
	_idle_gate()
	if failures.is_empty():
		print("PASS")
		get_tree().quit(0)
	else:
		for line in failures:
			print("FAIL %s" % line)
		print("FAILED %d checks" % failures.size())
		get_tree().quit(1)


## One tick of the whole model, exactly the order `Hero3Model._physics_process` uses.
func _tick() -> void:
	_clips.update(DT)
	_gait.update(DT)
	_clips.apply()


func _settle(ticks: int = 60) -> void:
	_model.stop_action()
	for i in ticks:
		_tick()


func _fail(line: String) -> void:
	failures.append(line)


# --- item 1: a clip has to let go ------------------------------------------------------------------

func _release_gate() -> void:
	var ids: Array[StringName] = []
	for id: StringName in _clips.clips:
		var clip: Dictionary = _clips.clips[id]
		if not bool(clip.get("loop", false)) and not bool(clip.get("hold", false)):
			ids.append(id)
	ids.sort()
	_model.set_locomotion(&"idle", 0.0, Vector2.ZERO)
	_gait.reset()
	_settle(120)
	var bones := _probe_bones()
	var worst_over := 0.0
	var worst_fade := 0.0
	for id in ids:
		for blend in BLENDS:
			_settle(30)
			var length: float = _model.play_action(id, blend)
			var last := _pose(bones)
			var ticks := 0
			while _clips.playing() and ticks < 1800:
				_tick()
				ticks += 1
				var now := _pose(bones)
				if _clips.weight() <= 0.0:
					worst_fade = maxf(worst_fade, _gap(now, last))
				last = now
			var budget := length + blend + DT
			if float(ticks) * DT > budget:
				worst_over = maxf(worst_over, float(ticks) * DT - budget)
				_fail("%s at blend %.2f let go after %.3f s, budget %.3f s"
						% [id, blend, float(ticks) * DT, budget])
			if _clips.playing() or _clips.weight() > 0.0:
				_fail("%s at blend %.2f is still writing bones at weight %.2f"
						% [id, blend, _clips.weight()])
			for bone_name: String in _clips.clips[id]["bones"]:
				if _clips.owns(bone_name):
					_fail("%s still owns %s after releasing" % [id, bone_name])
	print("RELEASE %d one-shot clips x %d blends | worst overrun %.3f s (gate 0) | worst frame during the fade-out %.3f m"
			% [ids.size(), BLENDS.size(), worst_over, worst_fade])


## The largest move any probe bone made between two poses, in metres.
func _gap(a: Array[Vector3], b: Array[Vector3]) -> float:
	var worst := 0.0
	for i in a.size():
		worst = maxf(worst, a[i].distance_to(b[i]))
	return worst


## `stop()` has to end a loop and a hold at once, and a hold has to survive to its last frame first.
func _stop_gate() -> void:
	for id: StringName in [&"guard_up", &"gatling_spin", &"hover", &"fly", &"death"]:
		var clip: Dictionary = _clips.clips.get(id, {})
		if clip.is_empty():
			_fail("%s has no clip" % id)
			continue
		_settle(30)
		var length: float = _model.play_action(id, 0.06)
		var held := bool(clip.get("hold", false))
		# a held clip is run a full second PAST its own end: it has to still be there, at full weight,
		# because `death` never ends on its own -- only `stop_action` lets go of it (lead r4 interim
		# item b)
		var run := int(float(clip["frames"])) + 60 if held else 30
		for i in run:
			_tick()
		if not _clips.playing():
			_fail("%s stopped on its own" % id)
		if held and _clips.weight() < 0.999:
			_fail("%s is a hold clip but ended at weight %.2f" % [id, _clips.weight()])
		var held_at := _pose(_probe_bones())
		var weight_at_end := _clips.weight()
		_model.stop_action()
		var ticks := 0
		while _clips.playing() and ticks < 600:
			_tick()
			ticks += 1
		if float(ticks) * DT > 0.06 + DT:
			_fail("stop_action on %s took %.3f s, budget %.3f s" % [id, float(ticks) * DT, 0.06 + DT])
		if _clips.playing():
			_fail("stop_action left %s playing" % id)
		_settle(20)
		var drift := _worst_drift(_probe_bones(), held_at)
		print("STOP    %-13s %-5s len %.2f s | still at weight %.2f a second past its end | stop_action released it in %.3f s, rig moved %.2f m"
				% [id, "hold" if held else "loop", length, weight_at_end, float(ticks) * DT, drift])


func _probe_bones() -> Array[int]:
	var out: Array[int] = []
	for bone_name in ["R_Hand", "L_Hand", "R_Foot", "L_Foot", "Head"]:
		out.append(_skel.find_bone(bone_name))
	return out


func _pose(bones: Array[int]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for idx in bones:
		out.append(_skel.get_bone_global_pose(idx).origin)
	return out


func _worst_drift(bones: Array[int], reference: Array[Vector3]) -> float:
	var now := _pose(bones)
	var worst := 0.0
	for i in bones.size():
		worst = maxf(worst, now[i].distance_to(reference[i]))
	return worst


# --- item 4: a chain starts from where the arm IS ----------------------------------------------------

## Every cut the game can make, at every frame it can make it. A melee link is cut at the EARLIEST
## frame `melee_table.gd` allows; anything else is swept every 4 frames, because there is no table to
## read a cancel window from and picking one convenient frame would not be a gate.
func _chain_gate() -> void:
	_model.set_locomotion(&"idle", 0.0, Vector2.ZERO)
	_gait.reset()
	for chain: Array in CHAINS:
		var cuts := _cut_frames(chain)
		for link in chain.size() - 1:
			for cut: int in cuts[link]:
				_check_cut(chain, link, cut)


## `cuts[i]` is every frame of `seq[i]` at which the game may start `seq[i + 1]`.
func _cut_frames(seq: Array) -> Array:
	var out: Array = []
	for i in seq.size() - 1:
		var id: StringName = seq[i]
		var frames := int(float(_clips.clips[id]["frames"]))
		if _table.has_move(id):
			out.append([int(_table.field(id, "cancel_from"))] as Array)
		else:
			var sweep: Array = []
			for f in range(4, frames, 4):
				sweep.append(f)
			out.append(sweep)
	return out


## Run the whole chain with this one cut at `cut`, and compare the hand's one-frame move over the
## three frames after it with the fastest frame either of the two clips makes on its own.
func _check_cut(seq: Array, link: int, cut: int) -> void:
	var fastest := maxf(_solo_fastest(seq[link]), _solo_fastest(seq[link + 1]))
	var run := _run_chain(seq, link, cut)
	var moves: Array[float] = run["moves"]
	var at: int = run["cut"]
	var jump := 0.0
	for k in range(at, mini(at + 3, moves.size())):
		jump = maxf(jump, moves[k])
	var label := "%s -> %s at f%d" % [seq[link], seq[link + 1], cut]
	if jump > fastest + 1e-6:
		_fail("CHAIN %s: hand jumps %.2f m in one frame, faster than either clip's own %.2f m"
				% [label, jump, fastest])
	print("CHAIN   %-34s jump %.2f m | fastest frame of the pair %.2f m | %s"
			% [label, jump, fastest, "ok" if jump <= fastest else "TOO FAST"])


## The clip's own fastest one-frame hand move, measured SOLO: played alone from a settled idle, with
## no chain and no cut. The chain's jump is compared against this, not against the clip's motion
## inside the chain -- for charge_r -> fire_r the first three frames after the cut ARE fire_r's
## recoil, so measuring "the rest of the clip" would exclude the very thing being compared.
func _solo_fastest(id: StringName) -> float:
	if _solo.has(id):
		return float(_solo[id])
	_settle(30)
	var hand := _skel.find_bone("R_Hand")
	var frames := int(float(_clips.clips[id]["frames"]))
	_model.play_action(id, 0.06)
	var last := _skel.get_bone_global_pose(hand).origin
	var worst := 0.0
	for f in frames + 8:
		_tick()
		var now := _skel.get_bone_global_pose(hand).origin
		worst = maxf(worst, now.distance_to(last))
		last = now
	_solo[id] = worst
	return worst


## Play `seq`, cutting from `seq[link]` to `seq[link + 1]` at frame `cut`. Every OTHER link runs to
## its own end, so the measurement is one cut inside an otherwise ordinary chain.
func _run_chain(seq: Array, link: int, cut: int) -> Dictionary:
	_settle(30)
	var hand := _skel.find_bone("R_Hand")
	var moves: Array[float] = []
	var at := -1
	var last := _skel.get_bone_global_pose(hand).origin
	for i in seq.size():
		_model.play_action(seq[i], 0.06)
		if i == link + 1:
			at = moves.size()
		var frames := int(float(_clips.clips[seq[i]]["frames"]))
		var run := cut if i == link else frames + 4
		for f in run:
			_tick()
			var now := _skel.get_bone_global_pose(hand).origin
			moves.append(now.distance_to(last))
			last = now
	return {"moves": moves, "cut": at}


# --- item 5: standing still, the feet do not move ---------------------------------------------------

func _idle_gate() -> void:
	var bones: Array[int] = []
	for bone_name in ["R_Foot", "L_Foot", "R_Toe", "L_Toe"]:
		bones.append(_skel.find_bone(bone_name))
	for spec: Array in [[&"", "no clip"], [&"melee_l1", "melee_l1"], [&"fire_r", "fire_r"]]:
		_model.set_locomotion(&"idle", 0.0, Vector2.ZERO)
		_gait.reset()
		_settle(120)
		if spec[0] != &"":
			_model.play_action(spec[0], 0.06)
		var start := _pose(bones)
		var last_roll := _gait.foot_rolls()
		var worst_move := 0.0
		var worst_roll := 0.0
		var steps := 0
		for t in int(IDLE_SECONDS / DT):
			_tick()
			worst_move = maxf(worst_move, _worst_drift(bones, start))
			var rolls := _gait.foot_rolls()
			for i in 2:
				worst_roll = maxf(worst_roll, absf(rad_to_deg(rolls[i] - last_roll[i])))
			last_roll = rolls
			steps = maxi(steps, 2 - _gait.support_count())
		print("IDLE    %-9s %.1f s | worst foot/toe move %.4f m (gate %.2f) | worst one-tick roll %.3f deg (gate %.1f) | feet off the ground %d"
				% [spec[1], IDLE_SECONDS, worst_move, IDLE_MOVE_GATE, worst_roll, IDLE_ROLL_GATE_DEG,
				steps])
		if worst_move > IDLE_MOVE_GATE:
			_fail("idle with %s moved a foot or toe %.3f m" % [spec[1], worst_move])
		if worst_roll > IDLE_ROLL_GATE_DEG:
			_fail("idle with %s changed a foot roll %.2f deg in one tick" % [spec[1], worst_roll])
