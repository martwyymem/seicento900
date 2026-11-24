## Headless probe of the Hypercar Seicento on a keyboard (roadmap B3): the handling figures and a scripted keyboard driver
## round one lap of the Goliath.
##   timeout 900 godot --headless --path godot -s tests/_hypercar_goliath_kb.gd -- [metrics] [drive] [car=hypercar|stock]
##       [aids=default|beginner|abs|off] [k=0.95] [fb=1.0] [delay=0.12] [analog] [zones] [set=field:value,...]
## metrics: top speed, braking 300->100 km/h (the brake key ramped as Game._update_input ramps it), the steady-state
## understeer gradient (deg of road-wheel angle per g beyond the geometric L/R) and the axle that saturates, from 60 to
## 300 km/h, and the keyboard's steering (road-wheel angle at full key, time to it, the heading a 0.1 s tap turns).
## drive: one lap of the Goliath in a Race (no rivals, the campaign's default aids unless aids= says otherwise) driven
## with the keys: the steering key pressed and released round the line the bots steer for (Driver.line_steer, seen
## `delay` s late, the key held until the wanted lock is passed), the brake key down while the car is faster than the
## track's speed profile for this car (Track.profile_for) times k allows with the braking envelope times fb, the throttle
## key up while it is slower. Logs every barrier contact, time off the road and the hardest braking zones.
## preview: how far ahead the driver looks along the line, s (0.6).
## analog: the same driver with an analog stick (exactly the wanted steering), to separate the keys from the car.
extends SceneTree

const DT := 1.0 / 120.0
const S := preload("res://tests/test_surfaces.gd")
const Probe := preload("res://tests/_hypercar_feel_probe.gd")

var car_key := "hypercar"
var aids_name := "default"
var k_pace := 0.95
var f_brake := 1.0
var delay := 0.12
var analog := false
var sets := {}
var trace_from := -1.0
var preview := 0.6
var trace_to := INF

const AIDS := {
	"default": {"abs": true, "tc": true, "esc": false, "steer": false, "brake": false},
	"beginner": {"abs": true, "tc": true, "esc": true, "steer": true, "brake": true},
	"abs": {"abs": true, "tc": false, "esc": false, "steer": false, "brake": false},
	"off": {"abs": false, "tc": false, "esc": false, "steer": false, "brake": false},
}

func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("car="):
			car_key = a.substr(4)
		elif a.begins_with("aids="):
			aids_name = a.substr(5)
		elif a.begins_with("k="):
			k_pace = float(a.substr(2))
		elif a.begins_with("fb="):
			f_brake = float(a.substr(3))
		elif a.begins_with("delay="):
			delay = float(a.substr(6))
		elif a.begins_with("preview="):
			preview = float(a.substr(8))
		elif a.begins_with("trace="):
			var tt := a.substr(6).split(":")
			trace_from = float(tt[0])
			trace_to = float(tt[1])
		elif a.begins_with("set="):
			for kv in a.substr(4).split(","):
				var f := kv.split(":")
				sets[f[0]] = float(f[1])
	analog = "analog" in args
	var cm := _model()
	if "metrics" in args or not ("drive" in args or "weave" in args):
		_metrics(cm)
	if "weave" in args:
		_weaves(cm)
		_slow(cm)
	if "drive" in args:
		_drive(cm, "zones" in args)
	quit()

func _model() -> CarModel:
	var cm := CarCatalog.model(car_key)
	for f in sets:
		cm.spec.set(f, sets[f])
	cm.refresh()
	return cm

# ------------------------------------------------------------------------------------------------ metrics

func _rig(cm: CarModel):
	var r = Probe.Rig.new("race", cm, "abs", S.surf_ids().asphalt)
	r.env.tc_on = true # the campaign's default aids: ABS and traction control
	r.env.drift_handling = Physics.player_drift_handling # as Race gives the player
	return r

func _metrics(cm: CarModel) -> void:
	print("\n==== %s metrics (set %s)" % [car_key, sets])
	# top speed
	var r = _rig(cm)
	r.reset(0.0)
	var t := 0.0
	var t300 := -1.0
	while t < 70.0:
		r.step(1.0, 0.0, 0.0)
		t += DT
		if t300 < 0.0 and r.speed() * 3.6 >= 300.0:
			t300 = t
	print("  top %.1f km/h   0-300 %.2f s" % [r.speed() * 3.6, t300])
	# braking with the key (ramped 8/s) from 300, 250 and 200 to 100 km/h
	for v0 in [340.0, 300.0, 250.0, 200.0]:
		if v0 / 3.6 > r.speed() * 0.99:
			continue
		var rb = _rig(cm)
		rb.reset(v0 / 3.6)
		var brk := 0.0
		var d := 0.0
		var tb := 0.0
		while rb.speed() > 100.0 / 3.6 and tb < 20.0:
			brk = move_toward(brk, 1.0, 8.0 * DT)
			rb.step(0.0, brk, 0.0)
			d += rb.speed() * DT
			tb += DT
		print("  brake key %3.0f->100 km/h: %6.1f m  %4.2f s  (mean %.2f g)" % [v0, d, tb, (v0 - 100.0) / 3.6 / tb / 9.81])
	# steady-state cornering: speed held, steering input fixed
	print("  steady state (speed held): input -> road wheel deg, lateral g, understeer gradient deg/g, slide deg, front/rear rho")
	for kmh in [60.0, 100.0, 150.0, 200.0, 250.0, 300.0]:
		var line := "  %3.0f km/h:" % kmh
		for u in [0.25, 0.5, 0.75, 1.0]:
			var ss := _steady(cm, kmh / 3.6, u)
			line += "  [%.2f] %4.2f° %4.2fg K%+5.2f b%+5.1f %4.2f/%4.2f%s" % [u, ss.delta, ss.g, ss.k, ss.beta, ss.rf, ss.rr, " SPIN" if ss.spun else ""]
		print(line)
	# keyboard steering: what a key does at each speed
	print("  keyboard: full-key road-wheel deg, s to full key, heading deg after a 0.1 s / 0.25 s tap (1.5 s later), peak yaw rad/s")
	for kmh in [40.0, 80.0, 120.0, 160.0, 200.0, 250.0, 300.0]:
		var v: float = kmh / 3.6
		var lock := rad_to_deg(cm.spec.steer_lock if v < 1.0 else Physics.new(cm).max_steer(v, 1.0))
		var t_full := 0.0
		var st := 0.0
		while st < 1.0:
			st = Physics.key_steer(st, 1.0, kmh, 0.0, DT)
			t_full += DT
		var taps := ""
		for tap in [0.1, 0.25]:
			var tp := _tap(cm, v, tap)
			taps += "  tap %.2f: %5.1f° (yaw %.2f)" % [tap, tp.x, tp.y]
		print("  %3.0f km/h: lock %5.2f°  full in %.2f s%s" % [kmh, lock, t_full, taps])

## Weave: the steering key right for half a period, left for the next half, 4 periods, at v with full throttle (full) or
## the throttle holding the speed. Peak slide angle and yaw rate, and the rear slide (Physics.rear_slide) peak.
func _weave(cm: CarModel, v: float, period: float, full: bool) -> Vector3:
	var r = _rig(cm)
	r.reset(v)
	var st := 0.0
	var t := 0.0
	var pb := 0.0
	var py := 0.0
	var pr := 0.0
	while t < period * 4.0:
		var key := 1.0 if fmod(t, period) < period / 2.0 else -1.0
		st = Physics.key_steer(st, key, r.speed() * 3.6, r.phys.rear_slide(r.car), DT)
		var err: float = v - r.speed()
		r.step(1.0 if full else clampf(0.2 + err * 0.8, 0.0, 1.0), 0.0, st)
		pb = maxf(pb, absf(_beta(r.car)))
		py = maxf(py, absf(r.car.yaw_rate))
		pr = maxf(pr, absf(r.phys.rear_slide(r.car)))
		t += DT
	return Vector3(rad_to_deg(pb), py, rad_to_deg(pr))

## A run at v with the steering at u (ramped in by key rate) and the throttle holding the speed; averages after 4 s.
func _steady(cm: CarModel, v: float, u: float) -> Dictionary:
	var r = _rig(cm)
	r.reset(v)
	var st := 0.0
	var acc := {"delta": 0.0, "ay": 0.0, "yaw": 0.0, "beta": 0.0, "rf": 0.0, "rr": 0.0}
	var n := 0
	var spun := false
	for k in int(7.0 / DT):
		st = move_toward(st, u, 2.0 * DT)
		var err: float = v - r.speed()
		r.step(clampf(0.2 + err * 0.8, 0.0, 1.0), clampf(-err * 0.3 - 0.1, 0.0, 1.0), st)
		var b: float = _beta(r.car)
		if absf(b) > deg_to_rad(25.0):
			spun = true
		if k * DT > 4.5:
			var ph: PhysState = r.car.phys
			acc.delta += r.car.steer
			acc.ay += r.car.yaw_rate * r.speed()
			acc.yaw += r.car.yaw_rate
			acc.beta += b
			acc.rf += maxf(ph.rho[0], ph.rho[1])
			acc.rr += maxf(ph.rho[2], ph.rho[3])
			n += 1
	for key in acc:
		acc[key] /= n
	var vs: float = maxf(r.speed(), 1.0)
	var ay: float = acc.ay
	var geo: float = cm.spec.wheelbase * acc.yaw / vs # L/R
	var g := absf(ay) / 9.81
	return {"delta": rad_to_deg(acc.delta), "g": g, "k": rad_to_deg(acc.delta - geo) / maxf(g, 0.05), "beta": rad_to_deg(acc.beta),
		"rf": acc.rf, "rr": acc.rr, "spun": spun}

func _beta(c: RaceCar) -> float:
	var ch := cos(c.heading)
	var sh := sin(c.heading)
	return atan2(-c.vx * sh + c.vy * ch, maxf(absf(c.vx * ch + c.vy * sh), 0.5))

## A tap of the steering key at v, throttle holding the speed: heading turned 1.5 s after, and the peak yaw rate.
func _tap(cm: CarModel, v: float, tap: float) -> Vector2:
	var r = _rig(cm)
	r.reset(v)
	var st := 0.0
	var t := 0.0
	var peak := 0.0
	while t < tap + 1.5:
		st = Physics.key_steer(st, 1.0 if t < tap else 0.0, r.speed() * 3.6, 0.0, DT)
		var err: float = v - r.speed()
		r.step(clampf(0.2 + err * 0.8, 0.0, 1.0), 0.0, st)
		peak = maxf(peak, absf(r.car.yaw_rate))
		t += DT
	return Vector2(rad_to_deg(absf(r.car.heading)), peak)

## Slow bends with the steering key held: steady at v (throttle holding the speed) for 3 s, then for 2 s either the throttle
## key (power-on exit), the brake key (braking in the bend) or a lift. Peak slide and rear slip after the change, deg.
func _slow(cm: CarModel) -> void:
	print("  slow bend, key held (peak slide / rear slip deg after the change)  TC on | TC off:")
	for kmh in [40.0, 60.0, 80.0, 110.0, 140.0]:
		var line := "  %3.0f km/h:" % kmh
		for what in ["power", "brake", "lift"]:
			line += "  %s" % what
			for tc in [true, false]:
				var r = _rig(cm)
				r.env.tc_on = tc
				var v: float = kmh / 3.6
				r.reset(v)
				var st := 0.0
				var thr := 0.0
				var brk := 0.0
				var t := 0.0
				var pb := 0.0
				var pr := 0.0
				while t < 5.0:
					st = Physics.key_steer(st, 1.0, r.speed() * 3.6, r.phys.rear_slide(r.car), DT)
					var err: float = v - r.speed()
					if t < 3.0:
						thr = clampf(0.2 + err * 0.8, 0.0, 1.0)
						brk = 0.0
					else:
						thr = move_toward(thr, 1.0 if what == "power" else 0.0, (6.0 if what == "power" else 20.0) * DT)
						brk = move_toward(brk, 1.0 if what == "brake" else 0.0, 8.0 * DT)
						pb = maxf(pb, absf(_beta(r.car)))
						pr = maxf(pr, absf(r.phys.rear_slide(r.car)))
					r.step(thr, brk, st)
					t += DT
				line += " %4.1f/%4.1f" % [rad_to_deg(pb), rad_to_deg(pr)]
		print(line)

func _weaves(cm: CarModel) -> void:
	print("  weave (key alternating; peak slide deg / yaw rad/s / rear slip deg), full throttle | speed held:")
	for kmh in [60.0, 100.0, 150.0, 200.0, 250.0]:
		var line := "  %3.0f km/h:" % kmh
		for per in [0.6, 1.0, 1.6]:
			var a := _weave(cm, kmh / 3.6, per, true)
			var b := _weave(cm, kmh / 3.6, per, false)
			line += "  T%.1f %4.1f/%4.2f/%4.1f | %4.1f/%4.2f/%4.1f" % [per, a.x, a.y, a.z, b.x, b.y, b.z]
		print(line)

# ------------------------------------------------------------------------------------------------ the Goliath

class Contact:
	var s := 0.0
	var kmh := 0.0
	var vn := 0.0 ## km/h into the wall
	var t := 0.0

func _drive(cm: CarModel, zones: bool) -> void:
	var rs := RaceSettings.new()
	rs.track = "goliath"
	rs.laps = 1
	rs.opponents = 0
	rs.car_class = "hypercar" if cm.spec.resource_name == "hypercar" else "stock"
	rs.race_control = false
	rs.collisions = false
	rs.aids = AIDS[aids_name]
	rs.fuel_mult = 0.0
	rs.wear_mult = 0.0
	var race := Race.new(rs, {"stints": [{"c": "M", "laps": 1}]}, 7, {"car_model": cm, "tyres": Tyres.new(), "strategy": Strategy.new(cm, Tyres.new())})
	var tr := race.track
	var car := race.player
	var input := Race.PlayerInput.new()
	var steer := 0.0
	var thr := 0.0
	var brk := 0.0
	var key := 0.0
	var want_q: Array[float] = []
	var nq := maxi(0, int(round(delay / DT)))
	var t := 0.0
	var contacts: Array[Contact] = []
	var last_wall := -INF
	var off_t := 0.0
	var spins := 0
	var spun := false
	var top := 0.0
	var resets := 0
	var max_beta := 0.0
	# per braking zone: [s0, s1] of each stretch where the brake key is down
	var brake_zones := []
	var in_zone := false
	var zone := {}
	var prof := tr.PROF
	var gr := cm.spec.grip_k / 1.4
	var aero := gr * 0.5 * 1.225 * maxf(0.0, -cm.spec.lift_a) / cm.mass_with_fuel(cm.spec.tank * 0.5)
	var lap_s := 0.0
	var prev_s := car.s
	while race.phase != "finished" and t < 1200.0:
		var ch := cos(car.heading)
		var sh := sin(car.heading)
		var v := car.vx * ch + car.vy * sh
		var racing := race.phase == "racing"
		var mu := race.grip(car)
		# ---- speed: the profile for this car, scaled, and the braking that leads to it
		var v_ref := INF
		var x := 0.0
		var lead := v * delay
		while x < 700.0:
			var va: float = tr.sample(prof, car.s + lead + x) * k_pace * sqrt(mu)
			var a_b: float = (9.81 * gr * 0.92 * mu + aero * mu * va * va) * f_brake
			var room := va * va + 2.0 * a_b * x
			v_ref = minf(v_ref, sqrt(room))
			if room > v * v + 2500.0:
				break
			x += 5.0
		var up := 0.0
		var down := 0.0
		if racing:
			if v > v_ref + 1.0:
				down = 1.0
			elif v < v_ref - 1.0:
				up = 1.0
		# ---- steering: the bots' line steer, seen `delay` late, through the keys
		var want := _pursuit(car.physics, tr, car, mu)
		want_q.append(want)
		var w: float = want_q.pop_front() if want_q.size() > nq else want_q[0]
		if analog:
			steer = w
		else:
			var db := 0.05
			if w > steer + db:
				key = 1.0
			elif w < steer - db:
				key = -1.0 if w < -db else 0.0
			elif absf(w) < db:
				key = 0.0
			steer = Physics.key_steer(steer, key, absf(car.speed) * 3.6, car.physics.rear_slide(car), DT)
		thr = move_toward(thr, up, 6.0 * DT)
		brk = move_toward(brk, down, 8.0 * DT)
		input.throttle = thr
		input.brake = brk
		input.steer = steer
		var wall_before := race._player_wall_t
		var vx0 := car.vx
		var vy0 := car.vy
		race.step(DT, input)
		t += DT
		if trace_from >= 0.0 and racing and car.s >= trace_from and car.s <= trace_to and int(round(t / DT)) % 12 == 0:
			print("    s %6.0f v %5.1f ref %5.1f prof %5.1f thr %.2f brk %.2f st %+5.2f want %+5.2f gear %d rpm %4.0f d %+5.2f beta %+5.1f tc %.2f" % [
				car.s, v * 3.6, v_ref * 3.6, tr.sample(prof, car.s) * 3.6, thr, brk, steer, want, car.gear, car.rpm, car.d, rad_to_deg(_beta(car)), car.phys.tc if car.phys else 1.0])
		if not racing:
			prev_s = car.s
			continue
		lap_s += tr.rel(car.s - prev_s)
		prev_s = car.s
		top = maxf(top, car.speed)
		var b := absf(_beta(car))
		if car.speed > 5.0:
			max_beta = maxf(max_beta, b)
		if b > deg_to_rad(35.0) and car.speed > 5.0:
			if not spun:
				spins += 1
				spun = true
		elif b < deg_to_rad(10.0):
			spun = false
		if absf(car.d) > tr.half + 0.3 - cm.spec.width / 2.0:
			off_t += DT
		if race._player_wall_t != wall_before:
			if race.clock - last_wall > 0.6:
				var c := Contact.new()
				c.s = car.s
				c.kmh = sqrt(vx0 * vx0 + vy0 * vy0) * 3.6
				var nx := tr.sample(tr.NX, car.s)
				var ny := tr.sample(tr.NY, car.s)
				c.vn = absf(vx0 * nx + vy0 * ny) * 3.6
				c.t = race.race_time
				contacts.append(c)
			last_wall = race.clock
		if down > 0.0 and not in_zone:
			in_zone = true
			zone = {"s0": car.s, "v0": v * 3.6, "vmin": v * 3.6, "dmax": 0.0, "walls": 0, "beta": 0.0}
		if in_zone:
			zone.vmin = minf(zone.vmin, v * 3.6)
			var lim := tr.limits(car.s)
			var room := minf(lim[1] - car.d, car.d - lim[0]) - cm.spec.width / 2.0
			zone.dmax = maxf(zone.dmax, -room)
			zone.beta = maxf(zone.beta, rad_to_deg(b))
			if race._player_wall_t != wall_before:
				zone.walls += 1
			# the zone runs until the car is back on the throttle and 150 m past the brake release
			if up > 0.0 and tr.rel(car.s - zone.s0) > 150.0 and v > zone.vmin / 3.6 + 3.0:
				in_zone = false
				zone.s1 = car.s
				brake_zones.append(zone)
	var total_damage := car.damage
	var heavy := contacts.filter(func(c): return c.vn > 15.0).size()
	print("\n==== %s on the Goliath, %s, aids %s, k %.2f, fb %.2f, delay %.2f s (set %s)" % [car_key, "ANALOG" if analog else "keys", aids_name, k_pace, f_brake, delay, sets])
	print("  phase %s  lap %s  top %.0f km/h  wall contacts %d (%d over 15 km/h into the wall)  off road %.1f s  spins %d  max slide %.1f°  damage %.2f" % [
		race.phase, ("%.1f s" % float(car.finish_time)) if car.finish_time != null else "DNF (%.0f m in %.0f s)" % [lap_s, t], top * 3.6, contacts.size(), heavy, off_t, spins,
		rad_to_deg(max_beta), total_damage])
	for c in contacts:
		print("    wall at s %6.0f  %3.0f km/h, %4.1f km/h into it  (t %.0f s)" % [c.s, c.kmh, c.vn, c.t])
	if zones:
		brake_zones.sort_custom(func(a, b2): return a.v0 - a.vmin > b2.v0 - b2.vmin)
		print("  hardest braking zones (s, entry -> min km/h, how far past the road edge m, slide deg, walls):")
		for z in brake_zones.slice(0, 10):
			print("    s %6.0f  %3.0f -> %3.0f  edge %+5.2f m  slide %4.1f  walls %d" % [z.s0, z.v0, z.vmin, z.dmax, z.beta, z.walls])
	race.dispose()

## Driver.pursuit_steer on the racing line with a human's preview: preview s ahead (8-60 m) instead of the bots' 6-26 m.
func _pursuit(phys: Physics, tr: Track, car: RaceCar, mu: float) -> float:
	var ch := cos(car.heading)
	var sh := sin(car.heading)
	var v := maxf(0.0, car.vx * ch + car.vy * sh)
	var lim := tr.half + tr.cfg.runoff - 1.0
	var Ld := clampf(5.0 + v * preview, 8.0, 60.0)
	var sl := car.s + Ld
	var dl := clampf(tr.sample(tr.RLD, sl), -lim, lim)
	var p := tr.pos(sl, dl)
	var dx := p[0] - car.x
	var dy := p[1] - car.y
	var lx := dx * ch + dy * sh
	var ly := -dx * sh + dy * ch
	var kap := 2.0 * ly / maxf(1.0, lx * lx + ly * ly)
	var delta := atan(kap * phys.wb)
	var ay := v * v * kap
	delta += signf(kap) * minf(0.08, absf(ay) / (mu * 9.81) * phys.APK * 0.35)
	delta += 0.06 * (v * kap - car.yaw_rate)
	return clampf(delta / phys.max_steer(v, mu), -1.0, 1.0)
