class_name FlowHivePods
extends RefCounted
## The look of one hive weak point (look/flow.md item 1): a cluster of 3–5 translucent sacs growing
## out of the trunk, not the single flat emissive sphere the user called a debug gizmo.
##
## Every sac of a cluster is merged into ONE ArrayMesh through SurfaceTool, so a spire costs five
## draw calls for its weak points (four pods + the core) instead of twenty, and a burst pod is still a
## single `visible = false`. Layout is seeded, so a spire looks the same every run and the E2E bot's
## captured frames are comparable.
##
## Local frame: +Y is the trunk's surface normal at the anchor, the sacs spread in the tangent plane
## and sink SUNK of their radius back into the shell.

const SHADER: Shader = preload("res://flow/hive_pod.gdshader")
## The review's floor. A 12x6 sphere at 60 m reads as a flat disc with a visible polygon outline.
const SAC_SEGMENTS := 32
const SAC_RINGS := 16
const SACS_MIN := 3
const SACS_MAX := 5
## Metres across the cluster: the review asks for 3–4 m sacs.
const SAC_RADIUS := 1.85
const SAC_SPREAD := 2.1
## Fraction of a sac's radius that stays under the shell — half sunk, per the review.
const SUNK := 0.28
const SQUASH := 0.78               ## flattened along the normal, so a sac hugs the trunk
const CORE_ENERGY := 1.45          ## review ceiling: 1.5


## One pod: a MeshInstance3D whose mesh is every sac of the cluster, placed by the caller. `spread`
## and `sunk` are the cluster's own knobs — the core packs its sacs tighter and pushes them further
## out of the shell than a pod does (`FlowHiveCore`).
static func cluster(color: Color, sac_radius: float, seed_value: int, spread: float = SAC_SPREAD,
		sunk: float = SUNK) -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := rng.randi_range(SACS_MIN, SACS_MAX)
	for i in count:
		_append_sac(tool, rng, sac_radius, float(i), float(count), spread, sunk)
	var mesh := tool.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material(color, phase_of(seed_value))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Cluster"
	return mi


## The cluster stood up on the trunk: +Y along `normal` (the sac's "out") and stepped `out` metres
## from the anchor onto the surface — the anchor sits inside the shell so the Hurtbox is flush with
## the mesh, and a cluster left there would be buried and read nothing.
static func on_trunk(color: Color, at: Vector3, normal: Vector3, sac_radius: float, seed_value: int,
		out: float) -> MeshInstance3D:
	var mi := cluster(color, sac_radius, seed_value)
	var up := normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP
	var axis := Vector3.UP.cross(up)
	var basis := Basis.IDENTITY
	if axis.length_squared() > 0.0001:
		basis = Basis(axis.normalized(), Vector3.UP.angle_to(up))
	elif up.dot(Vector3.UP) < 0.0:
		basis = Basis(Vector3.RIGHT, PI)
	mi.transform = Transform3D(basis, at + up * out)
	return mi


## Each cluster breathes on its own offset, so four pods on one trunk do not pulse as one object.
static func phase_of(seed_value: int) -> float:
	return float(seed_value % 997) * 0.0137


static func material(color: Color, phase: float, energy: float = CORE_ENERGY) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter(&"acid", color)
	mat.set_shader_parameter(&"phase", phase)
	mat.set_shader_parameter(&"core_energy", minf(energy, CORE_ENERGY))
	return mat


## The same membrane, breathing on a caller's band — the hive core asks for 0.6 -> 1.4 at 1.2 Hz
## (flow-look-r1 polish 1), a heartbeat rather than the pods' slow swell.
static func beating(color: Color, phase: float, lo: float, hi: float, hz: float,
		energy: float = CORE_ENERGY, mottle_scale: float = 6.0) -> ShaderMaterial:
	var mat := material(color, phase, energy)
	mat.set_shader_parameter(&"pulse_lo", lo)
	mat.set_shader_parameter(&"pulse_hi", hi)
	mat.set_shader_parameter(&"pulse_hz", hz)
	mat.set_shader_parameter(&"mottle_scale", mottle_scale)
	return mat


## The lead sac sits on the anchor; the rest ring it, each pushed out along the tangent plane and
## sunk back along -Y so the shell grows over it.
static func _append_sac(tool: SurfaceTool, rng: RandomNumberGenerator, sac_radius: float,
		index: float, count: float, spread: float, sunk: float) -> void:
	var lead := index < 1.0
	var r := sac_radius * (1.25 if lead else rng.randf_range(0.62, 0.95))
	var a := TAU * index / maxf(count - 1.0, 1.0) + rng.randf_range(-0.4, 0.4)
	var reach := 0.0 if lead else spread * rng.randf_range(0.75, 1.15)
	var spin := 0.0 if lead else rng.randf_range(0.0, TAU)
	var basis := Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3), spin,
			rng.randf_range(-0.3, 0.3)))
	var at := Vector3(cos(a) * reach, 0.0, sin(a) * reach) + Vector3.DOWN * r * sunk
	tool.append_from(_sphere(r), 0, Transform3D(basis.scaled(Vector3(1.0, SQUASH, 1.0)), at))


static func _sphere(radius: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = SAC_SEGMENTS
	s.rings = SAC_RINGS
	return s
