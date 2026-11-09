class_name CombatMesh
extends RefCounted
## Mesh and material builders shared by the saber, the shield and the crescent (melee + defence).
##
## The important one is `hdr()`: an UNSHADED material shows its albedo directly, so an albedo whose
## channels exceed 1.0 is what actually crosses the glow threshold and blooms under ART.md's
## environment. Setting `emission_energy_multiplier` on an unshaded material does nothing — that was
## why the blade, the trail and the shield read as flat paint in the r1 captures.

## Additive, unshaded, HDR: albedo is `color * energy`, so energy > 1 blooms. `alpha` stays ≤ 1.
static func hdr(color: Color, energy: float, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, alpha)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m


## Same, but the mesh supplies the colour through its vertex colours (ribbons, gradients).
static func hdr_vertex() -> StandardMaterial3D:
	var m := hdr(Color.WHITE, 1.0, 1.0)
	m.vertex_color_use_as_albedo = true
	return m


## The swing ribbon's material. NOT `hdr_vertex()`: StandardMaterial3D's ADD blend mode ignores the
## vertex alpha, so a ribbon built on it renders as one flat card at full brightness and then snaps
## off — which is exactly what the r4 filmstrips showed. Godot's `blend_add` render mode is
## SRC_ALPHA/ONE, so this fades along its length the way a trail has to.
static func trail() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


## A tapered blade: a flattened four-sided prism `length` long, `root_half` across at the hilt and
## drawn to a point at the tip (ART.md hero cyan-white). It runs along −Z with the origin at the
## hilt, so the caller can drop it straight onto a socket.
static func blade(length: float, root_half: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	## [distance along the blade, half-width there] — the taper the r1 review asked for.
	var sections: Array[Vector2] = [
		Vector2(0.0, root_half * 0.7), Vector2(length * 0.05, root_half),
		Vector2(length * 0.7, root_half * 0.66), Vector2(length * 0.92, root_half * 0.36),
		Vector2(length, 0.0),
	]
	for i in sections.size() - 1:
		var a := sections[i]
		var b := sections[i + 1]
		_segment(st, -a.x, a.y, -b.x, b.y)
	var mesh := st.commit()
	mesh.surface_set_material(0, hdr_vertex())
	return mesh


## One span of the blade between two cross-sections (a flattened diamond, so it catches light on a
## bevel and reads as a blade rather than a stick).
static func _segment(st: SurfaceTool, z0: float, h0: float, z1: float, h1: float) -> void:
	var ring0 := _section(z0, h0)
	var ring1 := _section(z1, h1)
	for i in 4:
		var j := (i + 1) % 4
		_tri(st, ring0[i], ring1[i], ring1[j])
		_tri(st, ring0[i], ring1[j], ring0[j])


static func _section(z: float, h: float) -> Array[Vector3]:
	return [
		Vector3(0.0, h, z), Vector3(h * 0.34, 0.0, z), Vector3(0.0, -h, z), Vector3(-h * 0.34, 0.0, z),
	]


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a)
	st.set_normal(n.normalized() if n.length_squared() > 1e-8 else Vector3.UP)
	st.set_color(Color.WHITE)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
