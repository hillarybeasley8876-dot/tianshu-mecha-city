class_name FeelDirector
extends Node
## Data-driven feel (feel unit). Instanced by main.tscn as res://fx/feel_director.tscn, and found at
## runtime through the &"feel_director" group.
##
## Feel.play(&"id", pos, strength, actors) arrives here through Feel.event_with_actors_requested;
## the row is looked up in fx/events/<id>.tres (one FeelEvent per docs/FEEL.md row) and every column
## fires at once: hit-stop, trauma, kick, flash, post effects, FOV, slow-mo, VFX, decals, audio and
## rumble.
##
## Division of labour with core/feel.gd: Feel owns Engine.time_scale, the signal bus and the camera
## kick channel; this node owns the table and the visuals. A LOCAL row's stop runs here on the
## `actors` the caller passed (FEEL.md:6 — gunfire freezes the victim, never the world); a caller
## that has to run it itself (a melee attacker the row does not know about) still reads
## hitstop_seconds(id).

## Fired after a row has been applied (tests, HUD, telemetry).
signal event_played(id: StringName, at: Vector3, strength: float)

const EVENTS_DIR := "res://fx/events/"
## First person pulls the screen effects back (juice-impact §13: shake x0.6, FOV x0.75).
const FP_SHAKE := 0.6
const FP_FOV := 0.75
## The camera rig clamps the FOV sum to +/-15 degrees (juice-impact §3.3); we never exceed it.
const MAX_FOV := 15.0
const HITSTOP_SCALE := 0.05   ## Engine.time_scale during a global micro-freeze
## Swarm-kill budgets (FEEL.md:42-43). A pack dying under a gatling burst must not chain world
## freezes, so a `budgeted` row takes at most one GLOBAL stop per GLOBAL_BUDGET seconds and one
## slow-mo per SLOW_BUDGET seconds; whatever the budget refuses plays on the victim instead.
const GLOBAL_BUDGET := 2.0
const SLOW_BUDGET := 6.0
const IMPACT_BW := 0.85       ## mix of the B/W impact frame (photosensitive mode dims it)
## Surface used when the caller gives no normal (Feel.play only carries a position).
const DEFAULT_NORMAL := Vector3.UP

var vfx: VfxLibrary
var screen: ScreenFx
var rumble: RumbleMixer

var _events: Dictionary = {}       ## StringName -> FeelEvent
var _last_played: Dictionary = {}  ## StringName -> real seconds
var _warned: Dictionary = {}
var _now: float = 0.0
var _last_global: float = -1000.0  ## real seconds of the last GLOBAL stop this director accepted
var _last_slow: float = -1000.0    ## real seconds of the last slow-mo a budgeted row took
var _ghost_jobs: Array[Dictionary] = []  ## pending afterimages: {"at": real seconds, "life": float}
var _played: int = 0
var _fp: bool = false
var _fp_checked: float = -1.0


func _ready() -> void:
	# Other units (and the gallery) find the director through this group instead of a class scan.
	add_to_group(&"feel_director")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_now = _clock()
	_load_events()
	vfx = VfxLibrary.new()
	vfx.name = "Vfx"
	add_child(vfx)
	rumble = RumbleMixer.new()
	rumble.name = "Rumble"
	add_child(rumble)
	screen = ScreenFx.new()
	screen.name = "ScreenFx"
	add_child(screen)
	Feel.event_with_actors_requested.connect(play)


## Applies the row `event`. `actors` are the nodes a LOCAL hit-stop belongs to (Feel.play's 4th
## argument). Returns false when the id is unknown or the per-id cooldown dropped it.
func play(event: StringName, at: Vector3 = Vector3.INF, strength: float = 1.0,
		actors: Array = []) -> bool:
	_now = _clock()
	var ev := _events.get(event) as FeelEvent
	if ev == null:
		if not _warned.has(event):
			_warned[event] = true
			push_warning("FeelDirector: no FeelEvent for id '%s' (expected %s%s.tres)" % [event, EVENTS_DIR, event])
		return false
	# The victim's own hold is not a screen effect: it fires even when the row's cooldown drops the
	# visuals (a salvo that kills six in one frame still holds all six) and distance never shortens it.
	if ev.hitstop_kind == FeelEvent.Stop.LOCAL:
		Feel.local_hit_stop(actors, ev.hitstop_seconds)
	if ev.cooldown > 0.0 and _now - float(_last_played.get(event, -1000.0)) < ev.cooldown:
		return false
	_last_played[event] = _now
	var s := clampf(strength, 0.0, 4.0)
	var f := falloff_factor(ev, at)
	var pos := at if at.is_finite() else _camera_pos()
	_fp = _first_person()
	vfx.set_first_person(_fp)
	_hitstop(ev, f, actors)
	_camera(ev, s * f)
	_screen(ev, s * f)
	_time(ev, s, f)
	_world(ev, pos, s)
	_afterimages(ev)
	_audio(ev, pos, s)
	if ev.rumble_ms > 0:
		Feel.rumble(ev.rumble_weak * s * f, ev.rumble_strong * s * f, float(ev.rumble_ms) / 1000.0)
	_played += 1
	event_played.emit(event, at, s)
	return true


## clamp(1 - d / falloff, 0, 1) from the active camera (FEEL.md header). 1.0 without a falloff or
## without a camera (tests, cutscenes).
func falloff_factor(ev: FeelEvent, at: Vector3) -> float:
	if ev == null or ev.falloff <= 0.0 or not at.is_finite():
		return 1.0
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return 1.0
	return clampf(1.0 - cam.global_position.distance_to(at) / ev.falloff, 0.0, 1.0)


## Seconds of LOCAL hit-stop for `id`, so the caller can run Feel.local_hit_stop(actors, s).
func hitstop_seconds(id: StringName) -> float:
	var ev := _events.get(id) as FeelEvent
	if ev == null or ev.hitstop_kind != FeelEvent.Stop.LOCAL:
		return 0.0
	return ev.hitstop_seconds


func event(id: StringName) -> FeelEvent:
	return _events.get(id) as FeelEvent


func has_event(id: StringName) -> bool:
	return _events.has(id)


func event_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _events:
		out.append(id)
	return out


func played_count() -> int:
	return _played


func warned_unknown() -> int:
	return _warned.size()


func reset_rate_limits() -> void:
	_last_played.clear()
	_last_global = -1000.0
	_last_slow = -1000.0


## GLOBAL rows go through core (rate-limited there). A `budgeted` row that the budget or the
## distance rule refuses gives the victim its own stop instead, so the kill still lands without the
## world stopping (FEEL.md:43, "local if another G fired < 2 s ago").
func _hitstop(ev: FeelEvent, f: float, actors: Array) -> void:
	if ev.hitstop_kind != FeelEvent.Stop.GLOBAL or ev.hitstop_seconds <= 0.0:
		return
	if ev.budgeted and (f < ev.budget_falloff or _now - _last_global < GLOBAL_BUDGET):
		Feel.local_hit_stop(actors, ev.hitstop_seconds)
		return
	# A row attenuated to zero (a kill 200 m away, past its falloff) must not even reach core: a 0 s
	# request is a no-op there but would still spend the 150 ms / 3-per-second global budget and drop
	# a nearby kill_large's freeze instead.
	if ev.hitstop_seconds * f <= 0.0:
		return
	if not Feel.hit_stop(ev.hitstop_seconds * f, HITSTOP_SCALE):
		Feel.local_hit_stop(actors, ev.hitstop_seconds)
		return
	if ev.budgeted:
		_last_global = _now


func _camera(ev: FeelEvent, s: float) -> void:
	if ev.trauma > 0.0:
		Feel.shake(ev.trauma * s * (FP_SHAKE if _fp else 1.0))
	if ev.kick_deg > 0.0:
		var dir := ev.kick_dir if ev.kick_dir.length_squared() > 0.001 else Vector3.UP
		Feel.kick(ev.kick_deg * s, _kick_dir(dir), ev.kick_seconds)
	if is_zero_approx(ev.fov_delta):
		return
	var deg := clampf(ev.fov_delta, -MAX_FOV, MAX_FOV) * (FP_FOV if _fp else 1.0)
	Feel.fov_kick(deg, ev.fov_seconds)


func _screen(ev: FeelEvent, s: float) -> void:
	if ev.flash_color.a > 0.0 and ev.flash_frames > 0:
		Feel.flash(Color(ev.flash_color, ev.flash_color.a * s), ev.flash_seconds())
	var d := ev.post_seconds
	if ev.uses_post(&"chromatic") and ev.chromatic_px > 0.0:
		Feel.post(&"chromatic", ev.chromatic_px * s, d)
	if ev.uses_post(&"radial_blur") and ev.radial_blur > 0.0:
		Feel.post(&"radial_blur", ev.radial_blur * s, d)
	if ev.uses_post(&"vignette") and ev.vignette > 0.0:
		# The tint is per row: a damage vignette is blood red, overdrive_ignite's rim is gold.
		screen.set_vignette_color(ev.vignette_color)
		Feel.post(&"vignette", ev.vignette * s, d)
	if ev.uses_post(&"speed_lines") and ev.speed_lines > 0.0:
		Feel.post(&"speed_lines", ev.speed_lines * s, d)
	if ev.uses_post(&"desaturate") and ev.desaturate > 0.0:
		Feel.post(&"desaturate", ev.desaturate * s, d)
	if ev.impact_frames > 0:
		Feel.post(&"impact_bw", IMPACT_BW * s, float(ev.impact_frames) * FeelEvent.FRAME)


func _time(ev: FeelEvent, s: float, f: float) -> void:
	if not ev.has_slow_mo():
		return
	if ev.budgeted:
		# FEEL.md:43: at most one slow-mo per 6 s, and none at all for a kill past half its falloff
		# (the shake, the flash and the fireball still play, so a distant kill reads as a pop).
		if f < ev.budget_falloff or _now - _last_slow < SLOW_BUDGET:
			return
		_last_slow = _now
	Feel.slow_mo(ev.slow_scale, ev.slow_seconds * maxf(s, 0.25), 0.05, 0.2, ev.slow_witch)


## Queues the row's afterimages of the player's model, spread over the dash / dodge arc so each
## ghost catches its own pose. No player (or a player with no model) is silent, not an error: the
## gallery, the tests and the enemies' probes all play these rows without a hero.
func _afterimages(ev: FeelEvent) -> void:
	if ev.ghosts <= 0 or _ghost_source() == null:
		return
	for i in ev.ghosts:
		_ghost_jobs.append({"at": _now + float(i) * ev.ghost_spread, "life": ev.ghost_life})


## The model the ghosts copy: `Game.player.model()` (player_mech.gd). Null when there is no hero.
func _ghost_source() -> Node3D:
	var player := Game.player as Node
	if player == null or not is_instance_valid(player) or not player.has_method(&"model"):
		return null
	return player.call(&"model") as Node3D


func _process(_delta: float) -> void:
	if _ghost_jobs.is_empty():
		return
	_now = _clock()
	var due: Array[Dictionary] = []
	var kept: Array[Dictionary] = []
	for job in _ghost_jobs:
		(due if float(job["at"]) <= _now else kept).append(job)
	_ghost_jobs = kept
	var source := _ghost_source()
	if source == null:
		_ghost_jobs.clear()
		return
	for job in due:
		vfx.afterimage(source, float(job["life"]))


## Particles, rings, lights and decals at the event position.
func _world(ev: FeelEvent, pos: Vector3, s: float) -> void:
	var scale := ev.vfx_scale * maxf(s, 0.25)
	for i in ev.vfx.size():
		var kind := ev.vfx[i]
		var delay := ev.vfx_delays[i] if i < ev.vfx_delays.size() else 0.0
		if delay > 0.0:
			vfx.queue(kind, pos, DEFAULT_NORMAL, scale, delay)
		elif kind == &"shockwave_ring":
			vfx.spawn_ring(pos, DEFAULT_NORMAL, ev.ring_radius * maxf(s, 0.25), ev.ring_seconds, ev.ring_color)
		else:
			vfx.spawn(kind, pos, DEFAULT_NORMAL, scale)
	if ev.decal != &"":
		vfx.decals.add(ev.decal, pos, DEFAULT_NORMAL, scale)
	if ev.light_color.a > 0.0 and ev.light_frames > 0:
		vfx.flash_light(pos, Color(ev.light_color, 1.0), ev.light_energy * s,
				ev.light_range * scale, float(ev.light_frames))


func _audio(ev: FeelEvent, pos: Vector3, s: float) -> void:
	for id in ev.audio:
		Audio.play(id, pos, 0.0 if s >= 0.5 else -6.0)


## Loads every row once at boot; a row that fails to load is an error, never a silent skip.
## ResourceLoader.list_directory(), NOT DirAccess: an exported .app stores each row as
## `*.tres.remap` (or packs it into a .pck), so DirAccess sees no `.tres` at all and the shipped
## build would load zero feel events — no hit-stop, no flash, no VFX. list_directory answers the
## resource paths either way (Godot 4.4+).
func _load_events() -> void:
	var files := ResourceLoader.list_directory(EVENTS_DIR)
	if files.is_empty():
		push_error("FeelDirector: %s lists no resources (no FEEL table)" % EVENTS_DIR)
		return
	for entry in files:
		if not entry.ends_with(".tres") and not entry.ends_with(".res"):
			continue
		var path := EVENTS_DIR.path_join(entry)
		var res := ResourceLoader.load(path)
		var ev := res as FeelEvent
		if ev == null:
			push_error("FeelDirector: %s is not a FeelEvent (got %s)" % [path, res])
			continue
		if ev.id == &"":
			ev.id = StringName(entry.get_basename())
		if _events.has(ev.id):
			push_error("FeelDirector: duplicate FeelEvent id '%s' in %s" % [ev.id, path])
		_events[ev.id] = ev


## First person is a camera-rig property; polled at most twice a second (it never changes mid-frame).
func _first_person() -> bool:
	if _now - _fp_checked < 0.5:
		return _fp
	_fp_checked = _now
	var rig := Game.camera_rig
	_fp = rig != null and rig.has_method(&"is_first_person") and bool(rig.call(&"is_first_person"))
	return _fp


## A row's kick_dir is camera-relative (x right, y up, z back) so "recoil up" and "kick opposite the
## dash" work whatever way the mech faces; the camera rig receives a world direction.
func _kick_dir(local: Vector3) -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return local.normalized()
	return (cam.global_basis * local.normalized()).normalized()


func _camera_pos() -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	return cam.global_position if cam != null else Vector3.ZERO


## Per-row cooldowns are "seconds of real time" (feel_event.gd), so they run on the game clock —
## the same one Feel.hit_stop's own limiter uses. A wall clock would shrink them under movie capture.
func _clock() -> float:
	return Feel.real_now()

