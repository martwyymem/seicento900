## Physics driver for the bots (port of js/driver.js): turns a target line and speed into throttle, brake
## and steering for the same four-wheel car model the player drives. Bots can therefore run wide, lock up,
## spin and lose time exactly like you do; their speed comes from how well they drive, not from a shortcut.
class_name Driver
extends RefCounted

const G := 9.81

## Pure pursuit on a point further up the racing line (shifted sideways by offs, plus a mistake's
## wobble), with a little yaw damping. This is the actual geometry a driver needs to make the corner —
## not a fixed lock, but exactly the angle the coming curvature calls for at this speed and grip. Used
## both to drive the bots and, as a ceiling, to keep a keyboard's digital steering from overshooting it.
static func pursuit_steer(phys: Physics, tr: Track, car: RaceCar, mu: float, offs: float, err) -> float:
	var ch := cos(car.heading)
	var sh := sin(car.heading)
	var v := maxf(0.0, car.vx * ch + car.vy * sh)
	var lim := tr.half + tr.cfg.runoff - 1.0
	var Ld := clampf(5.0 + v * 0.42, 6.0, 26.0)
	var sl := car.s + Ld
	var dl := clampf(tr.sample(tr.RLD, sl) + offs + (err.d if err else 0.0), -lim, lim)
	var p := tr.pos(sl, dl)
	var dx := p[0] - car.x
	var dy := p[1] - car.y
	var lx := dx * ch + dy * sh
	var ly := -dx * sh + dy * ch
	var kap := 2.0 * ly / maxf(1.0, lx * lx + ly * ly)
	var delta := atan(kap * phys.wb)
	# the tyres need a little slip angle to make the turn; more as the car nears its limit
	var ay := v * v * kap
	delta += signf(kap) * minf(0.08, absf(ay) / (mu * G) * phys.APK * 0.35)
	delta += 0.06 * (v * kap - car.yaw_rate)
	return clampf(delta / phys.max_steer(v, mu), -1.0, 1.0)

## The steer a driver on the racing line, exactly at car's own position, would ask for right now — used
## as a guide rail for keyboard/pad steering (see Race.steer_assist), not to drive anyone directly.
static func line_steer(phys: Physics, tr: Track, car: RaceCar, mu: float) -> float:
	return pursuit_steer(phys, tr, car, mu, 0.0, null)

## tg: {vT (speed wanted here, traffic included), dT (lateral target), K (profile scale), err (a mistake in
## progress)}. Fills and returns out.
static func control(phys: Physics, tr: Track, car: RaceCar, tg: Dictionary, mu: float, out: Physics.Controls) -> Physics.Controls:
	var ch := cos(car.heading)
	var sh := sin(car.heading)
	var v := maxf(0.0, car.vx * ch + car.vy * sh)
	var err = tg.err

	# ---- speed: the target here, and never so fast that the braking for what's ahead can't be made
	var aB := 0.86 * mu * G * (1.35 if err and err.kind == "late" else 1.0)
	var v_ref: float = tg.vT
	var lead := v * 0.12
	var K: float = tg.K
	var x := 5
	while x < 140:
		var va := tr.sample(tr.PROF, car.s + lead + x) * K
		var lim := sqrt(va * va + 2.0 * aB * x)
		if lim < v_ref:
			v_ref = lim
		if va * va + 2.0 * aB * x > v * v + 400.0:
			break
		x += 5
	var e := v_ref - v
	var throttle := 0.0
	var brake := 0.0
	if e > 0.0:
		throttle = clampf(0.35 + e * 0.9, 0.0, 1.0)
	elif e < -0.4:
		brake = clampf(-e * 0.45, 0.0, 1.0)
	else:
		throttle = clampf(0.35 + e * 0.9, 0.0, 1.0)
	# feel the front tyres: ease off when they're washing out
	var under := car.understeer
	if under > 1.08 and throttle > 0.0:
		throttle *= clampf(1.6 - (under - 1.08) * 4.0, 0.2, 1.0)

	# ---- steering
	var rl := tr.sample(tr.RLD, car.s)
	out.throttle = throttle
	out.brake = brake
	out.steer = pursuit_steer(phys, tr, car, mu, tg.dT - rl, err)
	return out
