## Bounding volume hierarchy for the software ray tracer (rt_reflections.gd / shaders/rt_reflections.glsl).
## Primitives (triangles or instances) are sorted along a Morton curve and split where their codes first
## differ, the linear-BVH scheme: the sort is native, so a 60k-triangle circuit mesh builds in a fraction of a
## second of GDScript. Nodes are 32 bytes in the layout the shader reads:
##   vec4(min.xyz, first)  vec4(max.xyz, count)
## A leaf has count > 0 and covers order[first .. first + count); an inner node has count 0 and its two
## children at first and first + 1. Indices are relative to the tree, so trees can be packed back to back.
class_name RtBvh
extends RefCounted

const LEAF_SIZE := 4
const NODE_BYTES := 32

static var _spread_table := PackedInt32Array()

var nodes := PackedByteArray()
var order := PackedInt32Array() ## primitive index per leaf slot
var node_count := 0

var _min: PackedVector3Array
var _max: PackedVector3Array
var _codes := PackedInt64Array()
var _rmin := Vector3.ZERO
var _rmax := Vector3.ZERO

## Builds over per-primitive bounds. An empty input gives an empty tree (node_count 0).
static func build(prim_min: PackedVector3Array, prim_max: PackedVector3Array) -> RtBvh:
	var bvh := RtBvh.new()
	bvh._build(prim_min, prim_max)
	return bvh

func _build(prim_min: PackedVector3Array, prim_max: PackedVector3Array) -> void:
	var n := prim_min.size()
	if n == 0:
		return
	if _spread_table.is_empty():
		_spread_table.resize(1024)
		for v in 1024:
			var x := v
			x = (x | (x << 16)) & 0x030000FF
			x = (x | (x << 8)) & 0x0300F00F
			x = (x | (x << 4)) & 0x030C30C3
			x = (x | (x << 2)) & 0x09249249
			_spread_table[v] = x
	_min = prim_min
	_max = prim_max
	var cmin := Vector3.INF
	var cmax := -Vector3.INF
	for i in n:
		var c := prim_min[i] + prim_max[i]
		cmin = cmin.min(c)
		cmax = cmax.max(c)
	var scale := Vector3.ONE * 1023.0 / (cmax - cmin).max(Vector3.ONE * 1e-6)
	var keys := PackedInt64Array()
	keys.resize(n)
	var table := _spread_table
	for i in n:
		var q := (prim_min[i] + prim_max[i] - cmin) * scale
		var code := table[int(q.x)] | (table[int(q.y)] << 1) | (table[int(q.z)] << 2)
		keys[i] = (code << 24) | i
	keys.sort()
	order.resize(n)
	_codes.resize(n)
	for i in n:
		order[i] = keys[i] & 0xFFFFFF
		_codes[i] = keys[i] >> 24
	nodes.resize(maxi(2 * n - 1, 1) * NODE_BYTES)
	node_count = 1
	_fill(0, 0, n)
	nodes.resize(node_count * NODE_BYTES)
	_codes = PackedInt64Array()

func _fill(node: int, first: int, count: int) -> void:
	if count <= LEAF_SIZE:
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for i in range(first, first + count):
			var p := order[i]
			lo = lo.min(_min[p])
			hi = hi.max(_max[p])
		_write(node, lo, hi, first, count)
		_rmin = lo
		_rmax = hi
		return
	var last := first + count - 1
	var split := first + (count >> 1)
	var diff := _codes[first] ^ _codes[last]
	if diff != 0:
		# the first primitive whose code has the highest differing bit set (codes share the bits above it)
		var bit := 1 << int(floor(log(float(diff)) / log(2.0)))
		if bit > diff:
			bit >>= 1
		elif (bit << 1) <= diff:
			bit <<= 1
		var lo_i := first
		var hi_i := last
		while lo_i < hi_i:
			var mid := (lo_i + hi_i) >> 1
			if _codes[mid] & bit:
				hi_i = mid
			else:
				lo_i = mid + 1
		split = lo_i
	var left := node_count
	node_count += 2
	_fill(left, first, split - first)
	var lmin := _rmin
	var lmax := _rmax
	_fill(left + 1, split, first + count - split)
	_rmin = _rmin.min(lmin)
	_rmax = _rmax.max(lmax)
	_write(node, _rmin, _rmax, left, 0)

func _write(node: int, lo: Vector3, hi: Vector3, first: int, count: int) -> void:
	var o := node * NODE_BYTES
	nodes.encode_float(o, lo.x)
	nodes.encode_float(o + 4, lo.y)
	nodes.encode_float(o + 8, lo.z)
	nodes.encode_s32(o + 12, first)
	nodes.encode_float(o + 16, hi.x)
	nodes.encode_float(o + 20, hi.y)
	nodes.encode_float(o + 24, hi.z)
	nodes.encode_s32(o + 28, count)
