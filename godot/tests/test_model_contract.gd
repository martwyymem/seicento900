## The Blender-built GLBs keep the object and material names the Godot code looks up (see AGENTS.md), so a rebuilt
## model never silently loses a part.
extends RefCounted

var completed := false
var errors: Array[String] = []

## model -> {"objects": names that must exist, "materials": names that must exist on some mesh}
const CONTRACT := {
	"res://models/seicento.glb": {"objects": ["Body", "Details", "Stripes", "Wheel"], "materials": ["Paint", "Taillight", "Glass", "Headlight"]},
	"res://models/town.glb": {"objects": ["Headframe", "ChurchSpire", "Streetlamp", "TrafficLight", "BusShelter", "LevelCrossing",
		"FestivalStage", "FestivalArch", "Tent", "FlagPole", "CarHatch", "CarSedan", "CarVan", "Maluch"], "materials": ["Paint", "Lamp", "Banner"]},
	"res://models/roadside.glb": {"objects": ["BushCluster"], "materials": []},
	"res://models/landmarks.glb": {"objects": ["Barbakan", "FloriaGate", "PszczynaCastle", "WilamowiceChurch"],
		"materials": ["Plaster", "Roof", "Copper", "Glass"]},
}

## model -> {object: [min size, max size]} in metres (x width, y height, z length): a prop built at the wrong scale fails here
const SIZES := {
	"res://models/town.glb": {
		"CarHatch": [Vector3(1.5, 1.2, 3.5), Vector3(2.1, 1.9, 4.6)],
		"CarSedan": [Vector3(1.5, 1.2, 4.0), Vector3(2.1, 1.9, 5.2)],
		"CarVan": [Vector3(1.6, 1.6, 4.0), Vector3(2.3, 2.7, 5.6)],
		"Maluch": [Vector3(1.3, 1.1, 2.9), Vector3(1.7, 1.5, 3.6)],
		"Streetlamp": [Vector3(0.1, 6.0, 0.5), Vector3(1.0, 12.0, 4.0)],
		"TrafficLight": [Vector3(0.3, 2.5, 0.3), Vector3(1.0, 5.0, 1.0)],
		"BusShelter": [Vector3(3.0, 2.3, 1.0), Vector3(6.0, 3.5, 3.0)],
		"TrainCar": [Vector3(2.6, 3.5, 19.0), Vector3(3.2, 5.6, 25.0)],
	},
	"res://models/trees.glb": {
		"Pine": [Vector3(4, 8, 4), Vector3(14, 26, 14)],
		"Birch": [Vector3(3, 7, 3), Vector3(10, 18, 10)],
		"Broadleaf": [Vector3(6, 8, 6), Vector3(18, 22, 18)],
	},
	"res://models/landmarks.glb": {
		"WilamowiceChurch": [Vector3(45.0, 30.0, 18.0), Vector3(55.0, 55.0, 28.0)],
		"Barbakan": [Vector3(30.0, 10.0, 25.0), Vector3(45.0, 40.0, 38.0)],
	},
	"res://models/roadside.glb": {
		"HayBale": [Vector3(0.6, 0.5, 0.6), Vector3(1.6, 1.4, 1.6)],
		"KilometrePost": [Vector3(0.1, 0.5, 0.1), Vector3(0.6, 1.3, 0.6)],
	},
}

func _size(n: Node) -> Vector3:
	var out := AABB()
	var first := true
	for m in [n] + n.find_children("*", "MeshInstance3D", true, false):
		if m is MeshInstance3D and m.mesh:
			var t := Transform3D.IDENTITY
			var p: Node = m
			while p != null and p != n.get_parent():
				if p is Node3D:
					t = p.transform * t
				p = p.get_parent()
			var b: AABB = t * m.mesh.get_aabb()
			out = b if first else out.merge(b)
			first = false
	return out.size

func run() -> Array:
	for path in CONTRACT:
		# a fresh copy: the game rewrites materials on the cached shared meshes (glass, headlights)
		var scene := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if scene == null:
			errors.append("%s does not load" % path)
			continue
		var root := scene.instantiate()
		var names := {}
		var mats := {}
		for n in [root] + root.find_children("*", "", true, false):
			names[String(n.name).split(".")[0]] = true # Godot may suffix duplicates
			if n is MeshInstance3D and n.mesh:
				for s in n.mesh.get_surface_count():
					var m: Material = n.mesh.surface_get_material(s)
					if m:
						mats[m.resource_name] = true
		for want in CONTRACT[path].objects:
			if not names.has(want):
				errors.append("%s lacks object '%s'" % [path, want])
		for want in CONTRACT[path].materials:
			if not mats.has(want):
				errors.append("%s lacks material '%s'" % [path, want])
		for obj in SIZES.get(path, {}):
			var node := root.find_child(obj, true, false)
			if node == null:
				continue # already reported as a missing object, or not part of the contract
			var size := _size(node)
			var lo: Vector3 = SIZES[path][obj][0]
			var hi: Vector3 = SIZES[path][obj][1]
			if size.x < lo.x or size.y < lo.y or size.z < lo.z or size.x > hi.x or size.y > hi.y or size.z > hi.z:
				errors.append("%s/%s is %.1f x %.1f x %.1f m, outside %s to %s" % [path, obj, size.x, size.y, size.z, lo, hi])
		root.free()
	completed = true
	return errors
