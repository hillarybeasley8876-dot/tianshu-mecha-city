class_name ChaffCloud
extends Node3D
## Test stand-in for the Spitter's spore-chaff cloud (enemies unit). The missile manager looks for
## nodes in group `&"chaff"` and reads their `radius` when they have one.

@export var radius: float = 14.0


func _ready() -> void:
	add_to_group(&"chaff")
