class_name PostLens
extends CompositorEffect
## The lens pass (post-render unit, brief §1 "Lens"): one full-resolution dispatch, post-transparent,
## over the resolved HDR image. Vignette, edge-only chromatic fringe, fine animated grain and CAS
## sharpening that undoes TAA's softness. This is the effect that runs on every preset.
##
## It does NOT duplicate feel's `fx/screen_fx` (that is a post-tonemap CanvasLayer for gameplay juice:
## flashes, radial blur, speed lines, damage vignette, impact frames). This one is pre-tonemap optics.

const SRC := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D src;
layout(rgba16f, set = 0, binding = 1) uniform image2D dst;

layout(push_constant, std430) uniform Params {
	vec2 texel;
	vec2 size;
	float vignette;
	float fringe;
	float grain;
	float sharpen;
	float time;
	float aspect;
	float legacy;
	float pad1;
} p;

vec3 tm(vec3 c) { return c / (1.0 + c); }
vec3 itm(vec3 c) { return c / max(vec3(1.0) - c, vec3(1e-3)); }
float hash(vec2 v) { return fract(sin(dot(v, vec2(12.9898, 78.233))) * 43758.5453); }

// city-art r16b §2: an integer hash. The sine hash above takes `pixel + time * 91.7`, and `time` is the
// process's age in seconds, so after ten minutes its argument is ~3e6 and fp32 has 0.35 of a radian of
// resolution left in it: the "white noise" quantises into a fixed diagonal ripple at 17.3 px and
// 118 deg that covers every flat area of the frame (measured at 1.24/255 on the r15 captures, and
// under 0.06/255 in the first minute of a run). Integer arithmetic has no such floor at any age.
uint hash_u(uvec2 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v ^= v >> 16u;
	v.x += v.y * 1664525u;
	return v.x;
}

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	ivec2 sz = ivec2(p.size);
	if (px.x >= sz.x || px.y >= sz.y) { return; }
	vec2 uv = (vec2(px) + 0.5) / p.size;
	vec2 rad = vec2((uv.x * 2.0 - 1.0) * p.aspect, uv.y * 2.0 - 1.0);
	float r = length(rad) / length(vec2(p.aspect, 1.0));

	vec4 centre = texture(src, uv);
	vec3 c = centre.rgb;
	if (p.fringe > 0.0) {
		// Edges only: a lens splits colour where it is steepest off-axis, never in the middle of frame.
		vec2 dir = r > 1e-4 ? rad / r : vec2(0.0);
		vec2 off = dir * (p.fringe * p.texel.x * smoothstep(0.45, 1.0, r));
		c.r = texture(src, uv + off).r;
		c.b = texture(src, uv - off).b;
	}
	if (p.sharpen > 0.0) {
		// AMD CAS, evaluated after a Reinhard map so HDR highlights are not ringed.
		vec2 t = p.texel;
		vec3 b = tm(c);
		vec3 n0 = tm(texture(src, uv + vec2(0.0, -t.y)).rgb);
		vec3 n1 = tm(texture(src, uv + vec2(-t.x, 0.0)).rgb);
		vec3 n2 = tm(texture(src, uv + vec2( t.x, 0.0)).rgb);
		vec3 n3 = tm(texture(src, uv + vec2(0.0,  t.y)).rgb);
		vec3 mn = min(min(min(n0, n1), min(n2, n3)), b);
		vec3 mx = max(max(max(n0, n1), max(n2, n3)), b);
		vec3 amp = sqrt(clamp(min(mn, vec3(1.0) - mx) / max(mx, vec3(1e-4)), 0.0, 1.0));
		vec3 w = amp * (-1.0 / mix(8.0, 5.0, clamp(p.sharpen, 0.0, 1.0)));
		c = itm(clamp((b + (n0 + n1 + n2 + n3) * w) / (vec3(1.0) + 4.0 * w), 0.0, 1.0));
	}
	if (p.vignette > 0.0) {
		c *= 1.0 - p.vignette * smoothstep(0.35, 1.05, r);
	}
	if (p.grain > 0.0) {
		vec3 m = tm(c);
		float lum = dot(m, vec3(0.2126, 0.7152, 0.0721));
		float n = p.legacy > 0.5
			? hash(vec2(px) + vec2(p.time * 91.7, p.time * 47.3)) - 0.5
			: float(hash_u(uvec2(px) + uvec2(uint(p.time * 60.0) * 2654435761u, 0u))
				& 0xffffffu) / 16777216.0 - 0.5;
		c = itm(clamp(m + n * p.grain * (1.0 - lum * 0.85), 0.0, 1.0));
	}
	imageStore(dst, px, vec4(max(c, vec3(0.0)), centre.a));
}
"""

## Set by PostStack from the preset / Settings; read by the render thread, so only floats and bools.
var vignette: float = 0.18
var fringe: float = 1.0
var grain: float = 0.016
var sharpen: float = 0.62
## city-art r16b §2, measurement only: the seconds value the grain's hash is offset by. Negative = the
## real clock. `--post-tune=lens_time:600` reproduces a ten-minute-old process in one frame, which is
## how the sine hash's fp32 floor was separated from every other suspect.
var time_offset: float = -1.0
## 1 = the pre-r16b sine hash, for the A/B that names it. Shipping is 0.
var legacy_grain: float = 0.0

var _pass: PostCompute


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	enabled = PostCompute.has_device()
	_pass = PostCompute.new(SRC)
	if not enabled:
		push_warning("PostLens: no RenderingDevice (head-less run) — the effect stays off")
	elif _pass.compile_error != "":
		push_error("PostLens: shader compile failed — %s" % _pass.compile_error)
		enabled = false


func _render_callback(_type: int, render_data: RenderData) -> void:
	if not _pass.is_ready():
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	if size.x < 8 or size.y < 8:
		return
	var scratch := _pass.scratch(buffers, &"post_lens_copy", size)
	if not scratch.is_valid():
		push_error("PostLens: could not create the %dx%d scratch texture" % [size.x, size.y])
		enabled = false
		return
	var params := PackedFloat32Array([
		1.0 / float(size.x), 1.0 / float(size.y), float(size.x), float(size.y),
		vignette, fringe, grain, sharpen,
		time_offset if time_offset >= 0.0 else Time.get_ticks_msec() * 0.001,
		float(size.x) / float(size.y), legacy_grain, 0.0])
	for view in range(buffers.get_view_count()):
		var colour := buffers.get_color_layer(view)
		if not _pass.copy_image(colour, scratch, size):
			enabled = false
			return
		var cl := _pass.begin()
		if cl < 0:
			return
		var uniforms: Array[RDUniform] = [
			_pass.tex_uniform(0, scratch),
			PostCompute.image_uniform(1, colour),
		]
		_pass.bind(cl, uniforms)
		_pass.push(cl, params)
		_pass.dispatch(cl, size)
		_pass.finish(cl)
