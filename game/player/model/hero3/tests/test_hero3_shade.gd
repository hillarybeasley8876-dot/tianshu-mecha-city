extends Node
## hero-v3 r7 gate: the Tianshu's material layer (lead brief r7 items 1-4).
##   tools/godot.sh test res://player/model/hero3/tests/test_hero3_shade.gd
##
##   1  the shell shader is installed on the armour surface and every texture it needs is bound
##   2  the armour albedo is lifted off Tripo's 0.009 linear and the gold trim is a real metal
##   3  the vents pulse with boost / charge / overdrive and the tint reaches the whole model
##   4  the rim lifts in third person and is OFF in first person
##   5  the modelled visor, vent and seven drone tips exist and sit on the plates they belong to

const SCENE := "res://player/model/hero3/hero3_model.tscn"
const DT := 1.0 / 120.0
## The armour's linear floor. The r7 brief asked for ">= 0.04", but the lead's r7 art note walked that
## back once city-art r15 raised the ambient: the plates must stay near-black and take their read from
## a sheen, so the floor is now a BAND -- enough that Tripo's 0.009 is not a hole, low enough that it
## can never read as lifted grey-blue again.
const ALBEDO_FLOOR := Vector2(0.015, 0.035)
## The trim's hue, measured off `GOLD_ALBEDO` in hero3_shade.gd: gold is 40-50 deg.
const GOLD_HUE_BAND := Vector2(0.08, 0.16)
## The head plate spans y 13.65..16.00 and the chest 11.14..13.56 (measured, probe_glow.gd).
const VISOR_BAND := Vector2(14.0, 15.4)
const VENT_BAND := Vector2(11.4, 13.0)

var failures: Array[String] = []
var _models: Array[Node3D] = []


func _ready() -> void:
	await _shell()
	await _accents()
	await _rim()
	await _glow()
	for m in _models:
		m.queue_free()
	if failures.is_empty():
		print("PASS")
		get_tree().quit(0)
	else:
		for f in failures:
			print("FAIL ", f)
		print("FAILED %d checks" % failures.size())
		get_tree().quit(1)


func _spawn() -> Node3D:
	var model: Node3D = (load(SCENE) as PackedScene).instantiate()
	model.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(model)
	_models.append(model)
	return model


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _shell() -> void:
	var model := _spawn()
	var shade: Hero3Shade = model.rig.shade
	_check(shade != null, "the rig built no Hero3Shade")
	if shade == null:
		return
	_check(shade.shell != null, "no shell ShaderMaterial on the armour")
	_check(shade.armour_surface >= 0, "the armour surface was never found")
	var body: MeshInstance3D = model.rig.body_mesh()
	_check(body.get_surface_override_material(shade.armour_surface) == shade.shell,
			"the shell is not the armour surface's override material")
	for uniform in [&"albedo_tex", &"normal_tex", &"orm_tex", &"emis_tex"]:
		var tex := shade.shell.get_shader_parameter(uniform) as Texture2D
		_check(tex != null, "shell uniform %s is unbound" % uniform)
		if tex != null:
			print("SHELL %-12s %s" % [uniform, tex.resource_path.get_file()])
	# item 2: the numbers the brief names, read back off the shader rather than trusted
	var lift: Vector3 = shade.shell.get_shader_parameter(&"lift_color")
	var floor_linear: float = maxf(lift.x, maxf(lift.y, lift.z))
	_check(floor_linear >= ALBEDO_FLOOR.x and floor_linear <= ALBEDO_FLOOR.y,
			"the armour lift is %.3f linear, outside the band %s" % [floor_linear, str(ALBEDO_FLOOR)])
	_check(absf(lift.z - lift.x) < 0.006,
			"the armour lift is blue-biased (%s) — that is what read as blue-grey metal" % str(lift))
	var gold_albedo: Vector3 = shade.shell.get_shader_parameter(&"gold_albedo")
	var gold_hue := _hue(gold_albedo)
	_check(gold_hue >= GOLD_HUE_BAND.x and gold_hue <= GOLD_HUE_BAND.y,
			"the trim albedo hue is %.3f, outside the gold band %s" % [gold_hue, str(GOLD_HUE_BAND)])
	var gold_metal: float = shade.shell.get_shader_parameter(&"gold_metallic")
	var gold_rough: Vector2 = shade.shell.get_shader_parameter(&"gold_roughness")
	_check(gold_metal >= 0.95, "gold trim metallic is %.2f, the brief wants ~1" % gold_metal)
	# the band comes back through a float32 uniform, so the bound carries a little slack
	_check(gold_rough.x >= 0.25 and gold_rough.y <= 0.401,
			"gold roughness band %s is outside 0.25-0.40" % str(gold_rough))
	print("SHELL lift %.3f linear, gold metallic %.2f roughness %s, gold albedo %s hue %.3f"
			% [floor_linear, gold_metal, str(gold_rough), str(gold_albedo), gold_hue])
	# item 4: the weapons carry the same accent language
	var saber := model.rig.weapon(&"Hero3Saber") as MeshInstance3D
	var edge := saber.get_surface_override_material(2) as StandardMaterial3D
	_check(edge != null and edge.emission_enabled, "the saber's edge does not emit")
	if edge != null:
		_check(edge.emission_energy_multiplier > 1.0,
				"the saber edge energy is %.2f" % edge.emission_energy_multiplier)


func _accents() -> void:
	var model := _spawn()
	var shade: Hero3Shade = model.rig.shade
	_step(model, 1)   # the dynamic uniforms are written by update(), not by setup()
	var idle: float = shade.shell.get_shader_parameter(&"vent_pulse")
	# driven through the RIG, not the shader: `Hero3Rig.update` re-derives the pulse every tick from the
	# thruster level and the charge flag, so calling `set_pulse` directly would be undone next tick
	model.set_thrusters(1.0)
	_step(model, 60)
	var boosted: float = shade.shell.get_shader_parameter(&"vent_pulse")
	_check(boosted > idle + 0.3, "boosting did not light the vents (%.2f -> %.2f)" % [idle, boosted])
	model.set_thrusters(0.0)
	model.rig.set_charging(true)
	_step(model, 60)
	var charging: float = shade.shell.get_shader_parameter(&"vent_pulse")
	_check(charging > 0.9, "a charge left the vents at %.2f" % charging)
	model.rig.set_charging(false)
	_step(model, 240)
	var rested: float = shade.shell.get_shader_parameter(&"vent_pulse")
	_check(rested < 0.5, "the vents did not settle back down (%.2f)" % rested)
	# overdrive: the tint has to reach the body AND the modelled glow, not just the emissive surfaces
	model.set_overdrive(true)
	_step(model, 120)
	_check(shade.tint > 0.95, "overdrive left the tint at %.2f" % shade.tint)
	var accent: Color = shade.shell.get_shader_parameter(&"accent_color")
	_check(accent.r > accent.b, "overdrive left the accent cyan: %s" % str(accent))
	_check(model.rig.glow.tips.size() == 7, "the drone tips went missing")
	var tip := model.rig.glow.tips[0].material_override as StandardMaterial3D
	_check(tip.albedo_color.r > tip.albedo_color.b, "the drone tips did not follow the overdrive tint")
	print("ACCENT idle %.2f boost %.2f charge %.2f rest %.2f overdrive tint %.2f"
			% [idle, boosted, charging, rested, shade.tint])


func _rim() -> void:
	var model := _spawn()
	var shade: Hero3Shade = model.rig.shade
	_step(model, 120)
	var third: float = shade.shell.get_shader_parameter(&"rim_gain")
	_check(third > 0.05, "the rim is off in third person (%.3f)" % third)
	Events.camera_mode_changed.emit(true)
	_step(model, 120)
	var first: float = shade.shell.get_shader_parameter(&"rim_gain")
	_check(first < 0.01, "the cockpit view still glows: rim %.3f" % first)
	Events.camera_mode_changed.emit(false)
	_step(model, 120)
	var back: float = shade.shell.get_shader_parameter(&"rim_gain")
	_check(back > 0.05, "the rim did not come back in third person (%.3f)" % back)
	print("RIM third %.3f first %.3f back %.3f" % [third, first, back])


func _glow() -> void:
	var model := _spawn()
	_step(model, 2)   # the panel uniforms are written by Hero3Glow.update(), not by setup()
	var glow: Hero3Glow = model.rig.glow
	_check(glow.visor.size() == 1, "the visor is %d panels, the concept has one slit"
			% glow.visor.size())
	_check(glow.vent.size() == 1, "the chest vent is %d panels, it should be one portcullis"
			% glow.vent.size())
	_check(glow.tips.size() == 7, "expected 7 drone tips, got %d" % glow.tips.size())
	_check(glow.visor_at.y > VISOR_BAND.x and glow.visor_at.y < VISOR_BAND.y,
			"the visor sits at y %.2f, outside the face band %s" % [glow.visor_at.y, str(VISOR_BAND)])
	_check(glow.visor_at.z < 0.0, "the visor is behind the helm (z %.2f)" % glow.visor_at.z)
	_check(glow.vent_at.y > VENT_BAND.x and glow.vent_at.y < VENT_BAND.y,
			"the vent sits at y %.2f, outside the chest band %s" % [glow.vent_at.y, str(VENT_BAND)])
	_check(glow.vent_at.z < glow.visor_at.z, "the vent is not on the chest front")
	# the panel's gain has to stay under 1.0 or the feathered edge clips back into a flat plate,
	# which is what the lead asked to get rid of
	if glow.vent.is_empty():
		print("GLOW no chest grille to measure")
		return
	var panel := glow.vent[0].material_override as ShaderMaterial
	var gain: float = panel.get_shader_parameter(&"glow_gain")
	_check(gain < 1.0, "the vent runs at gain %.2f, which clips to a flat plate" % gain)
	var stripes: float = panel.get_shader_parameter(&"stripes")
	_check(stripes >= 5.0, "the vent has %.0f bars — the concept's portcullis has gaps, not a plate"
			% stripes)
	var hue: Color = panel.get_shader_parameter(&"glow_color")
	_check(hue.r > 0.9 and hue.g > 0.55 and hue.b > 0.15 and hue.b < 0.40,
			"the vent hue %s is not the warm gold-amber the lead asked for" % str(hue))
	print("GLOW visor %s vent %s panels %d/%d bars %.0f tips %d gain %.2f hue %s"
			% [str(glow.visor_at.snapped(Vector3.ONE * 0.01)),
			str(glow.vent_at.snapped(Vector3.ONE * 0.01)), glow.visor.size(), glow.vent.size(),
			stripes, glow.tips.size(), gain, str(hue)])


## Hue in turns (0..1) from a linear RGB triple, the same convention the mask thresholds use.
func _hue(c: Vector3) -> float:
	var mx: float = maxf(c.x, maxf(c.y, c.z))
	var mn: float = minf(c.x, minf(c.y, c.z))
	var d := mx - mn
	if d < 1e-6:
		return 0.0
	if mx == c.x:
		return fposmod((c.y - c.z) / d, 6.0) / 6.0
	if mx == c.y:
		return ((c.z - c.x) / d + 2.0) / 6.0
	return ((c.x - c.y) / d + 4.0) / 6.0


func _step(model: Node3D, ticks: int) -> void:
	for i in ticks:
		model.rig.update(DT)
