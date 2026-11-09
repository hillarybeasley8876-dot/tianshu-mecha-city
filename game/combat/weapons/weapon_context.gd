class_name WeaponContext
extends RefCounted
## Everything a weapon needs from the mech, in one small object, so the weapon scripts never touch
## PlayerMech / AimSystem / HeroModel directly (and never form a cyclic script reference with the
## WeaponSystem that owns them). The WeaponSystem keeps the fields up to date each frame.
##
## Null-tolerant on purpose: while the mech, aim and hero-model units are still landing, sockets fall
## back to the player's chest, aim direction to the body's forward axis, and target scans to the
## `&"targetable"` group — so the component runs standalone in tests and captures.

const CHEST_HEIGHT := 11.5       ## chest pivot of the 16 m hero (SPEC §5)
## First-person VFX (lead r5 item 1). In the cockpit the lens sits ~6 m from `muzzle_r`, so a flash
## sized for the 42 m third-person arm is a disc across a third of the frame instead of a flash.
## Every muzzle-anchored metric is scaled by FP_SCALE and drawn at FP_OPACITY (FEEL.md:9).
const FP_SCALE := 0.27           ## 2.2 m gatling flash -> 0.6 m = 8 % of the 62 deg frame at 6 m
const FP_OPACITY := 0.6          ## FEEL.md:9 "VFX opacity -40 %" in first person
const FP_BEAM_START := 24.0      ## m down range: the lens must not stare into the beam tube's mouth
const FP_LIGHT_RANGE := 0.5      ## an omni at the gun lights the whole street from inside the cockpit
## The cockpit eye (camera-aim, `cockpit_frame.gd`): 13.5 m above the model root, never below the
## SPEC §5 11.5 m band floor, and 1.2 m forward at the canopy glass.
const EYE_HEIGHT := 13.5
const EYE_MIN := 11.5
const EYE_FORWARD := 1.2

var player: Node = null
var model: Node = null            ## HeroModel (player.model()) or null
var aim: Node = null              ## AimSystem (player.aim()) or null
var query: ShotQuery = null
var beams: BeamPool = null
var sparks: SparkPool = null
var bullets: ProjectileManager = null
var missiles: MissileManager = null
var casings: CasingPool = null
var ads: bool = false             ## aim action held this frame
var strafe_aim: bool = false      ## what we last asked the mech for
var fp_hint: bool = false         ## last Events.camera_mode_changed (stands in when there is no aim)


func _init(player_: Node = null) -> void:
	player = player_
	query = ShotQuery.new(player_)


## Global position of a model socket, with a chest-height fallback when the model is not in yet.
func socket(nm: StringName) -> Vector3:
	if model != null and is_instance_valid(model) and model.has_method(&"socket"):
		var n := model.call(&"socket", nm) as Node3D
		if n != null:
			return n.global_position
	return chest()


func chest() -> Vector3:
	if player == null or not is_instance_valid(player) or not (player is Node3D):
		return Vector3.ZERO
	var p := player as Node3D
	return p.global_position + Vector3.UP * CHEST_HEIGHT


func facing() -> Vector3:
	if player != null and is_instance_valid(player) and player is Node3D:
		return -(player as Node3D).global_basis.z.normalized()
	return Vector3.FORWARD


## Where the crosshair points (AimSystem, else a point 1,500 m down the body's forward axis).
func aim_point() -> Vector3:
	if _has(&"aim_point"):
		return aim.call(&"aim_point")
	return chest() + facing() * 1500.0


## Direction from `from` toward the crosshair.
func aim_dir_from(from: Vector3) -> Vector3:
	if _has(&"aim_dir_from"):
		var d: Vector3 = aim.call(&"aim_dir_from", from)
		if d.length_squared() > 0.0001:
			return d.normalized()
	var d2 := aim_point() - from
	return d2.normalized() if d2.length_squared() > 0.0001 else facing()


## Camera mode, from camera-aim's public API only: AimSystem.is_first_person() when the mech has an
## AimSystem, else the last `Events.camera_mode_changed` the WeaponSystem heard. Read live, so the
## size is right from the first round after a toggle and for a mech that was already in the cockpit
## when the component readied.
func is_first_person() -> bool:
	if _has(&"is_first_person"):
		return bool(aim.call(&"is_first_person"))
	return fp_hint


## Size of a muzzle-anchored visual: metres for the third-person arm, shrunk in the cockpit.
func fp_size(size_m: float) -> float:
	return size_m * FP_SCALE if is_first_person() else size_m


## The first-person lens, from camera-aim's public API (`AimSystem.camera()`). Only the cockpit
## visuals read it — the pools hide or shrink a casing, a missile flare or a smoke puff while it is
## close enough to fill the canopy (lead r6). Falls back to the model's `cockpit` socket at the
## SPEC §5 eye band, the same rule `player/camera/cockpit_frame.gd:54` uses, for a component running
## without a camera (the range scene, a bare rig).
func lens() -> Vector3:
	if _has(&"camera"):
		var cam := aim.call(&"camera") as Camera3D
		if cam != null:
			return cam.global_position
	var eye := chest() + Vector3.UP * (EYE_HEIGHT - CHEST_HEIGHT)
	if model != null and is_instance_valid(model) and model.has_method(&"socket"):
		var s := model.call(&"socket", &"cockpit") as Node3D
		if s != null:
			eye = s.global_position
	if player != null and is_instance_valid(player) and player is Node3D:
		var p := player as Node3D
		eye.y = maxf(eye.y, p.global_position.y + EYE_MIN)
		return eye - p.global_basis.z.normalized() * EYE_FORWARD
	return eye


## Opacity for a muzzle-anchored visual (FEEL.md:9 first-person rule).
func fp_alpha() -> float:
	return FP_OPACITY if is_first_person() else 1.0


## Energy and range for a muzzle / rail flash light: an omni 4 m from the lens floods the canopy and
## the street behind it, so in the cockpit it loses range as well as energy.
func fp_light_energy(energy: float) -> float:
	return energy * FP_OPACITY if is_first_person() else energy


func fp_light_range(range_m: float) -> float:
	return range_m * FP_LIGHT_RANGE if is_first_person() else range_m


## Where a beam starts: at the muzzle in third person, down range in the cockpit, so the camera never
## looks straight into the open end of the glow cylinder.
func fp_beam_from(muzzle: Vector3, dir: Vector3) -> Vector3:
	return muzzle + dir * FP_BEAM_START if is_first_person() else muzzle


## Targets inside the missile paint box (AimSystem, else a scan of the `&"targetable"` group).
func targets_in_view(max_count: int, max_range: float) -> Array[Targetable]:
	if _has(&"targets_in_view"):
		var out: Array[Targetable] = []
		for t: Variant in aim.call(&"targets_in_view", max_count, max_range):
			if t is Targetable:
				out.append(t as Targetable)
		return out
	return scan_targets(max_count, max_range)


## Fallback target scan: nearest valid Targetables inside `max_range` of the chest.
func scan_targets(max_count: int, max_range: float) -> Array[Targetable]:
	var out: Array[Targetable] = []
	if player == null or not is_instance_valid(player):
		return out
	var tree := player.get_tree()
	if tree == null:
		return out
	var origin := chest()
	var found: Array[Targetable] = []
	for n in tree.get_nodes_in_group(&"targetable"):
		var t := n as Targetable
		if t == null or not t.is_valid_target():
			continue
		if origin.distance_to(t.global_position) <= max_range:
			found.append(t)
	found.sort_custom(func(a: Targetable, b: Targetable) -> bool:
			return origin.distance_squared_to(a.global_position) < origin.distance_squared_to(b.global_position))
	for t in found:
		if out.size() >= max_count:
			break
		out.append(t)
	return out


## Whether the mech can pay `amount` EN right now (true when it has no EN API yet).
func has_energy(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if player == null or not is_instance_valid(player):
		return true
	var e: Variant = player.get(&"energy")
	return true if e == null else float(e) >= amount


## Spend EN; false when the mech cannot pay (or has no EN API yet).
func consume_energy(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if player == null or not is_instance_valid(player) or not player.has_method(&"consume_energy"):
		return true
	return bool(player.call(&"consume_energy", amount))


## Play a HeroModel action when a model exists (ids in SPEC §10).
func play_action(id: StringName) -> void:
	if model != null and is_instance_valid(model) and model.has_method(&"play_action"):
		model.call(&"play_action", id)


## Release a held clip (a spin-up that ended). The HeroModel API, CONTRACTS §5.
func stop_action() -> void:
	if model != null and is_instance_valid(model) and model.has_method(&"stop_action"):
		model.call(&"stop_action")


func _has(method: StringName) -> bool:
	return aim != null and is_instance_valid(aim) and aim.has_method(method)
