## The Volvo V50 (first generation, P1 platform, 2004-2007) estate with the 2.4i petrol engine (B5244S4, five cylinders,
## 20 valves): 125 kW (170 PS) at 6,000 rpm, 230 Nm at 4,400, ~1,420 kg kerb, a 5-speed manual, front-wheel drive, Cd ~0.31
## on ~2.20 m², 205/55 R16 tyres. Volvo quotes 0-100 km/h in 8.3 s (road tests 8.5-9.0) and 210 km/h (130 mph)
## (tests/_car_probe.gd measures the spec against both). The third campaign car (CarCatalog "v50"); its model is
## models/v50.glb from tools/blender/build_v50.py. Won by clearing the Kilometr na S1 mission (Missions reward_car).
class_name V50
extends RefCounted

static func spec() -> CarSpec:
	var s: CarSpec = load("res://data/seicento.tres").duplicate()
	s.resource_name = "v50" # Track.profile_for, Race's rail braking and the strategist key on a non-empty name
	s.mass_empty = 1345.0 # ~1,420 kg kerb: a 90 % tank, the driver counted separately at 80 kg (as Golf4)
	s.tank = 62.0
	s.length = 4.515
	s.width = 1.770
	s.wheelbase = 2.640
	s.wheel_radius = 0.309 # 205/55 R16, rolling radius
	s.gears = PackedFloat64Array([3.38, 2.00, 1.34, 1.03, 0.83])
	s.final_drive = 4.06
	s.shift_hold = 1.0 # 230 Nm spins the fronts in the wet: without a hold the automatic hunts 1st-2nd at ~43 km/h on the limiter
	s.efficiency = 0.90
	s.idle_rpm = 750.0
	s.redline = 6300.0
	s.limiter = 6600.0
	s.torque_curve = PackedVector2Array([
		Vector2(750, 120), Vector2(1000, 150), Vector2(1500, 178), Vector2(2000, 196), Vector2(2500, 207), Vector2(3000, 215),
		Vector2(3500, 222), Vector2(4000, 228), Vector2(4400, 230), Vector2(5000, 222), Vector2(5500, 211), Vector2(6000, 199),
		Vector2(6500, 172), Vector2(7000, 130)])
	s.bsfc = 275.0
	s.cd_a = 0.34 * 2.32 # Cd and frontal area tuned to the real car's 210 km/h
	s.crr = 0.012
	s.front_weight = 0.60
	s.cg_height = 0.56
	s.track_front = 1.535
	s.track_rear = 1.531
	s.wheel_inertia = 1.15
	s.engine_inertia = 0.16
	s.clutch_capacity = 340.0
	s.brake_front = 2600.0 # 300 mm vented discs
	s.brake_rear = 820.0 # 280 mm solid discs
	s.roll_gradient = 0.09
	s.pitch_gradient = 0.042
	s.susp_hz = 1.45
	s.lift_a = 0.15
	s.reverse_ratio = 3.30
	s.steer_lock = 0.5
	s.grip_k = 1.27 # 205/55 R16 road tyres: about 0.87 g on the skidpad (the Seicento model is calibrated at 1.4)
	return s

static func model() -> CarModel:
	return CarModel.new(spec())
