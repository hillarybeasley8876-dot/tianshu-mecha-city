class_name HudPrefs
extends RefCounted
## Player options the HUD reads. `damage_numbers` and `hud_scale` now live in the core `Settings`
## autoload (they were added after review r1), so this is a thin adapter: it reads and writes Settings
## and only keeps the one key that is genuinely HUD-local — the cockpit projection toggle — in
## `user://hud_prefs.cfg`.

const PATH := "user://hud_prefs.cfg"
## Keys owned by core/settings.gd: everything else in DEFAULTS is local to the HUD.
const SETTINGS_KEYS: Array[StringName] = [&"damage_numbers", &"hud_scale"]
const DEFAULTS: Dictionary = {
	&"cockpit_hud": true,
}

var _values: Dictionary = DEFAULTS.duplicate()


func _init() -> void:
	_load()


func get_value(key: StringName) -> Variant:
	if key in SETTINGS_KEYS:
		return Settings.get_value(key)
	return _values.get(key, DEFAULTS.get(key))


func get_bool(key: StringName) -> bool:
	return bool(get_value(key))


func get_float(key: StringName) -> float:
	return float(get_value(key))


func set_value(key: StringName, value: Variant) -> void:
	if key in SETTINGS_KEYS:
		Settings.set_value(key, value)
		return
	_values[key] = value
	_save()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key: StringName in DEFAULTS:
		_values[key] = cfg.get_value("hud", String(key), DEFAULTS[key])


func _save() -> void:
	var cfg := ConfigFile.new()
	for key: StringName in _values:
		cfg.set_value("hud", String(key), _values[key])
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("HudPrefs: could not save %s (error %d)" % [PATH, err])
