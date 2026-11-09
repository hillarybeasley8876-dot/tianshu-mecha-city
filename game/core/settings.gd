extends Node
## Settings (autoload, core-owned): player options with defaults, persisted to user://settings.cfg.
## Dev/tool runs pass --quality=... and then never read or write the file (reproducible captures).

signal changed(key: StringName)

const PATH := "user://settings.cfg"
const DEFAULTS: Dictionary = {
	&"quality": &"high",              ## low | medium | high
	&"mouse_sensitivity": 1.0,        ## multiplier on the camera unit's base rate
	&"stick_sensitivity": 1.0,
	&"invert_y": false,
	&"fov_third": 55.0,             ## vertical FOV (Godot convention)
	&"fov_first": 62.0,
	&"screen_shake": 1.0,             ## 0..1, feeds Feel.intensity
	&"fx_flash": 1.0,                 ## 0..1 full-screen flashes / impact frames
	&"fx_chromatic": 1.0,             ## 0..1
	&"fx_radial_blur": 1.0,           ## 0..1
	&"fx_speed_lines": 1.0,           ## 0..1
	&"fx_lens": true,                 ## post-render: vignette + chromatic fringe
	&"fx_film_grain": true,           ## post-render: film grain (also removed by `photosensitive`)
	&"rumble": 1.0,                   ## 0..1 gamepad vibration
	&"photosensitive": false,         ## true: no B/W impact frames, flashes ≤ 0.1 alpha, ≤ 1 flash/s
	&"damage_numbers": true,
	&"hud_scale": 1.0,                ## 0.8..1.4 HUD size multiplier
	&"hold_to_toggle": false,         ## accessibility: holds (guard, catch, paint, ascend) become toggles
	&"aim_assist": 1.0,               ## 0..1
	&"master_volume_db": 0.0,
	&"music_volume_db": -4.0,
	&"sfx_volume_db": 0.0,
	&"voice_volume_db": 0.0,
	&"ui_volume_db": -2.0,
}

var _values: Dictionary = DEFAULTS.duplicate()
var _persist: bool = true


func _ready() -> void:
	var q := Game.flag("quality")
	if q != "":
		_persist = false
		_values[&"quality"] = StringName(q)
	else:
		_load()
	Feel.intensity = float(_values[&"screen_shake"])


func get_value(key: StringName) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: StringName, value: Variant) -> void:
	_values[key] = value
	if key == &"screen_shake":
		Feel.intensity = float(value)
	changed.emit(key)
	if _persist:
		_save()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key: StringName in DEFAULTS:
		_values[key] = cfg.get_value("settings", String(key), DEFAULTS[key])


func _save() -> void:
	var cfg := ConfigFile.new()
	for key: StringName in _values:
		cfg.set_value("settings", String(key), _values[key])
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("Settings: could not save %s (error %d)" % [PATH, err])
