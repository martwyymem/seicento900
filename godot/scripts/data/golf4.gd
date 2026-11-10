## The VW Golf IV (Typ 1J, 1997-2003) five-door with the 1.4 16V petrol engine, the common Polish-market car: 55 kW (75 PS)
## at 5,000 rpm, 126 Nm at 3,800, ~1,150 kg kerb, a 5-speed manual, front-wheel drive, Cd 0.31 on ~1.98 m². The real car does
## 0-100 km/h in 13.9 s and tops out at 171 km/h (tests/_car_probe.gd measures the spec against both). The first car after the
## Seicento (CarCatalog "golf4"); its model is models/golf4.glb from tools/blender/build_golf4.py. Unlocked from the campaign
## save (CarCatalog.unlocked), not by fans.
class_name Golf4
extends RefCounted

static func spec() -> CarSpec:
	var s: CarSpec = load("res://data/seicento.tres").duplicate()
	s.resource_name = "golf4" # Track.profile_for, Race's rail braking and the strategist key on a non-empty name
	s.mass_empty = 1075.0 # ~1,150 kg kerb: a 90 % tank, the driver counted separately at 80 kg
	s.tank = 55.0
	s.length = 4.149
	s.width = 1.735
	s.wheelbase = 2.511
	s.wheel_radius = 0.3205 # 195/65 R15, rolling radius
	s.gears = PackedFloat64Array([3.778, 2.118, 1.360, 0.971, 0.756])
	s.final_drive = 4.24
	s.efficiency = 0.90
	s.idle_rpm = 800.0
	s.redline = 6200.0
	s.limiter = 6500.0
	s.torque_curve = PackedVector2Array([
		Vector2(800, 55), Vector2(1000, 82), Vector2(1500, 97), Vector2(2000, 107), Vector2(2500, 115), Vector2(3000, 121),
		Vector2(3800, 126), Vector2(4500, 119), Vector2(5000, 105), Vector2(5500, 93), Vector2(6000, 80), Vector2(6500, 62)])
	s.bsfc = 290.0
	s.cd_a = 0.31 * 1.98
	s.crr = 0.0125
	s.front_weight = 0.61
	s.cg_height = 0.55
	s.track_front = 1.513
	s.track_rear = 1.494
	s.wheel_inertia = 1.0
	s.engine_inertia = 0.11
	s.clutch_capacity = 230.0
	s.brake_front = 1900.0 # 256 mm vented discs
	s.brake_rear = 520.0 # 232 mm solid discs
	s.roll_gradient = 0.10
	s.pitch_gradient = 0.045
	s.susp_hz = 1.4
	s.lift_a = 0.15
	s.reverse_ratio = 3.5
	s.steer_lock = 0.5
	s.grip_k = 1.19 # 195/65 R15 road tyres: about 0.84 g on the skidpad (the Seicento model is calibrated at 1.4)
	return s

static func model() -> CarModel:
	return CarModel.new(spec())
