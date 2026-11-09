shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// city-kit props QA clay: front faces neutral clay, back faces flat magenta. A hole shows the magenta
// inside it; a flipped (inverted) face shows magenta on the outside. Ported from the lead's
// acceptance studio so my before/after sheets and theirs read the same way.

void fragment() {
	if (FRONT_FACING) {
		ALBEDO = vec3(0.34, 0.33, 0.31);
		ROUGHNESS = 0.55;
	} else {
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		EMISSION = vec3(1.0, 0.0, 0.85) * 0.9;
	}
}
