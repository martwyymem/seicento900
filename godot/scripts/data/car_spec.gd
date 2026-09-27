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
