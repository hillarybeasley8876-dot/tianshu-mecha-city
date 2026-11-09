extends StaticBody3D
## Capture-only target dummy (camera-aim): a damageable-looking block with a lock point, used by
## `camera_demo.tscn` so lock-on states can be photographed before the enemies unit exists.
## Targetable.actor() walks up the parents until it finds `take_hit`.

@export var tint: Color = Color(0.55, 0.25, 0.3)
## CONTRACTS §5 large-target framing: the rig asks the actor how tall it is and reframes at ≥ 30 m.
## 0 = an ordinary street target, which leaves the 42 m street shot alone. The rig calls the METHOD,
## so the export below is only the number it returns.
@export var declared_height: float = 0.0
@export var size: Vector3 = Vector3(10.0, 18.0, 10.0)

var _alive: bool = true


func _ready() -> void:
	collision_layer = Layers.ENEMY
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)
	var body := _block(size, Vector3.ZERO, tint)
	var mark := Targetable.new()
	mark.name = "Mark"
	add_child(mark)
	if declared_height >= 30.0:
		_make_giant(body)


## A giant reads as a giant only with a silhouette, so the large-target captures show what the extra
## 22 m of arm is buying. The collision box stays the full declared height; the visible body is rebuilt
## as legs + torso + head inside it.
func _make_giant(body: MeshInstance3D) -> void:
	var h := size.y
	var half := h * 0.5
	var torso := Vector3(size.x * 0.78, h * 0.44, size.z * 0.66)
	var leg := Vector3(size.x * 0.24, h * 0.5, size.z * 0.42)
	body.mesh = _box_mesh(torso)
	body.position = Vector3(0.0, half - h * 0.28, 0.0)
	_block(leg, Vector3(-size.x * 0.26, -half + h * 0.25, 0.0), tint.darkened(0.25))
	_block(leg, Vector3(size.x * 0.26, -half + h * 0.25, 0.0), tint.darkened(0.25))
	_block(Vector3(size.x * 0.34, h * 0.14, size.z * 0.34), Vector3(0.0, half - h * 0.06, 0.0),
			tint.darkened(0.4))


func _block(extents: Vector3, at: Vector3, colour: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _box_mesh(extents)
	mesh.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.metallic = 0.3
	mat.roughness = 0.6
	mesh.material_override = mat
	add_child(mesh)
	return mesh


func _box_mesh(extents: Vector3) -> BoxMesh:
	var bm := BoxMesh.new()
	bm.size = extents
	return bm


func framing_height() -> float:
	return declared_height


func take_hit(_hit: HitInfo) -> void:
	pass


func is_alive() -> bool:
	return _alive
