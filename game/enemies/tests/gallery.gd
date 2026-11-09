extends Node3D
## Capture gallery (enemies unit). `tools/godot.sh shot --scene res://enemies/tests/gallery.tscn
## --pose=<pose> --out enemies_<pose> --cams=...` builds one of the poses below in the core sandbox.
##
## Poses: types | pack | telegraph_parry | telegraph_red | stagger | wreck
## Subjects stand in a known place so the capture tool's static cameras can frame them.

const SANDBOX := "res://core/sandbox/sandbox.tscn"
const PILLAR_HEIGHT := 16.0   ## hero height (SPEC §2): the scale reference beside every monster
const ROW_Z := -60.0
const ROW_SPACING := 46.0

var _spawner: EnemySpawner
var _subjects: Array[EnemyBase] = []


func _ready() -> void:
	var pose := "types"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pose="):
			pose = arg.trim_prefix("--pose=")
	add_child((load(SANDBOX) as PackedScene).instantiate())
	_spawner = EnemySpawner.new()
	_spawner.name = "Spawner"
	_spawner.auto_spawn = false
	add_child(_spawner)
	match pose:
		"solo": _solo()
		"pack": _pack()
		"telegraph_parry": _telegraph(false)
		"telegraph_red": _telegraph(true)
		"stagger": _stagger()
		"wreck": _wreck()
		_: _types()


func _types() -> void:
	var x := -ROW_SPACING * 2.0
	for type: StringName in EnemyTypes.ALL:
		var e := _spawner.spawn(type, Transform3D(Basis(Vector3.UP, deg_to_rad(215.0)),
				Vector3(x, 0.0, ROW_Z)))
		if e != null:
			e.set_ai_enabled(false)
			_subjects.append(e)
		_pillar(Vector3(x - 17.0, 0.0, ROW_Z - 9.0))
		x += ROW_SPACING


## One archetype at the origin with its scale pillar, for a close 3/4 look: --enemy=ripper|...
func _solo() -> void:
	var type := EnemyTypes.JUGGERNAUT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--enemy="):
			type = StringName(arg.trim_prefix("--enemy="))
	var yaw := 180.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--yaw="):
			yaw = float(arg.trim_prefix("--yaw="))
	var e := _spawner.spawn(type, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), Vector3.ZERO))
	if e == null:
		push_error("gallery: unknown enemy type '%s'" % type)
		return
	e.set_ai_enabled(false)
	e.set_physics_process(false)
	if e.is_flyer:
		e.position.y = 14.0   ## flyers hover; show the silhouette off the deck
	_pillar(Vector3(-14.0, 0.0, -6.0))


## A ripper pack closing on a stand-in hero from three sides at once (SPEC §7 "flank").
func _pack() -> void:
	_hero(Vector3(0.0, 0.0, ROW_Z))
	for i in 10:
		var angle := TAU * float(i) / 10.0
		var at := Vector3(0.0, 0.0, ROW_Z) + Vector3(cos(angle), 0.0, sin(angle)) * 34.0
		var e := _spawner.spawn(EnemyTypes.RIPPER,
				Transform3D(Basis.looking_at((Vector3(0.0, 0.0, ROW_Z) - at).normalized(), Vector3.UP),
				at))
		if e == null:
			continue
		e.perception.acquire(get_node("Hero") as Node3D, false)
		_subjects.append(e)


## A parryable windup (white glint) and an unblockable one (red glow), frozen at the peak of the tell.
func _telegraph(unblockable: bool) -> void:
	var type: StringName = EnemyTypes.JUGGERNAUT if unblockable else EnemyTypes.MANTIS
	var e := _spawner.spawn(type, Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.0, ROW_Z + 30.0)))
	if e == null:
		return
	e.set_ai_enabled(false)
	var attack: EnemyAttack = null
	for a: EnemyAttack in e.attacks():
		if (a.kind == EnemyAttack.UNBLOCKABLE) == unblockable:
			attack = a
			break
	if attack == null:
		push_error("gallery: no %s attack on %s" % ["unblockable" if unblockable else "parryable", type])
		return
	e.play_action(attack.anim)
	e.begin_telegraph(attack)
	_tell_peak(e, attack)


## The model ramps its tell over the windup; drive it straight to the peak so a still frame shows it.
func _tell_peak(e: EnemyBase, attack: EnemyAttack) -> void:
	if e.model != null and e.model.has_method(&"set_telegraph"):
		e.model.call(&"set_telegraph", attack.kind, 1.0)
	e.set_physics_process(false)


## A staggered juggernaut: the finisher window, amber tell, stability broken (juice §7 ladder).
func _stagger() -> void:
	var e := _spawner.spawn(EnemyTypes.JUGGERNAUT,
			Transform3D(Basis(Vector3.UP, deg_to_rad(200.0)), Vector3(0.0, 0.0, ROW_Z)))
	if e == null:
		return
	e.set_ai_enabled(false)
	e.status.add_impact(e.status.stability_max)   ## fires the real stagger path: pose + amber tell
	e.set_physics_process(false)


## Two wrecks: the collapse pose monsters hold for 30 s before they dissolve.
func _wreck() -> void:
	var a := _spawner.spawn(EnemyTypes.RIPPER,
			Transform3D(Basis(Vector3.UP, deg_to_rad(210.0)), Vector3(-18.0, 0.0, ROW_Z)))
	var b := _spawner.spawn(EnemyTypes.MANTIS,
			Transform3D(Basis(Vector3.UP, deg_to_rad(200.0)), Vector3(18.0, 0.0, ROW_Z)))
	for e: EnemyBase in [a, b]:
		if e == null:
			continue
		e.set_ai_enabled(false)
		_kill(e)
		e._tick_wreck(0.8)   ## land the collapse tween at its end pose


func _kill(e: EnemyBase) -> void:
	var hit := HitInfo.make(e.hp_max * 2.0, HitInfo.BEAM, null, &"beam_rifle")
	hit.hurtbox_part = &"body"
	e.take_hit(hit)


## A 16 m grey box standing in for the hero, so scale reads in every shot.
func _hero(at: Vector3) -> Node3D:
	var body := StaticBody3D.new()
	body.name = "Hero"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.position = at
	add_child(body)
	_mesh(body, Vector3(8.0, 12.0, 6.0), Vector3(0.0, 8.0, 0.0), Color(0.72, 0.74, 0.78))
	_mesh(body, Vector3(4.0, 4.0, 4.0), Vector3(0.0, 16.0, 0.0), Color(0.82, 0.84, 0.88))
	return body


## The 16 m scale pillar that stands next to every monster in the line-up.
func _pillar(at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "ScalePillar"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.position = at
	add_child(body)
	_mesh(body, Vector3(1.6, PILLAR_HEIGHT, 1.6), Vector3(0.0, PILLAR_HEIGHT * 0.5, 0.0),
			Color(0.9, 0.9, 0.92))
	_mesh(body, Vector3(4.0, 0.6, 4.0), Vector3(0.0, PILLAR_HEIGHT, 0.0), Color(1.0, 0.85, 0.3))


func _mesh(parent: Node3D, size: Vector3, at: Vector3, colour: Color) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.6
	mi.material_override = mat
	parent.add_child(mi)
