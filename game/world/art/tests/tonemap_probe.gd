extends Node3D
## city-art r15 — the TONEMAP PROBE. One small render that measures the whole display chain.
##
## "Why does my blue come out magenta" is a question about the transfer function of
## AgX -> the post grade LUT -> sRGB, and answering it by A/B-ing a city render costs 4 minutes and a
## machine-wide slot. This renders a lattice of EXACT linear colours as unshaded quads (unshaded still
## goes through the tonemapper — it is a blit on the whole framebuffer, not a material feature) and
## writes the lattice next to the capture, so `tmp/city-art/r15/tonemap.py` can answer "what input
## colour lands on output hue H" offline, for any `--post-tune` row, in one 20-second run.
##
##   tools/godot.sh shot --scene=res://world/art/tests/tonemap_probe.tscn --out=tm --times=300 \
##     --post-tune=tonemap_agx_white:16.0
##   uv run --with numpy --with pillow python tmp/city-art/r15/tonemap.py tmp/city-art/r15/tm/tm.png

const OUT_REL := "tmp/city-art/r15/tm"
## The lattice's value axis. Geometric, because the interesting part of a tonemap is the bottom three
## stops, and linear spacing wastes half the quads on values that all clip to white.
const LEVELS: Array[float] = [0.004, 0.010, 0.022, 0.045, 0.090, 0.180, 0.380, 0.800, 1.700]
const COLS := 27          ## 9 * 3: the lattice is laid out as three 9x9 slices of the value cube
const CELL := 1.0
const WARM := 8

var _drew: bool = false


func _ready() -> void:
	var out := ArtRepo.at(OUT_REL)
	DirAccess.make_dir_recursive_absolute(out)
	_build_env()
	_build_grid()
	for i in 4:
		await get_tree().physics_frame
	await _frames(WARM)
	var img := await _grab()
	if img.save_png(out.path_join("tm.png")) != OK:
		push_error("tonemap_probe: cannot write tm.png")
	var f := FileAccess.open(out.path_join("lattice.json"), FileAccess.WRITE)
	if f == null:
		push_error("tonemap_probe: cannot write lattice.json (%d)" % FileAccess.get_open_error())
	else:
		f.store_string(JSON.stringify({"levels": Array(LEVELS), "cols": COLS, "cell": CELL,
			"w": img.get_width(), "h": img.get_height()}))
		f.close()
	print("TONEMAP wrote %s/tm.png (%dx%d, %d lattice points)"
		% [out, img.get_width(), img.get_height(), LEVELS.size() * LEVELS.size() * LEVELS.size()])
	get_tree().quit(0)


## A black room: no sky, no ambient, no glow, no fog. Everything in the capture is the tonemapper and
## the grade and nothing else.
func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.tonemap_agx_white = 16.29
	env.tonemap_agx_contrast = 1.25
	env.glow_enabled = false
	env.fog_enabled = false
	env.adjustment_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_grid() -> void:
	var n := LEVELS.size()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(CELL * 0.92, CELL * 0.92)
	var rows := int(ceil(float(n * n * n) / float(COLS)))
	for i in range(n * n * n):
		var r := LEVELS[i / (n * n)]
		var g := LEVELS[(i / n) % n]
		var b := LEVELS[i % n]
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# `albedo_color` is LINEAR in Godot, which is exactly what the lattice axis is.
		mat.albedo_color = Color(r, g, b)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = Vector3((i % COLS) * CELL, -(i / COLS) * CELL, 0.0)
		add_child(mi)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(float(COLS), float(rows)) * CELL
	cam.near = 0.05
	cam.far = 100.0
	cam.position = Vector3((COLS - 1) * CELL * 0.5, -(rows - 1) * CELL * 0.5, 10.0)
	add_child(cam)
	cam.current = true


func _grab() -> Image:
	_drew = false
	RenderingServer.frame_post_draw.connect(_on_drawn, CONNECT_ONE_SHOT)
	for i in 240:
		await get_tree().process_frame
		if _drew:
			break
		if i == 8:
			RenderingServer.force_draw(false)
	if not _drew:
		push_warning("tonemap_probe: frame_post_draw never fired — this frame is the previous one")
		if RenderingServer.frame_post_draw.is_connected(_on_drawn):
			RenderingServer.frame_post_draw.disconnect(_on_drawn)
	return get_viewport().get_texture().get_image()


func _on_drawn() -> void:
	_drew = true


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
