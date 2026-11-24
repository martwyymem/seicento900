## 3D Fiat Seicento 900 Cup race car.
## The model (models/seicento.glb) is built in Blender by tools/blender/build_seicento.py to the real car's
## dimensions. Its meshes are shared by every car; paint, stripes and tail lights are per-car materials,
## so a car costs a few dozen draw calls and a single shadow-casting shell. Wheels steer and spin from
## the physics model, the sprung body rolls and pitches, and lights follow braking and nightfall.
## The paint is a glossy clear coat (metallic with flake for silver/grey liveries); cars racing near the camera
## throw tyre smoke, wet-road spray and dust/grass/snow kick-up (tuned after WRC 3DS's kickup particles), and
## distant ones drop their cabin.
extends Node3D

const MODEL_PATH := "res://models/seicento.glb"
const WHEEL_RADIUS := 0.2665 ## 145/70 R13
const WHEELBASE := 2.2
const HALF_TRACK := 0.6315
const CABIN_RANGE := 45.0 ## m: farther cars skip the cabin (dash, seat, cage), unseen through the glass
const FX_REACH := [0.0, 35.0, 60.0, 90.0] ## m from the camera within which bots show effects, per quality preset
const FX_AXLE := Vector3(0.0, 0.03, 1.12) ## effects come off the rear contact patches (+Z is backwards)
const DRIVER_MODEL := "res://models/driver.glb" ## built by tools/blender/build_driver.py
const DRIVER_RANGE := 80.0 ## m: farther cars show no driver (a few pixels there) and skip his animation
const DRIVER_STEER_RATIO := 4.0 ## rad of steering wheel per rad of road-wheel steer
const DRIVER_WHEEL_MAX := 2.2 ## rad: the most the wheel turns on screen (126 degrees)
const DRIVER_RIM_R := 0.19 ## m: the rim radius driver.glb's wheel is built with (WHEEL_R in build_driver.py)
## Where the glove's centre sits from the shoulder in the arm mesh (right arm; the left mirrors x): the line the visual turns at the hand
const DRIVER_HAND_REST := Vector3(0.03, -0.185, -0.478)
const DRIVER_HIDE_CAMERAS := [2, 6, 7] ## RaceWorld camera modes that ride inside or just ahead of the car: the player's driver goes
const WHEEL_SPOTS := [Vector3(-HALF_TRACK, WHEEL_RADIUS, -1.1), Vector3(HALF_TRACK, WHEEL_RADIUS, -1.1),
	Vector3(-HALF_TRACK, WHEEL_RADIUS, 1.1), Vector3(HALF_TRACK, WHEEL_RADIUS, 1.1)] ## FL, FR, RL, RR like the physics

static var _shared := {} ## the stock Seicento's shared resources (and the model-independent ones every car reuses)
static var _shared_cars := {} ## CarCatalog key -> that car's shared resources, for every car but the stock one
var car_key := "stock" ## CarCatalog key: set before the visual enters the tree, or change it later with set_car()
var _fit: Dictionary = CarCatalog.STOCK_VISUAL ## CarCatalog.visual(car_key)
var _wheel_radius := WHEEL_RADIUS
var _wheelbase := WHEELBASE
var _wheel_spots: Array = WHEEL_SPOTS
static var _env_materials: Array[ShaderMaterial] = [] ## every car_coat.gdshader material, see _env_material()
static var _driver_cache := {} ## driver.glb's meshes by object name: {"mesh", "pos"} (shared by every car)

var paint_material: StandardMaterial3D
var stripe_material: StandardMaterial3D
var tail_material: StandardMaterial3D
var bulb_material: StandardMaterial3D
const BRAKE_LIGHT_ENERGY := 2.0
var _brake_light: SpotLight3D
var _near_beam: SpotLight3D ## wide dipped apron filling the tarmac right ahead of the bumper (top edge below horizontal)
var _beam_pool: Decal ## horizontal tarmac low-beam pool (normal_fade keeps it off walls)
var body_pivot: Node3D
var number_label: Label3D
var stripes_node: MeshInstance3D
var martini_node: MeshInstance3D
var livery := 0 ## 0 gloss, 1 metallic flake, 2 Martini Racing, 3 Abarth, 4 Marlboro
## The sponsor livery meshes by livery number (martini_node is the 2)
var livery_nodes := {}
## Liveries painted over a white car, without the twin stripes or the racing number decals
const PLATE_ROWS := 8 ## rows in textures/car/plate_pl.png
const WHITE_LIVERIES := [2, 4]
const LIVERY_MESHES := {2: "Martini", 3: "Abarth", 4: "Marlboro"}
var steer_pivots: Array[Node3D] = []
var wheels: Array[Node3D] = []
var _door_decal_l: MeshInstance3D
var _door_decal_r: MeshInstance3D
var _sunstrip_decal: MeshInstance3D
var _hood_decal: MeshInstance3D
var _sill_decal_l: MeshInstance3D
var _sill_decal_r: MeshInstance3D
var car_number := 1:
	set(value):
		car_number = value
		if is_instance_valid(_details_node):
			_details_node.set_instance_shader_parameter("plate_id", float(posmod(car_number * 5 + 3, PLATE_ROWS)))
		for name in _panels: # a plate on a bumper or the tailgate
			for p in _panels[name].parts:
				if String(p[0].name).ends_with("Details"):
					(p[0] as MeshInstance3D).set_instance_shader_parameter("plate_id", float(posmod(car_number * 5 + 3, PLATE_ROWS)))
		if is_instance_valid(number_label):
			number_label.text = str(car_number)
		_update_decals()
var is_player := false

# the driver (see _build_driver): a figure in the seat, a wheel that turns with the steering, a head that follows the corners
var _driver: Node3D
var _drv_body: MeshInstance3D
var _drv_head: MeshInstance3D
var _drv_arms: Array[MeshInstance3D] = [] ## left, right
var _drv_wheel: MeshInstance3D
var _drv_seat := Vector3.ZERO ## the hip, in the visual's frame
var _drv_hub := Vector3.ZERO
var _drv_wheel_r := 0.19
var _drv_scale := 1.0
var _drv_rake := Basis()
var _drv_wheel_scale := Basis()
var _drv_shoulders: Array[Vector3] = [] ## in the driver's frame (the arms' pivots)
var _drv_neck := Vector3.ZERO
var _drv_turn := 0.0 ## wheel angle, rad (+ = counter-clockwise seen by the driver)
var _drv_yaw := 0.0
var _drv_roll := 0.0
var _drv_pitch := 0.0
var _drv_accel := 0.0
var _drv_speed := 0.0
var _driver_shown := true ## false in the cameras that sit inside the car
var _drv_suit_mat: StandardMaterial3D ## this car's own two tinted materials (the meshes are shared)
var _drv_helmet_mat: StandardMaterial3D

## Smoothed presentation state (radians).
var grade_pitch := 0.0
var _roll := 0.0
var _spins := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _lamp_sig := Vector4(-1.0, -1.0, -1.0, -1.0) ## the lamp state last applied (set_lamps)
const BULB_OFF := Color(0.36, 0.09, 0.04)
const BULB_ON := Color(0.9, 0.2, 0.06)
const BULB_RED := Color(1.0, 0.015, 0.008) ## deep red: any green in a bright emitter turns orange under ACES (2026-11-21 dusk QA)
const BULB_WHITE := Color(1.0, 0.86, 0.72) ## the reversing lamp
var _sun: DirectionalLight3D ## the world's sun, for the paint's glint (found from the player's car)
var _sun_tried := -1000
var _sun_sig := Vector4.ZERO
var _sky_mat: ShaderMaterial ## the open world's sky shader, which the mirror passes take their colours from
var _ghost := false
var _paint := Color.WHITE
var _damage_shown := 0.0
var _previous_throttle := 0.0
var _hit_seen := 0.0 ## car.last_hit last frame (sparks off a wall touched mid-drift)
var _light_bar: Array[StandardMaterial3D] = [] ## safety car only: left and right lamps
var _beacon: OmniLight3D
var _shell: MeshInstance3D
var _details_node: MeshInstance3D
var _dents_shown := {"front": 0.0, "rear": 0.0, "left": 0.0, "right": 0.0}
## Crash damage the body shows (all cosmetic: nothing here feeds back into the sim). The model's loose panels (Bonnet,
## DoorL/R, BumperF/R, Boot, each with its "<panel>Details" and stripe/livery pieces, cut out of the Body by
## tools/blender/carkit.py) hang on hinges: the bonnet pops and flaps and is torn off, a door swings ajar on a side hit
## and is torn off by a big one, a bumper sags at the struck end and drops, the boot lid pops. The glass cracks
## (Windscreen: shaders/car_windscreen.gdshader) or shatters (side and rear windows), each lamp breaks
## (shaders/car_damage.gdshaderinc), crush_* blend shapes crumple the skin round each contact point (on top of the
## four whole-side dent_* ones), scrape decals show bare metal where it struck, and a huge crash tears a wheel off
## (RaceCar.wheel_off) or bends it. RaceCar.dents (RaceControl.hurt, FreeCar._dent: 3 x ((dv - 3) / 6.7)^2 per hit,
## full near 25 km/h) and RaceCar.hit_log (where and how hard each impact was) drive it; dents back to nothing (a pit
## repair, a reset) put everything back. Thresholds are the closing speed of one impact (m/s).
const BONNET_POP := 0.5 ## front dent that pops the bonnet's catch (one hit of about 21 km/h, or a few smaller ones)
const BONNET_TEAR_DV := 11.0 ## m/s (40 km/h) of speed lost in a crash that tears a popped bonnet off
const BONNET_RIP_DV := 15.0 ## m/s (54 km/h): a crash that pops and tears off a shut one at once
const BONNET_WIND_V := 33.0 ## m/s (120 km/h): a popped bonnet (or an ajar door) driven this fast ...
const BONNET_WIND_T := 4.0 ## ... for this long in s is torn off by the wind
const BONNET_REF_FALL := 30.0 ## m/s^2 the crash reference speed may fall
const DOOR_AJAR_DV := 7.0 ## a side hit on the door this hard springs it ajar (or a side dent of DOOR_AJAR_DENT)
const DOOR_AJAR_DENT := 0.6
const DOOR_TEAR_DV := 13.0 ## and this hard (47 km/h) tears it off
const BUMPER_SAG_DV := 6.0 ## a hit on a bumper this hard knocks one end loose (or a dent of BUMPER_SAG_DENT on that end)
const BUMPER_SAG_DENT := 0.45
const BUMPER_DROP_DV := 11.0 ## a hit this hard, or a sagging one hit again at BUMPER_SAG_DV, or dragged at 100 km/h for
const BUMPER_DROP_T := 5.0 ## this long, drops it
const BOOT_POP_DV := 6.5 ## a rear hit this hard (or a rear dent of BONNET_POP) pops the boot lid or tailgate
const WINDOW_DV := 8.0 ## a hit this hard on a side (the rear) shatters that side's (the rear) window ...
const WINDOW_DENT := 0.85 ## ... as does a dent this deep there
const LAMP_DV := 5.0 ## a hit this hard near a lamp breaks it; a dent of LAMP_DENT breaks both on that end
const LAMP_DENT := 0.8
const SCRAPE_DV := 3.5 ## a hit this hard scrapes the paint to bare metal there
const SCRAPES := 4 ## scrape decals a car keeps (the oldest is reused)
const PART_MASS := {"Bonnet": 12.0, "DoorL": 22.0, "DoorR": 22.0, "BumperF": 6.0, "BumperR": 6.0, "Boot": 12.0}
const WHEEL_MASS := 16.0
const PART_LIFE := 20.0 ## s a thrown part lies about
const PART_REACH := 150.0 ## m from the car past which a thrown part is cleared
const BONNET_LAYER := 1 << 19 ## physics layer of loose parts and the ground they land on (nothing else uses it)
const PANELS := ["Bonnet", "DoorL", "DoorR", "BumperF", "BumperR", "Boot"]
const PANEL_PIECES := ["Details", "Stripes", "Martini", "Abarth", "Marlboro"]
const GLASS := ["Windscreen", "WindowL", "WindowR", "RearWindow"]
const DENT_KEYS := ["front", "rear", "left", "right"]
const DENT_SCALE := 0.7 ## of the whole-side dent_* shapes the dents show, now the crush_* ones crumple the blow's own spot
## The crush_* blend shapes' sites (tools/blender/carkit.py CRUSH): along the car (0 nose .. 1 tail), across it (-1 left
## .. 1 right of the half width)
const CRUSH_SITES := {"fl": Vector2(0.0, -0.62), "fc": Vector2(0.0, 0.0), "fr": Vector2(0.0, 0.62),
	"rl": Vector2(1.0, -0.62), "rc": Vector2(1.0, 0.0), "rr": Vector2(1.0, 0.62),
	"l1": Vector2(0.2, -1.0), "l2": Vector2(0.4, -1.0), "l3": Vector2(0.6, -1.0), "l4": Vector2(0.82, -1.0),
	"r1": Vector2(0.2, 1.0), "r2": Vector2(0.4, 1.0), "r3": Vector2(0.6, 1.0), "r4": Vector2(0.82, 1.0)}
const CRUSH_REACH := 0.75 ## m from a site at which a hit still crushes it by 1/e
var _bonnet: Node3D ## the bonnet's hinge (null: a model without a Bonnet)
var _bonnet_parts: Array = [] ## [piece, the body mesh whose visibility it copies, or null]
var _bonnet_state := 0 ## 0 shut, 1 popped, 2 thrown off
var _panels := {} ## panel name -> {hinge, parts: [[piece, src]], state: 0 fitted / 1 loose / 2 gone, a, flap, t, box}
var _glass := {} ## Windscreen / WindowL / WindowR / RearWindow -> MeshInstance3D
var _glass_gone := {} ## the windows shattered
var _crack := 0.0 ## the windscreen's crack (car_windscreen.gdshader)
var _crack_at := Vector3.ZERO
var _crack_shown := 0.0
var _lamps_broken := Vector4.ZERO ## FL, FR, RL, RR
var _crush := {} ## site -> how crushed it is (target)
var _crush_shown := {}
var _shape_idx: Array = [] ## [[mesh instance, {blend shape name: index}]] of everything that crumples
var _scrapes: Array[Decal] = []
var _hits_seen := -1
var _wheel_lost := -1
var _corner_drop := 0.0
var _bend_shown := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _bonnet_flap := 0.0
var _bonnet_ref := 0.0 ## recent forward speed, falling at most BONNET_REF_FALL
var _bonnet_wind := 0.0 ## s driven above BONNET_WIND_V while popped
var _bonnet_last := Vector3.ZERO
var _bonnet_seen := false
var _vel := Vector3.ZERO ## the visual's own velocity (m/s), from its motion
var _loose: Array = [] ## [[Node3D holding a thrown part and its landing plane, age]]
var _half := Vector2(0.8, 2.0) ## the shell's half width and half length
var _decal_pins := {} ## a racing decal on a panel -> [panel name, its transform with the panel shut]
var _nose := -2.0 ## the shell's front z
var _fx_near := false ## this car shows effects: in a race, not a ghost, and the player or near the camera
var _world: Node = null ## the RaceWorld this car races in (effects only there, not for menus or the ghost)
var _fx_checked := false
var _fx := {} ## effect kind -> GPUParticles3D, made the first time the car needs it
var fx_quality := 2 ## graphics level for a car outside a race (the open world), which drives its effects with set_fx()

func _ready() -> void:
	_build()
	child_entered_tree.connect(_on_child_entered)
	for c in get_children():
		if c is SpotLight3D:
			_fit_headlight_beam(c as SpotLight3D)

func _on_child_entered(node: Node) -> void:
	if node is SpotLight3D:
		_fit_headlight_beam(node as SpotLight3D)

## Positions and shapes a front headlight SpotLight3D child to match this car's headlamps: aimed straight ahead and
## dipped slightly down for a clean low-beam cut-off (stops below upper storeys on walls), with shadows off.
func _fit_headlight_beam(s: SpotLight3D) -> void:
	if s.position.z >= 0.0:
		return
	var side: float = float(s.get_meta("_hl_side", -1.0 if s.position.x < 0.0 else 1.0))
	s.set_meta("_hl_side", side)
	var sh := _shared_resources(car_key)
	var bp: Vector3 = sh.get("beam_pos", Vector3(0.52, 0.66, -1.78))
	s.position = Vector3(side * bp.x, bp.y, bp.z)
	s.rotation = Vector3(deg_to_rad(-13.5), 0.0, 0.0)
	s.spot_range = 54.0
	s.spot_angle = 28.0
	s.spot_angle_attenuation = 2.6
	s.spot_attenuation = 1.4
	s.light_specular = 0.12
	s.light_color = Color(1.0, 0.95, 0.84)
	s.light_projector = null
	s.shadow_enabled = false

## Swaps the visual to another catalogue car: the body, lamps, wheels and decals are rebuilt, the paint, livery, stripes and
## number are kept.
func set_car(key: String) -> void:
	if key == car_key:
		return
	car_key = key
	if body_pivot == null:
		return # not built yet: _ready builds it for this key
	var stripes_on := stripes_node.visible if is_instance_valid(stripes_node) else true
	for c in get_children():
		remove_child(c)
		c.queue_free()
	steer_pivots.clear()
	wheels.clear()
	livery_nodes.clear()
	_light_bar.clear()
	_fx.clear()
	_brake_light = null
	_near_beam = null
	_beam_pool = null
	_beacon = null
	_driver = null
	_drv_body = null
	_drv_head = null
	_drv_wheel = null
	_drv_arms.clear()
	_lamp_sig = Vector4(-1.0, -1.0, -1.0, -1.0)
	_damage_shown = 0.0
	_dents_shown = {"front": 0.0, "rear": 0.0, "left": 0.0, "right": 0.0}
	_clear_bonnet()
	_build()
	set_paint(_paint)
	set_livery(livery)
	set_stripes(stripes_on)
	car_number = car_number

func _build() -> void:
	_fit = CarCatalog.visual(car_key)
	_wheel_radius = _fit.wheel_radius
	_wheelbase = _fit.wheelbase
	var half := _wheelbase * 0.5
	_wheel_spots = [Vector3(-_fit.half_track_front, _wheel_radius, -half), Vector3(_fit.half_track_front, _wheel_radius, -half),
		Vector3(-_fit.half_track_rear, _wheel_radius, half), Vector3(_fit.half_track_rear, _wheel_radius, half)]
	var sh := _shared_resources(car_key)
	paint_material = StandardMaterial3D.new()
	paint_material.vertex_color_use_as_albedo = true
	paint_material.vertex_color_is_srgb = true
	# base coat under a hard, near-mirror clear coat: the coat's Fresnel gives the sky reflection and the rim
	paint_material.roughness = 0.36
	paint_material.metallic = 0.0
	paint_material.metallic_specular = 0.55
	paint_material.clearcoat_enabled = true
	paint_material.clearcoat = 1.0
	paint_material.clearcoat_roughness = 0.03
	# orange peel: a fine, subtle triplanar bump that breaks up the sky reflection on flat panels
	paint_material.normal_enabled = true
	paint_material.normal_texture = _shared_resources().peel
	paint_material.normal_scale = 0.12
	paint_material.uv1_triplanar = true
	paint_material.uv1_scale = Vector3(22.0, 22.0, 22.0)
	paint_material.rim_enabled = true
	paint_material.rim = 0.18
	paint_material.rim_tint = 0.65
	stripe_material = StandardMaterial3D.new()
	stripe_material.roughness = 0.3
	stripe_material.clearcoat_enabled = true # decals sit under the same clear coat
	stripe_material.clearcoat = 0.8
	stripe_material.clearcoat_roughness = 0.05
	tail_material = StandardMaterial3D.new()
	tail_material.albedo_color = (_fit.get("tail_lamp", {}) as Dictionary).get("albedo", Color("#3c0404"))
	tail_material.roughness = 0.12
	tail_material.metallic_specular = 0.25
	tail_material.emission_enabled = true
	tail_material.emission = Color(1.0, 0.0, 0.0)
	tail_material.emission_energy_multiplier = 0.0 # off until set_lamps lights it

	bulb_material = StandardMaterial3D.new()
	bulb_material.albedo_color = BULB_OFF # a dull bulb behind the red lens by day (it read as lit in the sun)
	bulb_material.roughness = 0.15
	bulb_material.emission_enabled = true
	bulb_material.emission = BULB_RED
	bulb_material.emission_energy_multiplier = 0.0

	body_pivot = Node3D.new()
	body_pivot.name = "SuspendedBody"
	add_child(body_pivot)

	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	shell.mesh = sh.shell
	shell.set_surface_override_material(sh.paint_surface, paint_material)
	paint_material.next_pass = sh.coat
	body_pivot.add_child(shell)
	_shell = shell

	var details := MeshInstance3D.new()
	details.name = "Details"
	details.mesh = sh.details
	details.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	details.set_surface_override_material(sh.tail_surface, tail_material)
	if sh.bulb_surface >= 0:
		details.set_surface_override_material(sh.bulb_surface, bulb_material)
	body_pivot.add_child(details)
	_details_node = details
	details.set_instance_shader_parameter("plate_id", float(posmod(car_number * 5 + 3, PLATE_ROWS)))
	details.set_instance_shader_parameter("lit", 0.0)
	details.set_instance_shader_parameter("glow", 0.0)

	var cabin := MeshInstance3D.new()
	cabin.name = "Cabin"
	cabin.mesh = sh.cabin
	cabin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cabin.visibility_range_end = CABIN_RANGE
	cabin.visibility_range_end_margin = 4.0
	body_pivot.add_child(cabin)
	_build_driver()

	stripes_node = MeshInstance3D.new()
	stripes_node.name = "Stripes"
	stripes_node.mesh = sh.stripes
	stripes_node.material_override = stripe_material
	stripes_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body_pivot.add_child(stripes_node)
	for k in LIVERY_MESHES:
		var node := MeshInstance3D.new()
		node.name = LIVERY_MESHES[k]
		node.mesh = sh.liveries[k]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visible = false
		body_pivot.add_child(node)
		livery_nodes[k] = node
	martini_node = livery_nodes[2]
	_build_damage(sh)

	for spot in _wheel_spots:
		var pivot := Node3D.new()
		pivot.position = spot
		add_child(pivot)
		var wheel := Node3D.new() # spins about X
		pivot.add_child(wheel)
		var tyre := MeshInstance3D.new()
		tyre.mesh = sh.wheel
		tyre.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if spot.x < 0.0:
			tyre.rotation.y = PI # the model's outer face points +X
		wheel.add_child(tyre)
		steer_pivots.append(pivot)
		wheels.append(wheel)

	var contact := MeshInstance3D.new()
	contact.name = "ContactShadow"
	contact.mesh = sh.contact
	contact.position.y = 0.025
	contact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(contact)

	number_label = Label3D.new()
	number_label.name = "RoofNumber"
	number_label.text = str(car_number)
	number_label.font_size = 34
	number_label.outline_size = 8
	number_label.modulate = Color("#202124")
	number_label.position = _fit.roof_number
	number_label.rotation.x = -PI / 2.0
	number_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body_pivot.add_child(number_label)

	# Racing decals: door numbers, sunstrip, bonnet plate and sponsor stacks. Each quad sits 6 mm off the body
	# surface, at points and normals measured on models/seicento.glb's Body mesh (doors: centred on the model's
	# white door panel). Re-measure if the car is rebuilt.
	var decal_mat := _decal_material()
	if _fit.has("decal_aims"):
		# every car after the Seicento: the decals are aimed at the model by rays (CarCatalog), so nothing is measured by hand
		var aims: Dictionary = _fit.decal_aims
		_door_decal_l = _aim_decal("DoorDecalL", decal_mat, sh, aims.DoorDecalL)
		_door_decal_r = _aim_decal("DoorDecalR", decal_mat, sh, aims.DoorDecalR)
		_sunstrip_decal = _aim_decal("Sunstrip", decal_mat, sh, aims.Sunstrip)
		_hood_decal = _aim_decal("HoodDecal", decal_mat, sh, aims.HoodDecal)
		_sill_decal_l = _aim_decal("SillDecalL", decal_mat, sh, aims.SillDecalL)
		_sill_decal_r = _aim_decal("SillDecalR", decal_mat, sh, aims.SillDecalR)
		_update_decals()
		_pin_decals()
		return
	_door_decal_l = _add_decal("DoorDecalL", decal_mat, Vector3(-0.7408, 0.65, -0.02), Vector3(-0.9984, 0.0568, -0.0008), Vector3.UP)
	_door_decal_r = _add_decal("DoorDecalR", decal_mat, Vector3(0.7408, 0.65, -0.02), Vector3(0.9984, 0.0568, -0.0008), Vector3.UP)
	# along the top of the windscreen, reading from the front; "up" runs up the glass towards the roof
	_sunstrip_decal = _add_decal("Sunstrip", decal_mat, Vector3(0.0, 1.25, -0.167), Vector3(0.0, 0.824, -0.566), Vector3(0.0, 0.566, 0.824))
	# on the bonnet, reading from behind (the chase camera)
	_hood_decal = _add_decal("HoodDecal", decal_mat, Vector3(0.0, 0.7935, -1.22), Vector3(-0.0176, 0.9848, -0.1729), Vector3.FORWARD)
	_sill_decal_l = _add_decal("SillDecalL", decal_mat, Vector3(-0.7415, 0.385, 0.25), Vector3(-0.998, -0.065, 0.003), Vector3.UP)
	_sill_decal_r = _add_decal("SillDecalR", decal_mat, Vector3(0.7415, 0.385, 0.25), Vector3(0.998, -0.065, 0.003), Vector3.UP)
	_update_decals()
	_pin_decals()

## A decal on the car's body where a ray from aim.from along aim.dir meets it (the Body mesh's triangles), reading along aim.up.
func _aim_decal(label: String, mat: StandardMaterial3D, sh: Dictionary, aim: Dictionary) -> MeshInstance3D:
	if not sh.has("tri"):
		sh["tri"] = body_tri(sh)
	var dir: Vector3 = (aim.dir as Vector3).normalized()
	var hit: Dictionary = (sh.tri as TriangleMesh).intersect_ray(aim.from, dir) if sh.tri != null else {}
	if hit.is_empty():
		push_warning("%s: the ray from %s along %s misses the %s body" % [label, aim.from, dir, car_key])
		return _add_decal(label, mat, aim.from, -dir, aim.up)
	var n: Vector3 = hit.normal
	if n.dot(dir) > 0.0:
		n = -n
	return _add_decal(label, mat, hit.position, n, aim.up)

## The Body's triangles plus the panels' (the bonnet, doors, bumpers and boot cut out of it), for rays at the car's skin.
static func body_tri(sh: Dictionary) -> TriangleMesh:
	var panels: Dictionary = sh.get("panels", {})
	if panels.is_empty():
		return (sh.shell as Mesh).generate_triangle_mesh()
	var faces: PackedVector3Array = (sh.shell as Mesh).get_faces()
	for k in panels:
		faces.append_array((panels[k].mesh as Mesh).get_faces())
	var glass: Dictionary = sh.get("glass", {}) # (the sunstrip sits on the windscreen)
	for k in glass:
		faces.append_array((glass[k] as Mesh).get_faces())
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m.generate_triangle_mesh()

## The loose panels on their hinges, the glass, and the list of everything that crumples.
func _build_damage(sh: Dictionary) -> void:
	var box: AABB = (sh.shell as Mesh).get_aabb()
	_half = Vector2(box.size.x * 0.5, box.size.z * 0.5)
	_nose = box.position.z
	var parts: Dictionary = sh.get("panels", {})
	for name in PANELS:
		if parts.has(name):
			_build_panel(name, parts[name])
	if _panels.has("Bonnet"):
		_bonnet = _panels.Bonnet.hinge
		_bonnet_parts = _panels.Bonnet.parts
	for name in GLASS:
		var m: Mesh = (sh.get("glass", {}) as Dictionary).get(name)
		if m == null:
			continue
		var g := MeshInstance3D.new()
		g.name = name
		g.mesh = m
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var holder: Node3D = body_pivot
		# a hatchback's rear window is in its tailgate: it lifts with it
		if name == "RearWindow" and _panels.has("Boot"):
			var bb: AABB = _panels.Boot.box
			var gb := m.get_aabb()
			if gb.position.z >= bb.position.z - 0.03 and gb.end.y <= bb.end.y + 0.05:
				holder = _panels.Boot.hinge
				g.position = -holder.position
				_panels.Boot.parts.append([g, null])
		holder.add_child(g)
		_glass[name] = g
	if _glass.has("Windscreen"):
		var wb: AABB = (_glass.Windscreen as MeshInstance3D).mesh.get_aabb()
		_crack_at = Vector3(0.0, wb.position.y + wb.size.y * 0.35, wb.position.z + wb.size.z * 0.35)
	_shape_idx.clear()
	var meshes: Array = [_shell, _details_node, stripes_node] + livery_nodes.values()
	for name in _panels:
		for p in _panels[name].parts:
			meshes.append(p[0])
	meshes.append_array(_glass.values())
	for mi in meshes:
		var idx := {}
		for k in DENT_KEYS:
			var i: int = (mi as MeshInstance3D).find_blend_shape_by_name("dent_" + k)
			if i >= 0:
				idx["dent_" + k] = i
		for k in CRUSH_SITES:
			var i: int = (mi as MeshInstance3D).find_blend_shape_by_name("crush_" + k)
			if i >= 0:
				idx["crush_" + k] = i
		if not idx.is_empty():
			_shape_idx.append([mi, idx])

## One panel under its hinge: the Body's piece in this car's paint, its Details piece, and its stripe and livery pieces
## showing with those meshes.
func _build_panel(name: String, part: Dictionary) -> void:
	var mesh: Mesh = part.mesh
	var box := mesh.get_aabb()
	var top: Vector3 = part.get("top", Vector3(0.0, box.end.y, box.end.z))
	var hinge_at := Vector3(0.0, box.end.y, box.end.z) # the bonnet: its rear edge, under the windscreen (front is -Z)
	match name:
		"DoorL":
			hinge_at = Vector3(box.position.x, box.get_center().y, box.position.z) # its leading edge
		"DoorR":
			hinge_at = Vector3(box.end.x, box.get_center().y, box.position.z)
		"BumperF", "BumperR":
			hinge_at = Vector3(box.end.x, box.end.y, box.get_center().z) # set again at the end that stays on when it sags
		"Boot":
			hinge_at = Vector3(0.0, top.y, top.z) # its top, at the roof (a tailgate) or the rear screen (a boot lid)
	var hinge := Node3D.new()
	hinge.name = name + "Hinge"
	hinge.position = hinge_at
	body_pivot.add_child(hinge)
	var panel := MeshInstance3D.new()
	panel.name = name
	panel.mesh = mesh
	panel.position = -hinge_at
	panel.set_surface_override_material(int(part.paint), paint_material)
	hinge.add_child(panel)
	var pieces: Array = [[panel, null]]
	var given: Dictionary = part.pieces
	for k in PANEL_PIECES:
		if not given.has(k):
			continue
		var piece := MeshInstance3D.new()
		piece.name = name + k
		piece.mesh = given[k]
		piece.position = -hinge_at
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var src: MeshInstance3D = null
		if k == "Details":
			piece.set_instance_shader_parameter("plate_id", float(posmod(car_number * 5 + 3, PLATE_ROWS)))
		else:
			src = stripes_node if k == "Stripes" else body_pivot.get_node(NodePath(k))
			piece.material_override = src.material_override
			piece.visible = src.visible
		hinge.add_child(piece)
		pieces.append([piece, src])
	_panels[name] = {"hinge": hinge, "parts": pieces, "state": 0, "a": 0.0, "flap": randf() * TAU, "t": 0.0, "box": box,
		"end": 1.0}

func _panel_state(name: String) -> int:
	return int(_panels[name].state) if _panels.has(name) else 0

## The damage for this frame: new impacts, the dents, the panels on their hinges, the wheels.
func _update_damage(car: RaceCar, dt: float) -> void:
	_sync_bonnet_parts()
	var pos := global_position if is_inside_tree() else position
	var vel := (pos - _bonnet_last) / maxf(dt, 1e-3) if _bonnet_seen and dt > 0.0 else Vector3.ZERO
	if vel.length() > 120.0:
		vel = Vector3.ZERO # a teleport (reset, respawn), not motion
		_bonnet_ref = 0.0
	_bonnet_last = pos
	_bonnet_seen = true
	_vel = vel
	var fwd := maxf(0.0, vel.dot(-global_basis.z if is_inside_tree() else -basis.z))
	_bonnet_ref = maxf(_bonnet_ref - BONNET_REF_FALL * dt, fwd)
	var crash := _bonnet_ref - fwd
	var dents: Dictionary = car.dents
	var total := 0.0
	for k in DENT_KEYS:
		total += float(dents.get(k, 0.0))
	if total < 0.05 and car.wheel_off < 0:
		if _damaged():
			_repair()
		_hits_seen = car.hit_count
	elif not _ghost:
		if _hits_seen < 0 or car.hit_count < _hits_seen:
			_hits_seen = car.hit_count
		var fresh := mini(car.hit_count - _hits_seen, car.hit_log.size())
		for i in range(car.hit_log.size() - fresh, car.hit_log.size()):
			_take_hit(car.hit_log[i])
		_hits_seen = car.hit_count
		_from_dents(dents)
	# the bonnet: popped by the front dent, torn off by the crash itself or by the wind
	if _panels.has("Bonnet") and not _ghost:
		var b: Dictionary = _panels.Bonnet
		var front: float = float(dents.get("front", 0.0))
		if b.state == 0 and front >= BONNET_POP:
			_loosen("Bonnet")
			if crash >= BONNET_RIP_DV:
				_throw("Bonnet", vel)
		elif b.state == 1 and (crash >= BONNET_TEAR_DV or b.t > BONNET_WIND_T):
			_throw("Bonnet", vel)
	for name in _panels:
		_move_panel(name, vel, fwd, dt)
	_follow_decals()
	# the wheels: one torn off, the others bent
	if car.wheel_off >= 0 and _wheel_lost < 0 and car.wheel_off < steer_pivots.size():
		_lose_wheel(car.wheel_off, vel)
	elif car.wheel_off < 0 and _wheel_lost >= 0:
		steer_pivots[_wheel_lost].visible = true
		_wheel_lost = -1
	_corner_drop = move_toward(_corner_drop, 1.0 if _wheel_lost >= 0 else 0.0, dt * 4.0)
	for i in mini(4, wheels.size()):
		var bend: float = car.wheel_bend[i] if i < car.wheel_bend.size() else 0.0
		if absf(bend - _bend_shown[i]) > 0.01:
			_bend_shown[i] = bend
			var tyre := wheels[i].get_child(0) as Node3D
			# tilted on the spinning hub: the camber and toe wobble round as the wheel turns
			tyre.rotation = Vector3(0.0, (PI if _wheel_spots[i].x < 0.0 else 0.0) + 0.06 * bend, 0.1 * bend)
	_show_crush(dt)
	var i := 0
	while i < _loose.size():
		_loose[i][1] += dt
		var node: Node3D = _loose[i][0]
		var body := node.get_child(1) as Node3D if is_instance_valid(node) and node.get_child_count() > 1 else null
		if body == null or _loose[i][1] > PART_LIFE or body.global_position.distance_to(pos) > PART_REACH:
			if is_instance_valid(node):
				node.queue_free()
			_loose.remove_at(i)
		else:
			i += 1

## A wheel gone: that corner of the body down on its hub.
func _apply_corner_drop() -> void:
	if _corner_drop <= 0.0 or _wheel_lost < 0:
		return
	var spot: Vector3 = _wheel_spots[_wheel_lost]
	var drop := _wheel_radius * 0.55 * _corner_drop
	body_pivot.rotation.x += drop / _wheelbase * (-1.0 if spot.z < 0.0 else 1.0) # nose (tail) down
	body_pivot.rotation.z += drop / (absf(spot.x) * 2.0) * (1.0 if spot.x < 0.0 else -1.0) # that side down
	body_pivot.position.y = minf(body_pivot.position.y, -drop * 0.5)

## One impact (RaceCar.hit_log: right, ahead, closing speed), in the visual's frame: the crumple round it, a scrape, and
## whatever it breaks there.
func _take_hit(h: Vector3) -> void:
	var dv := h.z
	if dv < 2.0:
		return
	var across := clampf(h.x / maxf(_half.x, 0.1), -1.3, 1.3)
	var along := clampf(0.5 - 0.5 * h.y / maxf(_half.y, 0.1), -0.1, 1.1) # 0 nose .. 1 tail
	var front_back := absf(h.y) / _half.y > absf(h.x) / _half.x
	var zone := ("front" if h.y > 0.0 else "rear") if front_back else ("right" if h.x > 0.0 else "left")
	var x := clampf((dv - 3.0) / 6.7, 0.0, 2.0)
	var add := x * x * 1.6
	for k in CRUSH_SITES:
		var site: Vector2 = CRUSH_SITES[k]
		var d := Vector2((across - site.y) * _half.x, (along - site.x) * _half.y * 2.0)
		var w := exp(-d.length_squared() / (CRUSH_REACH * CRUSH_REACH))
		if w > 0.05:
			_crush[k] = minf(1.0, float(_crush.get(k, 0.0)) + add * w)
	if dv >= SCRAPE_DV:
		_scrape(zone, across, along, dv)
	match zone:
		"front", "rear":
			var end := 0 if zone == "front" else 2
			if dv >= LAMP_DV:
				if across < 0.25:
					_break_lamp(end, h)
				if across > -0.25:
					_break_lamp(end + 1, h)
			var bumper := "BumperF" if zone == "front" else "BumperR"
			if _panels.has(bumper):
				var st := _panel_state(bumper)
				if dv >= BUMPER_DROP_DV or (st == 1 and dv >= BUMPER_SAG_DV):
					_throw(bumper, _vel)
				elif st == 0 and dv >= BUMPER_SAG_DV:
					_sag(bumper, across)
			if zone == "front":
				if dv >= 9.0:
					if _crack < 0.05:
						_crack_at.x = clampf(h.x * 0.5, -0.45, 0.45)
					_crack = maxf(_crack, 0.35 + (dv - 9.0) / 12.0)
			else:
				if dv >= BOOT_POP_DV and _panel_state("Boot") == 0:
					_loosen("Boot")
				if dv >= WINDOW_DV + 3.0: # (laminated or set deep in the tailgate: it takes more)
					_shatter("RearWindow")
		"left", "right":
			var door := "DoorL" if zone == "left" else "DoorR"
			if _panels.has(door):
				var db: AABB = _panels[door].box
				var z := lerpf(_nose, _nose + _half.y * 2.0, along)
				if z > db.position.z - 0.3 and z < db.end.z + 0.3:
					if dv >= DOOR_TEAR_DV:
						_throw(door, _vel)
					elif dv >= DOOR_AJAR_DV and _panel_state(door) == 0:
						_loosen(door)
			if dv >= WINDOW_DV:
				_shatter("WindowL" if zone == "left" else "WindowR")
			if dv >= LAMP_DV + 2.0 and (along < 0.12 or along > 0.88): # a side swipe at a corner takes its lamp
				_break_lamp((0 if along < 0.5 else 2) + (1 if zone == "right" else 0), h)

## What the dents alone break (a car dented without impacts noted: many small knocks, a probe).
func _from_dents(dents: Dictionary) -> void:
	var front: float = float(dents.get("front", 0.0))
	var rear: float = float(dents.get("rear", 0.0))
	_crack = maxf(_crack, smoothstep(0.3, 1.0, front) * 0.9) # a spider web; frosting over takes a hard blow (_take_hit)
	if front >= LAMP_DENT:
		_break_lamp(0, Vector3.ZERO)
		_break_lamp(1, Vector3.ZERO)
	if rear >= LAMP_DENT:
		_break_lamp(2, Vector3.ZERO)
		_break_lamp(3, Vector3.ZERO)
	if rear >= BONNET_POP and _panel_state("Boot") == 0:
		_loosen("Boot")
	for b in [["BumperF", front], ["BumperR", rear]]:
		if b[1] >= BUMPER_SAG_DENT and _panel_state(b[0]) == 0:
			_sag(b[0], 0.0)
	for side in ["left", "right"]:
		var d: float = float(dents.get(side, 0.0))
		var door := "DoorL" if side == "left" else "DoorR"
		if d >= DOOR_AJAR_DENT and _panel_state(door) == 0:
			_loosen(door)
		if d >= WINDOW_DENT:
			_shatter("WindowL" if side == "left" else "WindowR")
	if _glass.has("Windscreen") and _crack != _crack_shown:
		_crack_shown = _crack
		(_glass.Windscreen as MeshInstance3D).set_instance_shader_parameter("crack", _crack)
		(_glass.Windscreen as MeshInstance3D).set_instance_shader_parameter("crack_at", _crack_at)

func _damaged() -> bool:
	for name in _panels:
		if _panels[name].state != 0:
			return true
	return not _glass_gone.is_empty() or _crack > 0.0 or _lamps_broken != Vector4.ZERO or not _crush.is_empty() \
		or not _scrapes.is_empty() or _wheel_lost >= 0

## Everything back on and whole (a repaired or reset car).
func _repair() -> void:
	for name in _panels:
		var p: Dictionary = _panels[name]
		p.state = 0
		p.a = 0.0
		p.t = 0.0
		(p.hinge as Node3D).visible = true
		(p.hinge as Node3D).rotation = Vector3.ZERO
	for name in _glass:
		(_glass[name] as Node3D).visible = true
	_glass_gone.clear()
	_crack = 0.0
	_crack_shown = 0.0
	if _glass.has("Windscreen"):
		(_glass.Windscreen as MeshInstance3D).set_instance_shader_parameter("crack", 0.0)
	_lamps_broken = Vector4.ZERO
	if is_instance_valid(_details_node):
		_details_node.set_instance_shader_parameter("lamp_broken", _lamps_broken)
	_lamp_sig = Vector4(-1.0, -1.0, -1.0, -1.0)
	_crush.clear()
	for d in _scrapes:
		d.queue_free()
	_scrapes.clear()
	for l in _loose:
		if is_instance_valid(l[0]):
			l[0].queue_free()
	_loose.clear()
	_bonnet_state = 0
	_follow_decals()
	_show_livery()

## Off its catch or hinge: the bonnet and the boot lid lift, a door swings ajar.
func _loosen(name: String) -> void:
	if not _panels.has(name) or _panels[name].state != 0:
		return
	_panels[name].state = 1
	_panels[name].t = 0.0
	if name == "Bonnet":
		_bonnet_state = 1
		_show_livery()

## A bumper's end torn off its clips: it hangs from the end away from the blow (across: where it was struck).
func _sag(name: String, across: float) -> void:
	if not _panels.has(name) or _panels[name].state != 0:
		return
	var p: Dictionary = _panels[name]
	var box: AABB = p.box
	var keep := -1.0 if across > 0.0 else 1.0 # the end that stays on
	if absf(across) < 0.1:
		keep = 1.0 if randf() < 0.5 else -1.0
	p.end = keep
	var hinge := p.hinge as Node3D
	hinge.position = Vector3(box.end.x if keep > 0.0 else box.position.x, box.end.y, box.get_center().z)
	for q in p.parts:
		(q[0] as Node3D).position = -hinge.position
	_loosen(name)

## A loose panel on its hinge: lifted and fluttering in the wind (bonnet, boot lid), swinging ajar (doors), hanging off one
## end and bouncing (bumpers). A popped bonnet or an ajar door at motorway speed is torn off by the wind, a sagging bumper
## dragged along drops.
func _move_panel(name: String, vel: Vector3, fwd: float, dt: float) -> void:
	var p: Dictionary = _panels[name]
	if p.state != 1:
		return
	var hinge := p.hinge as Node3D
	var k := clampf(vel.length() / 30.0, 0.0, 1.0)
	p.flap = float(p.flap) + dt * (8.0 + 16.0 * k)
	var flap: float = p.flap
	p.t = float(p.t) + dt if fwd > BONNET_WIND_V or (name.begins_with("Bumper") and fwd > 28.0) else 0.0
	match name:
		"Bonnet":
			var lift := 0.08 + 0.2 * k * k + (0.02 + 0.07 * k) * sin(flap) * (0.6 + 0.4 * sin(flap * 0.37))
			hinge.rotation.x = lerpf(hinge.rotation.x, lift, minf(1.0, dt * 14.0))
		"Boot":
			var lift := 0.22 + 0.1 * k + (0.03 + 0.05 * k) * sin(flap * 0.8) * (0.6 + 0.4 * sin(flap * 0.29))
			hinge.rotation.x = lerpf(hinge.rotation.x, -lift, minf(1.0, dt * 10.0))
		"DoorL", "DoorR":
			# ajar: it swings with the car's motion, the wind pressing it back towards the frame at speed
			var open := 0.42 * (1.0 - 0.6 * k) + 0.07 * sin(flap * 0.6) * (0.4 + 0.6 * k)
			var sgn := -1.0 if name == "DoorL" else 1.0
			hinge.rotation.y = lerpf(hinge.rotation.y, sgn * open, minf(1.0, dt * 6.0))
			if p.t > BONNET_WIND_T:
				_throw(name, vel)
		"BumperF", "BumperR":
			var box: AABB = p.box
			var drop := asin(clampf((box.position.y - 0.04) / maxf(box.size.x, 0.5), 0.02, 0.4)) # its free end just off the road
			var sag := drop * (0.8 + 0.2 * sin(flap * 1.3) * k)
			hinge.rotation.z = lerpf(hinge.rotation.z, sag * float(p.end), minf(1.0, dt * 10.0))
			if p.t > BUMPER_DROP_T:
				_throw(name, vel)
	if name == "Bonnet" and p.t > BONNET_WIND_T:
		_throw(name, vel)

## Tears a panel off: a copy goes flying as a RigidBody3D (a box the panel's size, PART_MASS) with the car's velocity and a
## kick (a bonnet up and back with a tumble, a door out to its side, a bumper just drops), onto a plane at the car's ground
## height (the tracks and the map have no physics floor); the panel on the car is hidden.
func _throw(name: String, vel: Vector3) -> void:
	if not _panels.has(name) or _panels[name].state == 2:
		return
	var p: Dictionary = _panels[name]
	p.state = 2
	var hinge := p.hinge as Node3D
	hinge.visible = false
	if name == "Bonnet":
		_bonnet_state = 2
	_show_livery()
	if name.begins_with("Door"):
		_shatter("WindowL" if name == "DoorL" else "WindowR")
	if not is_inside_tree() or get_parent() == null:
		return
	var speed := vel.length()
	var back := global_basis.z.normalized() # the car's rear
	var side := global_basis.x.normalized()
	var box: AABB = (p.parts[0][0] as MeshInstance3D).mesh.get_aabb()
	var body := _loose_body(PART_MASS.get(name, 10.0), hinge.global_transform)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(box.size.x, 0.06), maxf(box.size.y * 0.35, 0.06), maxf(box.size.z, 0.06))
	col.shape = shape
	col.position = box.get_center() - hinge.position
	body.add_child(col)
	var copy := hinge.duplicate() as Node3D
	copy.transform = Transform3D.IDENTITY
	copy.visible = true
	body.add_child(copy)
	match name:
		"DoorL", "DoorR":
			var out := side * (-1.0 if name == "DoorL" else 1.0)
			body.linear_velocity = vel * 0.85 + out * (2.5 + 0.08 * speed) + Vector3.UP * (1.5 + 0.03 * speed)
			body.angular_velocity = global_basis.y * randf_range(-4.0, 4.0) + back * randf_range(-3.0, 3.0)
		"BumperF", "BumperR":
			body.linear_velocity = vel * 0.7 + Vector3.UP * 0.8
			body.angular_velocity = back * randf_range(-2.0, 2.0) + global_basis.y * randf_range(-1.5, 1.5)
		_:
			body.linear_velocity = vel * 0.9 + Vector3.UP * (3.0 + 0.08 * speed) + back * (1.5 + 0.05 * speed) + side * randf_range(-1.0, 1.0)
			body.angular_velocity = side * (5.0 + 0.12 * speed) + global_basis.y * randf_range(-2.0, 2.0) + back * randf_range(-1.5, 1.5)
	if _fx_ok():
		FxParticles.burst(self, "debris", hinge.global_position, 12, _fx_level())

## A RigidBody3D for a part thrown off at xf, with a landing plane at the car's ground height, kept in _loose.
func _loose_body(mass: float, xf: Transform3D) -> RigidBody3D:
	var holder := Node3D.new()
	holder.name = "LoosePart"
	holder.top_level = true
	get_parent().add_child(holder)
	var ground := StaticBody3D.new()
	ground.collision_layer = BONNET_LAYER
	ground.collision_mask = 0
	var plane := CollisionShape3D.new()
	plane.shape = WorldBoundaryShape3D.new()
	ground.add_child(plane)
	holder.add_child(ground)
	ground.global_position = global_position
	var body := RigidBody3D.new()
	body.mass = mass
	body.collision_layer = BONNET_LAYER
	body.collision_mask = BONNET_LAYER
	body.linear_damp = 0.5 # a light panel catches the air
	body.angular_damp = 0.6
	holder.add_child(body)
	body.global_transform = xf
	_loose.append([holder, 0.0])
	return body

## The wheel at this corner torn off: it bounces away and that corner drops onto its hub.
func _lose_wheel(i: int, vel: Vector3) -> void:
	_wheel_lost = i
	var pivot := steer_pivots[i]
	pivot.visible = false
	if not is_inside_tree() or get_parent() == null:
		return
	var body := _loose_body(WHEEL_MASS, pivot.global_transform)
	var bounce := PhysicsMaterial.new()
	bounce.bounce = 0.45
	bounce.friction = 0.8
	body.physics_material_override = bounce
	body.linear_damp = 0.05
	body.angular_damp = 0.1
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = _wheel_radius
	shape.height = 0.2
	col.shape = shape
	col.rotation.z = PI / 2.0 # its axle across the car
	body.add_child(col)
	var copy := pivot.duplicate() as Node3D
	copy.transform = Transform3D.IDENTITY
	copy.visible = true
	body.add_child(copy)
	var out := global_basis.x.normalized() * (-1.0 if _wheel_spots[i].x < 0.0 else 1.0)
	body.linear_velocity = vel * 0.8 + out * (3.0 + 0.1 * vel.length()) + Vector3.UP * 2.5
	body.angular_velocity = global_basis.x * (vel.length() / _wheel_radius * 0.6) + global_basis.y * randf_range(-3.0, 3.0)
	if _fx_ok():
		FxParticles.burst(self, "sparks", pivot.global_position, 16, _fx_level())

## A window shattered: gone, with a shower of glass.
func _shatter(name: String) -> void:
	if not _glass.has(name) or _glass_gone.has(name):
		return
	_glass_gone[name] = true
	var g := _glass[name] as MeshInstance3D
	g.visible = false
	if _fx_ok():
		var c := g.mesh.get_aabb().get_center()
		FxParticles.burst(self, "glass", g.global_transform * c, 40, _fx_level())

## Lamp i (0 FL, 1 FR, 2 RL, 3 RR) smashed: dark, its lens crazed (car_damage.gdshaderinc), a few shards.
func _break_lamp(i: int, _h: Vector3) -> void:
	if _lamps_broken[i] >= 1.0:
		return
	_lamps_broken[i] = 1.0
	if is_instance_valid(_details_node):
		_details_node.set_instance_shader_parameter("lamp_broken", _lamps_broken)
	_lamp_sig = Vector4(-1.0, -1.0, -1.0, -1.0) # set_lamps works the light out again
	if _fx_ok():
		var spot := Vector3((-1.0 if i % 2 == 0 else 1.0) * _half.x * 0.7, 0.65, _nose if i < 2 else _nose + _half.y * 2.0)
		FxParticles.burst(self, "glass", to_global(spot), 14, _fx_level())

## 1 if the headlamp (front) or tail lamp on that side still works, 0 if it is smashed (the open world's beams follow it).
func lamp_working(left: bool, front: bool) -> float:
	return 1.0 - _lamps_broken[(0 if front else 2) + (0 if left else 1)]

## Bare metal where the paint was scraped off: a decal on the skin at the blow, streaked along it.
func _scrape(zone: String, across: float, along: float, dv: float) -> void:
	if not is_instance_valid(body_pivot):
		return
	var d: Decal
	if _scrapes.size() >= SCRAPES:
		d = _scrapes.pop_front()
	else:
		d = Decal.new()
		d.name = "Scrape"
		d.texture_albedo = _shared_resources().scrape_albedo
		d.texture_orm = _shared_resources().scrape_orm
		d.cull_mask = 1 | CarReflections.CAR_LAYER # the car's own skin (and nothing far off: the box is thin)
		d.normal_fade = 0.55 # not the crumpled facets turned away from the blow
		d.upper_fade = 0.3
		d.lower_fade = 0.3
		d.distance_fade_enabled = true
		d.distance_fade_begin = 40.0
		d.distance_fade_length = 15.0
		body_pivot.add_child(d)
	_scrapes.append(d)
	var length := clampf(0.3 + 0.04 * dv, 0.35, 1.1)
	var z := lerpf(_nose, _nose + _half.y * 2.0, clampf(along, 0.0, 1.0))
	var h := 0.45 + randf_range(-0.06, 0.12)
	var out: Vector3
	var from: Vector3
	if zone == "left" or zone == "right":
		out = Vector3(-1.0 if zone == "left" else 1.0, 0.0, 0.0)
		from = Vector3(out.x * (_half.x + 1.0), h, z)
	else:
		out = Vector3(0.0, 0.0, -1.0 if zone == "front" else 1.0)
		from = Vector3(clampf(across, -0.95, 0.95) * _half.x * 0.85, h - 0.05, _nose - 1.0 if zone == "front" else _nose + _half.y * 2.0 + 1.0)
	# where the skin is there (the body's own triangles, as the racing decals are aimed), facing which way
	var sh := _shared_resources(car_key)
	if not sh.has("tri"):
		sh["tri"] = body_tri(sh)
	var at := from - out * 1.0
	var y := out
	var hit: Dictionary = (sh.tri as TriangleMesh).intersect_ray(from, -out) if sh.tri != null else {}
	if not hit.is_empty():
		at = hit.position
		var n: Vector3 = hit.normal
		if n.dot(out) < 0.0:
			n = -n
		y = (n + out).normalized() # (between the skin's normal and the blow's: no steep smear round a corner)
	# a decal projects along its -Y: Y out of the skin, X along the streaks, Z up; its box reaches into the crumple
	var zz := (Vector3.UP - y * y.dot(Vector3.UP)).normalized()
	var xx := y.cross(zz).normalized()
	d.transform = Transform3D(Basis(xx, y, zz).rotated(y, randf_range(-0.15, 0.15)), at - y * 0.08)
	d.size = Vector3(length, 0.36, clampf(0.1 + 0.012 * dv, 0.12, 0.32))
	d.modulate = Color(1, 1, 1, clampf(0.5 + 0.04 * dv, 0.55, 0.9))

## Eases the crush_* blend shapes towards the crush, and the dent_* ones towards the car's dents.
func _show_crush(dt: float) -> void:
	var changed := false
	for k in CRUSH_SITES:
		var goal: float = float(_crush.get(k, 0.0))
		var now: float = float(_crush_shown.get(k, 0.0))
		if absf(goal - now) > 0.002:
			_crush_shown[k] = move_toward(now, goal, maxf(dt, 0.001) * (6.0 if goal > now else 1.5)) # in fast, out slowly
			changed = true
	if not changed:
		return
	for e in _shape_idx:
		var mi: MeshInstance3D = e[0]
		var idx: Dictionary = e[1]
		for k in CRUSH_SITES:
			if idx.has("crush_" + k):
				mi.set_blend_shape_value(idx["crush_" + k], float(_crush_shown.get(k, 0.0)))

## The stripe and livery pieces of every panel show with the body's.
func _sync_bonnet_parts() -> void:
	for name in _panels:
		for p in _panels[name].parts:
			if p[1] != null and (p[0] as Node3D).visible != (p[1] as Node3D).visible:
				(p[0] as Node3D).visible = (p[1] as Node3D).visible

## The racing decals on a panel (door numbers, the bonnet plate) move with it.
func _pin_decals() -> void:
	_decal_pins.clear()
	for e in [[_door_decal_l, "DoorL"], [_door_decal_r, "DoorR"], [_hood_decal, "Bonnet"]]:
		if is_instance_valid(e[0]) and _panels.has(e[1]):
			_decal_pins[e[0]] = [e[1], (e[0] as Node3D).transform]

func _follow_decals() -> void:
	for d in _decal_pins:
		var pin: Array = _decal_pins[d]
		var hinge := _panels[pin[0]].hinge as Node3D
		(d as Node3D).transform = hinge.transform * Transform3D(Basis.IDENTITY, -hinge.position) * (pin[1] as Transform3D) \
			if _panels[pin[0]].state == 1 else pin[1]

func _fx_ok() -> bool:
	return visible and not _ghost and (_fx_near or _world == null)

func _fx_level() -> int:
	return int(_world.quality) if is_instance_valid(_world) and "quality" in _world else fx_quality

func _clear_bonnet() -> void:
	for l in _loose:
		if is_instance_valid(l[0]):
			l[0].queue_free()
	_loose.clear()
	_bonnet = null
	_bonnet_parts = []
	_bonnet_state = 0
	_bonnet_seen = false
	_panels.clear()
	_glass.clear()
	_glass_gone.clear()
	_crack = 0.0
	_crack_shown = 0.0
	_lamps_broken = Vector4.ZERO
	_crush.clear()
	_crush_shown.clear()
	_shape_idx.clear()
	_scrapes.clear()
	_hits_seen = -1
	_wheel_lost = -1
	_corner_drop = 0.0
	_bend_shown = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])

func _exit_tree() -> void:
	for l in _loose:
		if is_instance_valid(l[0]):
			l[0].queue_free()
	_loose.clear()

func _add_decal(label: String, mat: StandardMaterial3D, surface: Vector3, normal: Vector3, up: Vector3) -> MeshInstance3D:
	var z := normal.normalized()
	var x := up.cross(z).normalized()
	var d := MeshInstance3D.new()
	d.name = label
	d.material_override = mat
	d.transform = Transform3D(Basis(x, z.cross(x), z), surface + z * 0.006)
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	d.visible = mat.albedo_texture != null # no atlas (models/car_decals.png missing): no blank white quads
	body_pivot.add_child(d)
	return d

## The open world's Monster Truck modifier: k times the wheel size, a slightly wider track and the body lifted
## so the bigger tyres still stand on the ground. 1.0 puts the stock wheels back.
func set_wheel_scale(k: float) -> void:
	for i in steer_pivots.size():
		var spot: Vector3 = _wheel_spots[i]
		steer_pivots[i].scale = Vector3.ONE * k
		steer_pivots[i].position = Vector3(spot.x * (1.0 + (k - 1.0) * 0.4), spot.y * k, spot.z)
	body_pivot.position.y = _wheel_radius * (k - 1.0)

func set_paint(color: Color) -> void:
	if not paint_material:
		return
	_paint = color
	_apply_finish()
	_apply_paint()
	_tint_driver()

## The base coat: Martini Racing and Marlboro cars are always white, whatever paint was picked.
func _base_paint() -> Color:
	return Color("#f1f1ec") if livery in WHITE_LIVERIES else _paint

## Gloss, metallic flake or a sponsor livery (Martini Racing, Abarth, Marlboro). Silver, grey and gunmetal paints
## are metallic whatever the choice (the flakes catch the sun under the coat); the metallic finish gives every
## colour a deep flake. The Abarth kit goes over the picked paint and keeps the stripes and door numbers.
func set_livery(value: int) -> void:
	livery = clampi(value, 0, 4)
	if not paint_material:
		return
	_apply_finish()
	_apply_paint()
	_tint_driver()
	_show_livery()
	if is_instance_valid(stripes_node) and livery in WHITE_LIVERIES:
		stripes_node.visible = false
	_sync_bonnet_parts()

## The livery mesh and the racing decals the livery leaves room for.
func _show_livery() -> void:
	for k in livery_nodes:
		(livery_nodes[k] as MeshInstance3D).visible = livery == k and not _ghost
	_sync_bonnet_parts()
	if is_instance_valid(_door_decal_l):
		var shown := not _ghost and _decal_material().albedo_texture != null
		for d in [_door_decal_l, _door_decal_r]:
			d.visible = shown and livery not in WHITE_LIVERIES
		for d in [_hood_decal, _sill_decal_l, _sill_decal_r]: # the Abarth shield and sill band sit where these go
			d.visible = shown and livery < 2
		_hood_decal.visible = _hood_decal.visible and _bonnet_state != 2 # it sits on the bonnet
		for d in [_door_decal_l, _door_decal_r]:
			var pin: Array = _decal_pins.get(d, [])
			if not pin.is_empty() and _panel_state(pin[0]) == 2:
				d.visible = false

func _apply_finish() -> void:
	var color := _base_paint()
	var grey := color.s < 0.3 and color.v > 0.25 and color.v < 0.85
	var flake := grey or livery == 1
	paint_material.metallic = (0.85 if livery == 1 else 0.65) if flake else 0.0
	paint_material.roughness = (0.3 if livery == 1 else 0.42) if flake else 0.36
	paint_material.normal_enabled = true
	paint_material.normal_texture = _shared_resources().peel
	paint_material.normal_scale = 0.12
	if flake:
		paint_material.normal_texture = _shared_resources().flakes
		paint_material.normal_scale = 0.55 if livery == 1 else 0.35
		paint_material.uv1_triplanar = true
		paint_material.uv1_scale = Vector3(14.0, 14.0, 14.0)
	stripe_material.albedo_color = Color.WHITE if color.get_luminance() < 0.42 else Color("#202124")

## Crumples the body, lamps and decals with the model's dent_* blend shapes, easing towards the car's dents.
func _show_dents(target: Dictionary, dt: float) -> void:
	var changed := false
	for k in _dents_shown:
		var goal: float = target.get(k, 0.0)
		var now: float = _dents_shown[k]
		if absf(goal - now) > 0.002:
			_dents_shown[k] = move_toward(now, goal, maxf(dt, 0.001) * 1.5)
			changed = true
	if not changed:
		return
	for e in _shape_idx:
		var mi: MeshInstance3D = e[0]
		var idx: Dictionary = e[1]
		for k in _dents_shown:
			if idx.has("dent_" + k):
				mi.set_blend_shape_value(idx["dent_" + k], _dents_shown[k] * DENT_SCALE)

## The paint keeps its colour at any damage: crashes show as dents, scrapes, cracked glass and torn panels,
## and the clear coat dulls with them. Repair restores the gloss (damage 0).
func _apply_paint() -> void:
	var c := _base_paint()
	c.a = 0.55 if _ghost else 1.0
	paint_material.albedo_color = c
	paint_material.clearcoat = 1.0 - 0.9 * _damage_shown
	paint_material.clearcoat_roughness = 0.03 + 0.4 * _damage_shown
	if _shell:
		# Scale clear-coat horizon band per car: richer/darker cars take full reflection,
		# while bright liveries are toned down to preserve highlight headroom and avoid blowout
		var lum := _base_paint().get_luminance()
		var coat_scale: float = lerpf(1.15, 0.6, smoothstep(0.2, 0.8, lum)) * (1.0 - 0.85 * _damage_shown)
		_shell.set_instance_shader_parameter("coat", coat_scale)
		for name in _panels: # the panels are painted with it
			(_panels[name].parts[0][0] as MeshInstance3D).set_instance_shader_parameter("coat", coat_scale)

## Dress this car as the safety car: white with yellow stripes and an amber light bar on the roof.
func make_safety_car() -> void:
	set_paint(Color("#f4f4f0"))
	set_stripes(true)
	stripe_material.albedo_color = Color("#ffc400")
	number_label.text = "SAFETY CAR"
	number_label.font_size = 16
	if is_instance_valid(_door_decal_l):
		_door_decal_l.visible = false
		_door_decal_r.visible = false
		_hood_decal.visible = false
		_sill_decal_l.visible = false
		_sill_decal_r.visible = false
	var bar := MeshInstance3D.new()
	bar.name = "LightBar"
	bar.mesh = _box(Vector3(1.1, 0.1, 0.22))
	var base := StandardMaterial3D.new()
	base.albedo_color = Color("#1c1c1c")
	bar.material_override = base
	bar.position = Vector3(0, 1.47, 0.3)
	body_pivot.add_child(bar)
	for side in [-1.0, 1.0]:
		var lamp := MeshInstance3D.new()
		lamp.mesh = _box(Vector3(0.44, 0.12, 0.2))
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#ff9d00")
		m.emission_enabled = true
		m.emission = Color("#ff9000")
		m.emission_energy_multiplier = 0.0
		lamp.material_override = m
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamp.position = Vector3(0.28 * side, 1.49, 0.3)
		body_pivot.add_child(lamp)
		_light_bar.append(m)
	_beacon = OmniLight3D.new()
	_beacon.light_color = Color("#ff9a10")
	_beacon.omni_range = 9.0
	_beacon.light_energy = 0.0
	_beacon.position = Vector3(0, 1.76, 0.3)
	_beacon.shadow_enabled = false
	body_pivot.add_child(_beacon)

func set_stripes(enabled: bool) -> void:
	if is_instance_valid(stripes_node):
		stripes_node.visible = enabled and livery not in WHITE_LIVERIES
	_sync_bonnet_parts()

## How far the headlamps are on (0 off .. 1 full) at this much night: the beams (OpenWorld.headlights, the race's pooled
## beams) and the lamp lenses (set_lamps) all follow it, so a lit lens always means a beam and a dark one none.
static func headlamp_level(night: float) -> float:
	return clampf(night * 1.6 - 0.2, 0.0, 1.0)

## The night's ambient on the shared mirror passes and particles (the lamps are per car: set_lamps, from sync).
static func set_night(night: float) -> void:
	_shared_resources() # the stock car's resources (and the shared ones) exist
	for m in _env_materials:
		m.set_shader_parameter("strength", float(m.get_meta("day_strength")) * (1.0 - 0.9 * night))
	var amb := Color(0.12, 0.14, 0.20).lerp(Color(0.52, 0.56, 0.62), 1.0 - night)
	var sun_col := Color(0.08, 0.10, 0.15).lerp(Color(1.0, 0.95, 0.88), 1.0 - night)
	FxParticles.set_environment_lighting(amb, sun_col, Vector3(0.3, 0.8, 0.3))

## The clear coat's horizon band follows the sky the world is showing (set from the player's car each frame).
static func set_sky(top: Color, horizon: Color) -> void:
	var coat: ShaderMaterial = _shared_resources().coat
	if coat.get_meta("sky", []) != [top, horizon]:
		coat.set_meta("sky", [top, horizon])
		for m in _env_materials:
			m.set_shader_parameter("sky_top", top)
			m.set_shader_parameter("sky_horizon", horizon)
		var ambient := horizon.lerp(top, 0.45) * 0.75
		var sun_col := Color(1.05, 0.98, 0.92)
		FxParticles.set_environment_lighting(ambient, sun_col, Vector3(0.42, 0.78, 0.46))
## The sun's direction and colour for the mirror passes (shaders/car_coat.gdshader), read from the world's directional light.
func _update_sun() -> void:
	if not is_instance_valid(_sun):
		var now := Engine.get_process_frames()
		if now - _sun_tried < 180 or not is_inside_tree():
			return
		_sun_tried = now
		for l in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
			if l.visible and (l as DirectionalLight3D).light_energy > 0.0:
				_sun = l
				break
		for e in get_tree().root.find_children("*", "WorldEnvironment", true, false):
			var env: Environment = (e as WorldEnvironment).environment
			if env and env.sky and env.sky.sky_material is ShaderMaterial:
				_sky_mat = env.sky.sky_material
				break
		if not is_instance_valid(_sun):
			return
	if _world == null and _sky_mat and _sky_mat.get_shader_parameter("top_color") is Color:
		set_sky(_sky_mat.get_shader_parameter("top_color"), _sky_mat.get_shader_parameter("horizon_color"))
	var dir := _sun.global_basis.z.normalized() # a light shines along -Z, so the sun lies along +Z
	var power := clampf(_sun.light_energy, 0.0, 2.5) * (1.0 if _sun.visible else 0.0)
	var sig := Vector4(dir.x, dir.y, dir.z, power)
	if sig.distance_squared_to(_sun_sig) > 1e-6:
		_sun_sig = sig
		for m in _env_materials:
			m.set_shader_parameter("sun_dir", dir)
			m.set_shader_parameter("sun_color", _sun.light_color)
			m.set_shader_parameter("sun_power", power)

## The lamps' glowing surfaces, matching the lights the car has on. By day everything is off (dark red tail lenses, a
## dull chrome headlamp) unless braking (bright red, blooming) or reversing (a white bulb behind the lens). After dark
## the headlamps glow with the beams (headlamp_level) and the tail lamps burn dimly as position lights, brighter when
## braking. Cheap to call every frame: the materials change only when the state does.
func set_lamps(night: float, braking := false, reversing := false) -> void:
	if not is_instance_valid(_details_node):
		return
	var head := headlamp_level(night)
	var tail := (0.4 + 0.35 * night) if braking else 0.08 * head # (lower by day and dusk: the sunlit lens is bright already and more clips red to orange)
	var rear_ok := 1.0 if _lamps_broken.z < 1.0 or _lamps_broken.w < 1.0 else 0.0 # (one smashed lens hides its own bulb)
	tail *= rear_ok
	var sig := Vector4(head, tail, 1.0 if braking else 0.0, (1.0 if reversing else 0.0) + 2.0 * rear_ok)
	if sig.is_equal_approx(_lamp_sig):
		return
	_lamp_sig = sig
	tail_material.emission_energy_multiplier = tail * float((_fit.get("tail_lamp", {}) as Dictionary).get("energy", 1.0))
	var bulb := ((2.2 + 1.3 * night) if braking else (2.4 if reversing else 0.5 * head)) * rear_ok
	bulb_material.emission_energy_multiplier = bulb
	bulb_material.emission = BULB_WHITE if reversing and not braking else BULB_RED
	bulb_material.albedo_color = BULB_ON if bulb > 0.0 else BULB_OFF
	# the lens (car_taillamp.gdshader): lit, with a prism glow, when braking; a dim position light after dark
	_details_node.set_instance_shader_parameter("glow", 1.0 if braking else (0.35 if reversing else 0.22 * head))
	# the headlamp reflector's bulb (car_headlamp.gdshader)
	_details_node.set_instance_shader_parameter("lit", 3.6 * head)

## Per-frame presentation. curvature is the road curvature under the car (for rail-driven cars).
func sync(car: RaceCar, dt: float, curvature: float, night: float, ghost: bool) -> void:
	var physical: bool = car.control == "free" and car.phys != null
	if physical:
		# the physics model's own sprung-body roll and pitch
		_roll = car.body_roll
		body_pivot.rotation = Vector3(car.body_pitch, 0.0, -_roll)
	else:
		var lat: float = car.v * car.v * curvature
		_roll += (clampf(-lat * 0.006, -0.07, 0.07) - _roll) * minf(1.0, dt * 5.0)
		var accel := -1.0 if car.brake_on else (0.5 if car.throttle > 0.3 else 0.0)
		body_pivot.rotation = Vector3(accel * 0.012, 0.0, -_roll)

	# each wheel turns at its own speed under physics, so lock-ups and wheelspin show
	for i in 4:
		if physical:
			_spins[i] = fmod(_spins[i] - car.phys.w[i] * dt, TAU)
		else:
			_spins[i] = fmod(_spins[i] - car.speed * dt / _wheel_radius, TAU)
		wheels[i].rotation.x = _spins[i]
	var steer_angle: float = car.steer if car.control == "free" else atan(_wheelbase * curvature) * 1.4
	steer_pivots[0].rotation.y = -steer_angle
	steer_pivots[1].rotation.y = -steer_angle
	_animate_driver(car, dt, steer_angle)

	var reversing: bool = car.control == "free" and car.rev
	set_lamps(night, car.brake_on, reversing)
	if is_player and not _ghost:
		_update_sun()
		if _brake_light == null:
			# a spot behind the bumper shining away from the car, so it lights the road and not the cabin
			_brake_light = SpotLight3D.new()
			_brake_light.light_color = Color(1.0, 0.04, 0.02)
			_brake_light.spot_range = 7.0
			_brake_light.spot_angle = 55.0
			_brake_light.shadow_enabled = false
			_brake_light.light_specular = 0.12 # a red wash on the road; on wet tarmac after dark full specular was a blinding blob
			_brake_light.transform = Transform3D(Basis.looking_at(Vector3(0.0, -0.3, 1.0).normalized()), _fit.brake_light)
			body_pivot.add_child(_brake_light)
		# one power: the sun drowns it by day, the dark shows it; white and softer for the reversing lamp
		_brake_light.light_color = Color(1.0, 0.04, 0.02) if car.brake_on or not reversing else Color(1.0, 0.92, 0.82)
		_brake_light.light_energy = BRAKE_LIGHT_ENERGY if car.brake_on else (BRAKE_LIGHT_ENERGY * 0.6 if reversing else 0.0)
		_sync_headlight_apron(headlamp_level(night))

	if ghost != _ghost:
		_ghost = ghost
		_refresh_driver()
		paint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if ghost else BaseMaterial3D.TRANSPARENCY_DISABLED
		_apply_paint()
		_show_livery()
		if is_instance_valid(_door_decal_l):
			_sunstrip_decal.visible = not ghost
	var hurt := car.damage + car.scuff # (scuff: the cosmetic damage of a race without mechanical damage)
	if hurt - _damage_shown > 0.035 and _fx_near:
		var q: int = _world.quality
		FxParticles.burst(self, "debris", global_position + Vector3(0.0, 0.35, 0.0), 14, q)
		FxParticles.burst(self, "sparks", global_position + Vector3(0.0, 0.25, 0.0), 10, q)
	_show_dents(car.dents, dt)
	_update_damage(car, dt)
	_apply_corner_drop()
	if absf(hurt - _damage_shown) > 0.02:
		_damage_shown = hurt
		_apply_paint()

	if not _light_bar.is_empty():
		# alternating amber flashes while the safety car is on duty
		var t := Time.get_ticks_msec() / 1000.0
		var phase := fmod(t * 2.5, 1.0)
		for i in _light_bar.size():
			var on: bool = car.sc_lights and ((phase < 0.5) == (i == 0))
			_light_bar[i].emission_energy_multiplier = (3.5 + 3.0 * night) if on else 0.0
		_beacon.light_energy = (1.2 + 1.8 * night) if car.sc_lights else 0.0
	_update_fx(car)
	if _previous_throttle > 0.6 and car.throttle < 0.08 and car.rpm > 3200.0 and _fx_near:
		# a pop from the tailpipe tip (build_seicento.py: 0.30 m right, 0.18 m up, behind the bumper) on a sharp lift
		FxParticles.burst(self, "backfire", to_global(_fit.tailpipe), 8, _world.quality)
	_previous_throttle = car.throttle
	if car.last_hit > _hit_seen and _fx_near and DriftStyle.amount(absf(DriftStyle.slip_angle(car.vx, car.vy, car.heading)), absf(car.speed)) > 0.2:
		FxParticles.burst(self, "sparks", global_position + Vector3(0.0, 0.25, 0.0), 14, _world.quality) # a wall touched mid-drift
	_hit_seen = car.last_hit

# ---------------- the driver ----------------
## The figure in the left seat (models/driver.glb, tools/blender/build_driver.py): body, helmet, two arms and a steering wheel that
## replaces the baked-in one (the shared Cabin mesh has it cut out, see _without_wheel). The meshes are shared by every car; each car
## has its own two tinted materials and about six draw calls, and none of it is seen past DRIVER_RANGE. The wheel turns with the
## steering, the hands ride its rim, the head turns into the corner, rolls with it and nods under braking and acceleration.
func _build_driver() -> void:
	var fit: Dictionary = _fit.get("driver", {})
	var parts := _driver_parts()
	if fit.is_empty() or parts.size() < 5:
		return
	_drv_seat = fit.seat
	_drv_hub = fit.wheel
	_drv_wheel_r = fit.wheel_r
	_drv_scale = fit.scale
	_drv_rake = Basis(Vector3.RIGHT, -deg_to_rad(float(fit.rake)))
	_drv_wheel_scale = Basis.from_scale(Vector3.ONE * (_drv_wheel_r / DRIVER_RIM_R))
	_driver = Node3D.new()
	_driver.name = "Driver"
	_driver.position = _drv_seat
	_driver.scale = Vector3.ONE * _drv_scale
	body_pivot.add_child(_driver)
	_drv_suit_mat = _driver_material(0.85, 0.0)
	_drv_helmet_mat = _driver_material(0.3, 0.6)
	_drv_body = _driver_mesh(_driver, "DriverBody", parts["DriverBody"])
	_drv_head = _driver_mesh(_driver, "DriverHead", parts["DriverHead"])
	_drv_neck = _drv_head.position
	_drv_arms.clear()
	_drv_shoulders.clear()
	for name in ["DriverArmL", "DriverArmR"]:
		var arm := _driver_mesh(_driver, name, parts[name])
		_drv_arms.append(arm)
		_drv_shoulders.append(arm.position)
	_drv_wheel = _driver_mesh(body_pivot, "SteeringWheel", parts["SteeringWheel"]) # in the car's frame: it is not scaled with the figure
	_drv_turn = 0.0
	_drv_yaw = 0.0
	_drv_roll = 0.0
	_drv_pitch = 0.0
	_drv_accel = 0.0
	_pose_driver()
	_tint_driver()
	_refresh_driver()

## One of driver.glb's meshes as a node (named after it) under parent, with this car's suit and helmet materials on its surfaces.
func _driver_mesh(parent: Node3D, label: String, part: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = label
	mi.mesh = part.mesh
	mi.position = part.pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = DRIVER_RANGE
	mi.visibility_range_end_margin = 6.0
	var m: Mesh = part.mesh
	for i in m.get_surface_count():
		var mat := m.surface_get_material(i)
		match mat.resource_name if mat else "":
			"Suit":
				mi.set_surface_override_material(i, _drv_suit_mat)
			"Helmet":
				mi.set_surface_override_material(i, _drv_helmet_mat)
	parent.add_child(mi)
	return mi

## A suit or helmet material: the mesh's vertex colours (white cloth, dark gloves and boots) times the tint set per car.
func _driver_material(rough: float, spec: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.metallic_specular = 0.5 if spec <= 0.0 else spec
	if spec > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = 0.7
		m.clearcoat_roughness = 0.12
	return m

## Suit and helmet colours from the car's paint (the Hypercar's AF Corse yellow gives a yellow suit and helmet, the visor dark; a
## white car or livery gets the team colours instead: Martini blue, Marlboro red, a dark navy otherwise, with a white helmet).
func _tint_driver() -> void:
	if _driver == null:
		return
	var base := _base_paint()
	var suit := base
	var helmet := Color.WHITE
	if livery == 2:
		suit = Color("#1d3f8f")
	elif livery == 4:
		suit = Color("#c8102e")
	elif base.s < 0.2 and base.v > 0.55:
		suit = Color("#1c2a4a") # white and silver cars
	else:
		suit = Color.from_hsv(base.h, minf(1.0, base.s * 0.95), base.v * 0.82)
	if suit.get_luminance() > 0.45:
		helmet = base # a bright suit (the yellow Hypercar): a helmet in the paint's colour, which shows against the dark seat
	_drv_suit_mat.albedo_color = suit
	_drv_helmet_mat.albedo_color = helmet

## Shown unless a camera inside the car (or a ghost) would have it in the way; set_driver_visible() is the outside's switch.
func _refresh_driver() -> void:
	if _driver:
		_driver.visible = _driver_shown and not _ghost
		_drv_wheel.visible = _driver_shown and not _ghost

func set_driver_visible(shown: bool) -> void:
	if shown != _driver_shown:
		_driver_shown = shown
		_refresh_driver()

## Moves the wheel, hands and head to the state in _drv_*. No allocations: only Basis, Vector3 and Transform3D values.
func _pose_driver() -> void:
	var wb := _drv_rake * Basis(Vector3.BACK, _drv_turn)
	_drv_wheel.transform = Transform3D(wb * _drv_wheel_scale, _drv_hub)
	_drv_head.transform = Transform3D(Basis.from_euler(Vector3(_drv_pitch, _drv_yaw, _drv_roll)), _drv_neck)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var hand := (_drv_hub + wb * Vector3(side * _drv_wheel_r, 0.0, 0.0) - _drv_seat) / _drv_scale # in the driver's frame
		var rest := Vector3(side * DRIVER_HAND_REST.x, DRIVER_HAND_REST.y, DRIVER_HAND_REST.z)
		var d := hand - _drv_shoulders[i]
		var arm := _drv_arms[i]
		arm.transform = Transform3D(Basis(Quaternion(rest.normalized(), d.normalized())) * (d.length() / rest.length()), _drv_shoulders[i])

## Follows the steering, the lateral and the longitudinal acceleration (smoothed, so a kerb or a bump does not jerk the head).
func _animate_driver(car: RaceCar, dt: float, steer_angle: float) -> void:
	if _driver == null or dt <= 0.0:
		return
	if is_player and _world != null and "camera_mode" in _world:
		set_driver_visible(not (_world.camera_mode in DRIVER_HIDE_CAMERAS))
	if not _driver.visible:
		return
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_squared_to(global_position) > DRIVER_RANGE * DRIVER_RANGE * 1.3:
		return
	var turn_goal := clampf(-steer_angle * DRIVER_STEER_RATIO, -DRIVER_WHEEL_MAX, DRIVER_WHEEL_MAX)
	_drv_turn += (turn_goal - _drv_turn) * minf(1.0, dt * 14.0)
	var ax := clampf((car.speed - _drv_speed) / dt, -16.0, 9.0)
	_drv_speed = car.speed
	var slow := minf(1.0, dt * 4.0)
	_drv_accel += (ax - _drv_accel) * minf(1.0, dt * 6.0)
	_drv_yaw += (clampf(-steer_angle * 1.1, -0.5, 0.5) - _drv_yaw) * slow
	_drv_roll += (clampf(-steer_angle * absf(car.speed) * 0.016, -0.14, 0.14) - _drv_roll) * slow
	_drv_pitch += (clampf(_drv_accel * 0.011, -0.13, 0.09) - _drv_pitch) * slow
	_pose_driver()

static func _driver_parts() -> Dictionary:
	if not _driver_cache.is_empty():
		return _driver_cache
	var root := _load_model(DRIVER_MODEL)
	if root == null:
		return _driver_cache
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		_driver_cache[String(mi.name).split(".")[0]] = {"mesh": (mi as MeshInstance3D).mesh, "pos": (mi as MeshInstance3D).position}
	root.free()
	return _driver_cache

## The Cabin mesh without its baked-in steering wheel (rim, spokes and hub boss, a disc round the hub in the wheel's plane,
## tilted cabin_tilt degrees by tools/blender/build_*.py): the driver brings a wheel that turns. The column stays. A new mesh;
## the shared model is not touched.
static func _without_wheel(mesh: Mesh, fit: Dictionary) -> Mesh:
	var d: Dictionary = fit.get("driver", {})
	if d.is_empty() or mesh.get_surface_count() == 0:
		return mesh
	var tilt := deg_to_rad(float(d.cabin_tilt))
	var normal := Vector3(0.0, sin(tilt), cos(tilt)) # Blender (0, -cos, sin) in Godot's frame
	var hub: Vector3 = d.wheel
	var reach: float = float(d.wheel_r) + 0.03
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if index.is_empty():
			index = PackedInt32Array(range(verts.size()))
		var kept := PackedInt32Array()
		for t in range(0, index.size() - 2, 3):
			var c := (verts[index[t]] + verts[index[t + 1]] + verts[index[t + 2]]) / 3.0 - hub
			var along := c.dot(normal)
			if absf(along) < 0.018 and (c - normal * along).length() < reach:
				continue
			kept.append(index[t])
			kept.append(index[t + 1])
			kept.append(index[t + 2])
		if kept.is_empty():
			continue # a surface that was only wheel (the yellow marker, the badge)
		arrays[Mesh.ARRAY_INDEX] = kept
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(s))
	return out

# ---------------- tyre smoke, spray and kick-up ----------------
## Effect strengths from what the car is doing and what it drives on. Bots only show them near the camera
## (none on the Low preset), and every emitter is made the first time it is needed.
func _update_fx(car: RaceCar) -> void:
	if not _fx_checked:
		_fx_checked = true
		var w := get_node_or_null("../..")
		if get_parent() and get_parent().name == "Cars" and w and "race" in w and "quality" in w:
			_world = w
	if not _world:
		return
	var race = _world.race
	if is_player and "sky_top_color" in _world:
		set_sky(_world.sky_top_color, _world.sky_horizon_color)
	var want := {}
	_fx_near = false
	if race and not _ghost and visible:
		var cam := get_viewport().get_camera_3d()
		var reach: float = FX_REACH[clampi(_world.quality, 0, FX_REACH.size() - 1)]
		if is_player or (cam and cam.global_position.distance_squared_to(global_position) < reach * reach):
			_fx_near = true
			want = _fx_strengths(race, car)
	_apply_fx(want)

## Effect strengths set from outside a race (the open world: OpenWorld works them out with surface_fx()).
func set_fx(want: Dictionary) -> void:
	if _world == null and visible:
		_apply_fx(want)

func _apply_fx(want: Dictionary) -> void:
	for kind in want:
		if want[kind] > 0.02 and not _fx.has(kind):
			_fx[kind] = _make_emitter(kind)
	for kind in _fx:
		var k: float = want.get(kind, 0.0)
		var p: GPUParticles3D = _fx[kind]
		p.emitting = k > 0.02
		if p.emitting:
			p.amount_ratio = clampf(k, 0.05, 1.0)

static func _fx_strengths(race, car: RaceCar) -> Dictionary:
	var v := absf(car.speed)
	if v < 1.5:
		return {}
	# what the outer wheels run on: off the tarmac onto grass or gravel, or a loose rally stage
	var tr: Track = race.track
	var side := signf(car.d) if car.d != 0.0 else 1.0
	var surf: int = race.surface_at(car, car.x + tr.sample(tr.NX, car.s) * side * 0.65,
		car.y + tr.sample(tr.NY, car.s) * side * 0.65)
	var loose: bool = race.s != null and race.s.surface != "tarmac"
	return surface_fx(surf, v, car.slip, race.weather.wet, race.weather.snow, loose, absf(DriftStyle.slip_angle(car.vx, car.vy, car.heading)))

## Effect strengths (kind -> 0..1) for a car at speed v (m/s) with tyre slip `slip` on surface surf (Physics.SURF_*),
## in weather this wet and snowy; loose: the whole road is a loose rally stage; angle: the slip angle (rad, a drift
## smokes more the deeper and faster it is).
static func surface_fx(surf: int, v: float, slip: float, wet: float, snow: float, loose: bool, angle := 0.0) -> Dictionary:
	var out := {}
	if v < 1.5:
		return out
	var go := smoothstep(3.0, 22.0, v)
	if surf == Physics.SURF_GRAVEL:
		out.gravel = go * (1.0 - 0.7 * wet)
	elif surf == Physics.SURF_GRAVEL_ROAD:
		# a gravel road: a pale cloud, and stones flicked up by the tyres, more of them in a slide
		out.gravel_dust = go * (1.0 - 0.7 * wet)
		out.grit = go * clampf(0.25 + 0.6 * slip, 0.0, 0.85)
	elif surf == Physics.SURF_DIRT or (loose and surf != Physics.SURF_GRASS):
		out.dust = go * (1.0 - 0.7 * wet) # a dirt road, or anything but grass on a loose rally stage
	elif surf == Physics.SURF_GRASS:
		out.grass = go
	else:
		out.spray = wet * smoothstep(6.0, 32.0, v)
		if snow > 0.2:
			out.snow = snow * smoothstep(5.0, 25.0, v)
		if wet > 0.35 and v > 9.0:
			out.splash = wet * smoothstep(9.0, 28.0, v)
	# tyre smoke: wheelspin, lock-ups and slides on a dry paved road (the wet road sprays, loose ground throws dust)
	if wet < 0.5 and not loose and not out.has("gravel") and not out.has("dust") and not out.has("gravel_dust") and not out.has("grass"):
		var spin := clampf((slip - 0.3) / 0.6, 0.0, 1.0) * smoothstep(2.0, 8.0, v)
		var drift := DriftStyle.amount(angle, v) * (0.55 + 0.45 * smoothstep(8.0, 25.0, v))
		out.smoke = maxf(spin, drift) * (1.0 - wet * 1.6)
	return out

const PRESET_FOR_KIND := {
	"spray": "spray",
	"smoke": "smoke",
	"dust": "kickup_dirt",
	"gravel_dust": "kickup_gravel_dust",
	"grit": "kickup_grit",
	"grass": "kickup_grass",
	"snow": "kickup_snow",
	"gravel": "kickup_gravel",
	"splash": "splash",
}

func _make_emitter(kind: String) -> GPUParticles3D:
	var preset: String = PRESET_FOR_KIND.get(kind, kind)
	if FxParticles.PRESETS.has(preset):
		var q: int = _world.quality if is_instance_valid(_world) and "quality" in _world else fx_quality
		var p := FxParticles.attach(self, preset, q, 1.0 if is_player else 0.7)
		if p:
			p.position = _fit.fx_axle
			return p
	var sh := _shared_resources()
	var spec: Dictionary = FX_KINDS[kind]
	var p := GPUParticles3D.new()
	p.name = "Fx_" + kind
	p.amount = spec.amount
	p.lifetime = spec.life
	p.randomness = 0.3
	p.local_coords = false # puffs stay where they were thrown while the car drives on
	p.process_material = sh.fx[kind]
	p.draw_pass_1 = sh.puff
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-30, -3, -30), Vector3(60, 14, 90))
	p.position = _fit.fx_axle
	p.emitting = false
	add_child(p)
	return p

## WRC 3DS kickup_*.lua for reference: 30-60 particles, 1-1.5 s, 0.4-2 m, alpha 0.65-0.75 fading out,
## 25-50 % of the car's speed inherited. Spray and smoke are fuller (and grow) to read from the chase camera.
const FX_KINDS := {
	"spray": {"amount": 44, "life": 0.9, "colour": Color(0.86, 0.89, 0.92, 0.42), "speed": [2.5, 6.0], "up": 0.45,
		"gravity": 5.0, "damp": 2.0, "inherit": 0.3, "scale": [0.7, 1.1], "grow": 2.8},
	"smoke": {"amount": 36, "life": 1.8, "colour": Color(0.93, 0.93, 0.94, 0.5), "speed": [0.6, 2.0], "up": 0.6,
		"gravity": -0.5, "damp": 1.2, "inherit": 0.15, "scale": [0.6, 1.0], "grow": 4.0},
	"dust": {"amount": 40, "life": 1.8, "colour": Color(0.80, 0.71, 0.59, 0.6), "speed": [1.5, 4.0], "up": 0.55,
		"gravity": 0.6, "damp": 1.5, "inherit": 0.25, "scale": [0.7, 1.2], "grow": 3.2},
	"grass": {"amount": 30, "life": 1.0, "colour": Color(0.40, 0.38, 0.26, 0.5), "speed": [2.0, 5.0], "up": 0.7,
		"gravity": 6.0, "damp": 1.0, "inherit": 0.3, "scale": [0.4, 0.7], "grow": 2.0},
	"snow": {"amount": 30, "life": 1.0, "colour": Color(0.97, 0.98, 1.0, 0.7), "speed": [1.5, 3.5], "up": 0.5,
		"gravity": 1.5, "damp": 1.5, "inherit": 0.25, "scale": [0.5, 0.7], "grow": 2.6},
}

# ---------------- shared geometry ----------------
static func _shared_resources(key := "stock") -> Dictionary:
	if key == "stock" and not _shared.is_empty():
		return _shared
	if key != "stock" and _shared_cars.has(key):
		return _shared_cars[key]
	var fit: Dictionary = CarCatalog.visual(key)
	var common: Dictionary = {} if key == "stock" else _shared_resources("stock") # the model-independent resources are made once
	# Local frame: -Z forward, +X right, +Y up; the model's origin is on the ground midway between the axles.
	var meshes := {}
	var root := _load_model(fit.model)
	if root:
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			meshes[mi.name] = (mi as MeshInstance3D).mesh
		root.free()
	var shell: Mesh = meshes.get("Body", BoxMesh.new())
	var cabin: Mesh = _without_wheel(meshes.get("Cabin", ArrayMesh.new()), fit)
	var details: Mesh = meshes.get("Details", BoxMesh.new())

	# the Details mesh and the panels' Details pieces cut from it (a bumper took the plate and the grille with it): the
	# plastics, plates, grilles and chrome below are set on all of them
	var dmeshes: Array = [details]
	for name in PANELS:
		if meshes.has(name + "Details"):
			dmeshes.append(meshes[name + "Details"])
	# the material each Details surface came with, by name, so the panels' Details pieces get what the Details mesh gets
	var detail_slots := {}
	for i in details.get_surface_count():
		var dm := details.surface_get_material(i)
		if dm:
			detail_slots[dm.resource_name] = i
	# Glass and headlights are the same on every car, so they live on the shared meshes.
	var glass := StandardMaterial3D.new() # tinted dark and glossy, see-through face-on with Fresnel sky reflection at grazing angles
	glass.resource_name = "Glass"
	glass.albedo_color = Color(0.01, 0.014, 0.018, 0.56)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.roughness = 0.02
	glass.metallic_specular = 0.6
	glass.clearcoat_enabled = false
	glass.next_pass = _env_material(0.85, 0.035, 0.0, false, 1.2)
	var head := ShaderMaterial.new() # the reflector bowl (car_headlamp.gdshader): dark chrome facets, a bulb that lights at night
	head.shader = load("res://shaders/car_headlamp.gdshader")
	head.resource_name = "Headlight" # still found by name (_surface) once it replaces the glTF's material on the mesh
	var glass_surface := _surface(shell, "Glass")
	if glass_surface >= 0:
		shell.surface_set_material(glass_surface, glass)
	var lens := ShaderMaterial.new() # clear polycarbonate cover with soft front-only headlamp scatter at night
	lens.shader = load("res://shaders/car_lamp_glass.gdshader")
	lens.resource_name = "LampGlass"
	lens.next_pass = _env_material(1.0, 0.12, 0.0, false)
	var lens_surface := _surface(details, "LampGlass")
	if lens_surface >= 0:
		details.surface_set_material(lens_surface, lens)
	var red_glass := ShaderMaterial.new() # the tail lamps' moulded red lens (car_taillamp.gdshader): prisms, a hard sheen, a glow
	red_glass.shader = load("res://shaders/car_taillamp.gdshader")
	var tl: Dictionary = fit.get("tail_lamp", {}) # a catalogue car's own lens (the shader's defaults are the Seicento's)
	for k in ["tint", "alpha_off", "alpha_lit", "glow_gain", "sheen"]:
		if tl.has(k):
			red_glass.set_shader_parameter(k, tl[k])
	red_glass.next_pass = _env_material(float(tl.get("reflect", 1.0)), 0.12, 0.0, false) # the sky in the lens
	var tail_glass_surface := _surface(details, "TailGlass")
	if tail_glass_surface >= 0:
		details.surface_set_material(tail_glass_surface, red_glass)
	var liveries := {}
	for k in LIVERY_MESHES:
		var lm: Mesh = meshes.get(LIVERY_MESHES[k], ArrayMesh.new())
		for i in lm.get_surface_count():
			var mm := lm.surface_get_material(i) as StandardMaterial3D
			if mm:
				mm = mm.duplicate()
				mm.clearcoat_enabled = true
				mm.clearcoat = 0.8
				mm.clearcoat_roughness = 0.05
				mm.roughness = 0.35
				lm.surface_set_material(i, mm)
		liveries[k] = lm
	var head_surface := _surface(details, "Headlight")
	var bezel_surface := _surface(details, "LampBezel")
	var lamp_info := _lamp_bounds(details, head_surface) if head_surface >= 0 else {"centre": Vector2(0.40, 0.64), "half": Vector2(0.18, 0.055), "beam_pos": Vector3(0.50, 0.64, -1.75)}
	var lamp_centre: Vector2 = lamp_info.centre if fit.model != CarCatalog.STOCK_VISUAL.model else Vector2(0.40, 0.64)
	var lamp_half: Vector2 = lamp_info.half
	if head_surface >= 0:
		details.surface_set_material(head_surface, head)
		head.set_shader_parameter("lamp_half", lamp_half)
		head.set_shader_parameter("twin_bowl", 1.0 if bezel_surface >= 0 else 0.0)
		if fit.model != CarCatalog.STOCK_VISUAL.model: # (the Seicento keeps the shader's hand-placed bulb)
			head.set_shader_parameter("centre", lamp_centre)
	if bezel_surface >= 0:
		var old_bezel := details.surface_get_material(bezel_surface) as BaseMaterial3D
		var bezel := ShaderMaterial.new() # inner headlamp bezel: satin metallic by day, catches warm bulb spill at night
		bezel.shader = load("res://shaders/car_headlamp_bezel.gdshader")
		bezel.resource_name = "LampBezel"
		bezel.set_shader_parameter("centre", lamp_centre)
		bezel.set_shader_parameter("lamp_half", lamp_half)
		if old_bezel:
			bezel.set_shader_parameter("base_color", old_bezel.albedo_color)
		details.surface_set_material(bezel_surface, bezel)
	if lens_surface >= 0:
		lens.set_shader_parameter("centre", lamp_centre)
		lens.set_shader_parameter("lamp_half", lamp_half)
	# Unpainted plastic (bumpers, sills, trim, gaskets): the world's warm sun, ACES and the car's reflection probe lifted the
	# glTF's dark grey to tan, so these get an explicit near-black, satin, low-specular material.
	for pair in [[dmeshes, "Bumper", 0.21, 0.55], [dmeshes, "Trim", 0.10, 0.5], [dmeshes, "Gasket", 0.07, 0.8],
			[[shell], "Trim", 0.10, 0.5], [[shell], "Gasket", 0.07, 0.8]]:
		if _has_surface(pair[0], pair[1]):
			var plastic := StandardMaterial3D.new()
			plastic.resource_name = pair[1]
			plastic.albedo_color = Color(pair[2] * 0.95, pair[2] * 0.97, pair[2])
			plastic.roughness = pair[3]
			plastic.metallic_specular = 0.22
			_set_surfaces(pair[0], pair[1], plastic)
	if _has_surface(dmeshes, "Plate"):
		var plate := ShaderMaterial.new() # a Polish plate from the atlas on the bumpers (car_plate.gdshader)
		plate.resource_name = "Plate"
		plate.shader = load("res://shaders/car_plate.gdshader")
		plate.set_shader_parameter("atlas", load("res://textures/car/plate_pl.png"))
		plate.set_shader_parameter("rows", float(PLATE_ROWS))
		if fit.has("plate_y"): # a catalogue car's plates sit elsewhere than the Seicento's
			var py: Vector3 = fit.plate_y
			plate.set_shader_parameter("y0_front", py.x)
			plate.set_shader_parameter("y0_rear", py.y)
			plate.set_shader_parameter("y_max", py.z)
		_set_surfaces(dmeshes, "Plate", plate)
	if _has_surface(dmeshes, "Grille"):
		var grille := ShaderMaterial.new() # the air intake's black diamond mesh (car_grille.gdshader)
		grille.resource_name = "Grille"
		grille.shader = load("res://shaders/car_grille.gdshader")
		_set_surfaces(dmeshes, "Grille", grille)
	if _has_surface(dmeshes, "Chrome"):
		# satin-polished automotive chrome: crisp metallic trim without a blinding sun-glare bloom blob across grilles
		var chrome := StandardMaterial3D.new()
		chrome.resource_name = "Chrome"
		chrome.albedo_color = Color(0.54, 0.56, 0.59)
		chrome.metallic = 0.52
		chrome.roughness = 0.44
		chrome.metallic_specular = 0.12
		_set_surfaces(dmeshes, "Chrome", chrome)

	# Soft dark ellipse under the car keeps it sitting on the road: a dense core under the floor (ambient
	# occlusion) and a wide soft falloff past the sills and bumpers.
	var contact := PlaneMesh.new()
	contact.size = fit.contact
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.5, 0.78, 1.0])
	fade.colors = PackedColorArray([Color(0, 0, 0, 0.82), Color(0, 0, 0, 0.72), Color(0, 0, 0, 0.3), Color(0, 0, 0, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = fade
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	var contact_mat := StandardMaterial3D.new()
	contact_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	contact_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	contact_mat.albedo_texture = tex
	contact_mat.albedo_color = Color.WHITE
	contact.material = contact_mat

	# the loose panels (RaceCarVisual._build_panel) and the glass that breaks: dressed as the Body and the Details they
	# were cut from
	var panels := {}
	for name in PANELS:
		var pm: Mesh = meshes.get(name)
		if pm == null:
			continue
		_dress_like(pm, shell, {})
		var pieces := {}
		for k in PANEL_PIECES:
			if meshes.has(name + k):
				pieces[k] = meshes[name + k]
				if k == "Details":
					_dress_like(pieces[k], details, detail_slots)
				elif k != "Stripes":
					var lm: Mesh = liveries.get(LIVERY_MESHES.find_key(k), null)
					if lm:
						_dress_like(pieces[k], lm, {})
		panels[name] = {"mesh": pm, "paint": maxi(0, _surface(pm, "Paint")), "pieces": pieces, "top": _top_point(pm)}
	var glass_meshes := {}
	var screen := ShaderMaterial.new() # the windscreen cracks (car_windscreen.gdshader), with the glass's reflection
	screen.shader = load("res://shaders/car_windscreen.gdshader")
	screen.resource_name = "Glass"
	screen.next_pass = glass.next_pass
	for name in GLASS:
		if meshes.has(name):
			var gm: Mesh = meshes[name]
			var gs := _surface(gm, "Glass")
			if gs >= 0:
				gm.surface_set_material(gs, screen if name == "Windscreen" else glass)
			glass_meshes[name] = gm
	var scrape: Array = common.get("scrape") if not common.is_empty() else _scrape_textures()
	var made := {"shell": shell, "details": details, "cabin": cabin, "panels": panels, "glass": glass_meshes,
		"scrape": scrape, "scrape_albedo": scrape[0], "scrape_orm": scrape[1],
		"flakes": common.get("flakes") if not common.is_empty() else _flake_texture(), "peel": common.get("peel") if not common.is_empty() else _peel_texture(),
		"coat": common.get("coat") if not common.is_empty() else _coat_material(), "puff": common.get("puff") if not common.is_empty() else _puff_mesh(),
		"fx": common.get("fx") if not common.is_empty() else _fx_materials(), "stripes": meshes.get("Stripes", BoxMesh.new()), "liveries": liveries,
		"wheel": meshes.get("Wheel", BoxMesh.new()), "contact": contact, "head": head, "beam_pos": lamp_info.beam_pos, "nose_z": shell.get_aabb().position.z,
		"paint_surface": maxi(0, _surface(shell, "Paint")), "tail_surface": maxi(0, _surface(details, "Taillight")), "bulb_surface": _surface(details, "TailBulb")}
	if key == "stock":
		_shared = made
	else:
		_shared_cars[key] = made
	return made

static func _has_surface(list: Array, material_name: String) -> bool:
	return list.any(func(m: Mesh) -> bool: return _surface(m, material_name) >= 0)

## Sets mat on the surface named material_name (the glTF's material) of every mesh in list that has one.
static func _set_surfaces(list: Array, material_name: String, mat: Material) -> void:
	for m in list:
		var i := _surface(m as Mesh, material_name)
		if i >= 0:
			(m as Mesh).surface_set_material(i, mat)

## Gives a cut-out piece's surfaces the materials the mesh it came from has by now (by the glTF material's name; slots:
## that mesh's surfaces by their original names, when its materials were replaced by unnamed ones).
static func _dress_like(piece: Mesh, ref: Mesh, slots: Dictionary) -> void:
	for i in piece.get_surface_count():
		var m := piece.surface_get_material(i)
		if m == null or m.resource_name == "" or m is ShaderMaterial: # (already dressed: a plate, a grille)
			continue
		var j: int = slots.get(m.resource_name, _surface(ref, m.resource_name))
		if j >= 0 and j < ref.get_surface_count() and ref.surface_get_material(j):
			piece.surface_set_material(i, ref.surface_get_material(j))

## The highest point of a mesh (a tailgate hinges at its top).
static func _top_point(mesh: Mesh) -> Vector3:
	var best := Vector3(0.0, -INF, 0.0)
	for v in mesh.get_faces():
		if v.y > best.y:
			best = v
	return best

## Bare metal scraped through the paint, for the scrape decals: [albedo (alpha: where the paint is gone), ORM (metallic)].
## Streaks run along the texture's X (along the blow), ragged at the ends, with flakes of primer round them.
static func _scrape_textures() -> Array:
	const W := 128
	const H := 64
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	noise.fractal_octaves = 3
	var streak := FastNoiseLite.new()
	streak.frequency = 0.02
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var orm := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for y in H:
		for x in W:
			var u := (float(x) + 0.5) / W * 2.0 - 1.0
			var v := (float(y) + 0.5) / H * 2.0 - 1.0
			var lines := 0.5 + 0.5 * sin(float(y) * 1.9 + 6.0 * streak.get_noise_2d(x * 0.2, y * 3.0)) # scratches along X
			var body := 1.0 - smoothstep(0.55, 1.0, sqrt(u * u * 0.8 + v * v * 1.2) + 0.35 * noise.get_noise_2d(x, y * 2.0))
			var a := clampf(body * (0.55 + 0.45 * lines), 0.0, 1.0)
			var rim := clampf(body * 4.0, 0.0, 1.0) * (1.0 - clampf(body * 1.6, 0.0, 1.0)) # primer round the bare patch
			var metal := 0.4 + 0.16 * lines + 0.06 * noise.get_noise_2d(x * 3.0, y)
			var c := Color(metal, metal * 1.01, metal * 1.04).lerp(Color(0.5, 0.48, 0.44), rim * 0.8)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
			orm.set_pixel(x, y, Color(1.0, lerpf(0.3, 0.6, 1.0 - lines) + rim * 0.3, 0.9 * (1.0 - rim), a))
	img.generate_mipmaps()
	orm.generate_mipmaps()
	return [ImageTexture.create_from_image(img), ImageTexture.create_from_image(orm)]

## The mirror pass (shaders/car_coat.gdshader) over the paint, glass and lamp lenses: a crisp horizon and sun glint on top of
## the sky's soft radiance. Every one made here is kept in "env" so the world's sky, the sun and the night reach all of them.
## strength is the weight at full day (set_night takes it down), f0 the reflectance face-on.
static func _env_material(strength: float, f0: float, priority: float, vertex_colour: bool, exposure := 1.7) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/car_coat.gdshader")
	m.set_shader_parameter("f0", f0)
	m.set_shader_parameter("exposure", exposure)
	m.set_shader_parameter("use_vertex_color", 1.0 if vertex_colour else 0.0)
	m.render_priority = int(priority) + 1
	m.set_meta("day_strength", strength)
	m.set_shader_parameter("strength", strength)
	_env_materials.append(m)
	return m

static func _coat_material() -> ShaderMaterial:
	return _env_material(1.0, 0.06, 0.0, true)

## Metallic flake: a fine bumpy normal map, tiled triplanar (the model has no UVs) at a few millimetres a flake.
static func _peel_texture() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.05
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 3.0
	tex.noise = noise
	return tex

static func _flake_texture() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.18
	noise.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	var tex := NoiseTexture2D.new()
	tex.width = 128
	tex.height = 128
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 2.0
	tex.noise = noise
	return tex

## One soft, lumpy puff (a billboard quad) shared by every effect; the process materials colour it.
static func _puff_mesh() -> QuadMesh:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.09
	noise.fractal_octaves = 3
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var r := Vector2(x - 31.5, y - 31.5).length() / 31.5
			var a := (1.0 - smoothstep(0.25, 1.0, r)) * clampf(0.7 + 0.6 * noise.get_noise_2d(x, y), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX # lit by sun and sky, dark at night, cheap
	m.disable_receive_shadows = true
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.proximity_fade_enabled = true # soft where a puff meets the road
	m.proximity_fade_distance = 0.5
	var quad := QuadMesh.new()
	quad.material = m
	return quad

static func _fx_materials() -> Dictionary:
	var out := {}
	var fade := Gradient.new() # quick fade in, long fade out (alpha over a puff's life)
	fade.offsets = PackedFloat32Array([0.0, 0.12, 0.45, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	for kind in FX_KINDS:
		var spec: Dictionary = FX_KINDS[kind]
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(0.6, 0.03, 0.12)
		pm.direction = Vector3(0.0, spec.up, 1.0).normalized()
		pm.spread = 24.0
		pm.initial_velocity_min = spec.speed[0]
		pm.initial_velocity_max = spec.speed[1]
		pm.gravity = Vector3(0.0, -spec.gravity, 0.0)
		pm.damping_min = spec.damp * 0.7
		pm.damping_max = spec.damp
		pm.inherit_velocity_ratio = spec.inherit
		pm.angle_min = -180.0
		pm.angle_max = 180.0
		pm.angular_velocity_min = -40.0
		pm.angular_velocity_max = 40.0
		pm.scale_min = spec.scale[0]
		pm.scale_max = spec.scale[1]
		var grow := Curve.new()
		grow.max_value = spec.grow
		grow.add_point(Vector2(0.0, 1.0))
		grow.add_point(Vector2(1.0, spec.grow), 0.0, 0.0)
		var grow_tex := CurveTexture.new()
		grow_tex.curve = grow
		pm.scale_curve = grow_tex
		pm.color = spec.colour
		pm.color_ramp = ramp
		out[kind] = pm
	return out

## The imported model when the editor has imported it, otherwise the GLB read directly (fresh checkouts).
static func _load_model(path := MODEL_PATH) -> Node:
	if ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed:
			return packed.instantiate()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), state) != OK:
		push_error("Car model %s could not be read" % path)
		return null
	return doc.generate_scene(state)

## The middle, half-size and beam origin of the right-hand headlamp (x > 0, in the model's frame) from a surface.
static func _lamp_bounds(mesh: Mesh, surface: int) -> Dictionary:
	var verts: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in verts:
		if v.x > 0.0:
			lo = lo.min(v)
			hi = hi.max(v)
	if lo.x >= INF:
		return {"centre": Vector2(0.40, 0.64), "half": Vector2(0.18, 0.055), "beam_pos": Vector3(0.50, 0.64, -1.75)}
	var c := Vector2((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5)
	var half := Vector2(maxf((hi.x - lo.x) * 0.5, 0.04), maxf((hi.y - lo.y) * 0.5, 0.03))
	var bp := Vector3(clampf(c.x, 0.42, 0.72), clampf(c.y, 0.58, 0.78), lo.z - 0.05)
	return {"centre": c, "half": half, "beam_pos": bp}

## The middle of the right-hand lamp of a surface (x > 0, in the model's frame) as (x, y): where car_headlamp.gdshader puts
## its bulb, so each car's reflector lights round its own lamp.
static func _lamp_centre(mesh: Mesh, surface: int) -> Vector2:
	return _lamp_bounds(mesh, surface).centre

## Keeps the player's near-bumper dipped apron light and ground beam pool in step with nightfall (and hides both if a
## probe explicitly switched off the parent's open-world SpotLight3D beams).
func _sync_headlight_apron(head: float) -> void:
	if head <= 0.0 and _near_beam == null and _beam_pool == null:
		return # daytime and never lit: no children scan, no resource lookup every frame
	var has_spot := false
	var any_spot_on := false
	for c in get_children():
		if c is SpotLight3D and (c as SpotLight3D).position.z < 0.0:
			has_spot = true
			if c.visible:
				any_spot_on = true
	var on := head > 0.0 and (not has_spot or any_spot_on)
	if not on and _near_beam == null and _beam_pool == null:
		return
	var sh := _shared_resources(car_key)
	var bp: Vector3 = sh.get("beam_pos", Vector3(0.52, 0.66, -1.78))
	var nose_z: float = minf(bp.z, float(sh.get("nose_z", bp.z)))
	if _near_beam == null:
		_near_beam = SpotLight3D.new()
		_near_beam.name = "HeadlightApron"
		_near_beam.position = Vector3(0.0, 0.48, nose_z - 0.08) # clear of the protruding nose/grille on every car
		_near_beam.rotation = Vector3(deg_to_rad(-48.0), 0.0, 0.0) # top edge -2 deg (below horizontal: never hits walls)
		_near_beam.spot_range = 10.0
		_near_beam.spot_angle = 46.0
		_near_beam.spot_angle_attenuation = 2.2
		_near_beam.spot_attenuation = 1.5
		_near_beam.light_specular = 0.08
		_near_beam.light_color = Color(1.0, 0.95, 0.84)
		_near_beam.shadow_enabled = false
		body_pivot.add_child(_near_beam)
	if _beam_pool == null:
		_beam_pool = Decal.new()
		_beam_pool.name = "HeadlightPool"
		_beam_pool.size = Vector3(13.5, 5.0, 36.0)
		_beam_pool.position = Vector3(0.0, -0.5, nose_z - 18.0) # starts right ahead of the bumper, reaches 36 m forward
		_beam_pool.texture_emission = _headlight_pool_texture()
		_beam_pool.albedo_mix = 0.0
		_beam_pool.modulate = Color(1.0, 0.94, 0.80)
		_beam_pool.upper_fade = 0.45
		_beam_pool.lower_fade = 0.45
		_beam_pool.normal_fade = 0.65 # horizontal road and verges only, never vertical walls or buildings
		body_pivot.add_child(_beam_pool)
	var working := 1.0 - 0.5 * (_lamps_broken.x + _lamps_broken.y) # smashed headlamps throw no light
	on = on and working > 0.0
	_near_beam.visible = on
	_near_beam.light_energy = 2.6 * head * working if on else 0.0
	_beam_pool.visible = on
	_beam_pool.emission_energy = 0.78 * head * working if on else 0.0

## Shared twin-headlamp low-beam road pool texture (Decal.texture_emission): two overlapping cones flaring smoothly from
## just ahead of the front bumper out to ~36 m, with a soft ECE kerb reach on the right and soft Gaussian edges.
static func _headlight_pool_texture() -> ImageTexture:
	var sh := _shared_resources()
	if sh.has("beam_pool"):
		return sh["beam_pool"]
	const N := 128
	const WIDTH := 13.5
	const LENGTH := 36.0
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	for y in N:
		var v := (float(y) + 0.5) / float(N)
		var d := (1.0 - v) * LENGTH # 0 m at front bumper (v=1), LENGTH m far ahead (v=0)
		var start_in := smoothstep(0.0, 0.65, d)
		var near_trim := lerpf(0.62, 1.0, smoothstep(0.5, 5.5, d)) # gentle right at bumper where SpotLight3Ds are close
		var hw := 0.52 + d * 0.21 # cone half-width flaring gently with distance
		for x in N:
			var u := (float(x) + 0.5) / float(N)
			var xm := (u - 0.5) * WIDTH # metres right of car centreline
			# Slight right-hand-traffic ECE kerb reach on the right side
			var reach := LENGTH * (1.0 + 0.14 * smoothstep(-0.5, 3.0, xm))
			var along := pow(clampf(1.0 - d / reach, 0.0, 1.0), 1.2)
			var left := exp(-pow((xm + 0.56) / hw, 2.0))
			var right := exp(-pow((xm - 0.56) / hw, 2.0))
			var fan := clampf((left + right) * 0.68, 0.0, 1.0)
			var edge_x := smoothstep(WIDTH * 0.5, WIDTH * 0.36, absf(xm))
			var val := clampf(fan * start_in * near_trim * along * edge_x, 0.0, 1.0)
			img.set_pixel(x, y, Color(val, val, val, 1.0))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	sh["beam_pool"] = tex
	return tex

## Index of the surface whose material has this name (from Blender), or -1.
static func _surface(mesh: Mesh, material_name: String) -> int:
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if m and m.resource_name == material_name:
			return i
	return -1

static func _box(size: Vector3) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	return box

## One vertex-coloured surface from [primitive, position, rotation (x angle or Basis), colour] parts.
static func _merge(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for part in parts:
		var basis: Basis = part[2] if part[2] is Basis else Basis(Vector3.RIGHT, part[2])
		var arrays: Array = (part[0] as PrimitiveMesh).get_mesh_arrays()
		var pv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var pi: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var xf := Transform3D(basis, part[1])
		var base := verts.size()
		for i in pv.size():
			verts.append(xf * pv[i])
			normals.append((basis * pn[i]).normalized())
			colors.append(part[3])
		for i in pi:
			indices.append(base + i)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	out[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh

func _update_decals() -> void:
	if not is_instance_valid(_door_decal_l):
		return
	var idx := clampi(car_number, 1, 99) - 1
	var door_m := _door_plate_mesh(idx)
	_door_decal_l.mesh = door_m
	_door_decal_r.mesh = door_m
	# 1-16 are cells of the atlas; above that a blank plate plus digit glyphs (car_door_plates.png) has its own material
	var door_mat := _decal_material() if idx < 16 else _door_plates_material()
	_door_decal_l.material_override = door_mat
	_door_decal_r.material_override = door_mat
	_sunstrip_decal.mesh = _sunstrip_mesh(idx % 4)
	_hood_decal.mesh = _hood_plate_mesh(idx % 4)
	var sill_m := _sill_stack_mesh(idx % 4)
	_sill_decal_l.mesh = sill_m
	_sill_decal_r.mesh = sill_m

const DECALS_TEX_PATH := "res://models/car_decals.png"

static func _decal_material() -> StandardMaterial3D:
	var sh := _shared_resources()
	if not sh.has("decal_mat"):
		var m := StandardMaterial3D.new()
		var tex = load(DECALS_TEX_PATH) as Texture2D
		if tex:
			m.albedo_texture = tex
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		# vinyl, not paint: a soft sheen, so the sky reflection doesn't wash the print out
		m.roughness = 0.6
		m.metallic_specular = 0.3
		m.render_priority = 2
		sh["decal_mat"] = m
	return sh["decal_mat"]

const DOOR_PLATES_TEX_PATH := "res://models/car_door_plates.png"

static func _door_plates_material() -> StandardMaterial3D:
	var sh := _shared_resources()
	if not sh.has("door_plates_mat"):
		var m := _decal_material().duplicate() as StandardMaterial3D
		m.albedo_texture = load(DOOR_PLATES_TEX_PATH) as Texture2D
		sh["door_plates_mat"] = m
	return sh["door_plates_mat"]

## Door number 17-99: the blank plate for that header variant and one quad per digit, laid out like the atlas plates
## (0.30 m per 256 px; the number area is the plate's px 68..198 vertically, centred horizontally).
static func _composed_door_mesh(number: int) -> ArrayMesh:
	const SHEET := Vector2(1024.0, 512.0)
	const PX := 0.30 / 256.0
	const DIGIT_PITCH := 67.0 # px: Archivo's digits are tabular, 66.8 px wide at the atlas's 116 px size
	var variant := (number - 1) % 4
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var quads: Array = [[Rect2(-128, -128, 256, 256), Rect2(variant * 256, 0, 256, 256)]]
	var text := str(number)
	for i in text.length():
		var d := text.unicode_at(i) - 48
		var cell := Rect2((d % 5) * 128, 256 + (d / 5) * 128, 128, 130)
		var cx := (float(i) - (text.length() - 1) * 0.5) * DIGIT_PITCH
		quads.append([Rect2(cx - 64.0, -60.0, 128, 130), cell]) # y down: the number area's centre is 5 px below the plate's
	for q in quads:
		var r: Rect2 = q[0]
		var u: Rect2 = q[1]
		var base := verts.size()
		verts.append(Vector3(r.position.x * PX, -r.end.y * PX, 0.0))
		verts.append(Vector3(r.end.x * PX, -r.end.y * PX, 0.0))
		verts.append(Vector3(r.end.x * PX, -r.position.y * PX, 0.0))
		verts.append(Vector3(r.position.x * PX, -r.position.y * PX, 0.0))
		uvs.append(Vector2(u.position.x, u.end.y) / SHEET)
		uvs.append(Vector2(u.end.x, u.end.y) / SHEET)
		uvs.append(Vector2(u.end.x, u.position.y) / SHEET)
		uvs.append(Vector2(u.position.x, u.position.y) / SHEET)
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3(0, 0, 1))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

static func _door_plate_mesh(idx: int) -> ArrayMesh:
	var sh := _shared_resources()
	var cache: Dictionary = sh.get("door_meshes", {})
	if cache.has(idx):
		return cache[idx]
	if idx >= 16:
		cache[idx] = _composed_door_mesh(idx + 1)
		sh["door_meshes"] = cache
		return cache[idx]
	var col := idx % 4
	var row := idx / 4
	var uv_min := Vector2(col * 0.125, row * 0.125)
	var uv_max := Vector2((col + 1) * 0.125, (row + 1) * 0.125)
	var m := _decal_quad(Vector2(0.30, 0.30), uv_min, uv_max)
	cache[idx] = m
	sh["door_meshes"] = cache
	return m

static func _sunstrip_mesh(variant: int) -> ArrayMesh:
	var sh := _shared_resources()
	var cache: Dictionary = sh.get("sunstrip_meshes", {})
	if cache.has(variant):
		return cache[variant]
	# the middle of the 16:1 strip, so the 8.6:1 visor keeps the lettering's proportions
	var uv_min := Vector2(0.22, 0.5 + variant * 0.0625)
	var uv_max := Vector2(0.78, 0.5 + (variant + 1) * 0.0625)
	var m := _decal_quad(Vector2(0.86, 0.1), uv_min, uv_max)
	cache[variant] = m
	sh["sunstrip_meshes"] = cache
	return m

static func _hood_plate_mesh(variant: int) -> ArrayMesh:
	var sh := _shared_resources()
	var cache: Dictionary = sh.get("hood_meshes", {})
	if cache.has(variant):
		return cache[variant]
	var col := variant % 2
	var row := variant / 2
	var uv_min := Vector2(0.5 + col * 0.25, row * 0.25)
	var uv_max := Vector2(0.5 + (col + 1) * 0.25, (row + 1) * 0.25)
	var m := _decal_quad(Vector2(0.28, 0.28), uv_min, uv_max)
	cache[variant] = m
	sh["hood_meshes"] = cache
	return m

static func _sill_stack_mesh(variant: int) -> ArrayMesh:
	var sh := _shared_resources()
	var cache: Dictionary = sh.get("sill_meshes", {})
	if cache.has(variant):
		return cache[variant]
	var col := variant % 2
	var row := variant / 2
	var uv_min := Vector2(col * 0.5, 0.75 + row * 0.125)
	var uv_max := Vector2((col + 1) * 0.5, 0.75 + (row + 1) * 0.125)
	var m := _decal_quad(Vector2(0.48, 0.09), uv_min, uv_max)
	cache[variant] = m
	sh["sill_meshes"] = cache
	return m

static func _decal_quad(size: Vector2, uv_min: Vector2, uv_max: Vector2) -> ArrayMesh:
	var half := size * 0.5
	var verts := PackedVector3Array([
		Vector3(-half.x, -half.y, 0.0),
		Vector3(half.x, -half.y, 0.0),
		Vector3(half.x, half.y, 0.0),
		Vector3(-half.x, half.y, 0.0)
	])
	var uvs := PackedVector2Array([
		Vector2(uv_min.x, uv_max.y),
		Vector2(uv_max.x, uv_max.y),
		Vector2(uv_max.x, uv_min.y),
		Vector2(uv_min.x, uv_min.y)
	])
	var normals := PackedVector3Array([Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)])
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
