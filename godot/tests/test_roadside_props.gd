## The roadside model loads with stable names and its seeded vegetation lands outside the driveable ribbon.
extends RefCounted

const PROPS := preload("res://scripts/ui/roadside_props.gd")

var completed := false
var errors: Array[String] = []

class MockWorld:
	extends Node3D
	var track: Track
	var track_root: Node3D
	var world_center := Vector2.ZERO
	var quality := 1
	var surroundings = null
	var race = null

	func _track_lookup(cell: float) -> Dictionary:
		var buckets := {"cell": cell}
		for i in track.n:
			var key := Vector2i(floori(track.X[i] / cell), floori(track.Y[i] / cell))
			if not buckets.has(key):
				buckets[key] = PackedInt32Array()
			buckets[key].append(i)
		return buckets

	func _clear_of_track(lookup: Dictionary, x: float, z: float, clearance: float) -> bool:
		var cell: float = lookup.cell
		var reach := ceili(clearance / cell)
		for dz in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				for i in lookup.get(Vector2i(floori(x / cell) + dx, floori(z / cell) + dz), PackedInt32Array()):
					var ddx := track.X[i] - x
					var ddz := track.Y[i] - z
					if ddx * ddx + ddz * ddz < clearance * clearance:
						return false
		return true

	func _near_tv_camera(_x: float, _z: float) -> bool:
		return false

	func _ground_at(_x: float, _z: float) -> float:
		return 0.0

func run() -> Array[String]:
	var model_meshes: Dictionary = PROPS.meshes()
	for name in PROPS.MESH_NAMES:
		if not model_meshes.has(name):
			errors.append("roadside.glb is missing %s" % name)
	for key in ["gp", "bor"]:
		var track := Track.new(Track.load_def(key))
		var a := _world(track)
		var b := _world(track)
		var props_a := PROPS.new()
		var props_b := PROPS.new()
		props_a.build(a)
		props_b.build(b)
		var sig_a := _signature(props_a.root)
		var sig_b := _signature(props_b.root)
		if sig_a != sig_b:
			errors.append("%s roadside placement is not deterministic" % key)
		for child in props_a.root.get_children():
			var instance := child as MultiMeshInstance3D
			if not instance or not instance.multimesh:
				continue
			for i in instance.multimesh.instance_count:
				var pos := instance.multimesh.get_instance_transform(i).origin
				if not a._clear_of_track(props_a._lookup, pos.x, pos.z, track.half + track.cfg.runoff + 2.9):
					errors.append("%s %s overlaps the road" % [key, instance.name])
					break
		a.free()
		b.free()
	completed = true
	return errors

func _world(track: Track) -> MockWorld:
	var w := MockWorld.new()
	w.track = track
	w.track_root = Node3D.new()
	w.add_child(w.track_root)
	return w

func _signature(parent: Node3D) -> Array:
	var out := []
	for child in parent.get_children():
		var instance := child as MultiMeshInstance3D
		if not instance or not instance.multimesh:
			continue
		var mm := instance.multimesh
		var transforms := []
		for i in mm.instance_count:
			var p := mm.get_instance_transform(i).origin
			transforms.append([p.x, p.y, p.z])
		out.append([child.name, transforms])
	return out
