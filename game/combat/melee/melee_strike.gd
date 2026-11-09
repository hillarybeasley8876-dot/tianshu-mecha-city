class_name MeleeStrike
extends RefCounted
## The "a hit lands" half of the melee component (melee_system.gd keeps the input and the state
## machine): sweeps the blade along the arc, plays the move's FEEL row, spawns sparks, applies the
## local hit-stop and shoves the victim. It also owns the geometry the swing needs — the chest pivot
## and the aim-following facing — and the crescent wave the charged slash throws.
##
## The arc here is GAMEPLAY ONLY (review r4): what is drawn is the hand-held blade on the model's
## `saber_r` socket, and the model's clip is what sweeps it. The hitbox keeps the arc so the frame
## data stays readable and independent of whichever model is installed.

const HEAVY_KICK_DEG := 1.4
const LIGHT_KICK_DEG := 0.8

var player: Node = null
var aim: Node = null
var sweep: BladeSweep = null

var last_hit_usec: int = 0
var last_hit_kind: StringName = &""


func _init(player_: Node, aim_: Node, sweep_: BladeSweep) -> void:
	player = player_
	aim = aim_
	sweep = sweep_


## One sweep per active tick, at this tick's place on the arc.
func sample(move: StringName, tick: int, startup: int, active: int) -> void:
	if sweep == null:
		return
	var progress := clampf(float(tick - startup) / float(maxi(active - 1, 1)), 0.0, 1.0)
	sweep.sample(move, pivot(), facing(), progress)



## FEEL.md melee rows: the event plays at the impact point, the local hit-stop freezes only the two
## actors involved, sparks come from the VFX library and the camera kicks along the swing.
func on_landed(move: StringName, hit: HitInfo, receiver: Node) -> void:
	last_hit_usec = Time.get_ticks_usec()
	last_hit_kind = sweep.last_hit_kind() if sweep != null else &"normal"
	Feel.play(MeleeTable.name_of(move, "feel"), hit.position, 1.0)
	Feel.local_hit_stop([player, receiver], MeleeTable.seconds(MeleeTable.field(move, "hitstop")))
	sparks(move, hit.position)
	shove(receiver, hit)


## Contact FX at the exact point the blade met the target: `spark_beam` streaks for every hit, a
## wider `spark_burst` plus a point light for the heavies (FEEL.md melee_light / melee_heavy).
## `spark_beam` is what the review asked to see on the blade's contact point.
func sparks(move: StringName, at: Vector3) -> void:
	var heavy := MeleeTable.field(move, "hitstop") >= 9.0
	var normal := -facing().z
	## `scale` multiplies particle VELOCITY as well as size, so these are small on purpose: at 2.4
	## a spark_burst is a 50 m fireball of additive streaks that whites out the whole frame.
	CombatVfx.spawn(player, &"spark_beam", at, normal, 1.5 if heavy else 1.1)
	if heavy:
		CombatVfx.spawn(player, &"spark_burst", at, normal, 0.9)
		CombatVfx.flash(player, at, Color(0.7, 0.95, 1.0), 3.5, 22.0)
	Feel.kick(HEAVY_KICK_DEG if heavy else LIGHT_KICK_DEG, normal, 0.18)


## CONTRACTS §6 `handles_own_knockback()`: `EnemyBase` returns true, because its own stagger reaction
## already carries the shove — adding ours on top is the ≈ +1.35 m double push the audit found.
func shove(receiver: Node, hit: HitInfo) -> void:
	if hit.knockback == Vector3.ZERO or not (receiver is CharacterBody3D):
		return
	if receiver.has_method(&"handles_own_knockback") \
			and bool(receiver.call(&"handles_own_knockback")):
		return
	(receiver as CharacterBody3D).velocity += hit.knockback


## Ram Kick: ×2.5 damage and impact against a staggered target (SPEC §4 assault boost).
func damage_scale(move: StringName) -> float:
	if move != MeleeTable.RAM_KICK:
		return 1.0
	var t := hard_target()
	return MeleeTable.RAM_KICK_STAGGER_MULT if t != null and is_staggered(t) else 1.0


## The charged slash also throws the crescent (skills-catalog §4.3): 90 m at 140 m/s, 24 m wide.
## It launches low, so its leading edge runs along the street instead of floating at chest height.
func spawn_wave(host: Node) -> void:
	if host == null or player == null:
		return
	var wave := CrescentWave.new()
	wave.name = "CrescentWave"
	host.add_child(wave)
	var p := pivot()
	wave.launch(p - facing().z * 6.0 - Vector3.UP * MeleeTable.WAVE_DROP, -facing().z, player)
	Feel.play(&"charge_slash", p, 1.0)


# --- geometry -----------------------------------------------------------------------------------

## The blade pivots at chest height (CONTRACTS §5: the model sits 7.5 m below the body origin).
func pivot() -> Vector3:
	if not (player is Node3D):
		return Vector3.ZERO
	var p := player as Node3D
	return p.global_position + Vector3.UP * MeleeTable.BLADE_HEIGHT + p.global_basis.x * 2.0


## Swings follow the aim, so a locked target is hit where the crosshair is; without an aim system the
## body facing is used.
func facing() -> Basis:
	if aim != null and aim.has_method(&"aim_dir_from") and player is Node3D:
		var dir: Vector3 = aim.call(&"aim_dir_from", pivot())
		var flat := Vector3(dir.x, 0.0, dir.z)
		if flat.length_squared() > 0.0001:
			return Basis.looking_at(flat.normalized(), Vector3.UP)
	return (player as Node3D).global_basis if player is Node3D else Basis.IDENTITY


func flat_distance(to: Vector3) -> float:
	if not (player is Node3D):
		return INF
	var d: Vector3 = to - (player as Node3D).global_position
	d.y = 0.0
	return d.length()


func hard_target() -> Node3D:
	if aim == null or not aim.has_method(&"hard_target"):
		return null
	return aim.call(&"hard_target") as Node3D


## The shipped VFX library, so melee sparks are the real effect: the FeelDirector's when the feel
## unit is instanced, else any library that registered itself (demo ranges run without a director).
func vfx_library() -> Node:
	return CombatVfx.library(player)


static func is_staggered(node: Node) -> bool:
	var s: Variant = node.get(&"status")
	return s != null and s.has_method(&"is_staggered") and bool(s.call(&"is_staggered"))
