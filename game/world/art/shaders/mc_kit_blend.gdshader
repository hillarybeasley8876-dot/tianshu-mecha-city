shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, fog_disabled, diffuse_burley, specular_schlick_ggx;
// mc_kit_blend — the same skin for a glTF material imported with transparency (glass canopies, the
// skybridge tubes). `render_mode` is compile-time, so it needs its own header.
#include "mc_kit_body.gdshaderinc"
