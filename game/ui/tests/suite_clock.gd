class_name HudClockSuite
extends RefCounted
## Regressions for the HUD audit's numeric/clock findings (reviews/hud-audit.md). Each check fails on
## the code as it was before the fix, which is the point: the widget clocks must ignore the time scale,
## and a projected world point must land where the widget draws it.

static func run(h: HudTestHarness) -> void:
	await _projection_scale(h)
	await _unscaled_clock(h)
	await _world_clock(h)
	await _menu_clock(h)


## Audit #1 (high): `Camera3D.unproject_position` speaks root-canvas pixels (1920×1080 under the
## project's stretch) while the widgets draw inside a root Control scaled by `ui_scale`. project()
## used to return the canvas position unchanged, so every plate, lock diamond, telegraph and damage
## number landed at ui_scale × its true position.
static func _projection_scale(h: HudTestHarness) -> void:
	var target := Vector3(30.0, 8.0, -40.0)
	var canvas := h.camera.unproject_position(target)
	var view := h.camera.get_viewport().get_visible_rect().size
	h.data.ui_scale = 1.0
	var one := h.data.project(target) as Dictionary
	h.check((one["pos"] as Vector2).is_equal_approx(canvas),
			"at scale 1.0 the projection is the canvas position")
	h.data.ui_scale = 1.2
	var scaled := h.data.project(target) as Dictionary
	var got := scaled["pos"] as Vector2
	h.check(absf(got.x - canvas.x / 1.2) < 0.01 and absf(got.y - canvas.y / 1.2) < 0.01,
			"at scale 1.2 the projection is divided by the HUD scale (audit #1)")
	h.check(got.x < canvas.x and canvas.x > 0.0, "a scaled projection moves toward the origin")
	# The on-screen test stays in canvas space: the viewport rect is what defines "on screen", and
	# dividing by ui_scale maps that rect exactly onto the widgets' layout rect.
	var corner := Vector3.ZERO
	h.data.ui_scale = 1.0
	var inside := h.data.project(corner) as Dictionary
	h.data.ui_scale = 2.0
	var inside2 := h.data.project(corner) as Dictionary
	h.check(bool(inside["visible"]) == bool(inside2["visible"]),
			"the on-screen test does not change with the HUD scale")
	h.check((inside2["pos"] as Vector2).x < (inside["pos"] as Vector2).x,
			"a world point maps into the layout rect, not past it")
	# Behind the camera is still off screen whatever the scale. `global_basis.z` points backwards.
	var behind := h.camera.global_position + h.camera.global_basis.z * 50.0
	h.check(not bool((h.data.project(behind) as Dictionary)["visible"]),
			"a point behind the camera is never visible")
	h.check(view.x > 1.0, "the test camera has a real viewport rect")
	h.data.ui_scale = 1.0


## Audit #3 (medium): the base class used to hand every widget the time-scaled frame delta, so a
## hit-stop froze the HUD's pops and lifetimes and a slow-mo stretched them. The marker must expire on
## real seconds: under a 0.1× slow-mo the old code took ten times as long.
static func _unscaled_clock(h: HudTestHarness) -> void:
	var marker := h.widget(&"hit_marker")
	marker.call(&"flash", &"kill")            # 0.25 s lifetime
	Feel.slow_mo(0.1, 0.5, 0.0, 0.0)
	await h.settle(12)                        # 12 frames at 1/120 s = 0.1 s of real time
	h.check(float(marker.get(&"left")) > 0.0, "the kill marker is still up after 0.1 s")
	await h.settle(24)                        # 0.3 s of real time in total
	h.check(float(marker.get(&"left")) <= 0.0 and not marker.visible,
			"the kill marker expires on real seconds through a slow-mo (audit #3)")
	await _normal_speed(h)
	# And at normal speed it still runs for its authored lifetime, not for ever.
	marker.call(&"flash", &"normal")          # 0.08 s
	await h.settle(24)
	h.check(not marker.visible, "the normal marker still expires in 0.2 s of play")
	# Audit #4: the reload sweep is a Feel clock, so it advances by game time — a wall clock would run
	# about 4x fast under Movie Maker's 70 ms frames.
	var panel := h.widget(&"weapon")
	h.feed({"reloading": true})
	await h.settle()
	var a := float(panel.call(&"sweep_phase"))
	await h.settle(6)
	var b := float(panel.call(&"sweep_phase"))
	h.check(absf(b - a) < 0.2, "the reload sweep advances by game time, not wall time (audit #4)")
	h.feed({"reloading": false})


## Waits for Feel to put the time scale back to 1 so the next check measures normal play.
static func _normal_speed(h: HudTestHarness) -> void:
	for i in 240:
		if Engine.time_scale >= 1.0:
			return
		await h.host.get_tree().process_frame


## Audit #3's other half: world-anchored widgets opt back into the scaled clock, so a windup tell
## stays up exactly as long as the attack is winding up.
static func _world_clock(h: HudTestHarness) -> void:
	var tells := h.widget(&"telegraphs")
	h.check(bool(tells.call(&"world_clock")), "telegraphs run on the world clock")
	h.check(bool(h.widget(&"markers").call(&"world_clock")), "threat arrows run on the world clock")
	h.check(not bool(h.widget(&"hit_marker").call(&"world_clock")),
			"UI feedback runs on the unscaled clock")


## Audit #6 (low): the victory page's 用时 TIME used to add up the scaled delta, so every hit-stop was
## under-counted.
static func _menu_clock(h: HudTestHarness) -> void:
	var menus := h.menus()
	menus.close()
	var stats := menus.get(&"stats") as Dictionary
	var before := float(stats["time"])
	Feel.slow_mo(0.2, 0.6, 0.0, 0.0)
	await h.settle(60)                        # 0.5 s of real time, 0.1 s of scaled time
	var after := float(stats["time"])
	await _normal_speed(h)
	h.check(after - before > 0.3,
			"the run clock counts real seconds through a slow-mo (audit #6, got %.3f)" % (after - before))

