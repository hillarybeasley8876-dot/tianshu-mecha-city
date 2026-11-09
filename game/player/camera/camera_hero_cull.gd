extends Node
## First-person chassis cull (camera-aim, lead r7 item 1). In the cockpit the lens sits 1.2 m in front
## of the model's `cockpit` socket — i.e. INSIDE the mech's own head — and `Hero3Aim` solves the weapon
## onto the aim line, which in first person starts at the lens. The rifle/gatling is therefore swung
## across the canopy the moment the trigger is held, and the frame goes black (r7 repro: the cockpit
## reads clean for ~1 s after `camera_toggle`, then black while `fire` is down).
##
## The fix is the one every first-person game uses: the pilot does not see their own chassis. The
## hero's visual instances are moved onto ONE dedicated visual layer and the first-person camera clears
## that layer from its `cull_mask`, so the body is hidden from THIS camera only — the trailer's
## cinematic cameras, the canopy HUD's SubViewport, the debug camera and every shadow keep seeing it,
## and third person is untouched.
##
## A cull mask rather than `visible = false` because hero-v3 shows and hides its own weapon nodes from
## its own tick (`set_saber_drawn`, the rifle swap) and would undo the flag on the next frame.
## Bit 18 is free: nothing in the tree sets `VisualInstance3D.layers` (checked across every .tscn).

const HIDE_BIT := 1 << 18        ## visual layer 19; everything else in the tree renders on layer 1
const RETAG_TICKS := 30          ## re-walk the model this often, so a weapon spawned later is caught

var _cam: Camera3D = null
var _bound: Node3D = null
var _ticks: int = 0


func setup(cam: Camera3D) -> void:
	_cam = cam


## Tag the hero model's visual subtree and set the camera's cull mask for this tick. `fp` is the rig's
## first-person blend: from 0.5 the canopy owns the frame, so the chassis goes.
func update(fp: float, player: Node3D) -> void:
	if _cam == null:
		return
	_ticks += 1
	if _ticks >= RETAG_TICKS or _bound == null:
		_ticks = 0
		_tag(player)
	_cam.cull_mask = _cam.cull_mask & ~HIDE_BIT if fp > 0.5 else _cam.cull_mask | HIDE_BIT


func _tag(player: Node3D) -> void:
	var model := player.call(&"model") as Node3D if player != null and player.has_method(&"model") \
			else null
	if model == null:
		return
	_bound = model
	_tag_node(model)


func _tag_node(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = HIDE_BIT
	for c in node.get_children():
		_tag_node(c)
