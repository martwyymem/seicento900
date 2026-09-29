## Compositor effect that adds ray-traced reflections to glossy surfaces (wet tarmac, puddles, car paint and
## glass). The scene is traced in a compute shader (shaders/rt_reflections.glsl) against BVHs built on the
## CPU by RayTracing (ray_tracing.gd), so it works on any GPU with compute shaders, Metal included; Godot
## 4.7's RenderingDevice exposes hardware ray queries only on some Vulkan/D3D12 drivers.
## The main thread hands data over with set_geometry()/set_frame(); the render thread uploads and dispatches.
class_name RtReflectionsEffect
extends CompositorEffect

const SHADER_FILE := preload("res://shaders/rt_reflections.glsl")
const PARAMS_BYTES := 256

var _rd: RenderingDevice
var _shader := RID()
var _pipeline := RID()
var _sampler := RID()
var _params := RID()
var _buffers := {} ## name -> [RID, capacity in bytes]
var _mutex := Mutex.new()
var _geometry: Array = [] ## [blas node bytes, triangle bytes] waiting for upload
var _frame := {} ## latest per-frame data from set_frame()
var _has_geometry := false

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	needs_normal_roughness = true
	RenderingServer.call_on_render_thread(_create_pipeline)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd:
		for entry in _buffers.values():
			_rd.free_rid(entry[0])
		for rid in [_params, _sampler, _shader]: # the pipeline goes with its shader
			if rid.is_valid():
				_rd.free_rid(rid)

## Triangle trees of every mesh (static and cars), replaced whenever the scene is rebuilt.
func set_geometry(blas_nodes: PackedByteArray, triangles: PackedByteArray) -> void:
	_mutex.lock()
	_geometry = [blas_nodes, triangles]
	_mutex.unlock()

## Per-frame data: instances, top-level trees, roots and lighting (see RayTracing._process).
func set_frame(frame: Dictionary) -> void:
	_mutex.lock()
	_frame = frame
	_mutex.unlock()

func _create_pipeline() -> void:
	_rd = RenderingServer.get_rendering_device()
	if not _rd:
		return
	var spirv: RDShaderSPIRV = SHADER_FILE.get_spirv()
	if spirv.compile_error_compute != "":
		push_error("rt_reflections.glsl: " + spirv.compile_error_compute)
		return
	_shader = _rd.shader_create_from_spirv(spirv)
	if not _shader.is_valid():
		return
	_pipeline = _rd.compute_pipeline_create(_shader)
	var sampler_state := RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	_sampler = _rd.sampler_create(sampler_state)
	_params = _rd.uniform_buffer_create(PARAMS_BYTES)

## Storage buffers only grow; contents are overwritten in place when they fit.
func _upload(name: String, data: PackedByteArray) -> RID:
	var size := maxi(data.size(), 16)
	var entry: Array = _buffers.get(name, [])
	if entry.is_empty() or entry[1] < size:
		if not entry.is_empty():
			_rd.free_rid(entry[0])
		var capacity := nearest_po2(size)
		entry = [_rd.storage_buffer_create(capacity), capacity]
		_buffers[name] = entry
	if not data.is_empty():
		_rd.buffer_update(entry[0], 0, data.size(), data)
	return entry[0]

func _render_callback(_callback_type: int, render_data: RenderData) -> void:
	if not _pipeline.is_valid():
		return
	var scene_buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene_data := render_data.get_render_scene_data()
	if not scene_buffers or not scene_data:
		return
	_mutex.lock()
	var geometry := _geometry
	_geometry = []
	var frame := _frame
	_mutex.unlock()
	if not geometry.is_empty():
		_upload("blas", geometry[0])
		_upload("triangles", geometry[1])
		_has_geometry = not geometry[1].is_empty()
	if not _has_geometry or frame.is_empty():
		return
	var instances := _upload("instances", frame.instances)
	var top := _upload("top", frame.top)

	var size := scene_buffers.get_internal_size()
	if size.x <= 0 or size.y <= 0:
		return
	var set1 := UniformSetCacheRD.get_cache(_shader, 1, [
		_storage(0, _buffers.blas[0]), _storage(1, _buffers.triangles[0]),
		_storage(2, instances), _storage(3, top)])
	var groups := Vector3i((size.x + 7) / 8, (size.y + 7) / 8, 1)
	for view in scene_buffers.get_view_count():
		_rd.buffer_update(_params, 0, PARAMS_BYTES, _params_bytes(frame, scene_data, view))
		var colour := scene_buffers.get_color_layer(view)
		var depth := scene_buffers.get_depth_layer(view)
		var normal_roughness := scene_buffers.get_texture_slice("forward_clustered", "normal_roughness", view, 0, 1, 1)
		var set0 := UniformSetCacheRD.get_cache(_shader, 0, [
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 0, [colour]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, [_sampler, depth]),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 2, [_sampler, normal_roughness]),
			_uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 3, [_params])])
		var list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _pipeline)
		_rd.compute_list_bind_uniform_set(list, set0, 0)
		_rd.compute_list_bind_uniform_set(list, set1, 1)
		_rd.compute_list_dispatch(list, groups.x, groups.y, groups.z)
		_rd.compute_list_end()

func _params_bytes(frame: Dictionary, scene_data: RenderSceneData, view: int) -> PackedByteArray:
	# depth buffer NDC (Vulkan-style, reversed Z) back to view space
	var projection := Projection.create_depth_correction(false) * scene_data.get_view_projection(view)
	var inv := projection.inverse()
	var cam := scene_data.get_cam_transform()
	cam.origin += cam.basis * scene_data.get_view_eye_offset(view)
	var f := PackedFloat32Array()
	for column in [inv.x, inv.y, inv.z, inv.w]:
		f.append_array([column.x, column.y, column.z, column.w])
	f.append_array([cam.basis.x.x, cam.basis.x.y, cam.basis.x.z, 0.0])
	f.append_array([cam.basis.y.x, cam.basis.y.y, cam.basis.y.z, 0.0])
	f.append_array([cam.basis.z.x, cam.basis.z.y, cam.basis.z.z, 0.0])
	f.append_array([cam.origin.x, cam.origin.y, cam.origin.z, 1.0])
	for key in ["sun_dir", "sun_color", "ambient", "sky_zenith", "sky_horizon", "fog"]:
		var v: Vector4 = frame[key]
		f.append_array([v.x, v.y, v.z, v.w])
	var bytes := f.to_byte_array()
	var roots: Vector4i = frame.roots
	var ints := PackedInt32Array([roots.x, roots.y, roots.z, roots.w]).to_byte_array()
	bytes.append_array(ints)
	var settings: Vector4 = frame.settings
	bytes.append_array(PackedFloat32Array([settings.x, settings.y, settings.z, settings.w]).to_byte_array())
	return bytes

func _storage(binding: int, buffer: RID) -> RDUniform:
	return _uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, binding, [buffer])

func _uniform(type: int, binding: int, ids: Array) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = type
	u.binding = binding
	for id in ids:
		u.add_id(id)
	return u
