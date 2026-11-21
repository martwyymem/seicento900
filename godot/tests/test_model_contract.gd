## The Blender-built GLBs keep the object and material names the Godot code looks up (see AGENTS.md), so a rebuilt
## model never silently loses a part.
extends RefCounted

var completed := false
var errors: Array[String] = []

## model -> {"objects": names that must exist, "materials": names that must exist on some mesh}
const CONTRACT := {
	"res://models/seicento.glb": {"objects": ["Body", "Details", "Stripes", "Wheel"], "materials": ["Paint", "Taillight", "Glass", "Headlight"]},
	"res://models/golf4.glb": {"objects": ["Body", "Details", "Stripes", "Wheel", "Cabin", "Martini", "Abarth", "Marlboro"],
		"materials": ["Paint", "Taillight", "Glass", "Headlight", "LampGlass", "TailGlass", "TailBulb", "Plate", "Bumper", "Trim", "Gasket", "Grille"]},
	"res://models/logan.glb": {"objects": ["Body", "Details", "Stripes", "Wheel", "Cabin", "Martini", "Abarth", "Marlboro"],
		"materials": ["Paint", "Taillight", "Glass", "Headlight", "LampGlass", "TailGlass", "TailBulb", "Plate", "Bumper", "Trim", "Gasket", "Grille"]},
	"res://models/v50.glb": {"objects": ["Body", "Details", "Stripes", "Wheel", "Cabin", "Martini", "Abarth", "Marlboro"],
		"materials": ["Paint", "Taillight", "Glass", "Headlight", "LampGlass", "TailGlass", "TailBulb", "Plate", "Bumper", "Trim", "Gasket", "Grille"]},
	"res://models/i20.glb": {"objects": ["Body", "Details", "Stripes", "Wheel", "Cabin", "Martini", "Abarth", "Marlboro"],
		"materials": ["Paint", "Taillight", "Glass", "Headlight", "LampGlass", "TailGlass", "TailBulb", "Plate", "Bumper", "Trim", "Gasket", "Grille"]},
	"res://models/sandero.glb": {"objects": ["Body", "Details", "Stripes", "Wheel", "Cabin", "Martini", "Abarth", "Marlboro"],
		"materials": ["Paint", "Taillight", "Glass", "Headlight", "LampGlass", "TailGlass", "TailBulb", "Plate", "Bumper", "Trim", "Gasket", "Grille"]},
	"res://models/focus.glb": {"objects": ["Body", "Details", "Stripes", "Wheel", "Cabin", "Martini", "Abarth", "Marlboro"],
		"materials": ["Paint", "Taillight", "Glass", "Headlight", "LampGlass", "TailGlass", "TailBulb", "Plate", "Bumper", "Trim", "Gasket", "Grille"]},
	"res://models/zafira.glb": {"objects": ["Body", "Details", "Stripes", "Wheel", "Cabin", "Martini", "Abarth", "Marlboro"],
		"materials": ["Paint", "Taillight", "Glass", "Headlight", "LampGlass", "TailGlass", "TailBulb", "Plate", "Bumper", "Trim", "Gasket", "Grille"]},
	"res://models/town.glb": {"objects": ["Headframe", "ChurchSpire", "Streetlamp", "TrafficLight", "BusShelter", "LevelCrossing",
		"FestivalStage", "FestivalArch", "Tent", "FlagPole", "CarHatch", "CarSedan", "CarVan", "Maluch"], "materials": ["Paint", "Lamp", "Banner"]},
	"res://models/traffic_cars.glb": {"objects": ["CarSeicento", "CarGolf4", "CarLogan", "CarV50", "CarI20", "CarSandero", "CarFocus", "CarZafira"],
		"materials": ["Paint", "Glass", "Headlight", "Taillight", "Indicator", "Alloy", "DarkTrim", "Tyre", "Plate"]},
	"res://models/roadside.glb": {"objects": ["BushCluster"], "materials": []},
	"res://models/landmarks.glb": {"objects": ["Barbakan", "FloriaGate", "PszczynaCastle", "WilamowiceChurch"],
		"materials": ["Plaster", "Roof", "Copper", "Glass"]},
	"res://models/wisents.glb": {"objects": ["WisentBull", "WisentCow", "WisentCowLying", "WisentCalf", "PaddockFence", "HayRack"],
		"materials": ["Fur", "FurDark", "Horn", "Wood"]},
}

## model -> {object: [min size, max size]} in metres (x width, y height, z length): a prop built at the wrong scale fails here
const SIZES := {
	"res://models/golf4.glb": { # a Golf IV 5-door: 4,149 x 1,735 (mirrors out: ~1.9) x 1,439 mm; the wheel is a 195/65 R15 (634 mm)
		"Body": [Vector3(1.8, 1.2, 4.10), Vector3(2.05, 1.50, 4.20)],
		"Wheel": [Vector3(0.18, 0.62, 0.62), Vector3(0.24, 0.66, 0.66)],
	},
	"res://models/logan.glb": { # a Logan I saloon: 4,247 x 1,735 (mirrors out: ~1.96) x 1,525 mm; the wheel is a 185/65 R15 (622 mm)
		"Body": [Vector3(1.8, 1.2, 4.20), Vector3(2.05, 1.45, 4.30)],
		"Wheel": [Vector3(0.17, 0.60, 0.60), Vector3(0.24, 0.64, 0.64)],
	},
	"res://models/v50.glb": { # a V50 estate: 4,515 x 1,770 (mirrors out: ~2.0) x 1,452 mm over the rails; the wheel is a 205/55 R16 (632 mm)
		"Body": [Vector3(1.85, 1.3, 4.47), Vector3(2.08, 1.47, 4.56)],
		"Wheel": [Vector3(0.19, 0.62, 0.62), Vector3(0.26, 0.65, 0.65)],
	},
	"res://models/i20.glb": { # a Hyundai i20 PB 5-door: 3,940 x 1,710 (mirrors out: ~1.91) x 1,490 mm; the wheel is a 185/60 R15 (603 mm)
		"Body": [Vector3(1.75, 1.2, 3.89), Vector3(1.98, 1.50, 3.99)],
		"Wheel": [Vector3(0.17, 0.59, 0.59), Vector3(0.23, 0.62, 0.62)],
	},
	"res://models/sandero.glb": { # Dacia Sandero Mk1 5-door: 4,020 x 1,746 (mirrors out: ~1.95) x 1,534 mm; 185/65 R15 (620 mm)
		"Body": [Vector3(1.80, 1.25, 3.97), Vector3(2.05, 1.55, 4.07)],
		"Wheel": [Vector3(0.17, 0.60, 0.60), Vector3(0.24, 0.64, 0.64)],
	},
	"res://models/focus.glb": { # Ford Focus Mk3.5 5-door: 4,358 x 1,823 (mirrors out: ~2.01) x 1,484 mm; 215/55 R16 (642 mm)
		"Body": [Vector3(1.90, 1.35, 4.31), Vector3(2.12, 1.52, 4.41)],
		"Wheel": [Vector3(0.20, 0.62, 0.62), Vector3(0.26, 0.66, 0.66)],
	},
	"res://models/zafira.glb": { # Opel Zafira B MPV: 4,467 x 1,801 (mirrors out: ~2.02) x 1,635 mm; 205/55 R16 (632 mm)
		"Body": [Vector3(1.88, 1.40, 4.42), Vector3(2.12, 1.65, 4.52)],
		"Wheel": [Vector3(0.19, 0.62, 0.62), Vector3(0.26, 0.65, 0.65)],
	},
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
	"res://models/traffic_cars.glb": {
		"CarSeicento": [Vector3(1.45, 1.35, 3.25), Vector3(1.75, 1.85, 3.55)],
		"CarGolf4": [Vector3(1.80, 1.40, 4.10), Vector3(2.05, 1.65, 4.30)],
		"CarLogan": [Vector3(1.80, 1.45, 4.20), Vector3(2.05, 1.95, 4.40)],
		"CarV50": [Vector3(1.85, 1.40, 4.45), Vector3(2.10, 1.70, 4.65)],
		"CarI20": [Vector3(1.75, 1.45, 3.85), Vector3(2.00, 1.75, 4.05)],
		"CarSandero": [Vector3(1.80, 1.45, 3.95), Vector3(2.05, 1.95, 4.15)],
		"CarFocus": [Vector3(1.88, 1.45, 4.30), Vector3(2.12, 1.70, 4.50)],
		"CarZafira": [Vector3(1.88, 1.55, 4.40), Vector3(2.12, 1.85, 4.60)],
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
	"res://models/wisents.glb": { # (x along the animal or the fence bay)
		"WisentBull": [Vector3(2.8, 1.7, 0.9), Vector3(3.8, 2.3, 1.6)],
		"WisentCalf": [Vector3(1.3, 0.8, 0.4), Vector3(2.0, 1.3, 0.9)],
		"PaddockFence": [Vector3(5.8, 1.7, 0.2), Vector3(6.4, 2.1, 0.5)],
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
