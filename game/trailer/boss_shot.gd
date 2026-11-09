extends Node3D
## Trailer wrapper around the boss unit's showcase scene (trailer unit, lead brief trailer-r2 §4).
##
##   tools/godot.sh movie --movie=<abs.avi> --scene=res://trailer/boss_shot.tscn \
##       --timeline=res://trailer/tl_s08_boss.json --trailer-rig=res://trailer/rig_boss_intro.json \
##       --god --tod=0.9 --boss-beats=…
##
## The showcase's own intro camera sits under the Crown deck, so the first seconds of the take are
## black. This wrapper instances the showcase untouched and puts a camera-kit rig in front of it for
## that window, then hands the view back to the boss's own camera. Nothing in the boss unit changes.

const SHOWCASE := "res://enemies/boss/tests/boss_showcase.tscn"

var rigs: Array[TrailerCamRig] = []


func _ready() -> void:
	var packed := load(SHOWCASE) as PackedScene
	if packed == null:
		push_error("TrailerBossShot: cannot load " + SHOWCASE)
		return
	add_child(packed.instantiate())
	_load_rigs()


func _load_rigs() -> void:
	var log_base := Game.flag("trailer-log", "")
	for i in 2:
		var path := Game.flag("trailer-rig" if i == 0 else "trailer-rig2", "")
		if path == "":
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary:
			push_error("TrailerBossShot: %s is not a rig JSON object" % path)
			continue
		var rig := TrailerCamRig.new()
		rig.name = "TrailerRig%d" % i
		add_child(rig)
		var log_path := log_base
		if log_path != "" and i > 0:
			log_path = log_path.get_basename() + "_%d.csv" % i
		rig.setup(data as Dictionary, log_path)
		rigs.append(rig)
