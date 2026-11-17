## The Dacia Logan (first generation, L90, 2004-2008) saloon with the 1.4 MPI petrol engine (Renault K7J, 8 valves), the base
## car: 55 kW (75 PS) at 5,500 rpm, 112 Nm at 3,000, ~1,020 kg kerb, a 5-speed manual (JH3), front-wheel drive, Cd ~0.34 on
## ~2.0 m², 185/65 R15 road tyres on steel wheels. The real car does 0-100 km/h in about 13.0 s and tops out at 162 km/h
## (tests/_car_probe.gd measures the spec against both). The second campaign car (CarCatalog "logan"); its model is
## models/logan.glb from tools/blender/build_logan.py. Won by clearing the Rajd Borów mission (Missions reward_car).
class_name Logan
extends RefCounted

static func spec() -> CarSpec:
	var s: CarSpec = load("res://data/seicento.tres").duplicate()
	s.resource_name = "logan" # Track.profile_for, Race's rail braking and the strategist key on a non-empty name
	s.mass_empty = 945.0 # ~1,020 kg kerb: a 90 % tank, the driver counted separately at 80 kg (as Golf4)
	s.tank = 50.0
	s.length = 4.247
	s.width = 1.735
	s.wheelbase = 2.630
	s.wheel_radius = 0.302 # 185/65 R15, rolling radius
	s.gears = PackedFloat64Array([3.727, 2.048, 1.393, 1.029, 0.756])
	s.final_drive = 4.50
	s.efficiency = 0.90
	s.idle_rpm = 800.0
	s.redline = 5900.0
	s.limiter = 6200.0
	s.torque_curve = PackedVector2Array([
		Vector2(800, 52), Vector2(1000, 72), Vector2(1500, 88), Vector2(2000, 98), Vector2(2500, 106), Vector2(3000, 112),
		Vector2(3500, 111), Vector2(4000, 108), Vector2(4500, 104), Vector2(5000, 99), Vector2(5500, 95), Vector2(6000, 82),
		Vector2(6500, 62)])
	s.bsfc = 295.0
	s.cd_a = 0.34 * 2.00 # Cd and frontal area tuned to the real car's 162 km/h
	s.crr = 0.0125
	s.front_weight = 0.61
	s.cg_height = 0.57 # a tall saloon with a high ride
	s.track_front = 1.466
	s.track_rear = 1.456
	s.wheel_inertia = 0.95
	s.engine_inertia = 0.11
	s.clutch_capacity = 210.0
	s.brake_front = 1800.0 # 259 mm vented discs
	s.brake_rear = 460.0 # 203 mm drums
	s.roll_gradient = 0.11
	s.pitch_gradient = 0.048
	s.susp_hz = 1.35
	s.lift_a = 0.16
	s.reverse_ratio = 3.545
	s.steer_lock = 0.5
	s.grip_k = 1.19 # 185/65 R15 road tyres: about 0.85 g on the skidpad (the Seicento model is calibrated at 1.4)
	return s

static func model() -> CarModel:
	return CarModel.new(spec())
