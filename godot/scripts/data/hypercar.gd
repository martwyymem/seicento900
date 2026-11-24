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
	s.cg_height = 0.38 ## lowered
	s.wheel_inertia = 1.2
	s.engine_inertia = 0.12
	s.clutch_capacity = 900.0
	# Brake-by-wire (CarSpec.brake_front_grip / brake_rear_grip / brake_stab): the calipers are big enough for
	# full downforce at 340 km/h, front ABS holds near peak grip without sawtooth chatter, rear EBD/CBC proportions
	# each rear wheel to its own load and backs off under rear lateral slip so the tail keeps its sideways grip,
	# and yaw-moment control (brake_stab) eases spin-side braking on steering taps and split-mu verges.
	s.brake_front = 3400.0
	s.brake_rear = 1600.0
	s.brake_front_grip = 1.03
	s.brake_rear_grip = 0.92
	s.brake_stab = 9.0
	s.abs_slip = 1.0
	s.roll_gradient = 0.04
	s.pitch_gradient = 0.02
	s.susp_hz = 2.6
	s.lift_a = -1.8 ## downforce
	# most of it from the rear wing: with the weight's own 55/45 split the car was neutral, and a held steering key at
	# 250 km/h (or lifting, or braking into a bend) slid the tail 20-40 degrees out
	s.aero_front = 0.38
	s.aero_rear = 0.62
	s.reverse_ratio = 3.2
	s.reverse_power = 0.3 ## the brake held past a stop selects reverse: back up like the Seicento (23 km/h in 2.5 s), not at 65
	s.steer_lock = 0.4
	# a full key press (or full stick) asks the fronts for their peak slip at speed, not past it: from 200 km/h up the lock
	# is ~3 deg (the fronts at 0.94 of their peak slip, 1.66-1.97 g, the most the car makes), fading in from 30 km/h.
	# With 0.45 from 80 km/h a held key asked 1.3-1.8x the peak (washing the nose out), and each key press turned the car
	# so far at 200-300 km/h that a keyboard driver weaved under braking and on the S1 (B3, tests/_hypercar_goliath_kb.gd)
	s.steer_fast = 0.3
	s.steer_fast_from = 8.0
	s.steer_fast_to = 55.0
	s.esc_grip = 1.3 ## stability control knows the slicks and the wings (it took 1.1 g for the limit and braked a wheel in every fast bend)
	s.esc_aero = 0.00017
	s.grip_k = 1.75
	s.load_sensitivity = 0.08
	return s

static func model() -> CarModel:
	return CarModel.new(spec())
