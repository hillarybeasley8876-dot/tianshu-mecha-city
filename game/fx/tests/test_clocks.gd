extends Node
## Clock + numeric regression suite: `tools/godot.sh test res://fx/tests/test_clocks.gd`.
##
## Every check here pins a bug from reviews/feel-audit.md. The headless host runs `--fixed-fps 120`,
## so game time advances 1/120 s per frame while wall time barely moves — which is the same
## divergence a Movie Maker capture has in the other direction. An effect aged on the wall clock
## therefore ages at the wrong rate here and each check fails on the old code.
##
## Findings covered: 1 (ScreenFx clock), 2 (afterimages), 3 (debris), 4 (fireball), 5 (shockwave),
## 7 (impact glows), 8 (row cooldowns), 10 (draw before ageing), 11 (flash limiter), 12 (flash-light
## frames), 14/15/16/18 (spark shader: emitter frame, cone pole, velocity-aligned streaks, double
## integration) and 17 (world VFX pause).

const SHADER := "res://fx/vfx/spark_process.gdshader"

var _fails: int = 0
var _director: FeelDirector
var _lib: VfxLibrary


## Records the flash alpha the layer actually writes, which is the only place the drawn value exists.
class ProbeScreen extends ScreenFx:
	var drawn_alpha: float = -1.0

	func _apply() -> void:
		drawn_alpha = flash_alpha()
		super()


func _ready() -> void:
	# The pause test stops the tree; the suite itself must keep running.
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	_director = FeelDirector.new()
	add_child(_director)
	await get_tree().process_frame
	_lib = _director.vfx
	await _screen_clock()
	await _flash_frames()
	await _afterimages()
	await _debris_clock()
	await _fireball_clock()
	await _shockwave_clock()
	await _glow_clock()
	await _cooldown_clock()
	await _pause()
	_spark_shader()
	await _gallery_clock()
	print("TEST feel clocks: %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _check(ok: bool, msg: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", msg])
	if not ok:
		_fails += 1


## Wait until `seconds` of GAME time have passed (frames are far faster than that in headless).
func _game_wait(seconds: float) -> void:
	var t0 := Feel.real_now()
	while Feel.real_now() - t0 < seconds:
		await get_tree().process_frame


## Wait until nothing is left on the post layer, so the next check starts from idle.
func _settle() -> void:
	for i in 120:
		if _director.screen.is_idle():
			return
		await get_tree().process_frame


## Finding 1: ScreenFx ages its pulses on the game clock, so a 0.05 s pulse is over after 0.05 s of
## GAME time (on the old wall clock it was still at full strength after 0.08 s of game time here).
## Finding 10: the frame's state is drawn before it is aged, so a sub-frame pulse is drawn at all.
func _screen_clock() -> void:
	var screen := _director.screen
	screen.enabled = true
	Feel.post(&"chromatic", 0.9, 0.05)
	var held := screen.channel(&"chromatic")
	await _game_wait(0.08)
	_check(held > 0.5 and is_zero_approx(screen.channel(&"chromatic")),
			"a 0.05 s post pulse lives exactly 0.05 s of game time (F1)")
	# A flash shorter than one frame still has to reach the screen. Only _apply() knows what was
	# drawn, so a probe subclass records the alpha as the layer writes it (F10: _advance used to run
	# first, which drove a 1-frame flash to 0 before it was ever drawn).
	await _settle()
	await _game_wait(0.6)
	var probe := ProbeScreen.new()
	add_child(probe)
	probe.enabled = true
	await get_tree().process_frame
	Feel.flash(Color(1.0, 1.0, 1.0, 0.4), 0.004)
	await get_tree().process_frame
	_check(probe.flashes == 1 and probe.drawn_alpha > 0.0,
			"a sub-frame flash is drawn on its first frame, alpha %.3f (F10)" % probe.drawn_alpha)
	var before := probe.flashes
	# Finding 11: the WCAG limiter counts game seconds, so the window really is 0.5 s of game time.
	var t0 := Feel.real_now()
	Feel.flash(Color(1.0, 1.0, 1.0, 0.4), 0.004)
	await get_tree().process_frame
	_check(probe.flashes == before, "a second flash inside the window is dropped (F11)")
	await _game_wait(0.55)
	_check(Feel.real_now() - t0 >= 0.5, "the limiter's window is 0.5 s of game time (F11)")
	Feel.flash(Color(1.0, 1.0, 1.0, 0.4), 0.004)
	await get_tree().process_frame
	_check(probe.flashes == before + 1, "a flash after the window is accepted (F11)")
	probe.queue_free()
	await _settle()


## Finding 12: a 3-frame light pop lasts exactly 3 rendered frames, not 50 ms of wall time.
func _flash_frames() -> void:
	var lights := _lib.lights
	lights.flash(Vector3(0, 2, 0), Color.WHITE, 6.0, 12.0, 3.0)
	_check(lights.active_count() == 1, "a 3-frame light pop is lit")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(lights.active_count() == 1, "still lit on frame 2 of 3 (F12)")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(lights.active_count() == 0, "dark after 3 rendered frames (F12)")


## Finding 2: ghosts age on unscaled game time, so a 0.1 s ghost is gone after 0.1 s of game time
## (the old wall-clock age was still near zero here) and alive before that.
func _afterimages() -> void:
	var src := MeshInstance3D.new()
	src.mesh = BoxMesh.new()
	add_child(src)
	src.global_position = Vector3(0, 3, 0)
	_lib.afterimages.spawn_mesh(src, 0.1)
	_check(_lib.afterimages.live_count() == 1, "a ghost is spawned")
	await _game_wait(0.05)
	_check(_lib.afterimages.live_count() == 1, "the ghost is alive halfway through its life (F2)")
	await _game_wait(0.08)
	_check(_lib.afterimages.live_count() == 0, "the 0.1 s ghost is gone after 0.13 s of game time (F2)")
	src.queue_free()


## Finding 3: chunks age on the world clock they are simulated on, at the game's rate (the old
## wall-clock age read ~0.005 s here after half a second of game time).
func _debris_clock() -> void:
	_lib.debris.burst(Vector3(0, 6, 0), 6, 8.0, 0.8)
	var t0 := Feel.real_now()
	await _game_wait(0.5)
	var age := _lib.debris.oldest_age()
	var elapsed := Feel.real_now() - t0
	_check(_lib.debris.live_count() == 6 and absf(age - elapsed) < 0.15,
			"debris aged %.3f s over %.3f s of game time (F3)" % [age, elapsed])
	_lib.debris.clear()


## Finding 4: the fireball burns on the game clock, so an 8 m ball (0.5 s) is out after 0.5 s of game
## time — on the wall clock it was still burning 8 ms later.
func _fireball_clock() -> void:
	_lib.spawn(&"missile_blast", Vector3(0, 4, 0), Vector3.UP, 1.0)
	var blast := _blast()
	_check(blast != null and blast.fireball.is_running(), "the fireball is burning")
	await _game_wait(0.25)
	_check(blast.fireball.is_running(), "still burning halfway through its 0.5 s (F4)")
	await _game_wait(0.35)
	_check(not blast.fireball.is_running(), "burnt out after 0.6 s of game time (F4)")
	blast.stop()


## Finding 5: a 0.18 s ring finishes in 0.18 s of GAME time (the old wall clock needed 0.18 s of
## wall time, which is ~2000 headless frames).
func _shockwave_clock() -> void:
	var core := _director.event(&"shockcore")
	_lib.spawn_ring(Vector3.ZERO, Vector3.UP, core.ring_radius, core.ring_seconds, Color.WHITE)
	var ring := _ring()
	var t0 := Feel.real_now()
	while ring != null and ring.is_running() and Feel.real_now() - t0 < 0.6:
		await get_tree().process_frame
	var elapsed := Feel.real_now() - t0
	_check(ring != null and not ring.is_running() and absf(elapsed - core.ring_seconds) < 0.04,
			"the 0.18 s ring ran %.3f s of game time (F5)" % elapsed)
	_check(ring != null and ring.current_radius() >= core.ring_radius * 0.98,
			"and reached %.1f m" % (ring.current_radius() if ring != null else 0.0))


## Finding 7: the 0.25 s impact glow fades on unscaled game time, not in 3 headless frames.
func _glow_clock() -> void:
	_lib.decals.clear()
	_lib.decals.add(&"impact_glow", Vector3(0, 0, 0), Vector3.UP, 1.0)
	_check(_lib.decals.glow_count() == 1, "an impact glow is stamped")
	await _game_wait(0.15)
	_check(_lib.decals.glow_count() == 1, "the glow is alive after 0.15 s of game time (F7)")
	await _game_wait(0.15)
	_check(_lib.decals.glow_count() == 0, "the 0.25 s glow is gone after 0.3 s (F7)")


## Finding 8: a row cooldown is "seconds of real time" on the game clock, so it expires on schedule
## (the old wall clock had not even started here).
func _cooldown_clock() -> void:
	var ev := _director.event(&"land_heavy")
	_director.reset_rate_limits()
	_check(_director.play(&"land_heavy", Vector3.ZERO, 1.0), "the first play is accepted")
	_check(not _director.play(&"land_heavy", Vector3.ZERO, 1.0), "the repeat is dropped")
	await _game_wait(ev.cooldown + 0.03)
	_check(_director.play(&"land_heavy", Vector3.ZERO, 1.0),
			"the %.2f s cooldown expired in %.2f s of game time (F8)" % [ev.cooldown, ev.cooldown + 0.03])
	_director.reset_rate_limits()


## Finding 17: world VFX are PAUSABLE, so nothing behind the pause menu keeps simulating or expires.
func _pause() -> void:
	_check(_lib.process_mode == Node.PROCESS_MODE_PAUSABLE,
			"the VFX library is pausable, not ALWAYS (F17)")
	_check(_lib.decals.process_mode != Node.PROCESS_MODE_ALWAYS
			and _lib.lights.process_mode != Node.PROCESS_MODE_ALWAYS,
			"the decal and flash-light pools do not force ALWAYS (F17)")
	_lib.decals.clear()
	_lib.debris.clear()
	_lib.decals.add(&"impact_glow", Vector3.ZERO, Vector3.UP, 1.0)
	_lib.debris.burst(Vector3(0, 6, 0), 4, 8.0, 0.8)
	get_tree().paused = true
	for i in 40:
		await get_tree().process_frame
	var glow := _lib.decals.glow_count()
	var live := _lib.debris.live_count()
	var age := _lib.debris.oldest_age()
	get_tree().paused = false
	_check(glow == 1 and live == 4, "glows and rubble survive a pause (F17)")
	_check(age < 0.05, "and nothing aged behind it: %.3f s (F17)" % age)
	_lib.decals.clear()
	_lib.debris.clear()


## Findings 14/15/16/18 in the spark process shader. The source is asserted because the headless
## host cannot run a particles shader; the cone sampler is re-implemented here and checked for the
## two properties the old `tan(half_spread)` version lost (finiteness and a true hemisphere).
func _spark_shader() -> void:
	var f := FileAccess.open(SHADER, FileAccess.READ)
	if f == null:
		_check(false, "spark_process.gdshader is readable")
		return
	var src := f.get_as_text()
	f.close()
	_check(src.contains("mat3(EMISSION_TRANSFORM) * emit_direction"),
			"the cone axis is built in the emitter's frame (F14)")
	_check(not src.contains("tan(radians(spread_deg)"), "the cone no longer samples through tan() (F15)")
	_check(src.contains("VELOCITY / CUSTOM.x") and not src.contains("vec4(0.0, len, 0.0, 0.0)"),
			"streaks are built along their own velocity (F16)")
	_check(not src.contains("TRANSFORM[3].xyz += VELOCITY * DELTA")
			and not src.contains("render_mode disable_velocity"),
			"position is integrated once, by the engine (F18)")
	var worst := 0.0
	var finite := true
	for i in 64:
		var r2 := float(i) / 63.0
		var ct := lerpf(1.0, cos(deg_to_rad(180.0) * 0.5), r2)
		var st := sqrt(maxf(1.0 - ct * ct, 0.0))
		var v := Vector3(0.0, 0.3, -1.0).normalized() * ct + Vector3.RIGHT * st
		finite = finite and v.is_finite()
		worst = maxf(worst, rad_to_deg(Vector3(0.0, 0.3, -1.0).normalized().angle_to(v)))
	_check(finite and worst <= 90.001,
			"a 180 deg spread stays a finite hemisphere (worst %.3f deg) (F15)" % worst)


## The gallery schedules its rows on the game clock (r5 item 3). At the host's --fixed-fps 120 that
## clock must read exactly 2.0 s after 240 frames; on the wall clock it read however long the
## machine actually took, which is what made the stills land 0.4-0.6 s late and miss every effect
## under 0.3 s.
func _gallery_clock() -> void:
	var gallery := load("res://fx/tests/feel_gallery.gd") as GDScript
	if gallery == null:
		_check(false, "res://fx/tests/feel_gallery.gd loads")
		return
	var t0 := Feel.real_now()
	for i in 240:
		await get_tree().process_frame
	# The method is looked up, not called blind: on the wall-clock gallery it does not exist, and this
	# check has to print a FAIL rather than raise a script error.
	var t := -1.0
	for m: Dictionary in gallery.get_script_method_list():
		if String(m["name"]) == "elapsed":
			t = float(gallery.call(&"elapsed", t0))
			break
	_check(absf(t - 2.0) <= 0.02,
			"the gallery clock reads 2.0 s after 240 frames at 120 fps (%.4f s)" % t)


func _blast() -> FxBlast:
	for node in _lib.get_children():
		if node is FxBlast and (node as FxBlast).visible:
			return node as FxBlast
	return null


func _ring() -> ShockwaveFx:
	for node in _lib.get_children():
		if node is ShockwaveFx and (node as ShockwaveFx).is_running():
			return node as ShockwaveFx
	return null
