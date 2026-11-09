class_name HudTestHarness
extends RefCounted
## Test rig for the HUD unit (`tools/godot.sh test res://ui/tests/test_hud.gd`): it puts the real
## `ui/hud.tscn` in the tree with a camera and a fake player, then drives the whole overlay through
## `HudData`'s forced-snapshot mode so every check is deterministic and independent of the other units.

const HUD_SCENE := "res://ui/hud.tscn"

var host: Node
var hud: Node = null
var data: HudData = null
var player: HudFakeActor = null
var rig: HudFakeRig = null
var camera: Camera3D = null
var enemies: Array[HudFakeActor] = []
var checks: int = 0
var failures: PackedStringArray = PackedStringArray()

## A full, plausible snapshot (every key the gameplay units publish). Suites merge over this.
const FULL: Dictionary = {
	"alive": true, "hp": 6400.0, "hp_max": 10000.0, "en": 720.0, "en_max": 1000.0,
	"od": 45.0, "od_max": 100.0, "overdrive_active": false, "outage": false,
	"state": "run", "speed": 16.0,
	"weapon": "beam_rifle", "ammo": 12, "ammo_max": 15, "reloading": false, "swapping": false,
	"charge": 0.0, "charge_stage": 0, "heat": 0.32, "overheated": false,
	"vent_needle": 0.32, "vent_mark": 0.7, "superheated": false,
	"missile_cd": 0.0, "missile_locks": 0, "missile_locks_max": 12, "missile_painting": false,
	"guarding": false, "perfect_window": false, "catch_count": 0, "guard_break": false,
	"guard_break_left": 0.0, "parries": 0,
	"combo_step": 0, "charging": 0.0, "execution_available": false, "jackpot": false,
	"hard_target": null, "soft_target": null, "first_person": false, "ads": false,
	"soft_distance": -1.0, "hard_distance": -1.0, "in_view": 0,
}


func build(host_node: Node) -> bool:
	host = host_node
	player = HudFakeActor.make(FULL, false)
	player.name = "FakePlayer"
	host.add_child(player)
	Game.register_player(player)
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.position = Vector3(0.0, 12.0, 40.0)
	host.add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.make_current()
	rig = HudFakeRig.new()
	rig.cam = camera
	host.add_child(rig)
	Game.camera_rig = rig
	var packed := load(HUD_SCENE) as PackedScene
	if packed == null:
		push_error("HudTestHarness: cannot load " + HUD_SCENE)
		return false
	hud = packed.instantiate()
	host.add_child(hud)
	data = hud.get(&"data") as HudData
	if data == null:
		push_error("HudTestHarness: hud.tscn has no HudData")
		return false
	data.use_forced = true
	data.forced = FULL.duplicate()
	data.refresh_refs()
	# The title screen suppresses the whole mech HUD by design; the suites drive pages themselves.
	menus().close()
	return true


## Adds a fake enemy `metres` in front of the player and returns it.
func add_enemy(at: Vector3, state: Dictionary = {}, type: StringName = &"mantis") -> HudFakeActor:
	var e := HudFakeActor.make({
		"name": "镰影 Mantis", "type": type, "hp": 1200.0, "hp_max": 1800.0,
		"stability": 400.0, "stability_max": 700.0, "staggered": false,
		"marks": 0, "primed": false, "alive": true,
	}, true, type)
	e.state.merge(state, true)
	e.position = at
	host.add_child(e)
	enemies.append(e)
	return e


func widget(key: StringName) -> HudWidget:
	return hud.call(&"widget", key) as HudWidget


func menus() -> HudMenuRoot:
	return hud.get(&"menus") as HudMenuRoot


func feed(extra: Dictionary) -> void:
	data.forced.merge(extra, true)


func reset_state() -> void:
	data.forced = FULL.duplicate()


## Runs the HUD for `frames` process frames so widgets read the new snapshot and timers advance.
func settle(frames: int = 3) -> void:
	for i in frames:
		await host.get_tree().process_frame


## Runs process frames until `seconds` have passed on Feel's real clock. The GAME_OVER death clock is
## measured on that clock (hud r7), so a suite waiting for it has to wait on the same one — a frame
## count would only be right at one fixed fps.
func wait_real(seconds: float) -> void:
	var until := Feel.real_now() + seconds
	while Feel.real_now() < until:
		await host.get_tree().process_frame


## Injects a menu action as an event, so the page's own `_input` path is what runs — the same path a
## key press takes. `Input.action_press` would NOT do: it never reaches `menu_root.gd:_input`.
func press(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	menus()._input(ev)


## A real pad button event, for the paths that read `InputEventJoypadButton` directly.
func pad_button(button: int) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button as JoyButton
	ev.pressed = true
	menus()._input(ev)


## The row with `id` on a page, or an empty dictionary.
static func find_row(s: HudMenuScreen, id: String) -> Dictionary:
	for r in s.rows:
		if String(r.get("id", "")) == id:
			return r
	return {}


## The index of the row with `id`, or -1.
static func row_index(s: HudMenuScreen, id: String) -> int:
	for i in s.rows.size():
		if String(s.rows[i].get("id", "")) == id:
			return i
	return -1


func check(ok: bool, label: String) -> bool:
	checks += 1
	if ok:
		print("PASS ", label)
	else:
		failures.append(label)
		print("FAIL ", label)
	return ok


func near(a: float, b: float, label: String, eps: float = 0.01) -> bool:
	return check(absf(a - b) <= eps, "%s (got %.4f, want %.4f)" % [label, a, b])


func release_all() -> void:
	for e in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	Game.player = null
	Game.camera_rig = null
	for n: Node in [player, rig, camera, hud]:
		if is_instance_valid(n):
			n.queue_free()
