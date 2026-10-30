## The Hypercar Seicento: a stock Seicento's body, weight and size (815 kg with the driver, 3.34 m long) with the engine
## of a Ferrari 499P (about 500 kW, 8,200 rpm), all-wheel drive, a seven-speed box geared for ~340 km/h, wings and grippy
## slicks. It is dressed as the Le Mans winner of 2025, AF Corse's yellow no. 83 (Kubica, Hanson, Ye). Unlocked at the top fan
## level (FanLevels); used by the open world's HYPERCAR modifier and by the final campaign race.
class_name Hypercar
extends RefCounted

const PAINT := Color("#ffd400") ## AF Corse yellow (the stripes follow: black on a bright paint)
const NUMBER := 83

static func spec() -> CarSpec:
	var s: CarSpec = load("res://data/seicento.tres").duplicate()
	s.resource_name = "hypercar" # Track.profile_for and Race's rail braking key on this
	s.tank = 60.0
	s.gears = PackedFloat64Array([3.2, 2.35, 1.8, 1.45, 1.2, 1.0, 0.84])
	s.final_drive = 2.93
	s.efficiency = 0.9
	s.awd = true
	s.shift_hold = 1.0
	s.idle_rpm = 1000.0
	s.redline = 8000.0
	s.limiter = 8200.0
	s.torque_curve = PackedVector2Array([
		Vector2(1000, 240), Vector2(2000, 400), Vector2(3000, 520), Vector2(4500, 640), Vector2(6000, 690),
		Vector2(7000, 690), Vector2(8000, 620), Vector2(8200, 560)])
	s.bsfc = 270.0
	s.cd_a = 0.75
	s.crr = 0.011
	s.front_weight = 0.55
	s.cg_height = 0.42 ## lowered
	s.wheel_inertia = 1.2
	s.engine_inertia = 0.12
	s.clutch_capacity = 900.0
	s.brake_front = 3600.0
	s.brake_rear = 750.0
	s.roll_gradient = 0.04
	s.pitch_gradient = 0.02
	s.susp_hz = 2.6
	s.lift_a = -1.8 ## downforce
	s.reverse_ratio = 3.2
	s.steer_lock = 0.4
	s.grip_k = 1.75
	s.load_sensitivity = 0.08
	return s

static func model() -> CarModel:
	return CarModel.new(spec())
