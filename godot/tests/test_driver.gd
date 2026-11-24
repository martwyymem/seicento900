## The driver in every car (RaceCarVisual._build_driver, models/driver.glb): present for all nine keys, seated inside the cabin
## under the roof and clear of the windscreen, the doors and the glass (rays against the model's own triangles), the baked-in
## wheel cut out of the Cabin and a turning one in its place, hands that ride the rim, head and wheel that follow the steering and
## the speed, a tint from the paint, an 80 m range, and no change when a door is torn off or a window shatters.
extends RefCounted

var completed := false
var errors: Array[String] = []

const VISUAL := preload("res://scripts/ui/race_car_visual.gd")
const CLEARANCE := 0.02 ## m of air the figure keeps from the skin and the glass

class FakeWorld extends Node:
	var camera_mode := 0
	var quality := 1
	var race = null

func check(ok: bool, what: String) -> void:
	if not ok:
		errors.append(what)

func run() -> Array:
	var parent := Node3D.new()
	Engine.get_main_loop().root.add_child(parent)
	for key in CarCatalog.KEYS:
		_seat(parent, key)
	_wheel_and_hands(parent)
	_head_motion(parent)
	_tint(parent)
	_range_and_cameras(parent)
	_damage(parent)
	_budget(parent)
	parent.free()
	completed = true
	return errors

## The skin and the glass of a car as one triangle mesh (a fresh copy of the model, in the visual's frame), and the Cabin's AABB.
func _skin(key: String) -> Dictionary:
	var fit: Dictionary = CarCatalog.visual(key)
	var scene := ResourceLoader.load(fit.model, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var root := scene.instantiate()
	var faces := PackedVector3Array()
	var cabin := AABB()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var n := String(mi.name).split(".")[0]
		if n in ["Body", "DoorL", "DoorR", "Windscreen", "WindowL", "WindowR", "RearWindow"]:
			faces.append_array((mi as MeshInstance3D).mesh.get_faces())
		elif n == "Cabin":
			cabin = (mi as MeshInstance3D).mesh.get_aabb()
	root.free()
	var tri := TriangleMesh.new()
	tri.create_from_faces(faces)
	return {"tri": tri, "cabin": cabin}

func _box(mi: MeshInstance3D) -> AABB:
	return mi.global_transform * mi.mesh.get_aabb()

## Distance along dir from from to the first triangle, or INF.
func _ray(tri: TriangleMesh, from: Vector3, dir: Vector3) -> float:
	var hit := tri.intersect_ray(from, dir)
	return INF if hit.is_empty() else from.distance_to(hit.position as Vector3)

func _seat(parent: Node3D, key: String) -> void:
	var car: Node3D = VISUAL.new()
	car.car_key = key
	parent.add_child(car)
	var d: Node3D = car.get_node_or_null("SuspendedBody/Driver")
	check(d != null, "%s: no driver in the car" % key)
	if d == null:
		car.free()
		return
	for n in ["DriverBody", "DriverHead", "DriverArmL", "DriverArmR"]:
		check(d.get_node_or_null(n) is MeshInstance3D, "%s: no %s" % [key, n])
	check(car.get_node_or_null("SuspendedBody/SteeringWheel") is MeshInstance3D, "%s: no steering wheel" % key)
	check(car._drv_arms.size() == 2 and car._drv_head != null, "%s: the driver's parts are not wired" % key)
	var skin := _skin(key)
	var tri: TriangleMesh = skin.tri
	var cabin: AABB = skin.cabin
	var head := _box(car._drv_head)
	var whole := _box(car._drv_body).merge(head).merge(_box(car._drv_arms[0])).merge(_box(car._drv_arms[1])).merge(_box(car._drv_wheel))
	# inside the cabin: across and along the car within the Cabin mesh (the seats and dash), the legs no deeper than the floor
	check(whole.position.x >= cabin.position.x - 0.03 and whole.end.x <= cabin.end.x + 0.03,
		"%s: the driver (x %.2f .. %.2f) is outside the cabin (%.2f .. %.2f)" % [key, whole.position.x, whole.end.x, cabin.position.x, cabin.end.x])
	check(whole.position.z >= cabin.position.z - 0.03 and whole.end.z <= cabin.end.z + 0.03,
		"%s: the driver (z %.2f .. %.2f) is outside the cabin (%.2f .. %.2f)" % [key, whole.position.z, whole.end.z, cabin.position.z, cabin.end.z])
	check(whole.position.y >= cabin.position.y - 0.08, "%s: the driver's feet (y %.2f) are through the floor (%.2f)" % [key, whole.position.y, cabin.position.y])
	# the figure sits left of the middle (left-hand drive) and the head is below the roof
	check(head.get_center().x < -0.25, "%s: the head is not over the left seat (x %.2f)" % [key, head.get_center().x])
	var corners := [Vector3(head.position.x, head.end.y, head.position.z), Vector3(head.end.x, head.end.y, head.position.z),
		Vector3(head.position.x, head.end.y, head.end.z), Vector3(head.end.x, head.end.y, head.end.z), Vector3(head.get_center().x, head.end.y, head.get_center().z)]
	var roof := INF
	for c in corners:
		roof = minf(roof, _ray(tri, c - Vector3(0.0, 0.05, 0.0), Vector3.UP) - 0.05)
	check(roof >= CLEARANCE, "%s: the helmet is %.0f mm from the roof (needs %.0f)" % [key, roof * 1000.0, CLEARANCE * 1000.0])
	# in front: the windscreen and the dash (a ray from the helmet's centre at three heights; the front of the helmet to the glass)
	var centre := head.get_center()
	var ahead := INF
	for dy in [-0.06, 0.0, 0.07]:
		ahead = minf(ahead, _ray(tri, centre + Vector3(0.0, dy, 0.0), Vector3(0.0, 0.0, -1.0)) - (centre.z - head.position.z))
	check(ahead >= CLEARANCE, "%s: the helmet is %.0f mm from the windscreen" % [key, ahead * 1000.0])
	# beside: the door and the side glass, at the helmet and at the shoulders
	var beside := _ray(tri, centre, Vector3.LEFT) - (centre.x - head.position.x)
	check(beside >= CLEARANCE, "%s: the helmet is %.0f mm from the left window" % [key, beside * 1000.0])
	var body := _box(car._drv_body)
	var bc := body.get_center()
	var shoulder_gap := _ray(tri, Vector3(bc.x, body.position.y + 0.55 * body.size.y, bc.z), Vector3.LEFT) - (bc.x - body.position.x)
	check(shoulder_gap >= CLEARANCE, "%s: the shoulders are %.0f mm from the door" % [key, shoulder_gap * 1000.0])
	# behind: the rear window and the seat back leave the head room too
	var behind := _ray(tri, centre, Vector3.BACK) - (head.end.z - centre.z)
	check(behind >= 0.0, "%s: the helmet is through the rear glass (%.0f mm)" % [key, behind * 1000.0])
	# the baked-in wheel is cut out of the Cabin: some triangles gone, not the seats
	var raw := _raw_cabin(key)
	var shared := VISUAL._shared_resources(key)
	var was := _tris(raw)
	var now := _tris(shared.cabin)
	print("    %-8s head top %.3f, roof clear %.0f mm, windscreen %.0f mm, left window %.0f mm, shoulders %.0f mm, rear glass %.0f mm, wheel cut %d of %d tris" % [
		key, head.end.y, roof * 1000.0, ahead * 1000.0, beside * 1000.0, shoulder_gap * 1000.0, behind * 1000.0, was - now, was])
	check(was - now >= 150 and was - now <= 900, "%s: %d Cabin triangles cut for the wheel (expected a few hundred: rim, spokes, boss)" % [key, was - now])
	check(now > was * 0.9, "%s: the wheel cut took %d of %d triangles, the seats went with it" % [key, was - now, was])
	car.free()

func _raw_cabin(key: String) -> Mesh:
	var scene := ResourceLoader.load(CarCatalog.visual(key).model, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var root := scene.instantiate()
	var m: Mesh = null
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).split(".")[0] == "Cabin":
			m = (mi as MeshInstance3D).mesh
	root.free()
	return m

func _tris(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		n += (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if not (a[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty() else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n

func _drive(car: Node3D, rc: RaceCar, frames: int, speed_step := 0.0) -> void:
	for i in frames:
		rc.speed += speed_step
		car.sync(rc, 1.0 / 60.0, 0.0, 0.0, false)

## A glove's place in the car's frame: the arm's transform applied to the glove's rest point.
func _glove(car: Node3D, i: int) -> Vector3:
	var side := -1.0 if i == 0 else 1.0
	var rest := Vector3(side * VISUAL.DRIVER_HAND_REST.x, VISUAL.DRIVER_HAND_REST.y, VISUAL.DRIVER_HAND_REST.z)
	return car._drv_seat + car._drv_scale * (car._drv_arms[i].transform * rest)

func _rim(car: Node3D, i: int) -> Vector3:
	var side := -1.0 if i == 0 else 1.0
	return car._drv_hub + car._drv_wheel.transform.basis.orthonormalized() * Vector3(side * car._drv_wheel_r, 0.0, 0.0)

func _wheel_and_hands(parent: Node3D) -> void:
	for key in ["stock", "golf4", "zafira"]:
		var car: Node3D = VISUAL.new()
		car.car_key = key
		parent.add_child(car)
		var rc := RaceCar.new()
		rc.control = "free"
		rc.speed = 20.0
		_drive(car, rc, 20)
		var basis0: Basis = car._drv_wheel.transform.basis.orthonormalized()
		var right0 := _glove(car, 1)
		for i in 2:
			check(_glove(car, i).distance_to(_rim(car, i)) < 0.01, "%s: at rest the glove %d is %.0f mm off the rim" % [key, i, _glove(car, i).distance_to(_rim(car, i)) * 1000.0])
		rc.steer = 0.3 # to the right
		_drive(car, rc, 40)
		var basis1: Basis = car._drv_wheel.transform.basis.orthonormalized()
		var turned := acos(clampf(basis0.x.dot(basis1.x), -1.0, 1.0))
		check(absf(turned - 0.3 * VISUAL.DRIVER_STEER_RATIO) < 0.06, "%s: a steer of 0.3 turned the wheel %.2f rad, not %.2f" % [key, turned, 0.3 * VISUAL.DRIVER_STEER_RATIO])
		check(basis1.x.y < basis0.x.y - 0.5 and basis1.get_euler().z != basis0.get_euler().z, "%s: the wheel did not turn clockwise for a right turn" % key)
		for i in 2:
			var off := _glove(car, i).distance_to(_rim(car, i))
			check(off < 0.01, "%s: steering right, glove %d is %.0f mm off the rim" % [key, i, off * 1000.0])
		check(_glove(car, 1).y < right0.y - 0.1, "%s: the right hand did not come down with a right turn (%.2f -> %.2f)" % [key, right0.y, _glove(car, 1).y])
		rc.steer = -0.3
		_drive(car, rc, 60)
		check(_glove(car, 1).y > right0.y + 0.1 and car._drv_turn > 1.0, "%s: the wheel did not turn the other way (%.2f)" % [key, car._drv_turn])
		car.free()

func _head_motion(parent: Node3D) -> void:
	var car: Node3D = VISUAL.new()
	parent.add_child(car)
	var rc := RaceCar.new()
	rc.control = "free"
	rc.speed = 20.0
	_drive(car, rc, 30)
	check(absf(car._drv_head.rotation.y) < 0.02 and absf(car._drv_head.rotation.x) < 0.02, "the head is not looking straight on a straight road")
	rc.steer = 0.3
	_drive(car, rc, 90)
	check(car._drv_head.rotation.y < -0.1, "the head does not turn into a right-hand corner (yaw %.2f)" % car._drv_head.rotation.y)
	check(car._drv_head.rotation.z < -0.02, "the head does not lean into a right-hand corner (roll %.2f)" % car._drv_head.rotation.z)
	rc.steer = 0.0
	rc.speed = 30.0
	_drive(car, rc, 60)
	_drive(car, rc, 40, -0.3) # braking at 18 m/s^2
	check(car._drv_head.rotation.x < -0.05, "the head does not nod forward under braking (pitch %.2f)" % car._drv_head.rotation.x)
	rc.speed = 10.0
	_drive(car, rc, 60)
	_drive(car, rc, 40, 0.15)
	check(car._drv_head.rotation.x > 0.03, "the head does not lean back under acceleration (pitch %.2f)" % car._drv_head.rotation.x)
	check(absf(car._drv_head.rotation.x) < 0.2 and absf(car._drv_head.rotation.y) < 0.6 and absf(car._drv_head.rotation.z) < 0.2, "the head's angles are not small")
	car.free()

func _tint(parent: Node3D) -> void:
	var red: Node3D = VISUAL.new()
	parent.add_child(red)
	red.set_paint(Color("#c0122c"))
	var suit: Color = red._drv_suit_mat.albedo_color
	check(suit.r > 0.4 and suit.r > suit.g * 2.5 and suit.r > suit.b * 2.5, "a red car's driver is not in a red suit (%s)" % suit)
	check(red._drv_helmet_mat.albedo_color.get_luminance() > 0.8, "a red car's helmet is not white (%s)" % red._drv_helmet_mat.albedo_color)
	red.set_paint(Color("#2fa14c"))
	check(red._drv_suit_mat.albedo_color.g > red._drv_suit_mat.albedo_color.r * 1.5, "the suit did not follow a repaint to green")
	var white: Node3D = VISUAL.new()
	parent.add_child(white)
	white.set_paint(Color("#f1f1ec"))
	check(white._drv_suit_mat.albedo_color.get_luminance() < 0.25, "a white car's driver is in white too, lost against the paint")
	var hyper: Node3D = VISUAL.new()
	hyper.car_key = "hypercar"
	parent.add_child(hyper)
	hyper.set_paint(Hypercar.PAINT)
	var hs: Color = hyper._drv_suit_mat.albedo_color
	check(hs.r > 0.5 and hs.g > 0.4 and hs.b < 0.1, "the AF Corse Hypercar's driver is not in the team yellow (%s)" % hs)
	var hh: Color = hyper._drv_helmet_mat.albedo_color
	check(hh.r > 0.7 and hh.g > 0.5 and hh.b < 0.2, "the AF Corse driver's helmet is not in the team yellow (%s)" % hh)
	for c in [red, white, hyper]:
		check(c._drv_suit_mat != c._drv_helmet_mat, "suit and helmet share a material")
	check(red._drv_suit_mat != white._drv_suit_mat, "two cars share a suit material: the tint would leak")
	red.free()
	white.free()
	hyper.free()

func _range_and_cameras(parent: Node3D) -> void:
	var car: Node3D = VISUAL.new()
	parent.add_child(car)
	var all: Array = [car._drv_body, car._drv_head, car._drv_arms[0], car._drv_arms[1], car._drv_wheel]
	for mi in all:
		var m := mi as MeshInstance3D
		check(m.visibility_range_end == VISUAL.DRIVER_RANGE and m.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"%s: range %.0f m (expected %.0f), shadow %d" % [m.name, m.visibility_range_end, VISUAL.DRIVER_RANGE, m.cast_shadow])
	check(car._driver.visible and car._drv_wheel.visible, "the driver is hidden on a plain car")
	car.set_driver_visible(false)
	check(not car._driver.visible and not car._drv_wheel.visible, "set_driver_visible(false) leaves the driver or his wheel showing")
	car.set_driver_visible(true)
	check(car._driver.visible and car._drv_wheel.visible, "set_driver_visible(true) did not bring the driver back")
	# a ghost has none; the player's driver goes in the cameras that ride inside the car
	car._ghost = true
	car._refresh_driver()
	check(not car._driver.visible, "a ghost car has a driver")
	car._ghost = false
	car._refresh_driver()
	var rc := RaceCar.new()
	rc.control = "free"
	car.is_player = true
	var world := FakeWorld.new()
	car._world = world
	car._fx_checked = true
	for mode in [0, 1, 2, 6, 7]:
		world.camera_mode = mode
		car.sync(rc, 1.0 / 60.0, 0.0, 0.0, false)
		var want: bool = not (mode in [2, 6, 7])
		check(car._driver.visible == want, "camera mode %d: the player's driver is %s" % [mode, "showing" if car._driver.visible else "hidden"])
	car._world = null
	world.free()
	car.free()

func _damage(parent: Node3D) -> void:
	for key in ["stock", "golf4", "zafira"]:
		var car: Node3D = VISUAL.new()
		car.car_key = key
		parent.add_child(car)
		var rc := RaceCar.new()
		rc.control = "free"
		car.sync(rc, 1.0 / 60.0, 0.0, 0.0, false)
		var before: Transform3D = car._drv_body.global_transform
		var half: Vector2 = car._half
		rc.note_hit(0.0, -half.x, 16.0) # a big hit on the left, the driver's side: the door goes and the window shatters
		rc.dents["left"] = 1.0
		for i in 12:
			car.sync(rc, 1.0 / 60.0, 0.0, 0.0, false)
		check(car._panel_state("DoorL") == 2, "%s: the left door stayed on a 58 km/h hit (state %d)" % [key, car._panel_state("DoorL")])
		check(car._glass_gone.has("WindowL"), "%s: the driver's window did not shatter" % key)
		check(car._driver.visible and car._drv_wheel.visible and car._drv_body.is_visible_in_tree() and car._drv_head.is_visible_in_tree(),
			"%s: the driver went with the door" % key)
		check(car._drv_body.global_transform.origin.distance_to(before.origin) < 0.15, "%s: the driver moved when the door was torn off" % key)
		car.free()

## What a car costs: triangles and surfaces (draw calls) of the driver, over the field of twelve.
func _budget(parent: Node3D) -> void:
	var car: Node3D = VISUAL.new()
	parent.add_child(car)
	var tris := 0
	var surfaces := 0
	for mi in [car._drv_body, car._drv_head, car._drv_arms[0], car._drv_arms[1], car._drv_wheel]:
		var m: Mesh = (mi as MeshInstance3D).mesh
		tris += _tris(m)
		surfaces += m.get_surface_count()
	print("    driver: %d triangles, %d surfaces (draw calls) per car; 12 cars: %d triangles, %d draw calls" % [tris, surfaces, tris * 12, surfaces * 12])
	check(tris >= 700 and tris <= 1500, "the driver is %d triangles (budget 1.0-1.5k)" % tris)
	check(surfaces <= 8, "the driver costs %d surfaces per car" % surfaces)
	car.free()
