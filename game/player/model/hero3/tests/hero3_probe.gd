class_name Hero3Probe
extends Node3D
## Shared plumbing for the hero-v3 r7 look probes (`hero3_read.gd`, `hero3_look.gd`): both drive the
## REAL game (`res://main.tscn`) from a fixed camera and both need the same three things -- wait for
## the city to finish building, grab a frame that cannot hang on a throttled display loop, and put it
## somewhere the Python side can measure.
##
## The frame grab is city-art r14's: `frame_post_draw` normally arrives on the next frame, but a
## windowed Godot on macOS throttles its display loop while another window covers it, so after a few
## frames the server is told to draw and the frame is taken whatever produced it.

const MAIN := "res://main.tscn"
## Frames the temporal upscaler needs to forget the geometry it was fed.
const HIDE_SETTLE := 26
const DRAW_TIMEOUT_FRAMES := 240

var out_dir: String = ""
var warm: int = 40
var tag: String = "r7"

var _drew: bool = false


## Instance the real game under this probe and give it a camera of its own. Returns the game node.
func boot() -> Node3D:
	var main := (load(MAIN) as PackedScene).instantiate()
	main.name = "Main"
	add_child(main)
	return main


func probe_dir(rel: String) -> String:
	out_dir = ProjectSettings.globalize_path("res://").path_join("..").path_join(rel)
	DirAccess.make_dir_recursive_absolute(out_dir)
	return out_dir


func wait_world() -> void:
	var game: Node = get_tree().root.get_node_or_null("Game")
	if game == null or game.get("world") == null:
		return
	var waited := 0.0
	while not bool(game.call("world_built")) and waited < 120.0:
		await get_tree().process_frame
		waited += get_tree().process_delta_time
	print("PROBE world ready after %.1f s" % waited)


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## The world's TimeOfDay, so a probe can sweep `--tod` in one run instead of one run per light.
func time_of_day() -> TimeOfDay:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is TimeOfDay:
			return node as TimeOfDay
		stack.append_array(node.get_children())
	return null


func hide_canvas(node: Node) -> void:
	for child in node.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
		hide_canvas(child)


func save_png(img: Image, stem: String) -> void:
	if img.save_png(out_dir.path_join(stem + ".png")) != OK:
		push_error("Hero3Probe: cannot write %s.png" % stem)


func grab() -> Image:
	_drew = false
	RenderingServer.frame_post_draw.connect(_on_drawn, CONNECT_ONE_SHOT)
	for i in DRAW_TIMEOUT_FRAMES:
		await get_tree().process_frame
		if _drew:
			break
		if i == 8:
			RenderingServer.force_draw(false)
	if not _drew:
		push_warning("Hero3Probe: frame_post_draw never fired — this frame is the previous one")
		if RenderingServer.frame_post_draw.is_connected(_on_drawn):
			RenderingServer.frame_post_draw.disconnect(_on_drawn)
	return get_viewport().get_texture().get_image()


func _on_drawn() -> void:
	_drew = true
