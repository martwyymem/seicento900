## Compares CarModel/Tyres against js/car.js (reference from tools/parity/car_ref.js).
extends RefCounted

func run() -> Array:
	var car := CarModel.new()
	var tyres := Tyres.new()
	var ref: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ref/car.json"))
	var errors := []
	var checked := 0
	for r in ref:
		var target: Object = tyres if r.fn in ["compound_grip", "wear_per_metre", "tyre_grip"] else car
		var args: Array = r.args
		if r.fn in ["rpm_for", "engine_rpm", "wheel_force"]:
			args[1] = int(args[1]) # gear
		var got = target.callv(r.fn, args)
		if absf(float(got) - float(r.v)) > 1e-9 * maxf(1.0, absf(float(r.v))):
			errors.append("%s%s: got %s, want %s" % [r.fn, r.args, got, r.v])
		checked += 1
	if checked != ref.size():
		errors.append("only %d of %d values checked" % [checked, ref.size()])
	return errors
