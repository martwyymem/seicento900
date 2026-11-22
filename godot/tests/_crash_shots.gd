## Windowed probe: a car driven into a wall at rising speeds, through the open world's own damage path (FreeCar._dent:
## RaceCar.dents, hit_log, wheel loss and bends), with screenshots of what the visual makes of it: the crumple at the
## contact point, scrapes, lamps, glass, the bonnet, doors, bumpers, boot and a torn-off wheel.
##   godot --path godot --audio-driver Dummy --always-on-top -s tests/_crash_shots.gd -- [out dir]
## CAR=golf4 picks the car for the frontal series (default: every scenario's own car).
extends SceneTree

const VISUAL := preload("res://scripts/ui/race_car_visual.gd")
const WALL_X := 0.0 ## the wall's face (the car drives along -Z into a wall across it at z = WALL_Z)
const WALL_Z := -6.0

## [name, car, km/h, how: front / corner / side / rear, night]
const SCENARIOS := [
	["front_20", "stock", 20.0, "corner", false],
	["front_35", "stock", 35.0, "front", false],
	["front_55", "stock", 55.0, "corner", false],
	["front_80", "stock", 80.0, "corner", false],
	["golf_front_50", "golf4", 50.0, "front", false],
	["golf_side_35", "golf4", 35.0, "side", false],
	["golf_side_60", "golf4", 60.0, "side", false],
	["logan_rear_30", "logan", 30.0, "rear", false],
	["v50_corner_75", "v50", 75.0, "corner", false],
	["i20_night_22", "i20", 22.0, "corner", true],
]

var out := "/tmp/crash_shots"
var env: Environment
var sun: DirectionalLight3D
var cam: Camera3D

func _wait(n: int) -> void:
	for k in n:
		paused = false
		await process_frame

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else out
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1200, 800)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#8a9099")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	we.environment = env
	root.add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#55585c")
	ground.material_override = gm
	root.add_child(ground)
	cam = Camera3D.new()
	cam.fov = 50.0
	root.add_child(cam)
	cam.current = true
	_run.call_deferred()

func _wall(at: Vector3, size: Vector3) -> MeshInstance3D:
	var w := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	w.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#b9b4a8")
	w.material_override = m
	w.position = at
	root.add_child(w)
	return w

func _run() -> void:
	var log := []
	for sc in SCENARIOS:
		if OS.get_environment("ONLY") != "" and not String(sc[0]) in OS.get_environment("ONLY").split(","): # ONLY=front_55,...
			continue
		var key: String = OS.get_environment("CAR") if CarCatalog.is_key(OS.get_environment("CAR")) and sc[3] in ["front", "corner"] else sc[1]
		log.append(await _crash(sc[0], key, sc[2], sc[3], sc[4]))
	var f := FileAccess.open(out + "/crash_log.txt", FileAccess.WRITE)
	for l in log:
		f.store_line(l)
		print(l)
	quit()

## One crash: the car rolls at kmh into the wall (front, a front corner, its side or its tail first), the impact goes
## through FreeCar._dent as in the open world, and the result is shot from two angles a moment later.
func _crash(name: String, key: String, kmh: float, how: String, night: bool) -> String:
	env.background_color = Color("#0c0f16") if night else Color("#8a9099")
	env.ambient_light_color = Color(0.08, 0.09, 0.12) if night else Color(0.7, 0.7, 0.75)
	sun.light_energy = 0.03 if night else 1.0
	var drive := FreeCar.new(null)
	var rc: RaceCar = drive.car
	rc.heading = 0.0 # map frame: ahead +x, right +y
	var car: Node3D = VISUAL.new()
	car.car_key = key
	car.car_number = 7
	root.add_child(car)
	car.set_paint(Color("#c4302b") if key == "stock" else Color("#3f78c8"))
	if OS.get_environment("NOSTRIPES") != "":
		car.set_stripes(false)
	var v := kmh / 3.6
	var half_l: float = car._half.y
	var half_w: float = car._half.x
	# the way it moves (visual frame) and the wall it meets
	var dir := Vector3(0, 0, -1)
	var wall: MeshInstance3D
	match how:
		"side":
			dir = Vector3(1, 0, 0)
			wall = _wall(Vector3(half_w + 0.15, 1.0, 0.0), Vector3(0.3, 2.0, 8.0))
		"rear":
			dir = Vector3(0, 0, 1)
			wall = _wall(Vector3(0.0, 1.0, half_l + 0.15), Vector3(8.0, 2.0, 0.3))
		_:
			wall = _wall(Vector3(0.0, 1.0, -half_l - 0.15), Vector3(8.0, 2.0, 0.3))
	car.position = -dir * v * 0.6 # 0.6 s from the wall
	rc.speed = v if how != "rear" else -v
	var t := 0.0
	while t < 0.6:
		var dt := 1.0 / 60.0
		car.position += dir * v * dt
		t += dt
		car.sync(rc, dt, 0.0, 1.0 if night else 0.0, false)
		await _wait(1)
	car.position = Vector3.ZERO
	rc.speed = 0.0
	# the contact point (map frame: x ahead, y right of the centre)
	var r := Vector2(half_l, 0.0)
	match how:
		"corner":
			r = Vector2(half_l, -half_w * 0.8)
		"side":
			r = Vector2(half_l * 0.15, half_w)
		"rear":
			r = Vector2(-half_l, half_w * 0.3)
	drive._dent(r, v)
	for k in 70:
		car.sync(rc, 1.0 / 60.0, 0.0, 1.0 if night else 0.0, false)
		await _wait(1)
	var views := {
		"front": [Vector3(-2.0, 1.3, -half_l - 2.0), Vector3(0, 0.55, -half_l * 0.45)],
		"side": [Vector3(3.6, 1.3, -0.6), Vector3(0, 0.6, 0.0)],
		"rear": [Vector3(-2.0, 1.4, half_l + 2.2), Vector3(0, 0.6, half_l * 0.45)],
	}
	var pick := ["front", "side"] if how != "rear" else ["rear", "side"]
	if how == "side":
		pick = ["side", "front"]
		views["side"] = [Vector3(3.4, 1.3, -1.6), Vector3(0, 0.6, 0.0)] # the struck right side
		views["front"] = [Vector3(2.2, 1.8, half_l + 2.4), Vector3(0.3, 0.6, 0.0)]
	wall.visible = false
	for p in pick:
		cam.look_at_from_position(views[p][0], views[p][1])
		await _wait(4)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s_%s.png" % [out, name, p])
	if name == "front_80": # then repaired (dents straightened, the wheel back on): everything refitted
		var before: String = "panels %s" % [car._panels.keys().map(func(k): return car._panels[k].state)]
		rc.straighten()
		for k in 30:
			car.sync(rc, 1.0 / 60.0, 0.0, 0.0, false)
			await _wait(1)
		cam.look_at_from_position(views["front"][0], views["front"][1])
		await _wait(4)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s_repaired.png" % [out, name])
		print("repaired: %s -> panels %s, glass gone %s, lamps %s, scrapes %d, wheel shown %s" % [before,
			car._panels.keys().map(func(k): return car._panels[k].state), car._glass_gone.keys(), car._lamps_broken,
			car._scrapes.size(), car.steer_pivots[0].visible])
	var states := []
	for k in car._panels:
		states.append("%s:%d" % [k, car._panels[k].state])
	var line := "%s %s %.0f km/h: dents %s, panels %s, glass gone %s, crack %.2f, lamps %s, crush %s, wheel off %d, bends %s, scrapes %d" % [
		name, key, kmh, rc.dents, " ".join(states), car._glass_gone.keys(), car._crack, car._lamps_broken,
		car._crush.keys(), rc.wheel_off, rc.wheel_bend, car._scrapes.size()]
	car.queue_free()
	wall.queue_free()
	await _wait(2)
	return line
