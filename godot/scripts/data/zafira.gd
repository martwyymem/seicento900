## The Opel Zafira B (second generation, A05, 2005) 7-seat compact MPV with the 1.8 16V petrol engine (Z18XER, ECOTEC
## VVT): 103 kW (140 PS) at 6,300 rpm, 175 Nm at 3,800 rpm, ~1,390 kg empty, 58 L tank, 5-speed F17+CR manual,
## front-wheel drive, Cd 0.31 on ~2.48 m², 205/55 R16 road tyres. Opel quotes 0-100 km/h in 11.5 s and 197 km/h.
## The seventh campaign car (CarCatalog "zafira"); its model is models/zafira.glb from tools/blender/build_zafira.py.
class_name Zafira
extends RefCounted

static func spec() -> CarSpec:
	var s: CarSpec = load("res://data/seicento.tres").duplicate()
	s.resource_name = "zafira" # Track.profile_for, Race's rail braking and the strategist key on a non-empty name
	s.mass_empty = 1390.0
	s.tank = 58.0
	s.length = 4.467
	s.width = 1.801
	s.wheelbase = 2.703
	s.wheel_radius = 0.310 # 205/55 R16, rolling radius
	s.gears = PackedFloat64Array([3.727, 2.136, 1.414, 1.121, 0.892]) # Opel F17+CR 5-speed manual
	s.final_drive = 3.94
	s.efficiency = 0.848
	s.idle_rpm = 750.0
	s.redline = 6500.0
	s.limiter = 6700.0
	s.torque_curve = PackedVector2Array([
		Vector2(750, 85), Vector2(1000, 112), Vector2(1500, 136), Vector2(2000, 152), Vector2(2500, 162), Vector2(3000, 168),
		Vector2(3500, 173), Vector2(3800, 175), Vector2(4500, 172), Vector2(5000, 168), Vector2(5500, 164), Vector2(6000, 160),
		Vector2(6300, 156), Vector2(6700, 138)])
	s.bsfc = 278.0
	s.cd_a = 0.305 * 2.24 # Cd and frontal area tuned to the real car's 197 km/h
	s.crr = 0.0125
	s.front_weight = 0.59
	s.cg_height = 0.62
	s.track_front = 1.488
	s.track_rear = 1.510
	s.wheel_inertia = 1.15
	s.engine_inertia = 0.14
	s.clutch_capacity = 280.0
	s.brake_front = 2700.0 # 308 mm vented discs
	s.brake_rear = 850.0 # 264 mm solid discs
	s.roll_gradient = 0.115
	s.pitch_gradient = 0.048
	s.susp_hz = 1.38
	s.lift_a = 0.18
	s.reverse_ratio = 3.308
	s.steer_lock = 0.5
	s.grip_k = 1.21 # 205/55 R16 road tyres on a tall MPV: ~0.83 g on the skidpad
	return s

static func model() -> CarModel:
	return CarModel.new(spec())
