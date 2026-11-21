## The Hyundai i20 (first generation, PB, 2008-2012) five-door with the 1.4 16V petrol engine (Gamma G4FA):
## 74 kW (100 PS) at 5,500 rpm, 137 Nm at 4,200, ~1,040 kg kerb, a 5-speed manual, front-wheel drive, Cd 0.32
## on ~2.08 m², 185/60 R15 road tyres. Hyundai quotes 0-100 km/h in 11.6 s and 180 km/h (tests/_car_probe.gd
## measures the spec against both). The fourth campaign car (CarCatalog "i20"); its model is models/i20.glb
## from tools/blender/build_i20.py. Won by clearing the S1 Sprint mission (Missions reward_car).
class_name I20
extends RefCounted

static func spec() -> CarSpec:
	var s: CarSpec = load("res://data/seicento.tres").duplicate()
	s.resource_name = "i20" # Track.profile_for, Race's rail braking and the strategist key on a non-empty name
	s.mass_empty = 1040.0 # ~1,075 kg kerb: a 90 % tank, the driver counted separately at 80 kg (as Golf4)
	s.tank = 45.0
	s.length = 3.940
	s.width = 1.710
	s.wheelbase = 2.525
	s.wheel_radius = 0.296 # 185/60 R15, rolling radius
	s.gears = PackedFloat64Array([3.615, 1.955, 1.286, 0.971, 0.774])
	s.final_drive = 4.056
	s.efficiency = 0.865
	s.idle_rpm = 750.0
	s.redline = 6200.0
	s.limiter = 6500.0
	s.torque_curve = PackedVector2Array([
		Vector2(750, 62), Vector2(1000, 88), Vector2(1500, 106), Vector2(2000, 118), Vector2(2500, 126), Vector2(3000, 131),
		Vector2(3500, 135), Vector2(4200, 137), Vector2(4800, 134), Vector2(5500, 128), Vector2(6000, 114), Vector2(6500, 92)])
	s.bsfc = 282.0
	s.cd_a = 0.32 * 2.07 # Cd and frontal area tuned to the real car's 180 km/h
	s.crr = 0.0125
	s.front_weight = 0.61
	s.cg_height = 0.56
	s.track_front = 1.505
	s.track_rear = 1.503
	s.wheel_inertia = 0.92
	s.engine_inertia = 0.11
	s.clutch_capacity = 240.0
	s.brake_front = 2050.0 # 256 mm vented discs
	s.brake_rear = 620.0 # 262 mm solid discs
	s.roll_gradient = 0.095
	s.pitch_gradient = 0.044
	s.susp_hz = 1.42
	s.lift_a = 0.15
	s.reverse_ratio = 3.545
	s.steer_lock = 0.5
	s.grip_k = 1.20 # 185/60 R15 road tyres: about 0.85 g on the skidpad (the Seicento model is calibrated at 1.4)
	return s

static func model() -> CarModel:
	return CarModel.new(spec())
