class_name Hero3Surface
extends RefCounted
## A front-surface sampler over one bone's armour vertices (hero-v3, lead r8 item 2).
##
## The r7 glow panels were FLAT quads placed at the frontmost point of their own footprint. On a domed
## helm that is a TANGENT PLANE: measured, the visor quad touched the armour at the midline and floated
## 0.40 m in front of it at both ends, which is the glowing rod the lead saw sticking out of the helmet.
## A panel built from samples of the real surface cannot do that -- every one of its vertices lies ON
## the armour, so its silhouette is the armour's silhouette.
##
## It is a bucket grid rather than a per-sample search: a panel is ~90 samples and a bone carries
## 50-80k vertices, so the naive loop is millions of distance tests at model setup -- seconds of hitch
## for a number a 10 cm bucket answers exactly as well.

## Metres per bucket. Finer than the panel's own sample spacing (5-10 cm), so the bucket grid is never
## the thing that limits the panel's accuracy.
const CELL := 0.10
## How far a sample may look for a surface point, in metres. A sample further than this from any
## armour is off the plate, and `sample` says so rather than inventing a point in mid-air.
const REACH := 0.16

var _points: PackedVector3Array = PackedVector3Array()
var _filled: PackedByteArray = PackedByteArray()
var _origin := Vector2.ZERO
var _size := Vector2i.ZERO


## Index the bone's vertices by their (x, y). Only the FRONTMOST vertex of each bucket is kept: the
## question every sample asks is "what is the nearest bit of the plate that faces the camera", and the
## front of a bucket is the only part of it that can answer.
func build(pts: Array[Vector3]) -> void:
	_points = PackedVector3Array()
	_filled = PackedByteArray()
	if pts.is_empty():
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		lo = lo.min(Vector2(p.x, p.y))
		hi = hi.max(Vector2(p.x, p.y))
	_origin = lo
	_size = Vector2i(int((hi.x - lo.x) / CELL) + 1, int((hi.y - lo.y) / CELL) + 1)
	_points.resize(_size.x * _size.y)
	_filled.resize(_size.x * _size.y)
	for p in pts:
		var i := _index(p.x, p.y)
		if i < 0:
			continue
		if _filled[i] == 0 or p.z < _points[i].z:
			_points[i] = p
			_filled[i] = 1


## The armour's own surface point nearest (x, y), or a point with `z == INF` when the plate does not
## reach there. Callers use the INF to shrink a panel rather than to draw one that hangs in the air.
func sample(x: float, y: float) -> Vector3:
	if _points.is_empty():
		return Vector3(x, y, INF)
	var cx := int(floor((x - _origin.x) / CELL))
	var cy := int(floor((y - _origin.y) / CELL))
	var span := int(ceil(REACH / CELL))
	var best := Vector3(x, y, INF)
	var best_d := INF
	for j in range(cy - span, cy + span + 1):
		if j < 0 or j >= _size.y:
			continue
		for i in range(cx - span, cx + span + 1):
			if i < 0 or i >= _size.x:
				continue
			var k := j * _size.x + i
			if _filled[k] == 0:
				continue
			var p := _points[k]
			var d := Vector2(p.x - x, p.y - y).length_squared()
			if d > REACH * REACH or d >= best_d:
				continue
			best_d = d
			best = p
	return best


## The FRONTMOST armour point within `radius` of (x, y), or a point with `z == INF` when nothing is
## that close. This is the number a conformed sheet is built from, and the radius is what makes the
## sheet provably clear of the mesh: a sheet vertex placed at `front(x, y, r) - PROUD` with
## `r` at least the panel's own cell diagonal is in front of every surface point in its cell, because
## every one of them is inside that disc. Sampling the NEAREST point instead (which is what
## `sample` does) only clears the mesh where the mesh is smooth -- measured, the chest plate's raised
## ridges poked back through a 3 cm offset and the atlas showed through the grille as cream blotches.
func front(x: float, y: float, radius: float) -> Vector3:
	if _points.is_empty():
		return Vector3(x, y, INF)
	var cx := int(floor((x - _origin.x) / CELL))
	var cy := int(floor((y - _origin.y) / CELL))
	var span := int(ceil(radius / CELL))
	var best := Vector3(x, y, INF)
	for j in range(cy - span, cy + span + 1):
		if j < 0 or j >= _size.y:
			continue
		for i in range(cx - span, cx + span + 1):
			if i < 0 or i >= _size.x:
				continue
			var k := j * _size.x + i
			if _filled[k] == 0:
				continue
			var p := _points[k]
			if Vector2(p.x - x, p.y - y).length_squared() > radius * radius:
				continue
			if p.z < best.z:
				best = p
	return best


## True when the plate covers (x, y) -- the panel-sizing predicate.
func covers(x: float, y: float) -> bool:
	return sample(x, y).z < INF


func _index(x: float, y: float) -> int:
	var i := int(floor((x - _origin.x) / CELL))
	var j := int(floor((y - _origin.y) / CELL))
	if i < 0 or j < 0 or i >= _size.x or j >= _size.y:
		return -1
	return j * _size.x + i
