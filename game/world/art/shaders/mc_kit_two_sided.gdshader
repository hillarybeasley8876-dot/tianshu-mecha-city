shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, fog_disabled, diffuse_burley, specular_schlick_ggx;
// mc_kit_two_sided — the same skin for a glTF material imported double-sided (thin kit pieces:
// railings, awnings, signage frames). `render_mode` is compile-time, so it needs its own header.
#include "mc_kit_body.gdshaderinc"
