## Replays the scripted scenarios from tools/parity/physics_ref.js through Physics and compares every tick.
## Transcendental functions differ in the last bits between V8 and libm, so the tolerance is 1e-9
## (relative, floor 1) rather than exact.
extends RefCounted

var completed := false

const DT := 1.0 / 120.0
const TOL := 1e-9
const FIELDS := ["x", "y", "heading", "vx", "vy", "yaw_rate", "rpm", "steer", "we", "clutch", "w0", "w1", "w2", "w3",
	"ax_f", "ay_f", "understeer", "slip", "body_roll", "body_pitch", "engine_power", "slide_power"]

static func surf_id(x: float, y: float) -> int:
	if y > 4.0:
		return Physics.SURF_GRASS
	if x > 40.0:
		return Physics.SURF_GRAVEL
	if y < -3.0:
		return Physics.SURF_ASPHALT
	return Physics.SURF_TRACK

func run() -> Array:
	var phys := Physics.new(CarModel.new())
	var ref: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/ref/physics.json"))
	var errors := []
	var checked := 0
	for sc in ref:
		var car := RaceCar.new()
		car.heading = sc.heading
		car.vx = sc.v0 * cos(sc.heading)
		car.vy = sc.v0 * sin(sc.heading)
		car.rpm = phys.spec.idle_rpm
		car.gear = int(sc.gear0)
		car.rev = sc.rev
		var env := Physics.Env.new()
		env.mu = sc.mu
		env.mass = sc.mass
		env.gx = sc.gx
		env.gy = sc.gy
		env.drag_mul = sc.dragMul
		env.abs_on = sc.aids
		env.tc_on = sc.aids
		env.esc_on = sc.aids
		env.surface = surf_id
		var inp := Physics.Controls.new()
		var worst := 0.0
		var worst_at := ""
		for t in sc.inputs.size():
			var i: Array = sc.inputs[t]
			inp.throttle = i[0]
			inp.brake = i[1]
			inp.steer = i[2]
			car.gear = int(i[3])
			car.shift_t = i[4]
			phys.step(car, inp, env, DT)
			car.shift_t = maxf(0.0, car.shift_t - DT)
			var ph := car.phys
			var got := [car.x, car.y, car.heading, car.vx, car.vy, car.yaw_rate, car.rpm, car.steer, ph.we, ph.clutch,
				ph.w[0], ph.w[1], ph.w[2], ph.w[3], ph.ax_f, ph.ay_f, car.understeer, car.slip, car.body_roll,
				car.body_pitch, phys.engine_power, phys.slide_power]
			var want: Array = sc.states[t]
			for f in got.size():
				var e := absf(got[f] - float(want[f])) / maxf(1.0, absf(float(want[f])))
				if e > worst:
					worst = e
					worst_at = "tick %d %s: got %s, want %s" % [t, FIELDS[f], got[f], want[f]]
				checked += 1
		if worst > TOL:
			errors.append("%s diverges (worst %s) at %s" % [sc.name, worst, worst_at])
		else:
			print("    %s: worst error %s over %d ticks" % [sc.name, worst, sc.inputs.size()])
	if checked == 0:
		errors.append("nothing checked")
	completed = true
	return errors
