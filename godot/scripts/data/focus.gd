## The Ford Focus (Mk3.5 facelift, 2015) five-door hatchback with the 1.5 EcoBoost 150 PS turbocharged petrol engine:
## 110 kW (150 PS) at 6,000 rpm, 240 Nm flat plateau from 1,600 to 4,000 rpm, ~1,265 kg empty, 55 L tank, 6-speed manual
## (Ford B6), front-wheel drive, Cd ~0.295 on ~2.24 m², 215/55 R16 road tyres. Ford quotes 0-100 km/h in 8.9 s and
## 210 km/h (tests/_car_probe.gd measures the spec against both). The sixth campaign car (CarCatalog "focus"); its model
## is models/focus.glb from tools/blender/build_focus.py.
class_name Focus
extends RefCounted

static func spec() -> CarSpec:
	var s: CarSpec = load("res://data/seicento.tres").duplicate()
	s.resource_name = "focus" # Track.profile_for, Race's rail braking and the strategist key on a non-empty name
	s.mass_empty = 1265.0 # ~1,325 kg kerb: a 90 % tank, the driver counted separately at 80 kg (as Golf4/V50)
	s.tank = 55.0
	s.length = 4.358
	s.width = 1.823
	s.wheelbase = 2.648
	s.wheel_radius = 0.315 # 215/55 R16, rolling radius
	s.gears = PackedFloat64Array([3.727, 2.048, 1.357, 1.032, 0.821, 0.690])
	s.final_drive = 4.067
	s.shift_hold = 1.0 # 240 Nm turbo plateau spins the fronts in low gears without a brief shift hold
	s.efficiency = 0.855
	s.idle_rpm = 750.0
	s.redline = 6300.0
	s.limiter = 6600.0
	s.torque_curve = PackedVector2Array([
		Vector2(750, 105), Vector2(1000, 145), Vector2(1300, 195), Vector2(1600, 240), Vector2(2200, 240),
		Vector2(3000, 240), Vector2(3600, 240), Vector2(4000, 240), Vector2(4500, 230), Vector2(5000, 210),
		Vector2(5500, 191), Vector2(6000, 175), Vector2(6400, 152), Vector2(6700, 122)])
	s.bsfc = 248.0 # direct-injected turbocharged EcoBoost
	s.cd_a = 0.300 * 2.24 # Cd and frontal area tuned to the real car's 210 km/h
	s.crr = 0.0115
	s.front_weight = 0.60
	s.cg_height = 0.54
	s.track_front = 1.544
	s.track_rear = 1.534
	s.wheel_inertia = 1.18
	s.engine_inertia = 0.13
	s.clutch_capacity = 350.0
	s.brake_front = 2850.0 # 300 mm vented front discs
	s.brake_rear = 860.0 # 271 mm solid rear discs
	s.roll_gradient = 0.085 # taut Focus Mk3.5 Control Blade multi-link rear chassis
	s.pitch_gradient = 0.040
	s.susp_hz = 1.48
	s.lift_a = 0.14
	s.reverse_ratio = 3.615
	s.steer_lock = 0.5
	s.grip_k = 1.225 # 215/55 R16 road tyres: about 0.88 g on the skidpad (the Seicento model is calibrated at 1.4)
	return s

static func model() -> CarModel:
	return CarModel.new(spec())
