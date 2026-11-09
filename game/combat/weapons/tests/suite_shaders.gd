class_name WeaponShaderSuite
extends RefCounted
## Lead r6 "Also" — a broken `.gdshader` is invisible to `tools/godot.sh check`.
##
## melee-defense r7 measured it: a deliberate syntax error in a shader file still reports
## `CHECK 0 failed`, because nothing in the import pass compiles GLSL. Two things are pinned here:
##
##   1. the weapons/projectiles pools own NO shader of their own — every material they build is a
##      `StandardMaterial3D` — so the audit below is the proof, and it fails the moment somebody
##      adds a `.gdshader` or a `Shader.new()` under those folders without compiling it here;
##   2. the shaders the weapons actually REACH do compile. Every impact, blast, dust puff and
##      shockwave ring goes out through `FxBridge` into the fx unit's `VfxLibrary`, whose presets are
##      built from the six shaders below — if one of them breaks, every weapon impact silently loses
##      its material and only a windowed run shows it.
##
## Compilation is forced the way melee-defense does it: the dummy renderer's material storage parses
## a shader's code on assignment and logs `SHADER ERROR` when it does not parse, and
## `get_shader_uniform_list()` is what makes it run the compiler at all.

const ErrorCounter := preload("res://tools/error_counter.gd")

## Folders this unit owns. Nothing here may contain a shader that is not compiled below.
const OWNED: Array[String] = ["res://combat/weapons/", "res://combat/projectiles/"]
## The fx unit's shaders behind the pooled kinds the weapons spawn: `spark_bullet` / `spark_beam`
## (spark_process + spark), `dust_puff` / smoke (puff), `missile_blast` (fireball), the impact pop
## (flash_pop) and `spawn_ring` (shockwave_ring).
const REACHED: Array[String] = [
	"res://fx/vfx/spark_process.gdshader",
	"res://fx/vfx/spark.gdshader",
	"res://fx/vfx/puff.gdshader",
	"res://fx/vfx/fireball.gdshader",
	"res://fx/vfx/flash_pop.gdshader",
	"res://fx/vfx/shockwave_ring.gdshader",
]


static func run(h: WeaponTestHarness) -> void:
	_owned(h)
	_reached(h)
	_self_test(h)


## No shader of our own, so the list below cannot grow a hole behind our backs.
static func _owned(h: WeaponTestHarness) -> void:
	var listed := _list(OWNED[1])
	h.check("shader.directory_listing_works", listed.has("beam_pool.gd"),
			"ResourceLoader.list_directory found %d entries under %s" % [listed.size(), OWNED[1]])
	var found: PackedStringArray = PackedStringArray()
	for dir in OWNED:
		for f in _list(dir):
			if f.ends_with(".gdshader") or f.ends_with(".gdshader.remap"):
				found.append(dir + f)
	h.check("shader.weapons_own_no_gdshader", found.is_empty(),
			"a shader was added under combat/ — compile it in this suite: %s"
			% ", ".join(found))


## The gate itself: a shader that does not parse MUST be reported, or every `*_compiles` check above
## is vacuous. It is behind a flag because proving it means making the engine log a real error, and
## `tools/godot.sh test` fails any run that logs one — which is exactly the point:
##   `tools/godot.sh test res://combat/weapons/tests/test_weapons.gd -- --shader-selftest`
## prints `SELFTEST ...` and then `TEST ERRORS 2` with `Shader compilation failed`, exit 1.
static func _self_test(h: WeaponTestHarness) -> void:
	if not OS.get_cmdline_user_args().has("--shader-selftest"):
		return
	var counter := ErrorCounter.new()
	OS.add_logger(counter)
	var probe := Shader.new()
	probe.code = "shader_type spatial;\nvoid fragment() { ALBEDO = vec3(1.0) }\nthis is not glsl"
	probe.get_shader_uniform_list()
	OS.remove_logger(counter)
	print("SELFTEST broken shader produced %d engine error(s): %s" % [counter.errors,
			counter.first_errors[0] if counter.first_errors.size() > 0 else ""])
	h.check("shader.a_broken_shader_is_caught", counter.errors > 0,
			"a deliberately broken shader compiled clean — the checks above prove nothing")


## Every shader the weapons reach through the fx library compiles.
static func _reached(h: WeaponTestHarness) -> void:
	for path in REACHED:
		_compile(h, path)


static func _compile(h: WeaponTestHarness, path: String) -> void:
	var source := FileAccess.get_file_as_string(path)
	var tag := path.get_file().get_basename()
	if source.is_empty():
		h.check("shader.%s_source_reads" % tag, false, "cannot read " + path)
		return
	var counter := ErrorCounter.new()
	OS.add_logger(counter)
	var probe := Shader.new()
	probe.code = source
	probe.get_shader_uniform_list()
	OS.remove_logger(counter)
	h.check("shader.%s_compiles" % tag, counter.errors == 0,
			"%d error(s): %s" % [counter.errors,
			counter.first_errors[0] if counter.first_errors.size() > 0 else ""])


## `ResourceLoader.list_directory` rather than `DirAccess`: the export remaps imported files, and the
## worker rules ban `DirAccess` on `res://` outright.
static func _list(dir: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for f in ResourceLoader.list_directory(dir):
		out.append(f)
		if f.ends_with("/"):
			out.append_array(_list(dir + f))
	return out
