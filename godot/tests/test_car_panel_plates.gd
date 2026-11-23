## The number plates go with their loose panel. Front (playtest 2026-11-22: "front plate on a dropped bumper"): in every car's
## model the front Plate surface sits only in the BumperF pieces, so when the bumper sags it hangs with it, when it is
## thrown the hidden hinge takes it along and the flying copy carries it, and a repair puts it back.
## Rear: the plate and its frame sit on exactly ONE loose part (the Boot, or BumperR where the car mounts the plate on the
## bumper) and none of it stays on the Body. `carkit.split_damage_parts` moves the bumper/boot cut round the plate's frame
## box (it used to straddle the cut on the Golf, Focus and Sandero: a torn boot took part of it, the Golf left a sliver).
extends RefCounted

var completed := false
var errors: Array[String] = []

const VISUAL := preload("res://scripts/ui/race_car_visual.gd")

func check(ok: bool, what: String) -> void:
	if not ok:
		errors.append(what)

func run() -> Array:
	var parent := Node3D.new()
	Engine.get_main_loop().root.add_child(parent)
	for key in CarCatalog.KEYS:
		_car(parent, key)
		_rear_car(parent, key)
	parent.free()
	completed = true
	return errors

## The meshes under node with a front plate: a Plate surface whose vertices sit at the nose (-Z, centred).
func _front_plates(node: Node) -> Array[MeshInstance3D]:
	return _plates(node, false)

## The meshes under node with a rear plate: a Plate surface with ANY vertex at the tail (+Z), near the centre line. Any
## vertex, not the average: a sliver of a plate left on the Body would hide in a mesh whose other plate faces sit elsewhere.
func _rear_plates(node: Node) -> Array[MeshInstance3D]:
	return _plates(node, true)

func _plates(node: Node, rear: bool) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			var plate := m != null and m.resource_name == "Plate"
			if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
				plate = plate or (m as ShaderMaterial).shader.resource_path.ends_with("car_plate.gdshader")
			if not plate:
				continue
			var v: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			if v.is_empty():
				continue
			var z := 0.0
			var at_tail := false
			for p in v:
				z += p.z
				if p.z > 1.4 and absf(p.x) < 0.4:
					at_tail = true
			if rear:
				if at_tail: # (the dash and door plates are inside the car, the roof number disc is above it)
					out.append(node)
					break
			elif z / v.size() < -1.4: # a plate at the nose
				out.append(node)
				break
	for c in node.get_children():
		out.append_array(_plates(c, rear))
	return out

func _car(parent: Node3D, key: String) -> void:
	var car: Node3D = VISUAL.new()
	car.car_key = key
	parent.add_child(car)
	var rc := RaceCar.new()
	rc.control = "free"
	car.sync(rc, 1.0 / 60.0, 0.0, 0.0, false)
	if not car._panels.has("BumperF"):
		errors.append("%s: no BumperF panel built" % key)
		car.free()
		return
	var hinge: Node3D = car._panels.BumperF.hinge
	var plates := _front_plates(car.body_pivot)
	check(not plates.is_empty(), "%s: no front number plate found in the car" % key)
	for mi in plates:
		check(hinge.is_ancestor_of(mi), "%s: the front plate (%s) is not under the front bumper's hinge, it would stay on a dropped bumper" % [key, mi.get_path()])
		check(mi.is_visible_in_tree(), "%s: the front plate is hidden on a whole car" % key)
	# sagging: the plate is still under the hinge, which has moved to the end that stays on
	car._sag("BumperF", 0.6)
	for mi in plates:
		check(hinge.is_ancestor_of(mi), "%s: the plate left the bumper's hinge when it sagged" % key)
	# thrown: the plate on the car goes with the hidden hinge, and the flying copy carries one
	car._throw("BumperF", Vector3(0.0, 0.0, -10.0))
	check(car._panel_state("BumperF") == 2, "%s: the bumper was not thrown" % key)
	for mi in plates:
		check(not mi.is_visible_in_tree(), "%s: the front plate still shows on the car after its bumper was thrown" % key)
	var flying := 0
	for l in car._loose:
		if is_instance_valid(l[0]):
			flying += _front_plates(l[0] as Node).size()
	check(flying >= plates.size(), "%s: the thrown bumper carries %d front plate mesh(es), not %d" % [key, flying, plates.size()])
	# a repair puts it back
	car._repair()
	for mi in plates:
		check(mi.is_visible_in_tree() and hinge.is_ancestor_of(mi), "%s: the plate is not back on the repaired bumper" % key)
	car.free()

## The rear plate: every mesh with a bit of it hangs under ONE panel's hinge (Boot or BumperR), so tearing that panel off
## takes all of it and the Body (and the other panel) keeps none.
func _rear_car(parent: Node3D, key: String) -> void:
	var car: Node3D = VISUAL.new()
	car.car_key = key
	parent.add_child(car)
	var rc := RaceCar.new()
	rc.control = "free"
	car.sync(rc, 1.0 / 60.0, 0.0, 0.0, false)
	var plates := _rear_plates(car.body_pivot)
	check(not plates.is_empty(), "%s: no rear number plate found in the car" % key)
	var owner := ""
	for name in ["Boot", "BumperR"]:
		if not car._panels.has(name):
			continue
		var hinge: Node3D = car._panels[name].hinge
		var n_under := 0
		for mi in plates:
			if hinge.is_ancestor_of(mi):
				n_under += 1
		if n_under > 0:
			check(owner == "", "%s: the rear plate is split across %s and %s" % [key, owner, name])
			check(n_under == plates.size(), "%s: only %d of %d rear plate meshes are on the %s, the rest stay on the body" % [key, n_under, plates.size(), name])
			owner = name
	check(owner != "", "%s: no rear plate mesh is under the Boot or the rear bumper: it would stay on the body" % key)
	if owner == "":
		car.free()
		return
	for mi in plates:
		check(mi.is_visible_in_tree(), "%s: the rear plate is hidden on a whole car" % key)
	# thrown: all of the plate goes with the hidden hinge, and the flying copy carries it
	car._throw(owner, Vector3(0.0, 0.0, 10.0))
	check(car._panel_state(owner) == 2, "%s: the %s was not thrown" % [key, owner])
	for mi in plates:
		check(not mi.is_visible_in_tree(), "%s: part of the rear plate still shows on the car after its %s was thrown" % [key, owner])
	var flying := 0
	for l in car._loose:
		if is_instance_valid(l[0]):
			flying += _rear_plates(l[0] as Node).size()
	check(flying >= plates.size(), "%s: the thrown %s carries %d rear plate mesh(es), not %d" % [key, owner, flying, plates.size()])
	# nothing of a rear plate is left in the car with the panel gone (the Body's own meshes, the other panels)
	var left := 0
	for mi in _rear_plates(car.body_pivot):
		if mi.is_visible_in_tree():
			left += 1
	check(left == 0, "%s: %d rear plate mesh(es) still visible on the car after the %s was thrown" % [key, left, owner])
	car._repair()
	for mi in plates:
		check(mi.is_visible_in_tree(), "%s: the rear plate is not back after the repair" % key)
	car.free()
