extends CanvasLayer
## HUD root (`ui/hud.tscn`, instanced by main.tscn). Owns the frame loop: it polls `HudData`, hands the
## snapshot to every widget and switches the whole overlay between the third-person screen layout and
## the first-person canopy projection (brief §7). It also owns the menu stack.

## Widgets are created in code and ordered back-to-front; the list below IS the draw order. The
## world-anchored readouts (plates, telegraphs, markers, numbers) sit UNDER the fixed chrome, so an
## enemy standing in the corner can never cover the ammo count.
const Widgets := {
	&"low_hp": preload("res://ui/widgets/low_hp.gd"),
	&"plates": preload("res://ui/widgets/enemy_plates.gd"),
	&"telegraphs": preload("res://ui/widgets/telegraphs.gd"),
	&"markers": preload("res://ui/widgets/markers.gd"),
	&"numbers": preload("res://ui/widgets/damage_numbers.gd"),
	&"compass": preload("res://ui/widgets/compass.gd"),
	&"objective": preload("res://ui/widgets/objective_bar.gd"),
	&"boss_bar": preload("res://ui/widgets/boss_bar.gd"),
	&"boss_card": preload("res://ui/widgets/boss_card.gd"),
	&"radar": preload("res://ui/widgets/radar.gd"),
	&"style": preload("res://ui/widgets/style_meter.gd"),
	&"hp": preload("res://ui/widgets/hp_bar.gd"),
	&"weapon": preload("res://ui/widgets/weapon_panel.gd"),
	&"od": preload("res://ui/widgets/od_ring.gd"),
	&"flight": preload("res://ui/widgets/flight_cue.gd"),
	&"hotbar": preload("res://ui/widgets/hotbar.gd"),
	&"tutorial": preload("res://ui/widgets/tutorial.gd"),
	&"callouts": preload("res://ui/widgets/callouts.gd"),
	&"hit_marker": preload("res://ui/widgets/hit_marker.gd"),
	&"reticle": preload("res://ui/widgets/reticle.gd"),
}

const GlassHud := preload("res://ui/cockpit/glass_hud.gd")
const MenuRoot := preload("res://ui/menus/menu_root.gd")
## The layout the HUD is authored in: the scale is `window_height / DESIGN.y` times `hud_scale`.
const DESIGN := Vector2(1600.0, 900.0)
## How loud each widget is allowed to be once nothing about it has changed for three seconds
## (look review item 9). Everything not listed stays at full strength: the reticle, the markers, the
## telegraphs and the feedback pops are what the player is looking at.
const REST_ALPHA: Dictionary = {
	&"hotbar": 0.45, &"od": 0.3, &"radar": 0.55, &"hp": 0.6, &"compass": 0.7, &"weapon": 0.75,
}

var data: HudData = null
var prefs: HudPrefs = null
var glass: HudGlassHud = null
var menus: HudMenuRoot = null
var first_person: bool = false
var _title_up: bool = false

var _root: Control = null
var _widgets: Dictionary = {}
var _glass_showing: bool = false


func _ready() -> void:
	Game.hud = self
	layer = 10
	prefs = HudPrefs.new()
	data = HudData.new()
	_root = Control.new()
	_root.name = "Screen"
	# TOP_LEFT, not FULL_RECT: `_apply_scale` owns size and scale so the widgets can lay out in virtual
	# 1600×900 pixels whatever the window is.
	_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	for key: StringName in Widgets:
		var w: Control = Widgets[key].new()
		w.name = String(key)
		w.set(&"data", data)
		_root.add_child(w)
		_widgets[key] = w
	(_widgets[&"numbers"] as Control).set(&"prefs", prefs)
	glass = GlassHud.new()
	glass.name = "GlassHud"
	add_child(glass)
	glass.build_widgets(data, Widgets, prefs)
	menus = MenuRoot.new()
	menus.name = "Menus"
	add_child(menus)
	Events.player_spawned.connect(func(_p: Node3D) -> void: data.refresh_refs())
	data.refresh_refs()
	_apply_mode(false, menus.page == HudMenuRoot.Page.TITLE)


## Test and tool accessor: `hud.widget(&"hotbar")`.
func widget(key: StringName) -> HudWidget:
	return _widgets.get(key) as HudWidget


## CONTRACTS §6: the flow asks for a contextual prompt, the HUD draws it. Nothing is shown that was
## not asked for, so free play and the sandbox stay clean. It goes to the canopy copy too — in first
## person the screen widgets are suppressed and the prompt must not vanish.
func prompt(id: StringName, action: StringName = &"", line: String = "") -> void:
	var shown := 0
	for t in _tutorials():
		t.call(&"prompt", id, action, line)
		shown += 1
	if shown == 0:
		push_warning("HUD: no tutorial widget for prompt '%s'" % id)


## CONTRACTS §6: retires a prompt early (the flow finished with that verb).
func dismiss_prompt(id: StringName) -> void:
	for t in _tutorials():
		t.call(&"dismiss_prompt", id)


## Both copies of the tutorial widget: the screen one and the canopy projection's.
func _tutorials() -> Array[HudWidget]:
	var out: Array[HudWidget] = []
	var screen_t := widget(&"tutorial")
	if screen_t != null:
		out.append(screen_t)
	if glass != null:
		var glass_t := glass.widget(&"tutorial")
		if glass_t != null:
			out.append(glass_t)
	return out


func widget_keys() -> Array:
	return _widgets.keys()


func _process(delta: float) -> void:
	_apply_scale()
	data.poll(delta)
	_apply_rest_alpha()
	_publish_chrome()
	var title := menus != null and menus.page == HudMenuRoot.Page.TITLE
	if data.first_person != first_person or title != _title_up:
		_apply_mode(data.first_person, title)
	var style := widget(&"style")
	if style != null and menus != null:
		menus.note_combo(int(style.get(&"count")))


## Collects the screen area each piece of chrome claims and hands it to the enemy plates, so a
## world-anchored readout can never land on the ammo count or the compass tape (look review item 10.4).
## The same list goes to the canopy copy: it lays out in the same virtual 1600×900 space.
func _publish_chrome() -> void:
	var rects: Array[Rect2] = []
	for key: StringName in _widgets:
		var w := widget(key)
		if w == null or not w.visible:
			continue
		var r := w.chrome_rect()
		if r.size != Vector2.ZERO:
			rects.append(r.grow(6.0))
	_set_avoid(widget(&"plates"), rects)
	if glass != null:
		_set_avoid(glass.widget(&"plates"), rects)


func _set_avoid(w: HudWidget, rects: Array[Rect2]) -> void:
	if w != null:
		w.set(&"avoid", rects)


## Rest alphas are set once a frame rather than in `_ready` because the widgets are built after this
## node exists. The canopy copies are deliberately left at 1.0: the projection is already fighting the
## sky through alpha-blended glass, and dimming it a second time made the cockpit readouts unreadable.
func _apply_rest_alpha() -> void:
	for key: StringName in REST_ALPHA:
		var w := widget(key)
		if w != null:
			w.rest_alpha = float(REST_ALPHA[key])


## One scale for the whole overlay: the widgets lay out in virtual 1600×900 pixels and the root
## Control is scaled by `window_height / 900 × hud_scale` (lead r1 MUST-FIX 1). Type is floored at
## 14 device px inside `HudPalette.fs()`, so a small `hud_scale` never makes a label unreadable.
func _apply_scale() -> void:
	var view := get_viewport().get_visible_rect().size
	if view.x < 1.0 or view.y < 1.0:
		return
	var k := clampf(view.y / DESIGN.y * prefs.get_float(&"hud_scale"), 0.4, 3.0)
	# The canopy projection renders into its own fixed buffer, so there the window size drops out and
	# only the player's `hud_scale` applies (brief §7). It also only takes the overlay over once its
	# quad is really on the glass — until then the screen widgets stay up rather than the pilot losing
	# every readout.
	var glass_k := clampf(HudGlassHud.RATIO * prefs.get_float(&"hud_scale"), 0.2, 2.0)
	var showing := glass != null and glass.is_showing()
	HudPalette.ui_scale = glass_k if showing else k
	# The world-anchored widgets draw inside `_root`, so HudData needs the same scale to turn a canvas
	# position into one that lands on the target (audit #1).
	data.ui_scale = HudPalette.ui_scale
	HudPalette.motion = 0.0 if bool(Settings.get_value(&"photosensitive")) else 1.0
	_root.scale = Vector2(k, k)
	_root.size = view / k
	_root.position = Vector2.ZERO
	if glass != null:
		glass.set_scale(glass_k)
	if showing != _glass_showing:
		_glass_showing = showing
		_set_suppressed(showing or _title_up)


## In the cockpit the canopy projection carries the WHOLE overlay, so every screen-space widget is
## suppressed (brief §7); on the title screen the mech HUD has no business being on at all. Pause and
## the end pages keep it up under the dim — the player still wants to read their state.
func _set_suppressed(on: bool) -> void:
	for key: StringName in _widgets:
		var w := widget(key)
		if w != null:
			w.suppressed = on


func _apply_mode(fp: bool, title: bool = false) -> void:
	first_person = fp
	_title_up = title
	if glass != null:
		glass.set_active(fp and not title and prefs.get_bool(&"cockpit_hud"))
	_glass_showing = glass != null and glass.is_showing()
	_set_suppressed(_glass_showing or title)
