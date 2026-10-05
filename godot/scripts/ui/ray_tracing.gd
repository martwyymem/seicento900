## Feeds the ray-traced reflections (rt_reflections.gd) with the race world: every opaque mesh under the
## circuit and the cars becomes a triangle BVH (built once per mesh and material set), the circuit's
## instances get a static top-level BVH, and the cars' parts a fresh one each frame. Nothing is built while
## ray tracing is off. Lives under RaceWorld and runs after it, once the cars have been placed.
class_name RayTracing
extends Node

const STRENGTH := 1.0 ## reflection intensity multiplier
const ROUGHNESS_CUT_OFF := 0.45 ## glossier than this reflects; wet tarmac is 0.16, puddles 0.03
const MAX_DISTANCE := 1500.0 ## m a reflection ray travels before it gives up and shows the sky
const SKIP_NODES := ["RacingLine", "StandCrowdFar"] ## overlays that are not part of the scene, and the far crowd (StandCrowd stands in for it)

var effect := RtReflectionsEffect.new()
var enabled := false:
	set(value):
		enabled = value
		effect.enabled = value
## 0 normal, 1 primary rays (the traced scene in place of the rendered one), 2 what the reflections see
var debug_view := 0
var shadows := true

var _world: Node3D
var _static_dirty := true
var _dynamic_dirty := true
var _blas_nodes := PackedByteArray()
var _triangles := PackedByteArray()
var _node_count := 0
var _triangle_count := 0
var _static_mark := [0, 0, 0, 0] ## node count, triangle count and byte sizes after the circuit
var _static_blas := {} ## mesh/material key -> BLAS record
var _dynamic_blas := {}
var _static_instances := PackedByteArray()
var _static_top := PackedByteArray()
var _static_instance_count := 0
var _dynamic: Array = [] ## [MeshInstance3D, BLAS record]

func _init() -> void:
	name = "RayTracing"
	process_priority = 100
	effect.enabled = false

func _ready() -> void:
	_world = get_parent()

## The circuit (static) or just the field of cars changed.
func invalidate(circuit: bool) -> void:
	if circuit:
		_static_dirty = true
	_dynamic_dirty = true

func _process(_delta: float) -> void:
	if not enabled or not is_instance_valid(_world) or not _world.track_root:
		return
	if _static_dirty or _dynamic_dirty:
		_rebuild()
	var dynamic := _pack_dynamic()
	var sun: DirectionalLight3D = _world.sun
	var env: Environment = _world.world_environment
	var zenith: Color = _world.sky_top_color.srgb_to_linear()
	var horizon: Color = _world.sky_horizon_color.srgb_to_linear()
	var to_sun := sun.global_basis.z.normalized()
	var sun_colour := sun.light_color.srgb_to_linear() * sun.light_energy
	var ambient := horizon.lerp(zenith, 0.5) * env.ambient_light_energy
	var fog := env.fog_light_color.srgb_to_linear()
	effect.set_frame({
		"instances": dynamic[0], # after the circuit's (set_static)
		"top": dynamic[1],
		"roots": Vector4i(0 if not _static_top.is_empty() else -1,
			_static_top.size() / RtBvh.NODE_BYTES if not dynamic[1].is_empty() else -1,
			_static_instance_count, debug_view),
		"sun_dir": Vector4(to_sun.x, to_sun.y, to_sun.z, 1.0 if shadows and sun.visible else 0.0),
		"sun_color": Vector4(sun_colour.r, sun_colour.g, sun_colour.b, 0.0) * (1.0 if sun.visible else 0.0),
		"ambient": Vector4(ambient.r, ambient.g, ambient.b, 0.0),
		"sky_zenith": Vector4(zenith.r, zenith.g, zenith.b, 0.0),
		"sky_horizon": Vector4(horizon.r, horizon.g, horizon.b, 0.0),
		"fog": Vector4(fog.r, fog.g, fog.b, env.fog_density if env.fog_enabled else 0.0),
		"settings": Vector4(STRENGTH, ROUGHNESS_CUT_OFF, MAX_DISTANCE, 0.0),
		"half": _world.quality < 3, # a ray per 2x2 pixels; Ultra traces every pixel
	})

func _rebuild() -> void:
	var t0 := Time.get_ticks_msec()
	if _static_dirty:
		_blas_nodes = PackedByteArray()
		_triangles = PackedByteArray()
		_node_count = 0
		_triangle_count = 0
		_static_blas.clear()
		var found: Array = []
		_collect(_world.track_root, found)
		var bounds := _instance_bounds(found)
		var bvh := RtBvh.build(bounds[0], bounds[1])
		_static_top = bvh.nodes
		_static_instances = _pack_instances(found, bvh.order)
		_static_instance_count = found.size()
		_static_mark = [_node_count, _triangle_count, _blas_nodes.size(), _triangles.size()]
		_static_dirty = false
		effect.set_static(_static_instances, _static_top)
		print("Ray tracing: circuit has %d instances, %d triangles (%d ms)" % [found.size(), _triangle_count, Time.get_ticks_msec() - t0])
	# the cars' meshes go after the circuit's, which stay put
	_node_count = _static_mark[0]
	_triangle_count = _static_mark[1]
	_blas_nodes.resize(_static_mark[2])
	_triangles.resize(_static_mark[3])
	_dynamic_blas.clear()
	_dynamic.clear()
	if is_instance_valid(_world.cars_root):
		var found: Array = []
		_collect(_world.cars_root, found, true)
		for entry in found:
			_dynamic.append([entry[0], entry[2]])
	_dynamic_dirty = false
	effect.set_geometry(_blas_nodes, _triangles)

## Appends [node, world transform, BLAS record, tint] for every mesh (and MultiMesh instance) under root.
func _collect(root: Node, out: Array, dynamic := false) -> void:
	# cars that are hidden now may show later: their visibility is checked every frame instead
	if String(root.name).rstrip("0123456789_") in SKIP_NODES or (not dynamic and root is Node3D and not root.visible):
		return
	if root is MeshInstance3D and root.mesh:
		var materials: Array = []
		for s in root.mesh.get_surface_count():
			materials.append(root.get_active_material(s))
		var record := _blas(root.mesh, materials, _dynamic_blas if dynamic else _static_blas)
		if not record.is_empty() and (dynamic or not is_zero_approx(root.global_basis.determinant())):
			out.append([root, root.global_transform, record, Color.WHITE])
	elif root is MultiMeshInstance3D and root.multimesh and root.multimesh.mesh:
		var mm: MultiMesh = root.multimesh
		var materials: Array = []
		for s in mm.mesh.get_surface_count():
			materials.append(root.material_override if root.material_override else mm.mesh.surface_get_material(s))
		var record := _blas(mm.mesh, materials, _dynamic_blas if dynamic else _static_blas)
		if not record.is_empty():
			var count := mm.instance_count if mm.visible_instance_count < 0 else mini(mm.visible_instance_count, mm.instance_count)
			for i in count:
				var xf: Transform3D = root.global_transform * mm.get_instance_transform(i)
				if is_zero_approx(xf.basis.determinant()):
					continue
				var tint := mm.get_instance_color(i).srgb_to_linear() if mm.use_colors else Color.WHITE
				out.append([root, xf, record, tint])
	for child in root.get_children():
		_collect(child, out, dynamic)

## The triangle BVH of a mesh with its materials: {node, triangle, lo, hi}, or {} if nothing is traceable.
func _blas(mesh: Mesh, materials: Array, cache: Dictionary) -> Dictionary:
	var key := str(mesh.get_instance_id())
	for m in materials:
		key += ":" + (str(m.get_instance_id()) if m else "-")
	if cache.has(key):
		return cache[key]
	var corners := PackedVector3Array() # three per triangle
	var colours := PackedColorArray()
	for s in mesh.get_surface_count():
		if mesh is ArrayMesh and mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var style := _surface_style(materials[s] if s < materials.size() else null)
		if style.is_empty():
			continue
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var vertex_colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if style.vertex_colour and arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var count := indices.size() if not indices.is_empty() else verts.size()
		var base: Color = style.colour
		for t in range(0, count - 2, 3):
			var a := indices[t] if not indices.is_empty() else t
			var b := indices[t + 1] if not indices.is_empty() else t + 1
			var c := indices[t + 2] if not indices.is_empty() else t + 2
			corners.append(verts[a])
			corners.append(verts[b])
			corners.append(verts[c])
			var colour := base
			if not vertex_colours.is_empty():
				var avg := (vertex_colours[a] + vertex_colours[b] + vertex_colours[c]) / 3.0
				if style.vertex_srgb:
					avg = avg.srgb_to_linear()
				colour = Color(base.r * avg.r, base.g * avg.g, base.b * avg.b)
				colour.a = base.a
			colours.append(colour)
	var n := colours.size()
	if n == 0:
		cache[key] = {}
		return {}
	var lo := PackedVector3Array()
	var hi := PackedVector3Array()
	lo.resize(n)
	hi.resize(n)
	var mesh_lo := Vector3.INF
	var mesh_hi := -Vector3.INF
	for i in n:
		var p0 := corners[i * 3]
		var p1 := corners[i * 3 + 1]
		var p2 := corners[i * 3 + 2]
		lo[i] = p0.min(p1).min(p2)
		hi[i] = p0.max(p1).max(p2)
		mesh_lo = mesh_lo.min(lo[i])
		mesh_hi = mesh_hi.max(hi[i])
	var bvh := RtBvh.build(lo, hi)
	var floats := PackedFloat32Array()
	floats.resize(n * 12)
	for i in n:
		var t := bvh.order[i]
		var p0 := corners[t * 3]
		var e1 := corners[t * 3 + 1] - p0
		var e2 := corners[t * 3 + 2] - p0
		var o := i * 12
		floats[o] = p0.x
		floats[o + 1] = p0.y
		floats[o + 2] = p0.z
		floats[o + 4] = e1.x
		floats[o + 5] = e1.y
		floats[o + 6] = e1.z
		floats[o + 8] = e2.x
		floats[o + 9] = e2.y
		floats[o + 10] = e2.z
	var bytes := floats.to_byte_array()
	for i in n:
		bytes.encode_u32(i * 48 + 12, _pack_colour(colours[bvh.order[i]]))
	var record := {"node": _node_count, "triangle": _triangle_count, "aabb": AABB(mesh_lo, mesh_hi - mesh_lo)}
	_blas_nodes.append_array(bvh.nodes)
	_triangles.append_array(bytes)
	_node_count += bvh.node_count
	_triangle_count += n
	cache[key] = record
	return record

## How a surface looks to the reflections: {colour (linear, alpha = emission), vertex_colour, vertex_srgb},
## or {} for surfaces that are not traced (see-through ones).
static func _surface_style(material: Material) -> Dictionary:
	var style := {"colour": Color(0.3, 0.3, 0.3, 0.0), "vertex_colour": false, "vertex_srgb": true}
	if material is BaseMaterial3D:
		if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return {}
		var colour: Color = material.albedo_color.srgb_to_linear()
		colour.a = 0.0
		if material.emission_enabled:
			colour.a = clampf(material.emission.srgb_to_linear().get_luminance() * material.emission_energy_multiplier, 0.0, 8.0)
		style.colour = colour
		style.vertex_colour = material.vertex_color_use_as_albedo
		style.vertex_srgb = material.vertex_color_is_srgb
	elif material is ShaderMaterial and material.shader:
		var shader: Shader = material.shader
		var path := shader.resource_path.get_file()
		if path == "foliage.gdshader":
			style.colour = Color(1, 1, 1, 0)
			style.vertex_colour = true
			return style
		for param in ["base_color", "deep_color"]:
			var value = material.get_shader_parameter(param)
			if value == null:
				value = RenderingServer.shader_get_parameter_default(shader.get_rid(), param)
			if value is Color or value is Vector3:
				var c := Color(value.r, value.g, value.b) if value is Color else Color(value.x, value.y, value.z)
				style.colour = c.srgb_to_linear()
				style.colour.a = 0.0
				break
		if material.get_shader_parameter("use_vertex_color") == true:
			style.colour = Color(1, 1, 1, 0)
			style.vertex_colour = true
	return style

static func _pack_colour(c: Color) -> int:
	var r := int(sqrt(clampf(c.r, 0.0, 1.0)) * 255.0 + 0.5)
	var g := int(sqrt(clampf(c.g, 0.0, 1.0)) * 255.0 + 0.5)
	var b := int(sqrt(clampf(c.b, 0.0, 1.0)) * 255.0 + 0.5)
	var a := int(sqrt(clampf(c.a / 8.0, 0.0, 1.0)) * 255.0 + 0.5)
	return r | (g << 8) | (b << 16) | (a << 24)

## [PackedVector3Array mins, maxes] of the instances' world bounds.
static func _instance_bounds(found: Array) -> Array:
	var lo := PackedVector3Array()
	var hi := PackedVector3Array()
	lo.resize(found.size())
	hi.resize(found.size())
	for i in found.size():
		var box: AABB = found[i][1] * found[i][2].aabb
		lo[i] = box.position
		hi[i] = box.end
	return [lo, hi]

## 64 bytes per instance in BVH order: world-to-local rows, then (root node, first triangle, tint, 0).
static func _pack_instances(found: Array, order: PackedInt32Array) -> PackedByteArray:
	var floats := PackedFloat32Array()
	floats.resize(order.size() * 16)
	for i in order.size():
		var inv: Transform3D = found[order[i]][1].affine_inverse()
		var o := i * 16
		for r in 3:
			floats[o + r * 4] = inv.basis.x[r]
			floats[o + r * 4 + 1] = inv.basis.y[r]
			floats[o + r * 4 + 2] = inv.basis.z[r]
			floats[o + r * 4 + 3] = inv.origin[r]
	var bytes := floats.to_byte_array()
	for i in order.size():
		var entry: Array = found[order[i]]
		bytes.encode_s32(i * 64 + 48, entry[2].node)
		bytes.encode_s32(i * 64 + 52, entry[2].triangle)
		bytes.encode_u32(i * 64 + 56, _pack_colour(entry[3]))
	return bytes

## [instance bytes, top-level node bytes] for the cars as they are this frame.
func _pack_dynamic() -> Array:
	var found: Array = []
	for entry in _dynamic:
		var mi: MeshInstance3D = entry[0]
		if not is_instance_valid(mi):
			_dynamic_dirty = true
			continue
		if not mi.is_visible_in_tree():
			continue
		var xf := mi.global_transform
		if is_zero_approx(xf.basis.determinant()):
			continue
		found.append([mi, xf, entry[1], Color.WHITE])
	if found.is_empty():
		return [PackedByteArray(), PackedByteArray()]
	var bounds := _instance_bounds(found)
	var bvh := RtBvh.build(bounds[0], bounds[1])
	return [_pack_instances(found, bvh.order), bvh.nodes]
