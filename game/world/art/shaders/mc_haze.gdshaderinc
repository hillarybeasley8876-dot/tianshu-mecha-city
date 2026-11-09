// mc_haze (city-art, review r3 §3 "Depth") — the city's aerial perspective, in two bands.
//
// Godot's depth fog is ONE colour over ONE curve that saturates at `fog_depth_end`. At 1.3 km it was
// already ~85 % of the warm fog colour, which is why every distant block merged into one flat orange
// band. The key art is layered: warm gold in the near/mid band the low sun is scattering through, then
// a cooler violet-blue past ~700 m, with the far towers still reading as separate silhouettes.
// So the materials that make up the city turn the built-in fog OFF (`fog_disabled`) and do this
// instead. A shader cannot post-process the lit result, so the air is applied the way in-scattering
// actually behaves: the surface's own contrast is pulled toward the haze colour and the haze colour is
// added back as emission.
// `eye` is passed in rather than read from CAMERA_POSITION_WORLD: code in an include is parsed outside
// the fragment scope, where the built-ins do not resolve.

uniform vec3 haze_near : source_color = vec3(0.91, 0.80, 0.66);
uniform vec3 haze_far : source_color = vec3(0.43, 0.41, 0.55);
uniform float haze_near_begin = 60.0;
uniform float haze_near_end = 600.0;
uniform float haze_near_amount : hint_range(0.0, 1.0) = 0.0;
uniform float haze_far_begin = 750.0;
uniform float haze_far_end = 1900.0;
uniform float haze_far_amount : hint_range(0.0, 1.0) = 0.0;
// How bright the air itself is, as a fraction of the haze colour. It has to land just under the sky's
// own horizon value or a hazed tower turns into a light source.
uniform float haze_gain = 0.62;

// The colour of the air in front of this fragment (rgb) and how much of it there is (a).
vec4 layered_haze(vec3 world, vec3 eye) {
	if (haze_near_amount + haze_far_amount <= 0.001) {
		return vec4(0.0);
	}
	float d = distance(world, eye);
	float near_t = smoothstep(haze_near_begin, haze_near_end, d) * haze_near_amount;
	float far_t = smoothstep(haze_far_begin, haze_far_end, d) * haze_far_amount;
	float total = near_t + far_t;
	return vec4(mix(haze_near, haze_far, far_t / max(total, 1e-4)), min(total, 0.94));
}

// Applies the air in front of a surface and returns the emission it should carry instead.
//
// A shader cannot touch the lit result, so the surface is handed over to the haze: its albedo is
// crushed toward black (which kills the warm key's contribution) and the in-scattered light is added
// as emission. Mixing the albedo toward the haze COLOUR instead — the obvious version — does nothing
// useful, because the warm sun then re-warms the result and the far band stays orange.
//
// Lead r4: crushing the surface to 12 % made every mid-distance block converge on exactly the haze
// value, which is a flat field — no silhouettes, no lit windows, and no detail energy past 200 m.
// Real in-scattering leaves some of the object: 30 % of its albedo response and 25 % of its own
// emission survive, so a tower still reads as a tower through the air.
vec3 apply_haze(inout vec3 albedo, vec3 emission, vec4 h) {
	albedo = mix(albedo, albedo * 0.30, h.a);
	return mix(emission, emission * 0.25 + h.rgb * haze_gain, h.a);
}

