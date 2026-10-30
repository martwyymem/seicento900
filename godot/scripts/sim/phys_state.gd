## Drivetrain, wheel and suspension state of a car under full physics (the JS car.phys).
class_name PhysState
extends RefCounted

var w := PackedFloat64Array([0, 0, 0, 0]) ## wheel spin (rad/s)
var we := 0.0 ## engine speed (rad/s)
var clutch := 0.0
var ax_f := 0.0 ## lagged body accelerations (suspension)
var ay_f := 0.0
var ax_d := 0.0
var ay_d := 0.0
var abs_k := PackedFloat64Array([1, 1, 1, 1]) ## ABS pressure factor per wheel
var tc := 1.0
var hb_grip := 1.0 ## rear grip left after the handbrake: drops while it is pulled, creeps back once it is released
var fx0 := 0.0
var fz := PackedFloat64Array([0, 0, 0, 0])
var rho := PackedFloat64Array([0, 0, 0, 0])
var slide := 0.0
var heat := 0.0
