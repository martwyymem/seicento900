## Headless probe of how the Hypercar Seicento feels against the stock Seicento and the Golf, through both simulation paths
## the player drives: the race physics (Physics with the race's assists, automatic box and reverse rule) and FreeCar on a flat
## open-world town. Logs stopping distance, lateral offset from the initial line, yaw, yaw rate, slide angle and how long
## each axle is locked, for braking (straight, perturbed, split-mu, on dirt, over a kerb, after a hop), lift-off, power-on
## and lane-change manoeuvres.
##   timeout 300 godot --headless --path godot -s tests/_hypercar_feel_probe.gd [-- only=hypercar]
## With "kb" it runs only the keyboard scenarios (digital brake and steering keys, ramped as Game._update_input ramps them):
## deceleration and stopping distance from 300 and 250 km/h, steering taps under full braking, a trail-braked 90-degree
## bend, both on the flat rig and inside a real Race on the Goliath (tyres, gradient, the race's assists):
##   timeout 300 godot --headless --path godot -s tests/_hypercar_feel_probe.gd -- kb [only=hypercar] [set=field:value,...]
extends SceneTree

const S := preload("res://tests/test_surfaces.gd")
const DT := 1.0 / 120.0

## The town of test_surfaces with a strip of grass (y > grass_y), a kerb-high step (x > step_x) and a pot-hole patch.
class ProbeTown extends S.FlatTown:
	var grass_y := INF
	var step_x := INF
	var step_h := 0.0
	var pot_x := INF
	func ground(x: float, _y: float) -> float:
		return step_h if x > step_x else 0.0
	func terrain(x: float, y: float) -> float:
		return ground(x, y)
	func road_at(x: float, y: float, _z_ref := -INF, _reach := 0.0) -> Dictionary:
		if y > grass_y:
			return {}
		return {"road": 0, "i": 0, "t": 0.0, "dist": 0.0, "half": 50.0, "deck": 0.0, "surface": 0, "height": ground(x, y)}
	func pothole(x: float, y: float) -> float:
		return 0.08 if x > pot_x and x < pot_x + 40.0 and y > 0.2 and fmod(x, 6.0) < 0.8 else 0.0
	func kerb_at(_x: float, _y: float) -> float:
		return 0.0
	func rail_bank(_x: float, _y: float, _keep_cut := false) -> float:
		return -INF

## One car in one of the two paths. kind "race": Physics stepped as Race.step_free does for the player; "free": FreeCar.
class Rig:
	var kind := "race"
	var model: CarModel
	var phys: Physics
	var env := Physics.Env.new()
	var ctl := Physics.Controls.new()
	var car: RaceCar
	var fc: FreeCar
	var town: ProbeTown
	var assists := "abs"
	var surf := 0
	var grass_y := INF

	func _init(kind_: String, cm: CarModel, assists_: String, surface_id: int) -> void:
		kind = kind_
		model = cm
		assists = assists_
		surf = surface_id
		if kind == "free":
			town = ProbeTown.new()
			town.force_surf = surface_id
			fc = FreeCar.new(town, cm)
			fc.assists = assists
			phys = fc.phys
		else:
			phys = Physics.new(cm)
			env.mass = cm.mass_with_fuel(S.FUEL)
			env.abs_on = assists != "off"
			env.tc_on = assists == "full"
			env.esc_on = assists == "full"
			env.drift_assist = Race.DRIFT_ASSIST_FULL if assists == "full" else (Race.DRIFT_ASSIST_ABS if assists == "abs" else 0.0)
			env.surface = func(_x: float, y: float) -> int: return Physics.SURF_GRASS if y > grass_y else surf

	func set_grass(y: float) -> void:
		grass_y = y
		if town:
			town.grass_y = y

	func reset(v0: float) -> void:
		if kind == "free":
			fc.place(Vector2.ZERO, 0.0)
			fc.rev_lock = false
			car = fc.car
		else:
			car = RaceCar.new()
			car.model = model
			car.physics = phys
			car.fuel = S.FUEL
			car.heading = 0.0
			car.rpm = model.spec.idle_rpm
			car.gear = 0
		car.vx = v0
		car.speed = v0
		# in the gear the box holds at this speed, the engine turning with the wheels
		car.gear = model.best_gear(v0)
		car.rpm = maxf(model.spec.idle_rpm, model.rpm_for(v0, car.gear))
		car.shift_t = 0.0
		car.hold_t = 0.0
		car.phys = null

	func step(thr: float, brk: float, steer: float, hb := 0.0) -> void:
		if kind == "free":
			fc.step(DT, thr, brk, steer, false, false, hb)
			return
		var vF := car.vx * cos(car.heading) + car.vy * sin(car.heading)
		# Race.step_free: reverse by holding the brake at a standstill
		if not car.rev and brk > 0.3 and thr < 0.05 and absf(vF) < 0.4:
			car.rev = true
			car.gear = 0
		elif car.rev and thr > 0.05:
			if vF >= -0.5:
				car.rev = false
		if car.rev:
			var t := thr
			thr = brk
			brk = t
		if not car.rev:
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

	func speed() -> float:
		return sqrt(car.vx * car.vx + car.vy * car.vy)

## Running figures of one manoeuvre.
class Log:
	var dist := 0.0
	var max_y := 0.0
	var max_head := 0.0
	var max_yaw := 0.0
	var max_beta := 0.0
	var lock_f := 0.0 ## s with a front wheel locked (turning under half the road speed)
	var lock_r := 0.0
	var spin_r := 0.0 ## s with a rear wheel spinning 30 % over the road speed
	var t := 0.0
	var max_ay := 0.0
	var max_back := 0.0 ## top speed backwards (m/s)
	var x_min_after := INF
	var x_stop := NAN

	func take(r: Rig) -> void:
		var c := r.car
		var ch := cos(c.heading)
		var sh := sin(c.heading)
		var vf := c.vx * ch + c.vy * sh
		var vl := -c.vx * sh + c.vy * ch
		var v := r.speed()
		t += DT
		dist += v * DT
		max_y = maxf(max_y, absf(c.y))
		max_head = maxf(max_head, absf(c.heading))
		max_yaw = maxf(max_yaw, absf(c.yaw_rate))
		if v > 3.0:
			max_beta = maxf(max_beta, absf(atan2(vl, absf(vf))))
		max_ay = maxf(max_ay, absf(c.yaw_rate) * v)
		max_back = maxf(max_back, -vf)
		if c.phys != null and vf > 3.0:
			var R := r.model.spec.wheel_radius
			var w: PackedFloat64Array = c.phys.w
			if minf(w[0], w[1]) * R < 0.5 * vf:
				lock_f += DT
			if minf(w[2], w[3]) * R < 0.5 * vf:
				lock_r += DT
			if maxf(w[2], w[3]) * R > 1.3 * vf:
				spin_r += DT

	func row() -> String:
		return "y %6.2f m  head %6.1f deg  yaw %5.2f rad/s  beta %5.1f deg  lockF %4.2f s  lockR %4.2f s" % [
			max_y, rad_to_deg(max_head), max_yaw, rad_to_deg(max_beta), lock_f, lock_r]

var only := ""
var brief := false
var trace := false

func _initialize() -> void:
	await process_frame
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5)
		if a == "brief":
			brief = true
	trace = "trace" in OS.get_cmdline_user_args()
	if trace:
		var cmt := CarCatalog.model(only if only != "" else "hypercar")
		for a in OS.get_cmdline_user_args():
			if a.begins_with("set="):
				for kv in a.substr(4).split(","):
					var f := kv.split(":")
					cmt.spec.set(f[0], float(f[1]))
				cmt.refresh()
		var ttap := 0.25
		var tat := -170.0
		for a in OS.get_cmdline_user_args():
			if a.begins_with("tap="):
				ttap = float(a.substr(4))
			if a.begins_with("at="):
				tat = float(a.substr(3))
		_kb_brake(_kb_rig(cmt, "race", "full", 250.0 / 3.6, "goliath"), ttap, tat)
		quit()
		return
	var cars := {"stock": CarCatalog.model("stock"), "golf4": CarCatalog.model("golf4"), "hypercar": CarCatalog.model("hypercar")}
	# set=field:value,field:value tries spec figures on the hypercar without editing hypercar.gd
	for a in OS.get_cmdline_user_args():
		if a.begins_with("set="):
			for kv in a.substr(4).split(","):
				var f := kv.split(":")
				cars.hypercar.spec.set(f[0], float(f[1]))
			cars.hypercar.refresh()
	if "kb" in OS.get_cmdline_user_args():
		for key in cars:
			if only == "" or key == only:
				_keyboard(key, cars[key])
		quit()
		return
	var ids := S.surf_ids()
	for key in cars:
		if only != "" and key != only:
			continue
		var cm: CarModel = cars[key]
		var top := _top_speed(cm)
		print("\n================ %s  (top %.0f km/h) ================" % [key, top * 3.6])
		_figures(cm)
		_axle_balance(cm)
		for path in ([["race", "full"], ["free", "abs"]] if brief else [["race", "full"], ["race", "abs"], ["race", "off"], ["free", "abs"], ["free", "off"]]):
			var tag := "%s/%s" % [path[0], path[1]]
			print("---- %s" % tag)
			for kmh in [100.0, 200.0, 300.0]:
				var v: float = kmh / 3.6
				if v > top * 0.97:
					continue
				var r := Rig.new(path[0], cm, path[1], ids.asphalt)
				print("  brake %3.0f straight      : %s" % [kmh, _brake(r, v, 0.0, 0.0, 0.0)])
				print("  brake %3.0f yaw 0.1 vy 0.5: %s" % [kmh, _brake(r, v, 0.0, 0.1, 0.5)])
				print("  brake %3.0f steer 0.1     : %s" % [kmh, _brake(r, v, 0.1, 0.0, 0.0)])
				print("  brake %3.0f key steer 0.3s: %s" % [kmh, _brake_tap(r, v)])
				r.set_grass(0.0)
				print("  brake %3.0f split-mu      : %s" % [kmh, _brake(r, v, 0.0, 0.0, 0.0)])
			var vh := minf(200.0 / 3.6, top * 0.9)
			var rd := Rig.new(path[0], cm, path[1], ids.dirt)
			print("  brake %3.0f on dirt        : %s" % [minf(vh, 40.0) * 3.6, _brake(rd, minf(vh, 40.0), 0.0, 0.1, 0.3)])
			var rr := Rig.new(path[0], cm, path[1], ids.asphalt)
			print("  trail brake %3.0f          : %s" % [vh * 0.75 * 3.6, _trail(rr, vh * 0.75)])
			print("  lift-off in bend %3.0f     : %s" % [vh * 3.6, _lift(rr, vh)])
			print("  launch, full key steer   : %s" % _launch(rr, 0.0, 1.0))
			print("  power out of 40 km/h bend: %s" % _launch(rr, 40.0 / 3.6, 1.0))
			for f in [0.5, 0.75]:
				print("  key held in a bend %3.0f   : %s" % [top * f * 3.6, _bend(rr, top * f)])
			for kmh in [100.0, 150.0, 250.0]:
				var v: float = kmh / 3.6
				if v > top * 0.97:
					continue
				print("  lane change %3.0f          : %s" % [kmh, _lane(rr, v)])
				print("  steer key held 1 s %3.0f   : %s" % [kmh, _key_hold(rr, v)])
			if path[0] == "free":
				print("  brake %3.0f over a kerb    : %s" % [vh * 3.6, _kerb(cm, path[1], vh, ids.asphalt, true)])
				print("  flat out over a kerb     : %s" % _kerb(cm, path[1], vh, ids.asphalt, false))
				print("  brake %3.0f over potholes  : %s" % [vh * 3.6, _potholes(cm, path[1], vh, ids.asphalt)])
				print("  brake %3.0f after a hop    : %s" % [vh * 3.6, _hop(cm, path[1], vh, ids.asphalt)])
	quit()

func _top_speed(cm: CarModel) -> float:
	var r := Rig.new("race", cm, "abs", S.surf_ids().asphalt)
	r.reset(0.0)
	for k in int(70.0 / DT):
		r.step(1.0, 0.0, 0.0)
	return r.speed()

## Headline figures: 0-100, 0-200, 0-300, top, 100-0, 200-0, 300-0, skidpad g, mid-range acceleration.
func _figures(cm: CarModel) -> void:
	var r := Rig.new("race", cm, "abs", S.surf_ids().asphalt)
	r.reset(0.0)
	var t := 0.0
	var marks := {100: -1.0, 200: -1.0, 300: -1.0}
	var a_peak := 0.0
	var v_prev := 0.0
	var t_30_25 := 0.0
	while t < 70.0:
		r.step(1.0, 0.0, 0.0)
		t += DT
		var v := r.speed()
		for m in marks:
			if marks[m] < 0.0 and v * 3.6 >= m:
				marks[m] = t
		if v < 25.0:
			t_30_25 = t
		v_prev = v
	var m := S.measure(_surf_rig(cm))
	print("  0-100 %.2f s  0-200 %.2f s  0-300 %.2f s  top %.1f km/h  0-25 m/s %.2f s (%.1f m/s2)  skidpad %.2f g  brake100 %.1f m" % [
		marks[100], marks[200], marks[300], r.speed() * 3.6, t_30_25, 25.0 / maxf(t_30_25, 0.01), m.lat_g, m.brake])
	# lateral g at speed: a steady bend at 60 and 80 % of the top speed
	for f in [0.5, 0.75]:
		var v: float = r.speed() * f
		var rr := Rig.new("race", cm, "abs", S.surf_ids().asphalt)
		rr.reset(v)
		var ay := 0.0
		var n := 0
		for k in int(8.0 / DT):
			var err: float = v - rr.speed()
			rr.step(clampf(0.3 + err * 0.6, 0.0, 1.0), 0.0, 1.0)
			if k * DT > 5.0:
				ay += absf(rr.car.yaw_rate) * rr.speed()
				n += 1
		print("  full-lock-input bend at %3.0f km/h: %.2f g (speed held %.0f km/h)" % [v * 3.6, ay / n / 9.81, rr.speed() * 3.6])

func _surf_rig(cm: CarModel):
	var ids := S.surf_ids()
	var r = S.PhysRig.new(ids.asphalt, 1.0)
	r.model = cm
	r.phys = Physics.new(cm)
	r.env.mass = cm.mass_with_fuel(S.FUEL)
	return r

## Which axle the brakes saturate first: brake force asked of each axle against the grip it has at the steady deceleration
## the tyres could give, per speed (over 1 = that axle locks at full pedal).
func _axle_balance(cm: CarModel) -> void:
	var s := cm.spec
	var m := cm.mass_with_fuel(S.FUEL)
	var out := ""
	for kmh in [30.0, 100.0, 200.0, 300.0]:
		var v: float = kmh / 3.6
		var down: float = -0.5 * 1.2 * s.lift_a * v * v
		var W := m * 9.81
		var dec: float = s.grip_k * (W + down) / m * 0.9
		var d_long: float = m * dec * s.cg_height / s.wheelbase
		var ff: float = W * s.front_weight + d_long + down * s.aero_front
		var fr: float = W + down - ff
		var fz0 := W / 4.0
		var mu_f: float = s.grip_k * clampf(1.0 - s.load_sensitivity * (ff / 2.0 / fz0 - 1.0), 0.75, 1.15)
		var mu_r: float = s.grip_k * clampf(1.0 - s.load_sensitivity * (maxf(fr, 0.0) / 2.0 / fz0 - 1.0), 0.75, 1.15)
		out += "  %3.0f: F %.2f R %.2f" % [kmh, 2.0 * s.brake_front / s.wheel_radius / maxf(mu_f * ff, 1.0), 2.0 * s.brake_rear / s.wheel_radius / maxf(mu_r * fr, 1.0)]
	print("  brake demand / axle grip at ~0.9 of the limit (km/h):%s" % out)

## Full brake in one frame from v, held 2.5 s past the stop. yaw0/vy0: a perturbation at the start; steer: held.
func _brake(r: Rig, v: float, steer: float, yaw0: float, vy0: float) -> String:
	r.reset(v)
	r.car.yaw_rate = yaw0
	r.car.vy = vy0
	return _brake_run(r, func(_t: float) -> float: return steer)

## The same with a keyboard tap on the steering: the key held 0.3 s (ramping at the keyboard's rate), then released.
func _brake_tap(r: Rig, v: float) -> String:
	r.reset(v)
	var st := [0.0]
	return _brake_run(r, func(t: float) -> float:
		st[0] = move_toward(st[0], 1.0 if t < 0.3 else 0.0, (2.6 if t < 0.3 else 8.0) * DT)
		return st[0])

func _brake_run(r: Rig, steer_at: Callable) -> String:
	var lg := Log.new()
	var t := 0.0
	var stopped := -1.0
	var x_stop := 0.0
	var gear_lo := 99
	var shifts := 0
	var g_prev := r.car.gear
	while t < 40.0:
		r.step(0.0, 1.0, steer_at.call(t))
		t += DT
		if stopped < 0.0:
			lg.take(r)
			if r.car.gear != g_prev:
				shifts += 1
				g_prev = r.car.gear
			if r.speed() < 0.4 or r.car.rev:
				stopped = t
				x_stop = r.car.x
		else:
			var vf := r.car.vx * cos(r.car.heading) + r.car.vy * sin(r.car.heading)
			lg.max_back = maxf(lg.max_back, -vf)
			if t > stopped + 2.5:
				break
	var back := Vector2(r.car.x - x_stop, r.car.y).length() if stopped >= 0.0 else 0.0
	return "stop %6.1f m in %5.2f s  %s  shifts %d | held 2.5 s on: %5.1f m back at %4.1f km/h" % [lg.dist, stopped, lg.row(), shifts, back, lg.max_back * 3.6]

## Into a bend on the brakes: full key steering (ramping) with the full brake for 1.2 s, then off the brake, still turning.
func _trail(r: Rig, v: float) -> String:
	r.reset(v)
	var lg := Log.new()
	var st := 0.0
	for k in int(3.5 / DT):
		var t := k * DT
		st = move_toward(st, 1.0, 2.6 * DT)
		r.step(0.0 if t < 1.2 else 0.3, 1.0 if t < 1.2 else 0.0, st)
		lg.take(r)
	return "beta %5.1f deg  yaw %5.2f rad/s  turned %6.1f deg  %4.2f g  lockR %4.2f s  end %3.0f km/h" % [
		rad_to_deg(lg.max_beta), lg.max_yaw, rad_to_deg(r.car.heading), lg.max_ay / 9.81, lg.lock_r, r.speed() * 3.6]

## A fast bend held on part throttle near the limit, then the throttle shut with the steering held.
func _lift(r: Rig, v: float) -> String:
	r.reset(v)
	var lg := Log.new()
	var before := Log.new()
	for k in int(6.0 / DT):
		var t := k * DT
		var err := v - r.speed()
		var thr := clampf(0.3 + err * 0.6, 0.0, 1.0) if t < 3.0 else 0.0
		r.step(thr, 0.0, minf(1.0, t * 2.6) * 0.8)
		if t < 3.0:
			before.take(r)
		else:
			lg.take(r)
	return "before: beta %4.1f deg %4.2f g | after the lift: beta %5.1f deg  yaw %5.2f rad/s  end beta %5.1f deg" % [
		rad_to_deg(before.max_beta), before.max_ay / 9.81, rad_to_deg(lg.max_beta), lg.max_yaw, rad_to_deg(_beta(r))]

func _beta(r: Rig) -> float:
	var c := r.car
	var ch := cos(c.heading)
	var sh := sin(c.heading)
	return atan2(-c.vx * sh + c.vy * ch, maxf(absf(c.vx * ch + c.vy * sh), 0.5))

## Full throttle with the steering key held 1.5 s, then straight for 2.5 s.
func _launch(r: Rig, v: float, steer: float) -> String:
	r.reset(v)
	var lg := Log.new()
	var st := 0.0
	for k in int(4.0 / DT):
		var t := k * DT
		st = move_toward(st, steer if t < 1.5 else 0.0, (4.4 if t < 1.5 else 8.0) * DT)
		r.step(1.0, 0.0, st)
		lg.take(r)
	return "beta %5.1f deg  yaw %5.2f rad/s  end beta %5.1f deg  end yaw %5.2f  spinR %4.2f s  end %3.0f km/h  %5.1f m" % [
		rad_to_deg(lg.max_beta), lg.max_yaw, rad_to_deg(_beta(r)), r.car.yaw_rate, lg.spin_r, r.speed() * 3.6, lg.dist]

## A quick left-right on the keys at speed: right 0.35 s, left 0.35 s, then hands off for 3 s.
func _lane(r: Rig, v: float) -> String:
	r.reset(v)
	var lg := Log.new()
	var st := 0.0
	var y_end := 0.0
	for k in int(4.0 / DT):
		var t := k * DT
		var want := 1.0 if t < 0.35 else (-1.0 if t < 0.7 else 0.0)
		var back := want == 0.0 or signf(want) != signf(st)
		st = move_toward(st, want, (8.0 if back else 2.6) * DT)
		var err := v - r.speed()
		r.step(clampf(0.3 + err * 0.6, 0.0, 1.0), 0.0, st)
		lg.take(r)
	return "moved %5.2f m  beta %5.1f deg  yaw %5.2f rad/s  %4.2f g | 3 s on: beta %5.1f deg  yaw %5.2f rad/s  heading %6.1f deg" % [
		r.car.y, rad_to_deg(lg.max_beta), lg.max_yaw, lg.max_ay / 9.81, rad_to_deg(_beta(r)), r.car.yaw_rate, rad_to_deg(r.car.heading)]

## The steering key held through a long bend, the speed held: the lateral g the car settles at and its slide angle.
func _bend(r: Rig, v: float) -> String:
	r.reset(v)
	var ay := 0.0
	var n := 0
	var beta := 0.0
	var lg := Log.new()
	for k in int(8.0 / DT):
		var err := v - r.speed()
		r.step(clampf(0.3 + err * 0.6, 0.0, 1.0), 0.0, minf(1.0, k * DT * 2.6))
		lg.take(r)
		if k * DT > 5.0:
			ay += absf(r.car.yaw_rate) * r.speed()
			beta += absf(_beta(r))
			n += 1
	return "%4.2f g  beta %5.1f deg (peak %5.1f)  speed held %3.0f km/h" % [ay / n / 9.81, rad_to_deg(beta / n), rad_to_deg(lg.max_beta), r.speed() * 3.6]

## The steering key held for a second at speed, flat out: how much the car turns and whether it lets go.
func _key_hold(r: Rig, v: float) -> String:
	r.reset(v)
	var lg := Log.new()
	var st := 0.0
	for k in int(3.0 / DT):
		var t := k * DT
		st = move_toward(st, 1.0 if t < 1.0 else 0.0, (2.6 if t < 1.0 else 8.0) * DT)
		r.step(1.0, 0.0, st)
		lg.take(r)
	return "beta %5.1f deg  yaw %5.2f rad/s  %4.2f g  steer angle %4.1f deg | 2 s on: beta %5.1f deg  yaw %5.2f rad/s" % [
		rad_to_deg(lg.max_beta), lg.max_yaw, lg.max_ay / 9.81, rad_to_deg(r.phys.max_steer(v, 1.0)), rad_to_deg(_beta(r)), r.car.yaw_rate]

## FreeCar over a kerb-high step (0.13 m) 30 m ahead, the left wheels' side first (the car crosses it at a slight angle).
func _kerb(cm: CarModel, assists: String, v: float, surf: int, braking: bool) -> String:
	var r := Rig.new("free", cm, assists, surf)
	r.town.step_x = 30.0
	r.town.step_h = 0.13
	r.reset(v)
	r.car.heading = 0.03
	r.car.vx = v * cos(0.03)
	r.car.vy = v * sin(0.03)
	var lg := Log.new()
	var air := 0.0
	var y_line := 0.0
	for k in int(8.0 / DT):
		r.step(0.0 if braking else 1.0, 1.0 if braking else 0.0, 0.0)
		if r.speed() < 0.4 or r.car.rev:
			break
		lg.take(r)
		if r.fc.airborne:
			air += DT
		y_line = maxf(y_line, absf(r.car.y - r.car.x * tan(0.03)))
	return "off line %5.2f m  head %5.1f deg  yaw %5.2f rad/s  beta %5.1f deg  air %4.2f s  stop %5.1f m  lockR %4.2f s" % [
		y_line, rad_to_deg(lg.max_head), lg.max_yaw, rad_to_deg(lg.max_beta), air, lg.dist, lg.lock_r]

func _potholes(cm: CarModel, assists: String, v: float, surf: int) -> String:
	var r := Rig.new("free", cm, assists, surf)
	r.town.pot_x = 10.0
	r.reset(v)
	return _brake_run(r, func(_t: float) -> float: return 0.0)

## Braking while the car is in the air for a moment (a crest), then landing on the brakes.
func _hop(cm: CarModel, assists: String, v: float, surf: int) -> String:
	var r := Rig.new("free", cm, assists, surf)
	r.reset(v)
	r.step(0.0, 0.0, 0.0)
	r.fc.airborne = true
	r.fc.vz = 2.5
	r.car.yaw_rate = 0.05
	return _brake_run(r, func(_t: float) -> float: return 0.0)

# ---------------- keyboard scenarios ----------------

## A driving rig for the keyboard runs: the flat-road Rig, or the player's car in a real Race on a real track.
class KbRig:
	var rig: Rig
	var race: Race
	var car: RaceCar
	var steer := 0.0
	var brake := 0.0
	var thr := 0.0
	var input := Race.PlayerInput.new()
	var x0 := 0.0
	var y0 := 0.0
	var h0 := 0.0

	## The keyboard's steering as Game._update_input ramps it: towards the key at 4.4/s under 40 km/h, 2.6/s from 120 km/h up,
	## back to the centre (or across) at 8/s. key: -1, 0 or 1.
	static func kb_steer(steer: float, key: float, v: float, dt: float) -> float:
		var back := key == 0.0 or signf(key) != signf(steer)
		var v_kmh := absf(v) * 3.6
		var rate := 4.4 if v_kmh < 40.0 else lerpf(4.4, 2.6, clampf((v_kmh - 40.0) / 80.0, 0.0, 1.0))
		return move_toward(steer, key, (8.0 if back else rate) * dt)

	func speed() -> float:
		return sqrt(car.vx * car.vx + car.vy * car.vy)

	## Lateral offset from the starting line, and the heading against it.
	func off_line() -> float:
		return -(car.x - x0) * sin(h0) + (car.y - y0) * cos(h0)

	func head() -> float:
		return wrapf(car.heading - h0, -PI, PI)

	func beta() -> float:
		var ch := cos(car.heading)
		var sh := sin(car.heading)
		return atan2(-car.vx * sh + car.vy * ch, maxf(absf(car.vx * ch + car.vy * sh), 0.5))

	## One 1/120 s frame with the keys: up/down (0/1) and the steering key (-1, 0, 1).
	func key_step(up: float, down: float, key: float) -> void:
		var dt := 1.0 / 120.0
		thr = move_toward(thr, up, 6.0 * dt)
		brake = move_toward(brake, down, 8.0 * dt)
		steer = kb_steer(steer, key, speed(), dt)
		if race:
			input.throttle = thr
			input.brake = brake
			input.steer = steer
			race.step(dt, input)
		else:
			rig.step(thr, brake, steer)

## A fresh run at v on the rig (path, assists) or, with track set, on that track's longest straight in a race.
func _kb_rig(cm: CarModel, path: String, assists: String, v: float, track := "") -> KbRig:
	var k := KbRig.new()
	if track == "":
		k.rig = Rig.new(path, cm, assists, S.surf_ids().asphalt)
		k.rig.reset(v)
		k.car = k.rig.car
	else:
		var rs := RaceSettings.new()
		rs.track = track
		rs.laps = 3
		rs.opponents = 0
		rs.car_class = "hypercar" if cm.spec.resource_name == "hypercar" else "stock"
		rs.race_control = false
		rs.collisions = false
		rs.assists = assists
		k.race = Race.new(rs, {"stints": [{"c": "M", "laps": 3}]}, 7, {"car_model": cm, "tyres": Tyres.new(), "strategy": Strategy.new(cm, Tyres.new())})
		var idle := Race.PlayerInput.new()
		var n := 0
		while k.race.phase != "racing" and n < 120 * 30:
			k.race.step(1.0 / 120.0, idle)
			n += 1
		var p := k.race.player
		var tr := k.race.track
		var s0 := _straight(tr, v)
		var pos := tr.pos(s0, tr.sample(tr.RLD, s0))
		p.s = s0
		p.x = pos[0]
		p.y = pos[1]
		p.d = tr.sample(tr.RLD, s0)
		p.heading = tr.heading(s0)
		p.vx = v * cos(p.heading)
		p.vy = v * sin(p.heading)
		p.yaw_rate = 0.0
		p.v = v
		p.speed = v
		p.gear = cm.best_gear(v)
		p.rpm = maxf(cm.spec.idle_rpm, cm.rpm_for(v, p.gear))
		p.phys = null
		p.rev = false
		p.control = "free"
		k.car = p
	k.x0 = k.car.x
	k.y0 = k.car.y
	k.h0 = k.car.heading
	return k

## The start of the track's straightest stretch long enough to stop from v (the stopping distance at 1 g, and 250 m).
func _straight(tr: Track, v: float) -> float:
	var need := maxf(250.0, v * v / (2.0 * 9.81) + 60.0)
	var best := 0.0
	var best_k := INF
	var s := 0.0
	while s < tr.L:
		var worst := 0.0
		var x := 0.0
		while x < need:
			worst = maxf(worst, absf(tr.sample(tr.RK, s + x)))
			x += 10.0
		if worst < best_k:
			best_k = worst
			best = s
		s += 25.0
	return best

class KbLog:
	var dist := 0.0
	var t := 0.0
	var max_beta := 0.0
	var max_head := 0.0
	var max_off := 0.0
	var dec := {} ## km/h mark -> g, from the speed lost over the 10 km/h round the mark
	var _mark_t := {}

	var v_start := -1.0
	var grass := 0.0 ## s with the outer wheels past the road's edge (race runs)
	var wall := false ## the car reached the barrier

	func take(k: KbRig, dt: float) -> void:
		var v := k.speed()
		if v_start < 0.0:
			v_start = v
		t += dt
		dist += v * dt
		if v > 3.0:
			max_beta = maxf(max_beta, absf(k.beta()))
		max_head = maxf(max_head, absf(k.head()))
		max_off = maxf(max_off, absf(k.off_line()))
		if k.race:
			var tr := k.race.track
			var hw: float = k.car.model.spec.width / 2.0
			if absf(k.car.d) > tr.half + 0.3 - hw:
				grass += dt
			var lim := tr.limits(k.car.s)
			if k.car.d > lim[1] - hw - 0.1 or k.car.d < lim[0] + hw + 0.1:
				wall = true
		for m in [300.0, 250.0, 200.0, 150.0, 100.0, 50.0]:
			var hi: float = (m + 5.0) / 3.6
			var lo: float = (m - 5.0) / 3.6
			if not _mark_t.has(m) and v <= hi and v_start > hi + 0.5:
				_mark_t[m] = t
			if _mark_t.has(m) and not dec.has(m) and v <= lo:
				dec[m] = (hi - lo) / maxf(t - float(_mark_t[m]), 1e-6) / 9.81

	func g_row() -> String:
		var out := ""
		for m in [300.0, 250.0, 200.0, 150.0, 100.0, 50.0]:
			if dec.has(m):
				out += " %3.0f:%4.2f" % [m, dec[m]]
		return out

## Full brake (the key held) from v to a stop; tap: the steering key held this long from tap_at (s) or, with tap_at < 0,
## from the moment the car is down to -tap_at km/h; hold_steer: the key held to the stop.
func _kb_brake(k: KbRig, tap := 0.0, tap_at := 0.0, hold_steer := false) -> KbLog:
	var lg := KbLog.new()
	var dt := 1.0 / 120.0
	var t_on := -1.0 if tap_at < 0.0 else tap_at
	while lg.t < 20.0:
		if t_on < 0.0 and k.speed() * 3.6 <= -tap_at:
			t_on = lg.t
		var key := 0.0
		if t_on >= 0.0 and lg.t >= t_on and (hold_steer or lg.t < t_on + tap):
			key = 1.0
		k.key_step(0.0, 1.0, key)
		lg.take(k, dt)
		if trace and int(round(lg.t / dt)) % 6 == 0:
			var c := k.car
			var ph: PhysState = c.phys
			var extra := ""
			if k.race:
				var tr := k.race.track
				extra = "  d %5.2f half %4.2f surf %s mu %.3f" % [c.d, tr.half, [k.race._surface_fn.call(c.x, c.y)], k.race.grip(c)]
			print("    t %4.2f v %5.1f st %5.2f beta %6.1f head %6.1f yaw %5.2f absk %s rho %s fz %s%s" % [lg.t, k.speed() * 3.6, k.steer,
				rad_to_deg(k.beta()), rad_to_deg(k.head()), c.yaw_rate, _fmt(ph.abs_k), _fmt(ph.rho), _fmt(ph.fz, 0), extra])
		if k.speed() < 0.5 or k.car.rev:
			break
	return lg

func _fmt(a: PackedFloat64Array, dec := 2) -> String:
	var o := []
	for x in a:
		o.append(("%." + str(dec) + "f") % x)
	return "[" + ",".join(o) + "]"

## Trail-braking into a 90-degree right-hander from v: the brake key and the steering key go down together, the brake is
## let go when the car is down to v_apex, the steering key is held until the car has turned 90 degrees, then the throttle.
func _kb_trail(k: KbRig, v_apex: float) -> String:
	var lg := KbLog.new()
	var dt := 1.0 / 120.0
	var braking := true
	var turned := false
	var t_turn := -1.0
	while lg.t < 8.0:
		if braking and k.speed() <= v_apex:
			braking = false
		if not turned and absf(k.head()) >= PI / 2.0:
			turned = true
			t_turn = lg.t
		k.key_step(0.0 if braking or not turned else 1.0, 1.0 if braking else 0.0, 0.0 if turned else 1.0)
		lg.take(k, dt)
		if turned and lg.t > t_turn + 1.5:
			break
	return "turned 90 in %s  beta max %5.1f deg  end beta %5.1f deg  yaw %5.2f rad/s  end %3.0f km/h%s" % [
		("%4.2f s" % t_turn) if t_turn > 0.0 else " never", rad_to_deg(lg.max_beta), rad_to_deg(k.beta()), k.car.yaw_rate, k.speed() * 3.6,
		"  SPUN" if lg.max_beta > deg_to_rad(30.0) else ""]

func _kb_row(lg: KbLog) -> String:
	return "stop %6.1f m %5.2f s  beta %5.1f  head %5.1f deg  off line %5.2f m%s%s%s" % [
		lg.dist, lg.t, rad_to_deg(lg.max_beta), rad_to_deg(lg.max_head), lg.max_off,
		"  grass %.2f s" % lg.grass if lg.grass > 0.0 else "", "  WALL" if lg.wall else "", "  SPUN" if lg.max_beta > deg_to_rad(30.0) else ""]

func _keyboard(key: String, cm: CarModel) -> void:
	print("\n================ %s: keyboard ================" % key)
	for where in [["race", "full", ""], ["free", "abs", ""], ["race", "full", "goliath"], ["race", "abs", "goliath"]]:
		var tag: String = "%s/%s%s" % [where[0], where[1], (" on " + where[2]) if where[2] != "" else ""]
		print("---- %s" % tag)
		for kmh in [300.0, 250.0]:
			var lg := _kb_brake(_kb_rig(cm, where[0], where[1], kmh / 3.6, where[2]))
			print("  brake %3.0f              : %s  g%s" % [kmh, _kb_row(lg), lg.g_row()])
		for tap in [0.1, 0.25, 0.5]:
			print("  250, tap %.2f s at once : %s" % [tap, _kb_row(_kb_brake(_kb_rig(cm, where[0], where[1], 250.0 / 3.6, where[2]), tap, 0.0))])
			print("  250, tap %.2f s at 170  : %s" % [tap, _kb_row(_kb_brake(_kb_rig(cm, where[0], where[1], 250.0 / 3.6, where[2]), tap, -170.0))])
		print("  250, key held to stop  : %s" % _kb_row(_kb_brake(_kb_rig(cm, where[0], where[1], 250.0 / 3.6, where[2]), 0.0, 0.0, true)))
		print("  250, key held from 170 : %s" % _kb_row(_kb_brake(_kb_rig(cm, where[0], where[1], 250.0 / 3.6, where[2]), 0.0, -170.0, true)))
		if where[2] == "":
			for va in [120.0, 90.0]:
				print("  trail 180 into a 90, off the brake at %3.0f: %s" % [va, _kb_trail(_kb_rig(cm, where[0], where[1], 180.0 / 3.6), va / 3.6)])
