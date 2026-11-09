class_name FxImpact
extends Node3D
## One pooled impact spark burst (feel unit): the velocity-stretched streaks plus the small
## camera-facing contact flash that marks the hit point. The streaks alone vanish at range, so the
## pop is what makes a 150 m hit read at all (r2 MUST-FIX 3); the streaks themselves also carry a
## screen-space size floor in fx/vfx/spark.gdshader.

var sparks: GPUParticles3D
var pop: FxFlashPop


func _ready() -> void:
	visible = false


## Builds the composite around an already-configured spark emitter.
func setup(emitter: GPUParticles3D, pop_node: FxFlashPop) -> void:
	sparks = emitter
	sparks.name = "Sparks"
	add_child(sparks)
	pop = pop_node
	pop.name = "Pop"
	add_child(pop)
	visible = false


## Fired by VfxLibrary. `radius` is unused: a spark burst is sized by `scale`, and it aims itself
## away from the surface it hit.
func fire(_at: Vector3, normal: Vector3, _radius: float, scale_mul: float = 1.0) -> void:
	visible = true
	global_basis = VfxPresets.facing(normal)
	var k := clampf(scale_mul, 0.05, 40.0)
	sparks.scale = Vector3.ONE
	VfxPresets.set_size_mul(sparks, k)
	VfxPresets.restart(sparks)
	pop.pop(1.4 * k, 0.075, VfxPresets.HOT, 5.0, 0.25)


func stop() -> void:
	visible = false
	if sparks != null:
		sparks.emitting = false
	if pop != null:
		pop.stop()
