## Headless probe of how the player's car drifts: scripted drivers on a flat asphalt plane through the race physics
## (Physics with the player's env, the race's automatic box) at a few entry speeds and driving-aid levels.
##   timeout 300 godot --headless --path godot -s tests/_drift_probe.gd [-- only=seicento] [legacy]
## "legacy" runs the AI's handling (Env.drift_handling 0) and the old keyboard ramp, i.e. the handling before the player's
## drift tuning (the handbrake's HB_* constants are shared, so "old" runs the current handbrake); without it both are run
## side by side. trace=driver:kmh:assists prints one run tick by tick.
## Drivers (all turn right; the course is the direction of travel, so 90 deg of course is a right-angle corner):
##   grip   full steering key, part throttle, no handbrake: the grip line through the corner
##   lift   turn in on full throttle, lift off and stab the brake: a lift-off oversteer, then the keyboard catch driver
##   kb     turn in for 0.25 s, then a 0.3 s handbrake tap, then a keyboard driver that counter-steers (bang-bang keys through the
##          keyboard ramp) to hold a 25 deg slide and steers back into the turn while it closes
##   pad    the same entry, then an analogue stick that holds a 30 deg slide (front wheels near the velocity plus a
##          proportional correction), throttle balancing the slide
##   late   the same entry, then full counter-steer only once the slide is past 40 deg (a late catch)
## Reported: peak slide angle, spin-out (slide past 100 deg), how long the first slide is held (|beta| > 10 deg), the time
## spent in a drift (12-50 deg), the time and
## speed at 90 deg of course (the corner exit) and the speed after 4 s.
extends SceneTree

const S := preload("res://tests/test_surfaces.gd")
const DT := 1.0 / 120.0

class Rig:
	var model: CarModel
	var phys: Physics
	var env := Physics.Env.new()
	var ctl := Physics.Controls.new()
	var car: RaceCar
	var legacy := false

	func _init(cm: CarModel, assists: String, legacy_: bool) -> void:
		model = cm
		legacy = legacy_
		phys = Physics.new(cm)
		env.mass = cm.mass_with_fuel(S.FUEL)
		env.abs_on = assists != "off"
		env.tc_on = assists == "full"
		env.esc_on = assists == "full"
		env.drift_assist = Race.DRIFT_ASSIST_FULL if assists == "full" else (Race.DRIFT_ASSIST_ABS if assists == "abs" else 0.0)
		if "drift_handling" in env:
			env.set("drift_handling", 0.0 if legacy else 1.0)
		env.surface = func(_x: float, _y: float) -> int: return Physics.SURF_ASPHALT

	func reset(v0: float) -> void:
		car = RaceCar.new()
		car.is_player = true
		car.model = model
		car.physics = phys
		car.fuel = S.FUEL
		car.heading = 0.0
		car.vx = v0
		car.speed = v0
		car.gear = model.best_gear(v0)
		car.rpm = maxf(model.spec.idle_rpm, model.rpm_for(v0, car.gear))
		car.phys = null

	func beta() -> float:
		var ch := cos(car.heading)
		var sh := sin(car.heading)
		return atan2(-car.vx * sh + car.vy * ch, maxf(car.vx * ch + car.vy * sh, 0.5))

	func speed() -> float:
		return sqrt(car.vx * car.vx + car.vy * car.vy)

	## The steering limit a full input in direction sgn gets (the old max_steer for legacy).
	func lock(sgn: float) -> float:
		var mu := 1.0
		if not legacy and phys.has_method("steer_limit"):
			return phys.call("steer_limit", car, sgn, mu, 1.0, 1.0)
		return phys.max_steer(speed(), mu)

	## Game._update_input's keyboard ramp (the new one when the physics has it, the old one for legacy).
	func key(steer: float, st: float) -> float:
		var kmh := absf(car.speed) * 3.6
		if not legacy and phys.has_method("key_steer"):
			return phys.call("key_steer", steer, st, kmh, phys.call("rear_slide", car), DT)
		var back := st == 0.0 or signf(st) != signf(steer)
		var rate := 4.4 if kmh < 40.0 else lerpf(4.4, 2.6, clampf((kmh - 40.0) / 80.0, 0.0, 1.0))
		return move_toward(steer, st, (8.0 if back else rate) * DT)

	func step(thr: float, brk: float, steer: float, hb := 0.0) -> void:
		var vF := car.vx * cos(car.heading) + car.vy * sin(car.heading)
		_auto_shift(vF, brk)
		ctl.throttle = thr
		ctl.brake = brk
		ctl.steer = steer
		ctl.handbrake = hb
		phys.step(car, ctl, env, DT)
		car.shift_t = maxf(0.0, car.shift_t - DT)
		car.hold_t = maxf(0.0, car.hold_t - DT)

	func _auto_shift(vF: float, brk: float) -> void:
		var cm := model
		var vp := maxf(0.0, vF)
		var top := cm.spec.gears.size() - 1
		var g := car.gear
		if vF < 1.0:
			g = 0
		elif g < top and (car.rpm > cm.spec.limiter - 150.0 or cm.wheel_force(vp, g + 1, 1.0) > cm.wheel_force(vp, g, 1.0)) and cm.rpm_for(vF, g + 1) > cm.spec.limiter * 4.0 / 9.0:
			g += 1
		elif g > 0 and car.hold_t <= 0.0 and (cm.spec.shift_hold <= 0.0 or cm.rpm_for(vF, g) < cm.spec.limiter * 0.5) and cm.rpm_for(vF, g - 1) < cm.spec.limiter - 400.0 and (cm.wheel_force(vp, g - 1, 1.0) > cm.wheel_force(vp, g, 1.0) * 1.06 or (brk > 0.1 and cm.rpm_for(vF, g) < cm.spec.limiter * 32.0 / 63.0)):
			g -= 1
		if g != car.gear:
			car.shift_t = 0.15 if g > car.gear else 0.12
			if g > car.gear:
				car.hold_t = cm.spec.shift_hold
			car.gear = g

## One run: returns the figures.
func run_one(cm: CarModel, assists: String, legacy: bool, driver: String, v0: float) -> Dictionary:
	var r := Rig.new(cm, assists, legacy)
	r.reset(v0)
	var steer := 0.0
	var peak := 0.0
	var spun := false
	var held := 0.0
	var window := 0.0
	var holding := false
	var hold_done := false
	var course := 0.0
	var last_c := 0.0
	var t90 := NAN
	var v90 := NAN
	var v4 := NAN
	var t := 0.0
	var started := false
	var pb := 0.0
	var total := 6.0
	while t < total:
		var b := r.beta()
		var v := r.speed()
		var thr := 0.0
		var brk := 0.0
		var hb := 0.0
		var st := 0.0
		match driver:
			"grip":
				st = 1.0
				thr = 0.45
				steer = r.key(steer, st)
			"lift", "kb":
				if driver == "lift" and t < 0.6:
					st = 1.0
					thr = 1.0 if t < 0.35 else 0.0
					brk = 0.5 if t > 0.35 and t < 0.5 else 0.0
				elif driver == "kb" and t < 0.55:
					# turn in, then a handbrake tap with the key still held
					st = 1.0
					hb = 1.0 if t > 0.25 else 0.0
					thr = 0.6
				else:
					# keyboard catch: counter-steer key while the slide is past the target or still opening; turn in
					# again when it is dying; throttle feeds the slide below target and eases above
					var bd := 0.436 # 25 deg
					var opening := (b - pb) * signf(b) > 0.0
					if absf(b) > bd or (absf(b) > bd * 0.6 and opening):
						st = signf(b)
					elif not opening:
						st = -signf(b) # closing under the target: back into the turn to keep it going
					thr = 1.0 if absf(b) < bd else 0.55
					steer = r.key(steer, st)
				if t < 0.6 and driver == "lift" or t < 0.55:
					steer = r.key(steer, st)
			"pad":
				if t < 0.55:
					steer = r.key(steer, 1.0)
					hb = 1.0 if t > 0.25 else 0.0
					thr = 0.6
				else:
					# front wheels along the front axle's velocity, plus a correction on the slide error and its rate
					var bd := 0.52 # 30 deg
					var ch := cos(r.car.heading)
					var sh := sin(r.car.heading)
					var vf := r.car.vx * ch + r.car.vy * sh
					var vs := -r.car.vx * sh + r.car.vy * ch
					var bf := atan2(vs + r.car.yaw_rate * r.phys.a, maxf(vf, 0.5))
					var bdot := (b - pb) / DT
					var want := bf + 0.6 * (b - signf(b) * bd) + 0.1 * bdot
					steer = clampf(want / r.lock(signf(want)), -1.0, 1.0)
					thr = clampf(0.75 + 2.0 * (bd - absf(b)), 0.2, 1.0)
			"late":
				# a late, clumsy keyboard catch: full counter-steer only once the slide is past 40 deg, off again under 15
				if t < 0.55:
					st = 1.0
					hb = 1.0 if t > 0.25 else 0.0
					thr = 0.6
				else:
					if absf(b) > 0.7:
						r.set_meta("c", true)
					elif absf(b) < 0.26:
						r.set_meta("c", false)
					st = signf(b) if r.get_meta("c", false) else 1.0
					thr = 0.7
				steer = r.key(steer, st)
		pb = b
		r.step(thr, brk, steer, hb)
		t += DT
		b = r.beta()
		if trace_on and int(round(t / DT)) % 6 == 0:
			print("    t %.2f beta %6.1f yaw %5.2f steer %5.2f delta %5.2f thr %.2f hb %.0f v %5.1f" % [t, rad_to_deg(b), r.car.yaw_rate, steer, r.car.steer, thr, hb, r.speed() * 3.6])
		peak = maxf(peak, absf(b))
		if absf(b) > 1.75:
			spun = true
			break
		if absf(b) > 0.21 and absf(b) < 0.87:
			window += DT
		if not hold_done:
			if absf(b) > 0.175:
				holding = true
				started = true
				held += DT
			elif holding or (started and absf(b) < 0.1):
				hold_done = holding
				holding = false
		var c := atan2(r.car.vy, r.car.vx)
		course += wrapf(c - last_c, -PI, PI)
		last_c = c
		if is_nan(t90) and absf(course) >= PI / 2:
			t90 = t
			v90 = r.speed()
		if is_nan(v4) and t >= 4.0:
			v4 = r.speed()
	return {"peak": rad_to_deg(peak), "spun": spun, "held": held, "window": window, "t90": t90, "v90": v90 * 3.6, "v4": v4 * 3.6, "v0": v0 * 3.6}

var trace_on := false

func _row(name: String, d: Dictionary) -> String:
	return "%-10s peak %5.1f deg %s held %4.2f s  12-50deg %4.2f s  90deg in %5.2f s at %5.1f km/h  v@4s %5.1f" % [
		name, d.peak, "SPIN" if d.spun else "    ", d.held, d.window, d.t90, d.v90, d.v4]

func _initialize() -> void:
	await process_frame
	var only := ""
	var legacy_only := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5)
		if a == "legacy":
			legacy_only = true
		if a.begins_with("trace="):
			# trace=driver:kmh:assists, both handlings
			var p := a.substr(6).split(":")
			trace_on = true
			for lg in [true, false]:
				print("-- trace %s legacy=%s" % [p[0], lg])
				run_one(CarCatalog.model(only if only != "" else "seicento"), p[2], lg, p[0], float(p[1]) / 3.6)
			quit(0)
			return
	var cars := ["seicento", "golf4", "hypercar"] if only == "" else [only]
	for key in cars:
		var cm := CarCatalog.model(key)
		for assists in ["abs", "off", "full"]:
			for v_kmh in [70.0, 100.0]:
				print("== %s  assists=%s  entry %d km/h" % [key, assists, int(v_kmh)])
				for driver in ["grip", "lift", "kb", "pad", "late"]:
					for legacy in ([true] if legacy_only else [true, false]):
						var d := run_one(cm, assists, legacy, driver, v_kmh / 3.6)
						print("  ", _row(("%s %s" % [driver, "old" if legacy else "new"]), d))
	await preload("res://tests/run_tests.gd").release(self)
	quit(0)
