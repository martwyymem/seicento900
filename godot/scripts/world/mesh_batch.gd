## Accumulates triangles into packed arrays and commits them as one ArrayMesh surface: much faster than
## SurfaceTool for the tens of thousands of quads the open world's terrain, streets and buildings need.
class_name MeshBatch
extends RefCounted

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var uvs := PackedVector2Array()
var uv2s := PackedVector2Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()
var use_uv2 := false
var use_color := false

func _init(with_uv2 := false, with_color := false) -> void:
	use_uv2 = with_uv2
	use_color = with_color

func is_empty() -> bool:
	return indices.is_empty()

func vertex(p: Vector3, n: Vector3, uv := Vector2.ZERO, uv2 := Vector2.ZERO, c := Color.WHITE) -> int:
	verts.append(p)
	normals.append(n)
	uvs.append(uv)
	if use_uv2:
		uv2s.append(uv2)
	if use_color:
		colors.append(c)
	return verts.size() - 1

## A triangle of existing vertices, wound so its front faces n (Godot: clockwise seen from the front).
func tri(a: int, b: int, c: int) -> void:
	indices.append(a)
	indices.append(b)
	indices.append(c)

## Quad a-b-c-d given counter-clockwise seen from the side it faces.
func quad(a: int, b: int, c: int, d: int) -> void:
	indices.append(a)
	indices.append(c)
	indices.append(b)
	indices.append(a)
	indices.append(d)
	indices.append(c)

## One flat-shaded triangle facing n (the winding is fixed to match).
func flat_tri(p0: Vector3, p1: Vector3, p2: Vector3, n: Vector3, uv0: Vector2, uv1: Vector2, uv2_: Vector2, c: Color, u2 := Vector2.ZERO) -> void:
	var base := verts.size()
	if (p1 - p0).cross(p2 - p0).dot(n) > 0.0:
		vertex(p0, n, uv0, u2, c)
		vertex(p2, n, uv2_, u2, c)
		vertex(p1, n, uv1, u2, c)
	else:
		vertex(p0, n, uv0, u2, c)
		vertex(p1, n, uv1, u2, c)
		vertex(p2, n, uv2_, u2, c)
	indices.append(base)
	indices.append(base + 1)
	indices.append(base + 2)

## A flat quad p0-p1-p2-p3 (in order round it) facing n.
func flat_quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3, c: Color, uv := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], u2 := Vector2.ZERO) -> void:
	flat_tri(p0, p1, p2, n, uv[0], uv[1], uv[2], c, u2)
	flat_tri(p0, p2, p3, n, uv[0], uv[2], uv[3], c, u2)

## A box between two points on the ground plane, h tall from y0, w wide (for posts, rails, kerbs).
func beam(a: Vector3, b: Vector3, w: float, h: float, c: Color) -> void:
	var d := b - a
	d.y = 0.0
	if d.length_squared() < 1e-6:
		d = Vector3.FORWARD
	var side := Vector3(-d.z, 0.0, d.x).normalized() * w * 0.5
	var up := Vector3.UP * h
	var p := [a - side, a + side, b + side, b - side]
	flat_quad(p[0] + up, p[1] + up, p[2] + up, p[3] + up, Vector3.UP, c)
	for k in 4:
		var q0: Vector3 = p[k]
		var q1: Vector3 = p[(k + 1) % 4]
		var n := (q1 - q0).cross(Vector3.UP).normalized()
		if n.dot(q0 - (a + b) * 0.5) < 0.0:
			n = -n
		flat_quad(q0, q1, q1 + up, q0 + up, n, c)

func commit(mesh: ArrayMesh = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	if indices.is_empty():
		return mesh
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	if use_uv2:
		arr[Mesh.ARRAY_TEX_UV2] = uv2s
	if use_color:
		arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh
