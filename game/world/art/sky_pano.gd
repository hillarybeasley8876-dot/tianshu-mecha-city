class_name SkyPano
extends RefCounted
## city-art r15 — the CC0 sky panorama `mc_sky` blends in as its cloud field (sky/README.md).
##
## The dome's own ramp still supplies every colour; the plate supplies the cloud structure a
## value-noise dome cannot make. `index.json` is the manifest — never a `DirAccess` walk, because the
## shipped .app has no `tests/` and remaps imported files.
##
## `--pano=<id|none>` and `--pano-blend=<0..1>` drive it from the command line, which is how the
## hand-built dome is A/B'd against a real sky on side-by-side sheets rather than on preference.

const INDEX := "res://world/art/sky/index.json"

## The world's sun azimuth in the sky shader's convention (atan2(z, x)), for `SUN_AZIMUTH_DEG` 315
## in TimeOfDay: `atan2(-cos(az), sin(az))`. Kept here rather than read off the light so the loader
## does not need the scene.
const WORLD_SUN_AZ_DEG := 225.0

static var _cache: Dictionary = {}


## Reads (and caches) the manifest. Returns an empty dictionary and warns if it is missing or broken —
## the sky must still render without a panorama, so this never throws.
static func manifest() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	if not FileAccess.file_exists(INDEX):
		push_warning("SkyPano: %s is missing — the sky runs on the procedural dome alone" % INDEX)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
	if not (parsed is Dictionary) or not (parsed as Dictionary).has("panos"):
		push_error("SkyPano: %s is not a manifest with a 'panos' table" % INDEX)
		return {}
	_cache = parsed as Dictionary
	return _cache


## The plate the manifest (or `--pano=`) selects, as {id, path, sun_az_deg, ref, gain}.
## `id_override` is for tests and for an A/B that wants a specific plate without a command line.
static func selected(id_override: String = "") -> Dictionary:
	var man := manifest()
	if man.is_empty():
		return {}
	var flag := id_override if not id_override.is_empty() else String(Game.flag("pano", ""))
	if flag == "none":
		return {}
	var id := flag if not flag.is_empty() else String(man.get("active", ""))
	var entry: Dictionary = (man.get("panos", {}) as Dictionary).get(id, {})
	if entry.is_empty():
		if not flag.is_empty():
			push_error("SkyPano: --pano=%s is not in %s" % [flag, INDEX])
		return {}
	var path := String(man.get("dir", "res://world/art/sky/")) + String(entry.get("file", ""))
	return {"id": id, "path": path, "sun_az_deg": float(entry.get("sun_az_deg", 0.0)),
		"ref": float(entry.get("ref", 0.6)), "gain": float(entry.get("gain", 1.0))}


## Pushes the plate and its alignment onto a sky material. `blend` is the manifest's, unless
## `--pano-blend=` overrides it. Safe to call with a null material or with no plate selected: the
## blend is then forced to 0 so the shader's `pano_blend > 0.001` branch never runs.
static func apply(mat: ShaderMaterial, blend_override: float = -1.0,
		id_override: String = "") -> void:
	if mat == null:
		return
	var man := manifest()
	var blend := float(man.get("blend", 0.0)) if not man.is_empty() else 0.0
	var flag := Game.flag("pano-blend", "")
	if flag.is_valid_float():
		blend = float(flag)
	if blend_override >= 0.0:
		blend = blend_override
	# r15: a plate is only LOADED when it is actually blended. `SkyPano` used to bind the texture and
	# then set the blend, which put 44 MB of VRAM behind a branch that never ran — the manifest ships
	# at blend 0 (the hand-built dome won the A/B, see status/city-art.md §4), so the shipped build was
	# paying for a panorama it does not draw.
	if blend <= 0.001:
		mat.set_shader_parameter(&"pano_blend", 0.0)
		return
	var sel := selected(id_override)
	if sel.is_empty():
		mat.set_shader_parameter(&"pano_blend", 0.0)
		return
	if not ResourceLoader.exists(String(sel["path"])):
		push_error("SkyPano: %s is listed in %s but not importable — the sky runs without it"
			% [sel["path"], INDEX])
		mat.set_shader_parameter(&"pano_blend", 0.0)
		return
	var tex := load(String(sel["path"])) as Texture2D
	if tex == null:
		push_error("SkyPano: %s did not load as a Texture2D" % sel["path"])
		mat.set_shader_parameter(&"pano_blend", 0.0)
		return
	mat.set_shader_parameter(&"pano", tex)
	mat.set_shader_parameter(&"pano_ref", float(sel["ref"]))
	mat.set_shader_parameter(&"pano_gain", float(sel["gain"]))
	# The plate's sun has to land on the world's sun, or the cloud lighting and the key light disagree.
	mat.set_shader_parameter(&"pano_yaw",
		wrapf(float(sel["sun_az_deg"]) - WORLD_SUN_AZ_DEG, -180.0, 180.0))
	mat.set_shader_parameter(&"pano_blend", clampf(blend, 0.0, 1.0))
	print("SKY pano %s blend=%.2f yaw=%.1f ref=%.3f"
		% [sel["id"], clampf(blend, 0.0, 1.0),
			wrapf(float(sel["sun_az_deg"]) - WORLD_SUN_AZ_DEG, -180.0, 180.0), float(sel["ref"])])
