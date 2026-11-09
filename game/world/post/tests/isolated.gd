extends Node3D
## Minimal scene for measuring what the post stack itself costs (`world/post/tests/isolated.tscn`).
##
## The city is CPU-bound at 1600x900 (frame time 8 ms with the stack off and 8 ms with it on), so a
## whole-scene A/B cannot resolve the stack's GPU cost — and Metal reports 0 for GPU timings
## (godot-tech rule 2). With no city, no props and no scripts the frame is almost pure GPU, so the
## difference between the compositor attached and detached is this unit's real cost.
##
##   tools/godot.sh shot --scene=res://world/post/tests/isolated.tscn --out=iso --times=300 \
##     --env-only --post-iso
##
## Prints one ISOPERF line per pass and a final mean delta per quality preset.

const POST_SCENE := "res://world/post/post_stack.tscn"
const ENV_SCENE := "res://world/art/environment.tscn"
const WARM := 120
const SAMPLE := 180
const PASSES := 3

var post: PostStack


func _ready() -> void:
	post = (load(POST_SCENE) as PackedScene).instantiate() as PostStack
	post.name = "PostStack"
	add_child(post)
	var env := (load(ENV_SCENE) as PackedScene).instantiate()
	env.name = "ArtEnvironment"
	add_child(env)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 40.0, 120.0)
	cam.look_at(Vector3(0.0, 60.0, 0.0), Vector3.UP)
	cam.fov = 55.0
	cam.near = 0.05
	cam.far = 6000.0
	add_child(cam)
	cam.current = true
	_measure.call_deferred()


func _measure() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# The brief's budget is quoted at 1600x900; `tools/godot.sh shot --size` does not resize the root
	# viewport, so the window is set here and the reported size is printed back as evidence.
	get_window().size = Vector2i(1600, 900)
	get_window().content_scale_size = Vector2i(1600, 900)
	for i in 30:
		await get_tree().process_frame
	var vp := get_viewport()
	print("ISOPERF warm=%d sample=%d passes=%d viewport=%dx%d"
			% [WARM, SAMPLE, PASSES, int(vp.get_visible_rect().size.x),
			int(vp.get_visible_rect().size.y)])
	var on_total := 0.0
	var off_total := 0.0
	for pass_i in PASSES:
		var on := await _timed(true)
		var off := await _timed(false)
		on_total += on
		off_total += off
		print("ISOPERF pass=%d post_on=%.3f ms post_off=%.3f ms delta=%.3f ms"
				% [pass_i, on, off, on - off])
	print("ISOPERF mean post_on=%.3f ms post_off=%.3f ms delta=%.3f ms (budget high 2.5, low 0.8)"
			% [on_total / PASSES, off_total / PASSES, (on_total - off_total) / PASSES])
	get_tree().quit(0)


func _timed(on: bool) -> float:
	post.set_active(on)
	for i in WARM:
		await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	for i in SAMPLE:
		await get_tree().process_frame
	return float(Time.get_ticks_usec() - t0) / 1000.0 / float(SAMPLE)
