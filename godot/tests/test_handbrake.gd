## The handbrake throws the rear end out, grip returns after it, the drift assist holds the slide, and without
## the handbrake nothing changes.
extends RefCounted

var completed := false
var errors: Array[String] = []

func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		errors.append("%s %s" % [what, detail])

## Drives the player's car on a flat, wide asphalt plane at 90 km/h. Returns {beta (peak slide angle), end_beta,
## heading (total turned), speed}.
func _run(race: Race, steer: float, hb_time: float, drift_assist: float, total: float) -> Dictionary:
	var car: RaceCar = race.player
	car.phys = null
	car.rev = false
	car.gear = 3
	car.heading = 0.0
	car.vx = 25.0
	car.vy = 0.0
	car.yaw_rate = 0.0
	car.x = 0.0
	car.y = 0.0
	var env := Physics.Env.new()
	env.surface = func(_x: float, _y: float) -> int: return Physics.SURF_ASPHALT
	env.mass = car.model.mass_with_fuel(car.fuel)
	env.drift_assist = drift_assist
	env.esc_on = true
	env.tc_on = true
	var ctl := Physics.Controls.new()
	var dt := 1.0 / 120.0
	var peak := 0.0
	var turned := 0.0
	var last := 0.0
	var beta := 0.0
	for k in int(total / dt):
		var t := k * dt
		ctl.throttle = 0.35
		ctl.steer = steer if t < hb_time + 0.3 else 0.0
		ctl.handbrake = 1.0 if t < hb_time else 0.0
		car.physics.step(car, ctl, env, dt)
		var ch := cos(car.heading)
		var sh := sin(car.heading)
		beta = atan2(-car.vx * sh + car.vy * ch, maxf(car.vx * ch + car.vy * sh, 0.5))
		peak = maxf(peak, absf(beta))
		turned += absf(car.yaw_rate) * dt
		last = car.heading
	return {"peak": peak, "end_beta": absf(beta), "turned": turned, "speed": sqrt(car.vx * car.vx + car.vy * car.vy)}

func run() -> Array:
	var st := RaceSettings.new()
	st.track = "gp"
	st.opponents = 1
	st.race_control = false
	var race := Race.new(st, null, 1)
	var plain := _run(race, 0.5, 0.0, 0.0, 2.0)
	var hb := _run(race, 0.5, 0.4, 0.0, 2.0)
	check("a turn without the handbrake stays tidy", plain.peak < 0.35, "(peak slide %.2f rad)" % plain.peak)
	check("the handbrake throws the rear out", hb.peak > plain.peak + 0.25 and hb.peak > 0.4, "(%.2f vs %.2f rad)" % [hb.peak, plain.peak])
	check("the handbrake scrubs speed", hb.speed < plain.speed, "(%.1f vs %.1f m/s)" % [hb.speed, plain.speed])
	var assisted := _run(race, 0.5, 0.4, 0.6, 4.0)
	var unassisted := _run(race, 0.5, 0.4, 0.0, 4.0)
	check("with the assist the car catches the slide", assisted.end_beta < 0.2, "(still %.2f rad sideways)" % assisted.end_beta)
	check("the assist keeps the car from spinning more than the unassisted one", assisted.turned <= unassisted.turned + 0.01,
		"(%.2f vs %.2f rad turned)" % [assisted.turned, unassisted.turned])
	check("the assisted car keeps rolling", assisted.speed > 6.0, "(%.1f m/s)" % assisted.speed)
	# grip returns: after the handbrake is released the rear grip factor is back to 1
	var car: RaceCar = race.player
	check("rear grip is restored after the slide", car.phys.hb_grip > 0.99, "(%.2f)" % car.phys.hb_grip)
	print("  handbrake: plain peak %.2f, handbrake peak %.2f, assisted end %.2f, unassisted end %.2f" % [plain.peak, hb.peak, assisted.end_beta, unassisted.end_beta])
	race.dispose()
	completed = true
	return errors
