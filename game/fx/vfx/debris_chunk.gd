class_name FxDebrisChunk
extends RefCounted
## Procedural rubble geometry for DebrisPool (feel unit). Four irregular low-poly chunks - a jittered
## cube, a slab, a wedge and a shard - built once at load so nothing is generated at shot time.
## Everything is a few hundred bytes of ArrayMesh; the look comes from rock.gdshader.

const VARIANTS := 4


## One irregular convex-ish chunk, roughly `radius` metres across, seeded so the four variants differ.
static func build(variant: int, radius: float = 0.5) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + variant * 7717
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match variant % VARIANTS:
		0:
			_jittered_box(st, rng, Vector3(1.0, 0.8, 0.9), radius, 0.28)
		1:
			_jittered_box(st, rng, Vector3(1.4, 0.34, 1.1), radius, 0.22)
		2:
			_wedge(st, rng, radius)
		_:
			_shard(st, rng, radius)
	st.generate_normals()
	return st.commit()


## A box whose 8 corners are pushed around: a broken block of concrete, not a cube.
static func _jittered_box(st: SurfaceTool, rng: RandomNumberGenerator, shape: Vector3,
		radius: float, jitter: float) -> void:
	var c: Array[Vector3] = []
	for i in 8:
		var v := Vector3(float(i & 1) - 0.5, float((i >> 1) & 1) - 0.5, float((i >> 2) & 1) - 0.5)
		c.append(v * shape * radius * 2.0 + Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0),
				rng.randf_range(-1.0, 1.0)) * radius * jitter)
	_face(st, c[0], c[2], c[3], c[1])   # -x
	_face(st, c[4], c[5], c[7], c[6])   # +x
	_face(st, c[0], c[1], c[5], c[4])   # -y
	_face(st, c[2], c[6], c[7], c[3])   # +y
	_face(st, c[0], c[4], c[6], c[2])   # -z
	_face(st, c[1], c[3], c[7], c[5])   # +z


## A wedge: one corner sheared off, the shape of a slab that broke diagonally.
static func _wedge(st: SurfaceTool, rng: RandomNumberGenerator, radius: float) -> void:
	var c: Array[Vector3] = []
	for i in 8:
		var v := Vector3(float(i & 1) - 0.5, float((i >> 1) & 1) - 0.5, float((i >> 2) & 1) - 0.5)
		v += Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(-0.1, 0.1), rng.randf_range(-0.1, 0.1))
		c.append(v * radius * 2.0)
	c[1] = Vector3(-0.1, 0.5, -0.5) * radius * 2.0   # pull one top corner in: a sheared break
	c[3] = c[1] + Vector3(0.0, -0.3, 0.4) * radius
	c[5] = c[1] + Vector3(0.4, -0.3, 0.0) * radius
	c[7] = (c[1] + c[3] + c[5]) / 3.0
	_face(st, c[0], c[2], c[3], c[1])
	_face(st, c[4], c[5], c[7], c[6])
	_face(st, c[0], c[1], c[5], c[4])
	_face(st, c[2], c[6], c[7], c[3])
	_face(st, c[0], c[4], c[6], c[2])
	_face(st, c[1], c[3], c[7], c[5])


## A thin shard: long, flat, sharp - a piece of plating or a pane of concrete.
static func _shard(st: SurfaceTool, rng: RandomNumberGenerator, radius: float) -> void:
	_jittered_box(st, rng, Vector3(0.35, 0.22, 1.7), radius, 0.35)


## Outward-facing quad. The winding is fixed against the chunk centre, so a jittered corner can never
## turn a face inside out and leave it black.
static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a)
	var outward := (a + b + c) / 3.0
	if n.dot(outward) < 0.0:
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(b)
	else:
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)

