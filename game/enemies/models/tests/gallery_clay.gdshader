shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Gallery clay pass (monster-assets, lead r5 item 1): front faces neutral clay, back faces flat
// magenta. A torn skin shows as a magenta sheet and a hole shows the magenta inside, which is how the
// acceptance pass spotted the fused limbs in the first place. `--gallery-clay=1` overrides every
// monster material with this so a turnaround can be judged for geometry alone.

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
