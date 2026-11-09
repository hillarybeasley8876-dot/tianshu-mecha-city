class_name FlowFakeEnemy
extends Node3D
## The smallest thing the encounter director tracks: a live monster with a type and an alive flag.
## The wave suite kills these to drive the start conditions without a navmesh or an AI.

var enemy_type: StringName = &"ripper"
var alive: bool = true


func is_alive() -> bool:
	return alive


func get_team() -> int:
	return 1
