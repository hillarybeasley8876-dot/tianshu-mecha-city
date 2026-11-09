class_name HudFakeActor
extends Node3D
## Test double for a damageable actor: a PlayerMech stand-in or an EnemyBase stand-in with a
## hand-written `hud_state()`, so the HUD test can drive every widget without the gameplay units.

var state: Dictionary = {}
var enemy_type: StringName = &"ripper"
var alive: bool = true
## Physics ticks seen, so a suite can prove the tree really froze (hud r6: GAME_OVER pauses it).
var ticks: int = 0


func _physics_process(_delta: float) -> void:
	ticks += 1


static func make(initial: Dictionary, is_enemy: bool, type: StringName = &"ripper") -> HudFakeActor:
	var a := HudFakeActor.new()
	a.state = initial
	a.enemy_type = type
	if is_enemy:
		a.add_to_group(&"enemy")
	return a


func hud_state() -> Dictionary:
	return state


func set_state(extra: Dictionary) -> void:
	state.merge(extra, true)


func clear_state() -> void:
	state = {}


func is_alive() -> bool:
	return alive


func get_team() -> int:
	return 1 if is_in_group(&"enemy") else 0


func take_hit(hit: HitInfo) -> void:
	hit.final_amount = hit.amount
	Events.hit_landed.emit(hit, self)


## A lock point for this actor, so the aim/marker code paths have something real to project.
func targetable() -> Targetable:
	var t := Targetable.new()
	t.radius = 4.0
	add_child(t)
	return t
