extends Node
## Main scene (core-owned). Boots the demo from optional parts so every unit can run alone:
##   world   res://world/city.tscn          (city units)      --sandbox or missing -> core sandbox
##   player  res://player/player_mech.tscn  (mech unit)       missing -> no player
##   camera  res://player/camera/camera_rig.tscn (camera unit, follows Game.player)
##   feel    res://fx/feel_director.tscn    (feel unit)
##   hud     res://ui/hud.tscn              (hud unit)
##   enemies res://enemies/spawner.tscn     (enemies unit: --enemies=type:n, --no-enemies)
##   flow    res://flow/game_flow.tscn      (encounters/objectives/menus)
##   boss    res://enemies/boss/boss_director.tscn (boss unit: skyline walker, Crown fight)
##   post    res://world/post/post_stack.tscn (post-render: grade, bloom, lens; --no-post disables it)
## Any part can be skipped with --stub=world,player,enemies,camera,feel,hud,flow,boss,post (tools, perf bisecting).

const PARTS: Array[Array] = [
	["feel", "res://fx/feel_director.tscn"],
	["player", "res://player/player_mech.tscn"],
	["enemies", "res://enemies/spawner.tscn"],
	["camera", "res://player/camera/camera_rig.tscn"],
	["hud", "res://ui/hud.tscn"],
	["flow", "res://flow/game_flow.tscn"],
	["boss", "res://enemies/boss/boss_director.tscn"],
	["post", "res://world/post/post_stack.tscn"],
]
const CITY := "res://world/city.tscn"
const SANDBOX := "res://core/sandbox/sandbox.tscn"


func _ready() -> void:
	_spawn_world()
	for part in PARTS:
		_spawn_optional(String(part[0]), String(part[1]))


func _spawn_world() -> void:
	if Game.stubbed("world"):
		Game.mark_world_built()
		return
	var path := SANDBOX if (Game.has_flag("sandbox") or not ResourceLoader.exists(CITY)) else CITY
	var world := _instance(path)
	if world == null:
		Game.mark_world_built()
		return
	world.name = "World"
	Game.world = world as Node3D
	add_child(world)


func _spawn_optional(part: String, path: String) -> void:
	if Game.stubbed(part) or not ResourceLoader.exists(path):
		return
	var node := _instance(path)
	if node != null:
		add_child(node)


func _instance(path: String) -> Node:
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("Main: cannot load %s" % path)
		return null
	return packed.instantiate()
