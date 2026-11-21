## The Dacia Sandero (first generation, B90, 2008-2012) five-door hatchback with the 1.6 MPI petrol engine (Renault K7M,
## 8 valves): 64 kW (87 PS) at 5,500 rpm, 128 Nm at 3,000, ~1,030 kg empty, a 5-speed manual (JH3), front-wheel drive,
## Cd ~0.35 on ~2.12 m², 185/65 R15 road tyres. Dacia quotes 0-100 km/h in 11.5 s and 174 km/h (tests/_car_probe.gd
## measures the spec against both). The fifth campaign car (CarCatalog "sandero"); its model is models/sandero.glb
## from tools/blender/build_sandero.py.
class_name Sandero
extends RefCounted

static func spec() -> CarSpec:
	var s: CarSpec = load("res://data/seicento.tres").duplicate()
	s.resource_name = "sandero" # Track.profile_for, Race's rail braking and the strategist key on a non-empty name
	s.mass_empty = 1030.0 # ~1,065 kg kerb with a 90 % tank, driver counted separately at 80 kg (as Golf4/Logan)
	s.tank = 50.0
	s.length = 4.020
	s.width = 1.746
	s.wheelbase = 2.588
	s.wheel_radius = 0.305 # 185/65 R15, rolling radius
	s.gears = PackedFloat64Array([3.727, 2.048, 1.393, 1.029, 0.795])
	s.final_drive = 4.36
	s.efficiency = 0.915
	s.idle_rpm = 800.0
	s.redline = 6000.0
	s.limiter = 6350.0
	s.torque_curve = PackedVector2Array([
		Vector2(800, 68), Vector2(1000, 92), Vector2(1500, 110), Vector2(2000, 120), Vector2(2500, 126), Vector2(3000, 128),
		Vector2(3500, 128), Vector2(4000, 127), Vector2(4500, 124), Vector2(5000, 120), Vector2(5500, 113), Vector2(6000, 102),
		Vector2(6500, 80)])
	s.bsfc = 290.0
	s.cd_a = 0.35 * 2.04 # Cd and frontal area tuned to the real car's 174 km/h
	s.crr = 0.0125
	s.front_weight = 0.61
	s.cg_height = 0.57 # taller Dacia ride height
	s.track_front = 1.480
	s.track_rear = 1.469
	s.wheel_inertia = 0.95
	s.engine_inertia = 0.11
	s.clutch_capacity = 230.0
	s.brake_front = 1950.0 # 259 mm vented discs
	s.brake_rear = 520.0 # 203 mm drums
	s.roll_gradient = 0.105
	s.pitch_gradient = 0.046
	s.susp_hz = 1.38
	s.lift_a = 0.16
	s.reverse_ratio = 3.545
	s.steer_lock = 0.5
	s.grip_k = 1.18 # 185/65 R15 road tyres: about 0.84 g on the skidpad (the Seicento model is calibrated at 1.4)
	return s

static func model() -> CarModel:
	return CarModel.new(spec())
