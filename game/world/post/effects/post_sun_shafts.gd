class_name PostSunShafts
extends CompositorEffect
## Screen-space god rays (post-render unit, brief §1): a radial blur of the bright sky mask away from the
## sun's screen position, added on top of the volumetric fog. This is the effect that puts gold shafts
## down the street canyons of `art/concept/keyart/v2_canyon-1.png`; the volumetric fog alone gives the
## haze, not the shafts.
##
## No depth buffer is needed: geometry occludes the shafts for free, because anything dark contributes
## nothing to the bright mask, so a tower simply leaves a shadow-shaped gap in the rays.
##
## Three dispatches at quarter resolution plus one full-resolution add. The add reads the scene through
## `imageLoad` at its own texel rather than a copy — the colour buffer has no CAN_COPY_FROM bit.

const SRC := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D src;    // scene (mode 0) or the mask (mode 1)
layout(rgba16f, set = 0, binding = 1) uniform image2D dst;

// Four vec4s rather than loose floats: std430 aligns vec2 to 8 bytes, and the mixed layout this started
// as needed 60 bytes where the GDScript side naturally supplied 56 or 64. vec4-only is always 64.
layout(push_constant, std430) uniform Params {
	vec4 pa;   // dst_size.xy, src_texel.xy
	vec4 pb;   // mode (0 mask, 1 blur, 2 add), sun_uv.xy, sun_visible
	vec4 pc;   // strength, steps, density, decay
	vec4 pd;   // threshold, aspect, -, -
} p;

const float MASK_CAP = 6.0;
const float FALLOFF = 3.2;

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= int(p.pa.xy.x) || px.y >= int(p.pa.xy.y)) { return; }
	vec2 uv = (vec2(px) + 0.5) / p.pa.xy;

	if (p.pb.x < 0.5) {
		// Only the sky and the sun itself are bright enough to throw a shaft. Averaging four half-texel
		// taps both antialiases the mask and halves the resolution for free.
		vec2 h = p.pa.zw * 0.5;
		vec3 c = (texture(src, uv + vec2(-h.x, -h.y)).rgb + texture(src, uv + vec2(h.x, -h.y)).rgb
				+ texture(src, uv + vec2(-h.x, h.y)).rgb + texture(src, uv + vec2(h.x, h.y)).rgb) * 0.25;
		float br = max(c.r, max(c.g, c.b));
		// Capped: a 10 000-nit sun disc must not drag the whole sky over the threshold with it.
		c = min(c, vec3(MASK_CAP)) * smoothstep(p.pd.x, p.pd.x * 2.0, br);
		imageStore(dst, px, vec4(c, 1.0));
		return;
	}
	if (p.pb.x < 1.5) {
		// Classic radial blur: march from this pixel toward the sun, each sample a little dimmer. The
		// result is bright where the line to the sun passes through a lot of bright sky and dark where a
		// tower blocks it — which is exactly a shaft.
		vec2 delta = (uv - p.pb.yz) * (p.pc.z / p.pc.y);
		vec2 at = uv;
		float w = 1.0;
		float wsum = 0.0;
		vec3 sum = vec3(0.0);
		for (int i = 0; i < 64; i++) {
			if (float(i) >= p.pc.y) { break; }
			at -= delta;
			sum += texture(src, at).rgb * w;
			wsum += w;
			w *= p.pc.w;
		}
		// Normalised by the weight sum, so the result is a weighted average of the mask and `strength`
		// stays a plain multiplier. Dividing by `steps` instead made the shafts scale with the step
		// count and blew V1 (sun in frame) to solid white.
		imageStore(dst, px, vec4(sum / max(wsum, 1e-4), 1.0));
		return;
	}
	// Add: gold, scaled by how far the sun is in front of the camera, and concentrated around it —
	// forward scattering falls off with the angle from the sun, so a frame-wide glow would be wrong as
	// well as ugly.
	float falloff = exp(-FALLOFF * length((uv - p.pb.yz) * vec2(p.pd.y, 1.0)));
	vec4 scene = imageLoad(dst, px);
	vec3 shaft = texture(src, uv).rgb * (p.pc.x * p.pb.w * falloff)
			* vec3(1.0, 0.82, 0.55);
	imageStore(dst, px, vec4(scene.rgb + shaft, scene.a));
}
"""

## Set by PostStack from the preset; `sun_uv` / `sun_visible` are refreshed every frame on the main thread.
var strength: float = 0.55
var steps: int = 24
var sun_uv := Vector2(0.5, 0.5)
var sun_visible: float = 0.0

## How far along the ray to the sun the march reaches (1.0 = all the way). Short of 1 keeps the sun disc
## itself from smearing across the frame.
const DENSITY := 0.72
const DECAY := 0.94
## The bright mask only wants sky: above this linear HDR value, well over sunlit concrete.
const THRESHOLD := 1.6
## Ceiling on one mask sample, so the sun disc itself cannot drive the whole frame.
const MASK_CAP := 6.0

var _pass: PostCompute
var _size := Vector2i.ZERO
var _view: int = -1
var _chain: Array[Dictionary] = []


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	enabled = PostCompute.has_device()
	_pass = PostCompute.new(SRC)
	if not enabled:
		push_warning("PostSunShafts: no RenderingDevice (head-less run) — the effect stays off")
	elif _pass.compile_error != "":
		push_error("PostSunShafts: shader compile failed — %s" % _pass.compile_error)
		enabled = false


func _render_callback(_type: int, render_data: RenderData) -> void:
	if not _pass.is_ready() or sun_visible <= 0.001:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	if size.x < 64 or size.y < 64:
		return
	for view in range(buffers.get_view_count()):
		if size != _size or view != _view:
			_build(buffers, size, view)
		if _chain.is_empty():
			return
		# The textures, sizes and uniform sets are cached; only the push constants are rebuilt, because the
		# sun's screen position and the preset strength change every frame.
		for step in _chain:
			var cl := _pass.begin()
			if cl < 0:
				return
			_pass.bind(cl, step["uniforms"])
			_pass.push(cl, _params(step["size"], step["src_size"], step["mode"]))
			_pass.dispatch(cl, step["size"])
			_pass.finish(cl)


func _build(buffers: RenderSceneBuffersRD, size: Vector2i, view: int) -> void:
	_chain.clear()
	_size = size
	_view = view
	var quarter := Vector2i(maxi(size.x / 4, 16), maxi(size.y / 4, 16))
	var mask := _pass.scratch(buffers, &"post_shafts_mask", quarter)
	var blurred := _pass.scratch(buffers, &"post_shafts_blur", quarter)
	var colour := buffers.get_color_layer(view)
	if not mask.is_valid() or not blurred.is_valid():
		push_error("PostSunShafts: could not allocate the %dx%d mask" % [quarter.x, quarter.y])
		enabled = false
		return
	_add(colour, mask, quarter, size, 0.0)
	_add(mask, blurred, quarter, quarter, 1.0)
	_add(blurred, colour, size, quarter, 2.0)


func _add(src: RID, dst: RID, dst_size: Vector2i, src_size: Vector2i, mode: float) -> void:
	var uniforms: Array[RDUniform] = [
		_pass.tex_uniform(0, src),
		PostCompute.image_uniform(1, dst),
	]
	_chain.append({"uniforms": uniforms, "size": dst_size, "src_size": src_size, "mode": mode})


func _params(dst_size: Vector2i, src_size: Vector2i, mode: float) -> PackedFloat32Array:
	return PackedFloat32Array([
		float(dst_size.x), float(dst_size.y),
		1.0 / float(src_size.x), 1.0 / float(src_size.y),
		mode, sun_uv.x, sun_uv.y, sun_visible,
		strength, float(steps), DENSITY, DECAY,
		THRESHOLD, float(_size.x) / float(maxi(_size.y, 1)), 0.0, 0.0])
