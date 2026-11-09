class_name ArenaProbes
extends Node3D
## One ReflectionProbe per arena (city-art, ART.md §3: with GI off, "one ReflectionProbe per arena").
## Arenas are where the fights happen and where the wet plazas and dark glass need something to
## reflect; the rest of the city uses the sky. Probes are created at load only — godot-tech §4.6 warns
## that the FIRST probe added mid-game triggers a pipeline compile, which is a visible stutter.
## Disabled entirely on the low preset (`ArtQuality` `reflection_probes`).

const MARGIN := 30.0        ## metres added around the arena's bounds
const MIN_SIZE := 60.0
const UPDATE_MODE := ReflectionProbe.UPDATE_ONCE


## Builds a probe per arena from the layout's `arenas` array. Returns how many were created.
func build(arenas: Array) -> int:
	if not bool(ArtQuality.get_preset().get("reflection_probes", false)):
		return 0
	var made := 0
	for a in arenas:
		var box := _bounds(a.get("polygon", []))
		if box.size.length_squared() < 1.0:
			continue
		var tiers: Array = a.get("tiers", [0.0])
		var low := INF
		var high := -INF
		for t in tiers:
			low = minf(low, float(t))
			high = maxf(high, float(t))
		if low == INF:
			low = 0.0
			high = 0.0
		var probe := ReflectionProbe.new()
		probe.name = "probe_" + String(a.get("id", "arena"))
		probe.update_mode = UPDATE_MODE
		probe.box_projection = false
		probe.intensity = 1.0
		probe.max_distance = 260.0
		probe.size = Vector3(
			maxf(box.size.x + MARGIN * 2.0, MIN_SIZE),
			maxf(high - low + MARGIN * 3.0, MIN_SIZE),
			maxf(box.size.y + MARGIN * 2.0, MIN_SIZE))
		# Godot coordinates: Blender (x, y) -> (x, -y).
		probe.position = Vector3(box.get_center().x, (low + high) * 0.5 + MARGIN,
			-box.get_center().y)
		add_child(probe)
		made += 1
	return made


## 2D bounds of a layout polygon in Blender X/Y.
func _bounds(polygon: Array) -> AABB:
	var r := AABB()
	var first := true
	for p in polygon:
		var v := Vector3(float(p[0]), 0.0, float(p[1]))
		if first:
			r = AABB(v, Vector3.ZERO)
			first = false
		else:
			r = r.expand(v)
	return r
