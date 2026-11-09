shader_type spatial;
// hero-v3 r8 gate helper: draw ONLY the fragments whose dominant skin bind is `bind_index`, flat
// grey, so a capture gives an exact screen mask of one bone's plate (the helmet, for the visor gate).
// Nothing in the game uses this -- `hero3_look.gd --look-debug=glow` swaps it on for one frame.
//
// Godot 4 spells the skinning attributes `BONE_INDICES` / `BONE_WEIGHTS` (`BONES` / `WEIGHTS` was
// Godot 3). Getting that wrong fails the whole shader's compilation and the engine quietly falls
// back to a default material, which drew the ENTIRE body and made the visor gate pass for free.
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

uniform int bind_index = -1;

varying float w_bone;

void vertex() {
	w_bone = 0.0;
	for (int i = 0; i < 4; i++) {
		if (int(BONE_INDICES[i]) == bind_index) {
			w_bone = max(w_bone, BONE_WEIGHTS[i]);
		}
	}
}

void fragment() {
	if (w_bone < 0.5) {
		discard;
	}
	ALBEDO = vec3(0.5);
}
