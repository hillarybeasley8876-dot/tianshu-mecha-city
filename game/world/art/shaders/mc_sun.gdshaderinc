// mc_sun (city-art r14, lead brief r14 §2) — how much of a window's own light survives on a face the
// sun is on.
//
// The key art's golden hour has SPARSE warm lit windows, and they read in the SHADOWED faces: a wall
// the low sun is on is a hundred times brighter than the lamp behind the glass, so a lit cell there is
// invisible in life and has to be invisible here. Without this the same `mc_lit_fraction` lights every
// cell on every wall and the midground towers glitter in broad daylight, which is the first thing the
// lead's r14 brief names.
//
// `sun_dir` and `sun_face_kill` are pushed by `McMaterials.set_sun` (TimeOfDay owns the ramp, the same
// way it owns the haze and the wetness), so a material that declares `sun_dir` is collected onto the
// sun push list as it is built. `sun_face_kill` is ~0.9 through the golden hour and falls toward 0.3
// under the storm, when the sun is at 5 degrees and the city is lit by its own lights.

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform float sun_face_kill : hint_range(0.0, 1.0) = 0.0;

// 1.0 on a face turned away from the sun, (1 - sun_face_kill) on one square to it.
float sun_face_dim(vec3 world_normal) {
	return 1.0 - sun_face_kill * clamp(dot(normalize(world_normal), sun_dir), 0.0, 1.0);
}
