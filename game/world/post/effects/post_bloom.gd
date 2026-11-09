class_name PostBloom
extends CompositorEffect
## Wide, soft, physically-shaped bloom (post-render unit, brief §1 "Bloom that reads").
##
## A dual-filter (Kawase) mip chain over the HDR image: bright pass at half resolution, `mips` levels of
## 5-tap downsample, then an 8-tap tent upsample that adds each level back on the way up — so a window,
## a neon strip, the tether or the sun disc gets a halo as wide as the chain allows while sunlit concrete
## (which sits well under the threshold in linear HDR) never does.
##
## It replaces the engine glow rather than adding to it: `PostStack` turns `Environment.glow_enabled` off
## while this runs, because engine glow at a low threshold is a full-frame wash (screen blend) instead of
## a halo, and at city-art's 1.45 threshold it bloomed nothing at all.
##
## Also carries the anamorphic streaks: one extra wide horizontal blur of the second mip, tinted cool and
## added on the composite. `Settings.photosensitive` zeroes it (PostStack does that), since a bright
## horizontal shimmer is exactly what that mode exists to remove.

const SRC := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D src;     // finer level, or the scene (modes 0 and 4)
layout(set = 0, binding = 1) uniform sampler2D coarse;  // coarser level (mode 2), or bloom (mode 4)
// `dst` is read as well as written, but only ever at the invocation's OWN texel (the composite adds to
// the scene it is writing). That is well defined and saves a full-resolution copy of the frame: the
// scene colour buffer has no CAN_COPY_FROM bit, so a copy would have to be a dispatch of its own.
layout(rgba16f, set = 0, binding = 2) uniform image2D dst;
layout(set = 0, binding = 3) uniform sampler2D extra;   // streak texture (mode 4)

layout(push_constant, std430) uniform Params {
	vec2 dst_size;
	vec2 src_texel;
	float mode;        // 0 bright, 1 downsample, 2 upsample+add, 3 streak, 4 composite
	float threshold;
	float knee;
	float strength;    // bloom mix on the composite
	float streak;      // streak mix on the composite
	float blur_len;    // streak blur reach, in texels of the streak level
	float cap;         // ceiling on one bright-pass sample
	float pad0;
	float pad2;
	float pad3;
	float pad4;
	float pad5;
} p;

vec3 tap(sampler2D t, vec2 uv) { return max(texture(t, uv).rgb, vec3(0.0)); }

vec3 bright_pass(vec2 uv) {
	vec2 h = p.src_texel * 0.5;
	vec3 c = (tap(src, uv + vec2(-h.x, -h.y)) + tap(src, uv + vec2(h.x, -h.y))
			+ tap(src, uv + vec2(-h.x, h.y)) + tap(src, uv + vec2(h.x, h.y))) * 0.25;
	// Soft-knee bright pass: a source fades into the bloom over `knee` instead of popping at the
	// threshold, which is what keeps a slow camera move from making every window flicker.
	float br = max(c.r, max(c.g, c.b));
	float soft = clamp(br - p.threshold + p.knee, 0.0, 2.0 * p.knee);
	soft = soft * soft / (4.0 * p.knee + 1e-4);
	return c * (max(soft, br - p.threshold) / max(br, 1e-4));
}

vec3 downsample(vec2 uv) {
	vec2 t = p.src_texel;
	vec3 s = tap(src, uv) * 4.0;
	s += tap(src, uv + vec2(-t.x, -t.y));
	s += tap(src, uv + vec2( t.x,  t.y));
	s += tap(src, uv + vec2( t.x, -t.y));
	s += tap(src, uv + vec2(-t.x,  t.y));
	return s * 0.125;
}

vec3 upsample(vec2 uv) {
	vec2 h = p.src_texel * 0.5;
	vec3 s = tap(coarse, uv + vec2(-h.x * 2.0, 0.0));
	s += tap(coarse, uv + vec2(-h.x,  h.y)) * 2.0;
	s += tap(coarse, uv + vec2( 0.0,  h.y * 2.0));
	s += tap(coarse, uv + vec2( h.x,  h.y)) * 2.0;
	s += tap(coarse, uv + vec2( h.x * 2.0, 0.0));
	s += tap(coarse, uv + vec2( h.x, -h.y)) * 2.0;
	s += tap(coarse, uv + vec2( 0.0, -h.y * 2.0));
	s += tap(coarse, uv + vec2(-h.x, -h.y)) * 2.0;
	return s * (1.0 / 12.0) + tap(src, uv);
}

vec3 streak(vec2 uv) {
	vec3 s = vec3(0.0);
	float wsum = 0.0;
	for (int i = -6; i <= 6; i++) {
		float fi = float(i);
		float w = exp(-fi * fi / 18.0);
		s += tap(src, uv + vec2(fi * p.blur_len * p.src_texel.x, 0.0)) * w;
		wsum += w;
	}
	return s / wsum;
}

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= int(p.dst_size.x) || px.y >= int(p.dst_size.y)) { return; }
	vec2 uv = (vec2(px) + 0.5) / p.dst_size;
	if (p.mode < 0.5) {
		imageStore(dst, px, vec4(bright_pass(uv), 1.0));
	} else if (p.mode < 1.5) {
		imageStore(dst, px, vec4(downsample(uv), 1.0));
	} else if (p.mode < 2.5) {
		imageStore(dst, px, vec4(upsample(uv), 1.0));
	} else if (p.mode < 3.5) {
		imageStore(dst, px, vec4(streak(uv), 1.0));
	} else {
		// Composite: scene + bloom + a cool anamorphic streak. The streak is the only coloured part —
		// the bloom itself stays neutral so it reads as light, not as a tint.
		vec4 scene = imageLoad(dst, px);
		vec3 add = tap(coarse, uv) * p.strength
				+ tap(extra, uv) * (p.streak * vec3(0.42, 0.60, 1.0));
		imageStore(dst, px, vec4(scene.rgb + add, scene.a));
	}
}
"""

## Set by PostStack from the preset; read by the render thread, so only numbers.
var strength: float = 0.34
var threshold: float = 1.00
var knee: float = 0.50
var mips: int = 6
var streak: float = 0.14
## Streak reach in texels of the quarter-resolution level: ~4 % of the frame width at 1600 px.
const STREAK_LEN := 4.0
## The level the anamorphic streak is taken from (1 = quarter resolution).
const STREAK_LEVEL := 1
## Ceiling on one bright-pass sample, in linear HDR. High enough that a window still blooms brightly,
## low enough that the sun disc and the tether core cannot wash the frame.
const BRIGHT_CAP := 5.0

var _pass: PostCompute
var _chain: Array[Dictionary] = []   ## one entry per dispatch, rebuilt only when the size changes
var _chain_size := Vector2i.ZERO
var _chain_view: int = -1


func configure(row: Dictionary) -> void:
	strength = float(row[&"bloom_strength"])
	threshold = float(row[&"bloom_threshold"])
	knee = float(row[&"bloom_knee"])
	mips = clampi(int(row[&"bloom_mips"]), STREAK_LEVEL + 2, 8)


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	enabled = PostCompute.has_device()
	_pass = PostCompute.new(SRC)
	if not enabled:
		push_warning("PostBloom: no RenderingDevice (head-less run) — the effect stays off")
	elif _pass.compile_error != "":
		push_error("PostBloom: shader compile failed — %s" % _pass.compile_error)
		enabled = false


func _render_callback(_type: int, render_data: RenderData) -> void:
	if not _pass.is_ready():
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	if size.x < 64 or size.y < 64:
		return
	for view in range(buffers.get_view_count()):
		_run_view(buffers, size, view)


## Walks the prepared chain. It is rebuilt only when the internal size or the view changes, so the steady
## state is `2 * mips + 1` dispatches and no uniform objects are allocated per frame.
func _run_view(buffers: RenderSceneBuffersRD, size: Vector2i, view: int) -> void:
	if size != _chain_size or view != _chain_view:
		_build_chain(buffers, size, view)
	if _chain.is_empty():
		push_error("PostBloom: could not allocate the bloom chain at %dx%d" % [size.x, size.y])
		enabled = false
		return
	for step in _chain:
		var cl := _pass.begin()
		if cl < 0:
			return
		_pass.bind(cl, step["uniforms"])
		_pass.push(cl, step["params"])
		_pass.dispatch(cl, step["size"])
		_pass.finish(cl)


func _build_chain(buffers: RenderSceneBuffersRD, size: Vector2i, view: int) -> void:
	_chain.clear()
	_chain_size = size
	_chain_view = view
	var levels: Array[Vector2i] = []
	for i in mips:
		levels.append(Vector2i(maxi(size.x >> (i + 1), 8), maxi(size.y >> (i + 1), 8)))
	var down: Array[RID] = []
	var up: Array[RID] = []
	for i in mips:
		down.append(_pass.scratch(buffers, StringName("post_bloom_d%d" % i), levels[i]))
		if i < mips - 1:
			up.append(_pass.scratch(buffers, StringName("post_bloom_u%d" % i), levels[i]))
	var streak_tex := _pass.scratch(buffers, &"post_bloom_streak", levels[STREAK_LEVEL])
	var colour := buffers.get_color_layer(view)
	for r in down + up + [streak_tex]:
		if not r.is_valid():
			return
	# 1. bright pass, full res -> half res
	_add(colour, colour, down[0], levels[0], size, 0.0)
	# 2. downsample chain
	for i in range(mips - 1):
		_add(down[i], down[i], down[i + 1], levels[i + 1], levels[i], 1.0)
	# 3. upsample chain: level mips-1 is the seed, each step adds the finer bright level back
	for i in range(mips - 2, -1, -1):
		var coarse: RID = down[mips - 1] if i == mips - 2 else up[i + 1]
		_add(down[i], coarse, up[i], levels[i], levels[i + 1], 2.0)
	# 4. anamorphic streak off the quarter-res accumulation
	_add(up[STREAK_LEVEL], up[STREAK_LEVEL], streak_tex, levels[STREAK_LEVEL],
			levels[STREAK_LEVEL], 3.0)
	# 5. composite back into the scene
	_add(colour, up[0], colour, size, size, 4.0, streak_tex)


## One dispatch: `fine` is binding 0, `coarse` binding 1, `dst` the storage image, `extra` binding 3.
func _add(fine: RID, coarse: RID, dst: RID, dst_size: Vector2i, src_size: Vector2i, mode: float,
		extra: RID = RID()) -> void:
	var fourth := extra if extra.is_valid() else fine
	var uniforms: Array[RDUniform] = [
		_pass.tex_uniform(0, fine),
		_pass.tex_uniform(1, coarse),
		PostCompute.image_uniform(2, dst),
		_pass.tex_uniform(3, fourth),
	]
	var params := PackedFloat32Array([
		float(dst_size.x), float(dst_size.y),
		1.0 / float(src_size.x), 1.0 / float(src_size.y),
		mode, threshold, knee, strength, streak, STREAK_LEN, BRIGHT_CAP,
		0.0, 0.0, 0.0, 0.0, 0.0])
	_chain.append({"uniforms": uniforms, "params": params, "size": dst_size})
