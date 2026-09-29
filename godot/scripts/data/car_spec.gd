## Fiat Seicento 900 figures. Real 899 cc car where known (39 hp @ 5500, 65 Nm @ 3000, ~735 kg,
## ~140 km/h); gearing and aero are close approximations. Edit data/seicento.tres in the Inspector.
class_name CarSpec
extends Resource

@export_group("Mass")
@export var mass_empty := 735.0
@export var driver_mass := 80.0
@export var fuel_density := 0.745 ## kg per litre
@export var tank := 35.0 ## litres

@export_group("Dimensions")
@export var length := 3.34
@export var width := 1.51
@export var wheelbase := 2.2
@export var wheel_radius := 0.277 ## 145/70 R13

@export_group("Drivetrain")
@export var gears := PackedFloat64Array([3.909, 2.158, 1.345, 0.974, 0.784])
@export var final_drive := 4.923
@export var efficiency := 0.88
@export var idle_rpm := 850.0
@export var redline := 6100.0
@export var limiter := 6300.0
## Engine torque curve: x = rpm, y = Nm.
@export var torque_curve := PackedVector2Array([
	Vector2(800, 40), Vector2(1500, 52), Vector2(2000, 58), Vector2(3000, 65), Vector2(4000, 62),
	Vector2(5000, 56), Vector2(5500, 51.5), Vector2(6000, 45), Vector2(6300, 38)])
@export var bsfc := 330.0 ## g/kWh at load

@export_group("Resistance")
@export var cd_a := 0.33 * 1.84
@export var crr := 0.013
@export var front_weight := 0.62 ## FWD traction share

@export_group("Chassis")
@export var cg_height := 0.54
@export var track_front := 1.36
@export var track_rear := 1.33
@export var wheel_inertia := 0.6 ## kg·m² per wheel incl. brake disc and half-shaft
@export var engine_inertia := 0.045 ## crank + flywheel
@export var clutch_capacity := 125.0 ## Nm
@export var brake_front := 1250.0 ## Nm per wheel at full pedal
@export var brake_rear := 130.0 ## rear drums behind a load-sensing valve
@export var roll_front := 0.6 ## front share of roll stiffness
@export var roll_gradient := 0.11 ## body roll, rad per g
@export var pitch_gradient := 0.045 ## body pitch, rad per g
@export var susp_hz := 1.5
@export var susp_zeta := 0.55
@export var lift_a := 0.12 ## Cl·A, a little lift at speed
@export var reverse_ratio := 3.55
@export var steer_lock := 0.5 ## road-wheel angle at full lock (rad)
@export var ackermann := 0.5 ## fraction of true Ackermann geometry

@export_group("Tyre model")
@export var load_sensitivity := 0.1 ## grip lost per unit of extra load over static
@export var grip_k := 1.4 ## calibrates the tyre so the car's steady-state limit matches the field's
@export var v_ref := 2.5 ## low-speed slip floor (m/s)
@export var substeps := 8 ## physics substeps per race tick
