class_name PostDof
extends CompositorEffect
## Cinematic depth of field (post-render unit, brief §1: drop-in, collapse, boss intro/death — never in
## play). A far-field bokeh blur with a near-field guard, driven by `PostStack.set_cinematic()` and by
## `CameraRig.is_cinematic()`, so a shot list that is already running does not need a second caller.
##
## It reads the resolved depth buffer, which is reversed-Z in Godot 4 (1 at the near plane, 0 at far), so
## linearising is `near * far / (far - z * (far - near))`.
##
## The pass only allocates and dispatches while `active` is true, so in gameplay it costs nothing at all —
## not even its textures.

const SRC := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D src;     // the scene, blurred
layout(set = 0, binding = 1) uniform sampler2D sharp;   // the scene, untouched
layout(rgba16f, set = 0, binding = 2) uniform image2D dst;
layout(set = 0, binding = 3) uniform sampler2D depth;

// vec4-only for the same reason as PostSunShafts: a mixed vec2/float std430 block lands on a size the
// GDScript side does not naturally produce (this one wanted 44 bytes against a 48-byte push), and a
// mismatch is a per-dispatch engine error rather than a compile error.
layout(push_constant, std430) uniform Params {
	vec4 pa;   // dst_size.xy, texel.xy
	vec4 pb;   // max_blur px, focus m, range m, mode (0 = half-res blur, 1 = bokeh composite)
	vec4 pc;   // near_plane, far_plane, -, -
} p;

// 13-tap golden-angle disc: cheap, and a disc is what a bokeh is. Offsets are rotated per pixel so the
// 13 taps do not print a fixed rosette pattern across the sky.
const vec2 DISC[13] = vec2[13](
	vec2(0.0, 0.0), vec2(0.567, 0.196), vec2(-0.129, 0.591), vec2(-0.612, -0.135),
	vec2(0.203, -0.585), vec2(0.416, 0.463), vec2(-0.487, 0.404), vec2(-0.549, -0.345),
	vec2(0.244, 0.611), vec2(0.660, -0.253), vec2(-0.203, -0.669), vec2(-0.676, 0.245),
	vec2(0.357, 0.427));

float linear_depth(vec2 uv) {
	float z = texture(depth, uv).r;
	float n = p.pc.x;
	float f = p.pc.y;
	return n * f / max(f - z * (f - n), 1e-4);
}

void main() {
	vec2 dst_size = p.pa.xy;
	vec2 texel = p.pa.zw;
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= int(dst_size.x) || px.y >= int(dst_size.y)) { return; }
	vec2 uv = (vec2(px) + 0.5) / dst_size;
	if (p.pb.w < 0.5) {
		// Half-resolution box blur: the disc below samples this, so 13 taps reach twice as far for the
		// same cost, and a bokeh hides the resolution completely.
		vec2 h = texel * 0.5;
		vec3 c = (texture(src, uv + vec2(-h.x, -h.y)).rgb + texture(src, uv + vec2(h.x, -h.y)).rgb
				+ texture(src, uv + vec2(-h.x, h.y)).rgb + texture(src, uv + vec2(h.x, h.y)).rgb) * 0.25;
		imageStore(dst, px, vec4(c, 1.0));
		return;
	}
	vec4 centre = texture(sharp, uv);

	// Far field only: the brief asks for bokeh on the background, and a near-field blur in a third-person
	// action camera just smears the hero.
	float d = linear_depth(uv);
	float coc = clamp((d - p.pb.y) / max(p.pb.z, 1e-3), 0.0, 1.0);
	if (coc <= 0.001) {
		imageStore(dst, px, centre);
		return;
	}
	float radius = coc * p.pb.x;
	float rot = fract(sin(dot(vec2(px), vec2(12.9898, 78.233))) * 43758.5453) * 6.2831853;
	float cs = cos(rot);
	float sn = sin(rot);
	vec3 sum = centre.rgb;
	float wsum = 1.0;
	for (int i = 1; i < 13; i++) {
		vec2 o = DISC[i];
		o = vec2(o.x * cs - o.y * sn, o.x * sn + o.y * cs) * radius * texel;
		vec3 c = texture(src, uv + o).rgb;
		// Weight by brightness so a light behind the focal plane keeps its bokeh instead of being
		// averaged into the background.
		float w = 1.0 + dot(c, vec3(0.2126, 0.7152, 0.0722)) * 0.6;
		sum += c * w;
		wsum += w;
	}
	imageStore(dst, px, vec4(mix(centre.rgb, sum / wsum, coc), centre.a));
}
"""

var active: bool = false
var focus: float = 60.0
var max_blur: float = 8.0
var near_plane: float = 0.05
var far_plane: float = 6000.0
## Metres past the focal plane over which the blur reaches full strength. The hero is 16 m and a boss
## 60 m, so 90 m keeps the arena sharp and only the city behind it soft.
const RANGE := 90.0

var _pass: PostCompute
var _size := Vector2i.ZERO
var _view: int = -1
var _blur_uniforms: Array[RDUniform] = []
var _uniforms: Array[RDUniform] = []
var _half := Vector2i.ZERO
var _scene: RID = RID()
var _blurred: RID = RID()


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	access_resolved_depth = true
	enabled = PostCompute.has_device()
	_pass = PostCompute.new(SRC)
	if not enabled:
		push_warning("PostDof: no RenderingDevice (head-less run) — the effect stays off")
	elif _pass.compile_error != "":
		push_error("PostDof: shader compile failed — %s" % _pass.compile_error)
		enabled = false


func _render_callback(_type: int, render_data: RenderData) -> void:
	if not active or not _pass.is_ready():
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	if size.x < 16 or size.y < 16:
		return
	for view in range(buffers.get_view_count()):
		if size != _size or view != _view:
			_build(buffers, size, view)
		if _uniforms.is_empty():
			return
		var colour := buffers.get_color_layer(view)
		if not _pass.copy_image(colour, _scene, size):
			enabled = false
			return
		var cl := _pass.begin()
		if cl < 0:
			return
		_pass.bind(cl, _blur_uniforms)
		_pass.push(cl, _params(_half, 0.0))
		_pass.dispatch(cl, _half)
		_pass.barrier(cl)
		_pass.bind(cl, _uniforms)
		_pass.push(cl, _params(size, 1.0))
		_pass.dispatch(cl, size)
		_pass.finish(cl)


func _params(dst_size: Vector2i, mode: float) -> PackedFloat32Array:
	return PackedFloat32Array([
		float(dst_size.x), float(dst_size.y),
		1.0 / float(_size.x), 1.0 / float(_size.y),
		max_blur, focus, RANGE, mode,
		near_plane, far_plane, 0.0, 0.0])


## `sharp` is the untouched copy, `src` a half-resolution blur it samples with the disc, so the 13 taps
## reach twice as far for the same cost. A half-res blur is invisible behind a bokeh.
func _build(buffers: RenderSceneBuffersRD, size: Vector2i, view: int) -> void:
	_uniforms.clear()
	_blur_uniforms.clear()
	_size = size
	_view = view
	_half = Vector2i(maxi(size.x / 2, 8), maxi(size.y / 2, 8))
	_scene = _pass.scratch(buffers, &"post_dof_scene", size)
	_blurred = _pass.scratch(buffers, &"post_dof_half", _half)
	var depth := buffers.get_depth_layer(view)
	var colour := buffers.get_color_layer(view)
	if not _scene.is_valid() or not _blurred.is_valid() or not depth.is_valid():
		push_error("PostDof: could not allocate its buffers at %dx%d" % [size.x, size.y])
		enabled = false
		return
	_blur_uniforms = [
		_pass.tex_uniform(0, _scene),
		_pass.tex_uniform(1, _scene),
		PostCompute.image_uniform(2, _blurred),
		_pass.tex_uniform(3, depth),
	]
	_uniforms = [
		_pass.tex_uniform(0, _blurred),
		_pass.tex_uniform(1, _scene),
		PostCompute.image_uniform(2, colour),
		_pass.tex_uniform(3, depth),
	]
