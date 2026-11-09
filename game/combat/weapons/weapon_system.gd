class_name WeaponSystem
extends Node3D
## Weapon component of the PlayerMech (CONTRACTS §5): owns the two primaries (P1 Pierce-Light rifle,
## P2 Thunder Spindle gatling) and the S3 Hailstorm launcher, plus every pooled visual and projectile
## they need. Reads input actions, fires from the model's `muzzle_r` socket toward the crosshair,
## plays the model actions and answers `hud_state()`.
##
## hud_state() keys: weapon, ammo, ammo_max, reloading, charge, charge_stage, heat, overheated,
## vent_needle, vent_mark, superheated, missile_cd, missile_locks, missile_locks_max,
## missile_painting, swapping, last_hit_usec, last_hit_kind.

const RIFLE := 0
const GATLING := 1

@export var swap_time: float = 0.35
@export var strafe_release: float = 0.6   ## how long strafe-aim stays on after the last shot

var ctx: WeaponContext = null
var rifle: PierceLightRifle = null
var gatling: ThunderSpindleGatling = null
var hailstorm: HailstormLauncher = null
var beams: BeamPool = null
var sparks: SparkPool = null
var casings: CasingPool = null
var bullets: ProjectileManager = null
var missiles: MissileManager = null

var current: int = RIFLE

var _swap_left: float = 0.0
var _strafe_left: float = 0.0
var _fire_held: bool = false
var _reload_held: bool = false
var _missile_held: bool = false
var _player_ref: Node = null


func _ready() -> void:
	rifle = get_node_or_null(^"Rifle") as PierceLightRifle
	gatling = get_node_or_null(^"Gatling") as ThunderSpindleGatling
	hailstorm = get_node_or_null(^"Hailstorm") as HailstormLauncher
	beams = get_node_or_null(^"Beams") as BeamPool
	sparks = get_node_or_null(^"Sparks") as SparkPool
	casings = get_node_or_null(^"Casings") as CasingPool
	bullets = get_node_or_null(^"Bullets") as ProjectileManager
	missiles = get_node_or_null(^"Missiles") as MissileManager
	for n: Variant in [rifle, gatling, hailstorm, beams, sparks, casings, bullets, missiles]:
		if n == null:
			push_error("WeaponSystem: missing child node (check weapon_system.tscn)")
			return
	_refresh_player()
	ctx = WeaponContext.new(_player_ref)
	_exclude_player(_player_ref)
	ctx.beams = beams
	ctx.sparks = sparks
	ctx.casings = casings
	ctx.bullets = bullets
	ctx.missiles = missiles
	bullets.query = ctx.query
	missiles.query = ctx.query
	bullets.sparks = sparks
	missiles.sparks = sparks
	if rifle != null:
		rifle.setup(ctx)
	if gatling != null:
		gatling.setup(ctx)
	if hailstorm != null:
		hailstorm.setup(ctx)
	if not Events.camera_mode_changed.is_connected(_on_camera_mode):
		Events.camera_mode_changed.connect(_on_camera_mode)
	set_physics_process(true)


## camera-aim's public API (CONTRACTS §5). The weapons size their muzzle visuals by camera mode; the
## live `AimSystem.is_first_person()` read wins when the mech has one, this is the fallback for a
## component running without an AimSystem (range scene, headless tests).
func _on_camera_mode(first_person: bool) -> void:
	if ctx != null:
		ctx.fp_hint = first_person


## The pools that keep drawing after the shot has left the muzzle — spent casings and the missile
## circus — cannot ask the AimSystem themselves (they are plain world-space pools), so the component
## pushes the mode and the lens into them once per tick. Everything they draw is world-clock, so this
## has to be a push, not a pull at fire time: a casing ejected a frame before a cockpit toggle is
## still on screen after it.
func _publish_camera_mode() -> void:
	var fp := ctx.is_first_person()
	var eye := ctx.lens()
	casings.first_person = fp
	casings.lens = eye
	if missiles.visuals != null:
		missiles.visuals.first_person = fp
		missiles.visuals.lens = eye


## The mech instances this component before its model/aim siblings are guaranteed ready, so the
## references are refreshed every tick until they resolve.
func _refresh_player() -> void:
	var p := get_parent()
	if p == null:
		return
	if p != _player_ref:
		_player_ref = p
		if ctx != null:
			ctx.player = p
			ctx.query.source = p
		_exclude_player(p)
	if ctx == null:
		return
	if ctx.model == null and p.has_method(&"model"):
		ctx.model = p.call(&"model")
	if ctx.aim == null and p.has_method(&"aim"):
		ctx.aim = p.call(&"aim")


func _exclude_player(p: Node) -> void:
	if ctx == null or not (p is CollisionObject3D):
		return
	var rids: Array[RID] = [(p as CollisionObject3D).get_rid()]
	for n in p.find_children("*", "CollisionObject3D", true, false):
		rids.append((n as CollisionObject3D).get_rid())
	ctx.query.exclude = rids


func current_weapon() -> StringName:
	return PierceLightRifle.ID if current == RIFLE else ThunderSpindleGatling.ID


func _physics_process(delta: float) -> void:
	_refresh_player()
	# CONTRACTS §3: every weapon timer is player-side — full speed in witch time (the guns never slow
	# with the world) and frozen by a global hit-stop (that freeze is the impact). The rounds and
	# missiles already in the air keep the world clock in their own `_physics_process`.
	var dt := Feel.player_delta(delta)
	ctx.ads = Input.is_action_pressed(&"aim")
	_publish_camera_mode()
	var fire := Input.is_action_pressed(&"fire")
	var reload := Input.is_action_pressed(&"reload")
	var missiles_held := Input.is_action_pressed(&"missiles")
	var fire_pressed := fire and not _fire_held
	var fire_released := not fire and _fire_held
	var reload_pressed := reload and not _reload_held
	var missile_released := not missiles_held and _missile_held
	_fire_held = fire
	_reload_held = reload
	_missile_held = missiles_held
	_swap(dt, fire_pressed, fire_released, reload_pressed)
	hailstorm.update(dt, missiles_held, missile_released, ctx.ads)
	_strafe(dt, fire, ctx.ads)


## `player_dt` is `Feel.player_delta(delta)` (CONTRACTS §3), never raw scaled delta.
func _swap(player_dt: float, fire_pressed: bool, fire_released: bool, reload_pressed: bool) -> void:
	if Input.is_action_just_pressed(&"weapon_next"):
		switch_weapon(1)
	elif Input.is_action_just_pressed(&"weapon_prev"):
		switch_weapon(-1)
	var swapping := _swap_left > 0.0
	if swapping:
		_swap_left = maxf(_swap_left - player_dt, 0.0)
	# The gatling's gauge belongs to the mech, not to the trigger: its heat, jam, reload and
	# Superheated clocks keep running while it is holstered, or the reticle would draw a frozen arc.
	if current != GATLING or swapping:
		gatling.tick_holstered(player_dt)
	if swapping:
		return
	if current == RIFLE:
		rifle.update(player_dt, _fire_held, fire_pressed, fire_released)
		if reload_pressed:
			rifle.reload()
	else:
		gatling.update(player_dt, _fire_held, fire_pressed, reload_pressed)


## 0.35 s swap, announced on the bus (HUD swaps the plate, audio swaps the loop).
func switch_weapon(step: int) -> void:
	if _swap_left > 0.0 or step == 0:
		return
	current = posmod(current + step, 2)
	_swap_left = swap_time
	if current == RIFLE:
		gatling.cancel()
	else:
		rifle.cancel()
	Events.weapon_switched.emit(current_weapon())


## Strafe-aim stays on while firing or aiming down sights, and for 0.6 s afterwards.
func _strafe(player_dt: float, fire: bool, ads: bool) -> void:
	var firing := fire or ads or rifle.is_firing() or gatling.is_firing() or hailstorm.painting
	if firing:
		_strafe_left = strafe_release
	else:
		_strafe_left = maxf(_strafe_left - player_dt, 0.0)
	var want := _strafe_left > 0.0
	_apply_strafe(want)


## The one place `ctx.strafe_aim` is written, so the mech is told exactly once per change.
func _apply_strafe(want: bool) -> void:
	if want == ctx.strafe_aim:
		return
	ctx.strafe_aim = want
	if ctx.player != null and ctx.player.has_method(&"set_strafe_aim"):
		ctx.player.call(&"set_strafe_aim", want)


func hud_state() -> Dictionary:
	var out: Dictionary = {"weapon": current_weapon(), "swapping": _swap_left > 0.0}
	var active: Node = rifle if current == RIFLE else gatling
	if active != null:
		out.merge(active.call(&"hud_state"), true)
	# the heat/vent gauge belongs to the gatling but the HUD draws it whenever the mech carries one
	var g := gatling.hud_state()
	for key: String in ["heat", "overheated", "vent_needle", "vent_mark", "superheated"]:
		out[key] = g[key]
	out.merge(hailstorm.hud_state(), true)
	out["last_hit_usec"] = ctx.query.last_hit_usec
	out["last_hit_kind"] = ctx.query.last_hit_kind
	return out


func reset() -> void:
	rifle.reset_state()
	gatling.reset_state()
	hailstorm.reset_state()
	current = RIFLE
	_swap_left = 0.0
	_strafe_left = 0.0


## Stop everything the mech is holding down — the death gate's hook (mech-move Request 17). It is
## `reset()`'s opposite: nothing is handed back, so the cell, the belt, the heat, the jam, the
## Superheated and missile clocks and the selected weapon are all exactly what the caller found.
## The bus stays silent too: a corpse announces no `weapon_switched` and no lock change.
func stop_volley() -> void:
	rifle.cancel()
	gatling.cancel()
	hailstorm.cancel()
	_strafe_left = 0.0
	if ctx == null:
		return
	ctx.ads = false
	_apply_strafe(false)
