extends Node
## city-art r16a: the settle index must be a STATIC world (world/art/tests/test_surface_static.gd).
## Run: tools/godot.sh test res://world/art/tests/test_surface_static.gd
##
## `PhysicsServer3D.body_create()` returns a DYNAMIC body in 4.7.2 + Jolt, and `ArtSurfaces` never set a
## mode — so every support the settle pass and `tools/float_audit.gd` measured was falling at 9.8 m/s²
## from the tick it entered the space. A top face that starts at y = 0 is at y = −4.94 one second later,
## and any ray cast after that describes a world that has sunk. Found by hero-v3 r9
## (`game/player/model/hero3/tests/probe_surface_mode.gd`), which read this same class.
##
## This test is the gate: a support's top face must still be where it was after a full second of
## physics. Both bodies are checked — the one shared body per kind, and the per-support body the
## diagnostics build with `named`.

## A second of simulated time at the fixed 120 Hz every `tools/godot.sh` run uses.
const TICKS := 120
## A support may not move by more than this. A dynamic body moves 4 905 mm in the same second.
const DRIFT := 0.01

var _failures: int = 0


func _ready() -> void:
	# The root viewport's world: a head-less run still simulates physics, which is the whole point.
	var world := get_viewport().world_3d
	_expect(world != null, "the test runs inside a viewport with a World3D")
	if world == null:
		_done()
		return
	for named: bool in [false, true]:
		await _check(world, named)
	_done()


## One `ArtSurfaces` index holding a single box, measured before and after a second of physics.
func _check(world: World3D, named: bool) -> void:
	var what := "named body" if named else "shared body"
	var surfaces := ArtSurfaces.new()
	surfaces.named = named
	if not surfaces.setup(world):
		_expect(false, "%s: ArtSurfaces.setup() found a world" % what)
		return
	var box := BoxMesh.new()
	box.size = Vector3(4.0, 0.2, 4.0)
	# Identity transform, so the box's top face is at y = +0.1 and its centre column is the origin.
	surfaces.add(box, Transform3D.IDENTITY, "probe_box", ArtSurfaces.ROOF)
	_expect(surfaces.size() == 1, "%s: the index holds the one support it was given" % what)
	var before := _top(surfaces, what)
	_expect(not is_nan(before), "%s: a ray from y = 3 finds the box's top face" % what)
	if is_nan(before):
		surfaces.dispose()
		return
	for i in TICKS:
		await get_tree().physics_frame
	var after := _top(surfaces, what)
	var drift := after - before
	_expect(not is_nan(after) and absf(drift) < DRIFT,
			"%s: the support is still at y %.3f after %.1f s of physics (was %.3f, drift %+.3f m)"
			% [what, after, float(TICKS) / 120.0, before, drift])
	surfaces.dispose()


## The y of the highest surface under the origin, or NAN when the ray found nothing.
func _top(surfaces: ArtSurfaces, what: String) -> float:
	var hit := surfaces.top_below(Vector3(0.0, 3.0, 0.0), [ArtSurfaces.ROOF] as Array[StringName])
	if hit.is_empty():
		push_warning("test_surface_static: %s — no surface under the probe point" % what)
		return NAN
	return float(hit["y"])


func _done() -> void:
	print("SURFACE STATIC TEST %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	if ok:
		return
	_failures += 1
	print("SURFACE STATIC FAIL: %s" % what)
