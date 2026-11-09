extends Node
## Feel unit tests: `tools/godot.sh test res://fx/tests/test_feel.gd`.
## Covers the brief's "Done when": every FEEL.md row has a resource, per-id rate limits, distance
## falloff, global hit-stop goes through core Feel, unknown ids warn once, and a stress frame
## (300 sparks + 40 blasts + 96 decals) stays under 8 ms of extra frame time.

const SPAWN_BUDGET_MS := 8.0
const STRESS_SPARKS := 300
const STRESS_BLASTS := 40
const STRESS_DECALS := 96
const IDLE_FRAMES := 30
const STRESS_FRAMES := 60

var _fails: int = 0
var _director: FeelDirector


func _ready() -> void:
	await get_tree().process_frame
	_director = FeelDirector.new()
	add_child(_director)
	await get_tree().process_frame
	await _table()
	_rate_limits()
	_falloff()
	await _hitstop()
	_unknown()
	await _flash_rate()
	await _screen_channels()
	await _flash_cap()
	await _settings_sliders()
	await _shockwave()
	_impact_vfx()
	_persistent_emitters()
	await _afterimages()
	await _stress()
	print("TEST feel: %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _check(ok: bool, msg: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", msg])
	if not ok:
		_fails += 1


## Every id in the FEEL.md table has fx/events/<id>.tres, and it only uses vfx kinds we can spawn.
func _table() -> void:
	var ids := FeelTable.ids()
	_check(ids.size() >= 40, "FEEL.md table parsed (%d ids)" % ids.size())
	var missing: PackedStringArray = []
	var bad_vfx: PackedStringArray = []
	for id in ids:
		var ev := _director.event(id)
		if ev == null:
			missing.append(String(id))
			continue
		for kind in ev.vfx:
			if not _kind_exists(kind):
				bad_vfx.append("%s:%s" % [id, kind])
		if ev.decal != &"" and not ev.decal in VfxLibrary.DECAL_KINDS:
			bad_vfx.append("%s:decal %s" % [id, ev.decal])
	_check(missing.is_empty(), "every FEEL.md id has a .tres (missing: %s)" % ", ".join(missing))
	_check(bad_vfx.is_empty(), "every vfx kind exists (bad: %s)" % ", ".join(bad_vfx))
	var loaded := _director.event_ids().size()
	_check(loaded == ids.size(), "loaded %d resources for %d table rows" % [loaded, ids.size()])
	# Packaging: the director lists fx/events/ through ResourceLoader, so the rows survive an export
	# (where they are *.tres.remap or packed). DirAccess found nothing there and shipped no feel.
	var listed := 0
	for entry in ResourceLoader.list_directory(FeelDirector.EVENTS_DIR):
		if entry.ends_with(".tres") or entry.ends_with(".res"):
			listed += 1
	_check(listed >= 44 and loaded >= 44,
			"ResourceLoader lists %d rows and the director loaded %d (export-safe)" % [listed, loaded])


## A row with a cooldown drops the second play inside the window and accepts it after.
func _rate_limits() -> void:
	var ev := _director.event(&"land_heavy")
	_check(ev != null and ev.cooldown > 0.0, "land_heavy has a cooldown")
	var first := _director.play(&"land_heavy", Vector3(0, 0, 0), 1.0)
	var second := _director.play(&"land_heavy", Vector3(0, 0, 0), 1.0)
	_check(first and not second, "cooldown drops the repeat play inside the window")
	_director.reset_rate_limits()
	_check(_director.play(&"land_heavy", Vector3(0, 0, 0), 1.0), "play accepted after reset_rate_limits")


## clamp(1 - d / falloff, 0, 1) against the active camera.
func _falloff() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.global_position = Vector3.ZERO
	var ev := _director.event(&"missile_hit")
	_check(ev != null and ev.falloff > 0.0, "missile_hit has a falloff radius")
	var near := _director.falloff_factor(ev, Vector3(0, 0, 10))
	var half := _director.falloff_factor(ev, Vector3(0, 0, ev.falloff * 0.5))
	var far := _director.falloff_factor(ev, Vector3(0, 0, ev.falloff * 2.0))
	_check(is_equal_approx(near, 1.0 - 10.0 / ev.falloff), "falloff at 10 m = %.3f" % near)
	_check(absf(half - 0.5) < 0.01, "falloff at half the radius = 0.5 (%.3f)" % half)
	_check(is_zero_approx(far), "falloff beyond the radius = 0")
	_check(is_equal_approx(_director.falloff_factor(_director.event(&"dash"), Vector3(0, 0, 500)), 1.0),
			"an event without falloff is full strength anywhere")
	cam.queue_free()


## GLOBAL rows call core Feel.hit_stop (time scale drops); LOCAL rows do not touch time at all.
func _hitstop() -> void:
	Engine.time_scale = 1.0
	_director.play(&"melee_heavy", Vector3.ZERO, 1.0)
	_check(is_equal_approx(Engine.time_scale, 1.0), "a LOCAL hit-stop row leaves Engine.time_scale alone")
	_check(absf(_director.hitstop_seconds(&"melee_heavy") - 0.15) < 0.001,
			"hitstop_seconds(melee_heavy) = 0.15 for the caller")
	_check(is_zero_approx(_director.hitstop_seconds(&"kill_large")),
			"hitstop_seconds() is 0 for a GLOBAL row (the director fires it)")
	_director.reset_rate_limits()
	_director.play(&"kill_large", Vector3.ZERO, 1.0)
	await get_tree().process_frame   ## core Feel applies the time scale in its own _process
	_check(Engine.time_scale <= 0.06, "a GLOBAL row freezes the game through core (scale %.2f)" % Engine.time_scale)
	for i in 30:
		await get_tree().process_frame
	Engine.time_scale = 1.0


func _unknown() -> void:
	var before := _director.warned_unknown()
	var a := _director.play(&"not_a_feel_event", Vector3.ZERO)
	var b := _director.play(&"not_a_feel_event", Vector3.ZERO)
	_check(not a and not b, "an unknown id never plays")
	_check(_director.warned_unknown() - before == 1, "an unknown id warns exactly once (2 plays)")


## WCAG: at most 2 full-screen flashes per second, so a burst of flash rows is thinned out.
func _flash_rate() -> void:
	# Game seconds, not wall time: the limiter counts Feel.real_now() and the headless test host runs
	# --fixed-fps, so frames fly by far faster than wall time and 0.5 s of it is ~60 frames.
	var until := Feel.real_now() + 0.6
	while Feel.real_now() < until:
		await get_tree().process_frame
	var before := _director.screen.flashes
	for i in 6:
		Feel.flash(Color(1, 1, 1, 0.4), 0.05)
	_check(_director.screen.flashes - before == 1,
			"6 flashes in one frame collapse to 1 (rate limit 2/s)")




## A stress frame must not cost more than 8 ms of extra time, and the pools must stay capped.
## Every post channel reaches the shader, the 1-2 frame B/W impact frame included (a screenshot of a
## 33 ms window is a lottery; the channel value is not). The clamps from the r1 review are checked
## here too: the flash never washes the screen and the radial blur stays an edge effect.
func _screen_channels() -> void:
	var screen := _director.screen
	screen.enabled = true
	Feel.post(&"impact_bw", 0.85, 0.2)
	Feel.post(&"vignette", 0.6, 0.4)
	Feel.post(&"chromatic", 3.0, 0.4)
	Feel.post(&"radial_blur", 0.2, 0.4)
	Feel.post(&"speed_lines", 1.0, 0.4)
	Feel.post(&"desaturate", 0.6, 0.4)
	await get_tree().process_frame
	_check(screen.channel(&"impact_bw") > 0.5, "the B/W impact frame reaches the shader (%.2f)"
			% screen.channel(&"impact_bw"))
	_check(screen.channel(&"vignette") > 0.5, "the damage vignette reaches the shader")
	_check(screen.channel(&"chromatic") > 2.0, "chromatic aberration reaches the shader in px")
	_check(screen.channel(&"radial_blur") <= ScreenFx.RADIAL_MAX + 0.0001,
			"radial blur is clamped to %.2f at the edges" % ScreenFx.RADIAL_MAX)
	_check(screen.channel(&"speedlines") > 0.9, "speed lines reach the shader")
	_check(not screen.is_idle(), "the post layer is visible while channels are live")
	# Speed lines are driven by the player's speed and stay off below SPEED_MIN.
	screen.set_speed(10.0)
	_check(screen.channel(&"speedlines") > 0.5, "a timed speed-line pulse survives a slow player")
	screen.set_speed(0.0)
	await get_tree().process_frame


## A full-screen flash is capped at FLASH_MAX_ALPHA (juice-impact rule 12: no washes).
func _flash_cap() -> void:
	var screen := _director.screen
	Feel.flash(Color(1.0, 1.0, 1.0, 1.0), 0.5)
	await get_tree().process_frame
	_check(screen.flash_alpha() <= ScreenFx.FLASH_MAX_ALPHA + 0.0001,
			"a full-strength flash is capped at %.2f alpha" % ScreenFx.FLASH_MAX_ALPHA)


## The accessibility Settings keys the lead added reach the post stack: each slider zeroes its own
## channel, and photosensitive mode kills the B/W impact frame and caps the flash at 0.1 alpha.
func _settings_sliders() -> void:
	var screen := _director.screen
	for key: StringName in [&"fx_chromatic", &"fx_radial_blur", &"fx_speed_lines", &"fx_flash"]:
		Settings.set_value(key, 0.0)
	Feel.post(&"chromatic", 3.0, 0.4)
	Feel.post(&"radial_blur", 0.2, 0.4)
	Feel.post(&"speed_lines", 1.0, 0.4)
	Feel.post(&"impact_bw", 0.85, 0.4)
	Feel.flash(Color(1.0, 1.0, 1.0, 1.0), 0.4)
	await get_tree().process_frame
	_check(is_zero_approx(screen.channel(&"chromatic")), "Settings fx_chromatic = 0 mutes chromatic")
	_check(is_zero_approx(screen.channel(&"radial_blur")), "Settings fx_radial_blur = 0 mutes blur")
	_check(is_zero_approx(screen.channel(&"speedlines")), "Settings fx_speed_lines = 0 mutes lines")
	_check(is_zero_approx(screen.channel(&"impact_bw")), "Settings fx_flash = 0 mutes the impact frame")
	_check(is_zero_approx(screen.flash_alpha()), "Settings fx_flash = 0 mutes the flash")
	for key: StringName in [&"fx_chromatic", &"fx_radial_blur", &"fx_speed_lines", &"fx_flash"]:
		Settings.set_value(key, 1.0)
	# Photosensitive mode: no B/W frame at all, and the flash can never exceed 0.1 alpha.
	Settings.set_value(&"photosensitive", true)
	Feel.post(&"impact_bw", 0.85, 0.4)
	Feel.flash(Color(1.0, 1.0, 1.0, 1.0), 0.4)
	await get_tree().process_frame
	_check(is_zero_approx(screen.channel(&"impact_bw")), "photosensitive mode disables the B/W frame")
	_check(screen.flash_alpha() <= ScreenFx.PHOTO_FLASH_ALPHA + 0.0001,
			"photosensitive mode caps the flash at %.2f alpha (%.3f)"
			% [ScreenFx.PHOTO_FLASH_ALPHA, screen.flash_alpha()])
	Settings.set_value(&"photosensitive", false)
	await get_tree().process_frame


## The FEEL rows' published shockwave numbers: shockcore's fresnel shell reaches 32 m in 0.18 s and
## collapse's implosion ring 20 m (r2 MUST-FIX 5). Checked against the growth curve and against a
## ring actually driven to its peak on the real clock.
func _shockwave() -> void:
	var core := _director.event(&"shockcore")
	var collapse := _director.event(&"collapse")
	_check(core != null and is_equal_approx(core.ring_radius, 32.0) and is_equal_approx(
			core.ring_seconds, 0.18), "shockcore is a 32 m shell in 0.18 s")
	_check(collapse != null and is_equal_approx(collapse.ring_radius, 20.0),
			"collapse implodes through a 20 m ring")
	_check(is_equal_approx(ShockwaveFx.radius_at(32.0, 1.0), 32.0),
			"the ring front reaches its full radius at the end of its life")
	_check(ShockwaveFx.radius_at(32.0, 0.5) > 22.0,
			"the front is past 70 %% of its radius halfway through (%.1f m at p=0.5)"
			% ShockwaveFx.radius_at(32.0, 0.5))
	var lib := _director.vfx
	lib.spawn_ring(Vector3.ZERO, Vector3.UP, core.ring_radius, core.ring_seconds, Color.WHITE)
	var ring := _live_ring(lib)
	# Game seconds, not wall time: the ring expands on Feel.real_now() and the headless host runs
	# --fixed-fps, so frames fly by far faster than wall time (see tests/test_clocks.gd).
	var t0 := Feel.real_now()
	while ring != null and ring.is_running() and Feel.real_now() - t0 < 0.5:
		await get_tree().process_frame
	var elapsed := Feel.real_now() - t0
	_check(ring != null and ring.current_radius() >= 31.5,
			"a live shockcore ring measured %.1f m after %.3f s" % [ring.current_radius() if ring != null
			else 0.0, elapsed])


## FEEL.md:31-32 — the dash and the perfect dodge each leave three afterimages. A stand-in player
## whose model moves between the spawns proves they are spread along the motion (three on one pose
## is the Overdrive r2 blob), and each ghost carries its source's `layers`, so first person hides it
## with the hero's body instead of drawing it over the cockpit.
func _afterimages() -> void:
	var pool := _director.vfx.afterimages
	var model := MeshInstance3D.new()
	model.name = "StandInModel"
	model.mesh = BoxMesh.new()
	model.layers = 1 << 5   # a layer the default camera does not draw, like the first-person cull
	var player := Node3D.new()
	player.name = "StandInPlayer"
	player.set_script(load("res://fx/tests/stand_in_player.gd"))
	player.add_child(model)
	add_child(player)
	Game.player = player
	await get_tree().process_frame
	for id: StringName in [&"dash", &"perfect_dodge"]:
		# get(), not a direct read: on a build with no afterimage column this must print a FAIL rather
		# than raise a script error that hides the rest of the table.
		var want := -1
		var ev := _director.event(id)
		if ev != null:
			var column: Variant = ev.get(&"ghosts")
			if column != null:
				want = int(column)
		_check(want == 3, "%s asks for 3 afterimages (FEEL.md), got %d" % [id, want])
		_hide_ghosts(pool)
		_director.reset_rate_limits()
		while Engine.time_scale < 0.999:
			await get_tree().process_frame
		_director.play(id, Vector3.ZERO, 1.0)
		var seen: Array[Vector3] = []
		var layers_ok := true
		var most := 0
		var t0 := Feel.real_now()
		while Feel.real_now() - t0 < 0.5:
			player.global_position += Vector3(2.0, 0.0, 0.0)
			await get_tree().process_frame
			var live := _ghosts(pool)
			most = maxi(most, live.size())
			for g in live:
				if g.global_position not in seen:
					seen.append(g.global_position)
				layers_ok = layers_ok and g.layers == model.layers
		_check(most == 3, "%s leaves 3 live ghosts (%d)" % [id, most])
		_check(seen.size() == 3, "%s spreads them over 3 distinct positions (%d)" % [id, seen.size()])
		_check(layers_ok, "%s ghosts carry the source's layers" % id)
	# Nothing to ghost is silent, not an error.
	Game.player = null
	_director.reset_rate_limits()
	_check(_director.play(&"dash", Vector3.ZERO, 1.0), "a dash with no player still plays")
	await get_tree().process_frame
	_check(_ghosts(pool).is_empty(), "a dash with no player leaves no ghosts")
	player.queue_free()


## The pool's live ghosts, read straight off its children so this check also compiles against a
## build that has no afterimage support at all (the FAIL-before evidence run).
func _ghosts(pool: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in pool.get_children():
		var g := child as MeshInstance3D
		if g != null and g.visible and g.mesh != null:
			out.append(g)
	return out


func _hide_ghosts(pool: Node) -> void:
	for child in pool.get_children():
		var g := child as MeshInstance3D
		if g != null:
			g.visible = false
			g.mesh = null


## Spark bursts carry a contact flash and leave a hot glow decal; heavy hits get the cross flare.
func _impact_vfx() -> void:
	var lib := _director.vfx
	_check(lib.pool_size(&"impact_star") > 0, "impact_star (r2 SHOULD) is pooled")
	_check(lib.spawn(&"spark_bullet", Vector3(0, 1, 0), Vector3.UP, 1.0), "spark_bullet spawns")
	_check(lib.decals.glow_count() > 0, "a spark burst stamps a hot impact glow decal")
	var impact := _pooled(lib, &"spark_bullet") as FxImpact
	_check(impact != null and impact.pop != null, "spark_bullet is the streak + contact-flash composite")


func _live_ring(lib: VfxLibrary) -> ShockwaveFx:
	for node in lib.get_children():
		if node is ShockwaveFx and (node as ShockwaveFx).is_running():
			return node as ShockwaveFx
	return null


func _pooled(lib: VfxLibrary, kind: StringName) -> Node3D:
	for node in lib.get_children():
		if node is FxImpact and String(node.name).begins_with(String(kind)):
			return node as Node3D
	return null


## The continuous city/wreck emitters (r1 SHOULD) are handed out and returned, never spawned ad hoc.
func _persistent_emitters() -> void:
	var lib := _director.vfx
	var fire := lib.emitter(&"fire_loop", Vector3.ZERO, 1.0)
	var smoke := lib.emitter(&"smoke_column", Vector3(10, 0, 0), 2.0)
	_check(fire != null, "fire_loop hands out a pooled emitter")
	_check(smoke != null, "smoke_column hands out a pooled emitter")
	_check(lib.emitter(&"not_an_emitter", Vector3.ZERO) == null, "an unknown emitter kind returns null")
	if fire != null:
		lib.release_emitter(fire)
		_check(not fire.visible, "a released emitter is hidden again")
	if smoke != null:
		lib.release_emitter(smoke)


func _stress() -> void:
	var lib := _director.vfx
	var idle := await _avg_frame_ms(IDLE_FRAMES)
	var t0 := Time.get_ticks_usec()
	for i in STRESS_SPARKS:
		lib.spawn(&"spark_bullet", _ring(i), Vector3.UP, 1.0)
	for i in STRESS_BLASTS:
		lib.spawn(&"missile_blast", _ring(i), Vector3.UP, 1.0)
	for i in STRESS_DECALS:
		lib.decals.add(&"scorch", _ring(i), Vector3.UP, 1.0)
	var spawn_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var busy := await _avg_frame_ms(STRESS_FRAMES)
	_check(spawn_ms < SPAWN_BUDGET_MS,
			"%d sparks + %d blasts + %d decals spawn in %.2f ms" % [STRESS_SPARKS, STRESS_BLASTS,
			STRESS_DECALS, spawn_ms])
	_check(busy - idle < SPAWN_BUDGET_MS,
			"frame time %.3f ms loaded vs %.3f ms idle (extra %.3f ms)" % [busy, idle, busy - idle])
	_check(lib.pool_size(&"spark_bullet") == VfxPresets.pool_size(&"spark_bullet")
			and lib.active_count() <= _pool_total(),
			"pools stay capped after the burst (%d live instances)" % lib.active_count())
	_check(lib.decals.active_count() == DecalPool.MAX_DECALS, "the decal ring buffer holds %d"
			% DecalPool.MAX_DECALS)


func _pool_total() -> int:
	var n := 0
	for kind: StringName in VfxPresets.POOL:
		n += VfxPresets.pool_size(kind)
	return n


func _avg_frame_ms(frames: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in frames:
		await get_tree().process_frame
	return float(Time.get_ticks_usec() - t0) / 1000.0 / float(frames)


func _ring(i: int) -> Vector3:
	var a := float(i) * 0.7
	return Vector3(cos(a) * 25.0, float(i % 5), sin(a) * 25.0)


func _kind_exists(kind: StringName) -> bool:
	return VfxPresets.POOL.has(kind) or kind in VfxLibrary.DECAL_KINDS or kind == &"debris"


