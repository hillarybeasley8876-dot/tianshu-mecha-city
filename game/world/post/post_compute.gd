class_name PostCompute
extends RefCounted
## RenderingDevice plumbing shared by every CompositorEffect in `world/post/` (post-render unit).
## One instance owns one compute shader plus the boilerplate copy shader every pass needs: the scene
## colour buffer has no `CAN_COPY_FROM` bit, so `rd.texture_copy` is not available and the "copy the
## image so the blur can read its neighbours" step has to be a dispatch of its own.
## Follows the Metal-verified template in `ref/research/godot-tech.md` §9 (`gray_effect.gd`).

## Workgroup edge, matched to `local_size_x/y` in every shader of this unit.
const LOCAL := 8
## Scratch textures live in the scene-buffer context, which frees them with the buffers — we never free
## them ourselves, so a resize costs nothing and leaves no leak.
const CONTEXT := &"3D"

const COPY_SRC := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform readonly image2D src;
layout(rgba16f, set = 0, binding = 1) uniform image2D dst;
layout(push_constant, std430) uniform Params { vec2 size; vec2 pad; } p;
void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= int(p.size.x) || px.y >= int(p.size.y)) { return; }
	imageStore(dst, px, imageLoad(src, px));
}
"""

var rd: RenderingDevice
var compile_error: String = ""

var _shader: RID = RID()
var _pipeline: RID = RID()
var _copy_shader: RID = RID()
var _copy_pipeline: RID = RID()
var _sampler: RID = RID()


func _init(compute_source: String) -> void:
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		compile_error = "no RenderingDevice (the dummy driver is in use)"
		return
	_shader = _compile(compute_source)
	if not _shader.is_valid():
		return
	_pipeline = rd.compute_pipeline_create(_shader)
	if not _pipeline.is_valid():
		compile_error = "compute_pipeline_create failed"


func _compile(source: String) -> RID:
	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = source
	var spirv := rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_compute != "":
		compile_error = spirv.compile_error_compute
		return RID()
	var shader := rd.shader_create_from_spirv(spirv)
	if not shader.is_valid():
		compile_error = "shader_create_from_spirv failed"
	return shader


func is_ready() -> bool:
	return _pipeline.is_valid()


## Head-less runs use the dummy renderer, where there is no RenderingDevice at all. That is expected,
## not a failure: the effect disables itself quietly instead of reporting a shader error that is not one.
static func has_device() -> bool:
	return RenderingServer.get_rendering_device() != null


## A scratch texture with the usage bits every pass in this unit needs.
func scratch(buffers: RenderSceneBuffersRD, name: StringName, size: Vector2i) -> RID:
	var usage := (RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
			| RenderingDevice.TEXTURE_USAGE_STORAGE_BIT)
	return buffers.create_texture(CONTEXT, name, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
			usage, RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, false, false)


## image -> image copy in its own compute list. Returns false (and stays quiet) if the copy pipeline
## could not be built, which lets a pass skip itself instead of writing garbage.
func copy_image(from: RID, to: RID, size: Vector2i) -> bool:
	if not _copy_ready():
		return false
	var uniforms: Array[RDUniform] = [image_uniform(0, from), image_uniform(1, to)]
	var uset := UniformSetCacheRD.get_cache(_copy_shader, 0, uniforms)
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _copy_pipeline)
	rd.compute_list_bind_uniform_set(cl, uset, 0)
	var pc := PackedFloat32Array([float(size.x), float(size.y), 0.0, 0.0])
	rd.compute_list_set_push_constant(cl, pc.to_byte_array(), pc.size() * 4)
	rd.compute_list_dispatch(cl, (size.x - 1) / LOCAL + 1, (size.y - 1) / LOCAL + 1, 1)
	rd.compute_list_end()
	return true


func _copy_ready() -> bool:
	if _copy_pipeline.is_valid():
		return true
	if not _copy_shader.is_valid():
		_copy_shader = _compile(COPY_SRC)
		if not _copy_shader.is_valid():
			return false
	_copy_pipeline = rd.compute_pipeline_create(_copy_shader)
	return _copy_pipeline.is_valid()


func begin() -> int:
	if not is_ready():
		return -1
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _pipeline)
	return cl


func bind(cl: int, uniforms: Array[RDUniform], set_index: int = 0) -> void:
	rd.compute_list_bind_uniform_set(cl, UniformSetCacheRD.get_cache(_shader, set_index, uniforms),
			set_index)


## Push constants are floats only and must be a multiple of 4 floats (16 bytes); every shader here
## declares its own `Params` block to match.
func push(cl: int, params: PackedFloat32Array) -> void:
	rd.compute_list_set_push_constant(cl, params.to_byte_array(), params.size() * 4)


func dispatch(cl: int, size: Vector2i) -> void:
	rd.compute_list_dispatch(cl, (size.x - 1) / LOCAL + 1, (size.y - 1) / LOCAL + 1, 1)


func barrier(cl: int) -> void:
	rd.compute_list_add_barrier(cl)


func finish(cl: int) -> void:
	rd.compute_list_end()


## Linear clamp sampler, one per effect instance (freed with it, so nothing leaks at exit).
func sampler() -> RID:
	if not _sampler.is_valid():
		var st := RDSamplerState.new()
		st.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		st.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		st.mip_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		st.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		st.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		st.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		_sampler = rd.sampler_create(st)
	return _sampler


## A sampled-texture uniform (binding N) — read side of a pass.
func tex_uniform(binding: int, texture: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u.binding = binding
	u.add_id(sampler())
	u.add_id(texture)
	return u


## A storage-image uniform (binding N) — write side of a pass.
static func image_uniform(binding: int, texture: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(texture)
	return u


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE or rd == null:
		return
	for rid in [_pipeline, _copy_pipeline, _shader, _copy_shader, _sampler]:
		var r: RID = rid
		if r.is_valid():
			rd.free_rid(r)
