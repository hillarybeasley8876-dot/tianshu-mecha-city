extends Node
## The real game plus this unit's stack (`world/post/tests/game_with_post.tscn`).
##
## The brief's "patch list applied" step needs the stack inside `main.tscn`, which is the lead's file —
## until that lands (see `status/post-render.md` `## Requests`) this harness wraps the shipped game so the
## in-play A/B and the fight frame times are still measured on the real scene graph, not a look-dev stand-in:
##
##   tools/godot.sh drive --scene=res://world/post/tests/game_with_post.tscn --sandbox \
##     --timeline=res://enemies/tests/fight_timeline.json --shots=3,6 --out=post_fight
##   tools/godot.sh drive ... --no-post            (the "before" half)

const GAME_SCENE := "res://main.tscn"
const POST_SCENE := "res://world/post/post_stack.tscn"


func _ready() -> void:
	var post := (load(POST_SCENE) as PackedScene).instantiate()
	post.name = "PostStack"
	add_child(post)
	var game := (load(GAME_SCENE) as PackedScene).instantiate()
	game.name = "Game"
	add_child(game)
	print("GAME+POST stack=%s" % [(post as PostStack).enabled])
