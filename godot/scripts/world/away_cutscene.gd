## The trip to a campaign stage abroad (CampaignObjective.AWAY), played at the Away Races gate before the stage loads:
## out of black onto a small set of its own (a station platform with an EN57 and a car-carrier wagon, or an apron with
## a cargo plane), the player's car drives up the ramp onto the wagon or into the hold, the train pulls away or the plane
## rolls and lifts off, and it fades back to black. About six seconds; Enter / Esc / pad A or B skips it (a short fade).
## The set stands SET_ORIGIN away from the town, beyond the camera's far plane from every part of the map, so nothing of
## the town shows or gets in the way, and it is built from boxes (the EN57 reuses the town's TrainCab / TrainCar meshes
## when they are there). OpenWorld drives it: step(), then car_xform / cam_xform / fade on its car, camera and fade rect,
## and `done` hands over to the stage.
class_name AwayCutscene
extends Node3D

const SET_ORIGIN := Vector3(52000.0, 0.0, 0.0) ## m: > camera.far (42 km) from all of the map (a few km across)
const LENGTH := 6.4 ## s, start to black
const FADE := 0.6 ## s of fade in and of fade out
const SKIP_FADE := 0.35 ## s of fade out after a skip
const DRIVE_FROM := 0.35 ## s: the car sets off
const DRIVE_TO := 3.3 ## s: the car is aboard; the vehicle leaves from here
const DECK := 1.15 ## m: the wagon's deck / the hold's floor over the ground
const CAR_FORWARD := Basis(Vector3.UP, -PI / 2.0) ## a car visual facing +X (its nose is -Z, see OpenWorld._sync_car)

var by := "train" ## "train" or "plane"
var t := 0.0
var done := false
var skipped := false
var fade := 1.0 ## 0 clear .. 1 black
var car_xform := Transform3D(CAR_FORWARD, SET_ORIGIN)
var cam_xform := Transform3D()
var vehicle_xform := Transform3D() ## the train / plane's place relative to SET_ORIGIN
var _end := LENGTH
var _fade_from := 0.0 ## the fade when a skip started
var _skip_t := -1.0
var _path: Array[Vector3] = [] ## the car's drive in set coordinates, ground to the deck
var _vehicle: Node3D

## by: "train" or "plane"; models: TownBuilder.models entries {"TrainCab": [mesh, local], "TrainCar": [...]}; night 0..1
## turns the floodlights up.
func setup(mode: String, models := {}, night := 0.0) -> void:
	by = "plane" if mode == "plane" else "train"
	position = SET_ORIGIN
	if by == "plane":
		_path = [Vector3(-48.0, 0.0, 0.0), Vector3(-19.0, 0.0, 0.0), Vector3(-16.0, DECK, 0.0), Vector3(-6.0, DECK, 0.0)]
	else:
		_path = [Vector3(-46.0, 0.0, 0.0), Vector3(-19.0, 0.0, 0.0), Vector3(-13.0, DECK, 0.0), Vector3(-3.0, DECK, 0.0)]
	_build_set(models, night)
	step(0.0)

## Skips to the end: a short fade to black, then done.
func skip() -> void:
	if done or _skip_t >= 0.0:
		return
	skipped = true
	_skip_t = t
	_fade_from = fade
	_end = minf(_end, t + SKIP_FADE)

func step(dt: float) -> void:
	if done:
		return
	t += dt
	if t >= _end:
		t = _end
		done = true
	# the fade: in from black, out at the end (or from wherever a skip found it)
	if _skip_t >= 0.0:
		fade = lerpf(_fade_from, 1.0, clampf((t - _skip_t) / SKIP_FADE, 0.0, 1.0))
	else:
		fade = maxf(1.0 - t / FADE, clampf((t - (LENGTH - FADE)) / FADE, 0.0, 1.0))
	if done:
		fade = 1.0
	# the vehicle: still until the car is aboard, then away along +X (the plane lifts off past 30 m)
	var go := maxf(t - DRIVE_TO, 0.0)
	var along := (1.6 if by == "train" else 4.2) * go * go
	var lift := 0.0
	var pitch := 0.0
	if by == "plane" and along > 30.0:
		lift = (along - 30.0) * 0.16
		pitch = deg_to_rad(minf((along - 30.0) * 0.35, 9.0))
	vehicle_xform = Transform3D(Basis(Vector3.BACK, pitch), Vector3(along, lift, 0.0))
	if is_instance_valid(_vehicle):
		_vehicle.transform = vehicle_xform
	# the car: along its path (eased), on board it rides with the vehicle
	var k := smoothstep(DRIVE_FROM, DRIVE_TO, t)
	var at := _along_path(k)
	var p: Vector3 = at[0]
	var car_pitch: float = at[1]
	var local := Transform3D(CAR_FORWARD * Basis(Vector3.RIGHT, car_pitch), p)
	car_xform = Transform3D(Basis(), SET_ORIGIN) * (vehicle_xform * local if k >= 1.0 else local)
	# the camera: a side view that turns to follow; it pulls back as the vehicle goes
	var eye := Vector3(-8.0, 3.2, 17.0) if by == "train" else Vector3(-14.0, 4.5, 30.0)
	var look := car_xform.origin - SET_ORIGIN + Vector3(0.0, 0.8, 0.0)
	if k >= 1.0:
		look = vehicle_xform * Vector3(2.0, 1.6, 0.0)
		eye += Vector3(along * 0.35, lift * 0.5, along * 0.1)
	cam_xform = Transform3D(Basis(), SET_ORIGIN) * Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)

## [position, pitch] k (0..1) of the way along the car's path by distance: flat, up the ramp, along the deck.
func _along_path(k: float) -> Array:
	var total := 0.0
	for i in range(1, _path.size()):
		total += _path[i].distance_to(_path[i - 1])
	var want := clampf(k, 0.0, 1.0) * total
	for i in range(1, _path.size()):
		var a := _path[i - 1]
		var b := _path[i]
		var l := a.distance_to(b)
		if want <= l or i == _path.size() - 1:
			var u := clampf(want / maxf(l, 1e-4), 0.0, 1.0)
			return [a.lerp(b, u), atan2(b.y - a.y, Vector2(b.x - a.x, b.z - a.z).length())]
		want -= l
	return [_path[_path.size() - 1], 0.0]

# ------------------------------------------------------------------ the set

func _mat(c: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material, rot := Basis()) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = Transform3D(rot, at)
	parent.add_child(mi)
	return mi

## A ramp from the ground (x0) up to h at x1, w wide.
func _ramp(parent: Node3D, x0: float, x1: float, h: float, w: float, mat: Material) -> void:
	var l := Vector2(x1 - x0, h).length()
	var ang := atan2(h, x1 - x0)
	_box(parent, Vector3(l, 0.12, w), Vector3((x0 + x1) * 0.5, h * 0.5, 0.0), mat, Basis(Vector3.BACK, ang))

func _build_set(models: Dictionary, night: float) -> void:
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3000.0, 3000.0)
	ground.mesh = pm
	ground.material_override = _mat(Color(0.30, 0.36, 0.24))
	ground.position.y = -0.03
	add_child(ground)
	var tarmac := _mat(Color(0.22, 0.22, 0.24))
	var steel := _mat(Color(0.35, 0.37, 0.40), 0.5, 0.6)
	var paint := _mat(Color(0.86, 0.88, 0.90), 0.5)
	var dark := _mat(Color(0.08, 0.09, 0.10), 0.6)
	_vehicle = Node3D.new()
	_vehicle.name = "Vehicle"
	add_child(_vehicle)
	if by == "train":
		_box(self, Vector3(600.0, 0.02, 4.2), Vector3(0.0, 0.0, 0.0), _mat(Color(0.36, 0.33, 0.30))) # track bed
		for z in [-0.72, 0.72]:
			_box(self, Vector3(600.0, 0.16, 0.08), Vector3(0.0, 0.08, z), steel)
		_box(self, Vector3(80.0, 0.9, 6.0), Vector3(-30.0, 0.45, 5.6), _mat(Color(0.55, 0.54, 0.52))) # the platform
		_box(self, Vector3(70.0, 0.02, 7.0), Vector3(-45.0, 0.0, 0.0), tarmac) # the loading road up to the ramp
		_ramp(self, -19.0, -13.0, DECK, 3.0, steel)
		# the car-carrier wagon: a flat deck with low sides and bogies, the EN57 coupled ahead of it
		_box(_vehicle, Vector3(20.0, 0.25, 3.0), Vector3(-2.5, DECK - 0.12, 0.0), steel)
		for z in [-1.45, 1.45]:
			_box(_vehicle, Vector3(20.0, 0.45, 0.1), Vector3(-2.5, DECK + 0.2, z), dark)
		for x in [-10.0, 5.0]:
			_box(_vehicle, Vector3(2.6, 0.8, 2.4), Vector3(x, 0.45, 0.0), dark)
		for i in 2:
			var name := "TrainCab" if i == 1 else "TrainCar"
			var x := 7.5 + 21.2 * (i + 0.5)
			var place := Transform3D(Basis.looking_at(Vector3.RIGHT if i == 1 else Vector3.LEFT, Vector3.UP), Vector3(x, 0.27, 0.0))
			var mi := MeshInstance3D.new()
			mi.name = "EN57_%d" % i
			if models.has(name):
				mi.mesh = models[name][0]
				mi.transform = place * (models[name][1] as Transform3D)
			else:
				var bm := BoxMesh.new()
				bm.size = Vector3(2.9, 2.7, 20.6)
				mi.mesh = bm
				mi.material_override = _mat(Color(0.18, 0.32, 0.62))
				mi.transform = place * Transform3D(Basis(), Vector3(0.0, 2.2, 0.0))
			_vehicle.add_child(mi)
	else:
		_box(self, Vector3(900.0, 0.02, 40.0), Vector3(300.0, 0.0, 0.0), tarmac) # the apron and runway
		for i in 30:
			_box(self, Vector3(6.0, 0.03, 0.4), Vector3(40.0 + i * 20.0, 0.01, 0.0), paint) # centre line
		# the cargo plane: an open-backed hold (floor, walls, roof), a nose, wings, a tail and the lowered ramp
		var hull := _mat(Color(0.78, 0.80, 0.82), 0.45, 0.2)
		_box(_vehicle, Vector3(32.0, 0.2, 4.6), Vector3(0.0, DECK - 0.1, 0.0), steel)
		for z in [-2.4, 2.4]:
			_box(_vehicle, Vector3(32.0, 4.2, 0.2), Vector3(0.0, DECK + 2.0, z), hull)
		_box(_vehicle, Vector3(32.0, 0.25, 5.0), Vector3(0.0, DECK + 4.1, 0.0), hull)
		_box(_vehicle, Vector3(5.0, 3.6, 4.6), Vector3(18.0, DECK + 1.9, 0.0), hull) # the nose
		_box(_vehicle, Vector3(1.2, 1.0, 3.2), Vector3(20.7, DECK + 3.0, 0.0), dark) # cockpit glass
		_box(_vehicle, Vector3(5.0, 0.35, 40.0), Vector3(2.0, DECK + 4.0, 0.0), hull) # the wings
		for z in [-9.0, 9.0]:
			_box(_vehicle, Vector3(4.2, 1.6, 1.6), Vector3(4.0, DECK + 3.0, z), dark) # engines
		_box(_vehicle, Vector3(4.0, 5.5, 0.3), Vector3(-15.0, DECK + 6.6, 0.0), hull) # the fin
		_box(_vehicle, Vector3(3.0, 0.25, 12.0), Vector3(-15.0, DECK + 4.2, 0.0), hull) # the tailplane
		for x in [-6.0, 12.0]:
			_box(_vehicle, Vector3(1.2, DECK, 1.0), Vector3(x, DECK * 0.5, 0.0), dark) # undercarriage
		_ramp(_vehicle, -19.0, -16.0, DECK, 4.0, steel)
	# floodlights: a station's or an apron's, brighter at night
	for x in [-30.0, 10.0]:
		var l := OmniLight3D.new()
		l.position = Vector3(x, 9.0, 12.0)
		l.omni_range = 45.0
		l.light_energy = lerpf(0.4, 3.0, clampf(night, 0.0, 1.0))
		l.light_color = Color(1.0, 0.92, 0.78)
		add_child(l)
