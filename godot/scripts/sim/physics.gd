## Vehicle dynamics: a rigid body on four Pacejka tyres (port of js/physics.js).
## - Magic Formula tyres with combined slip, load sensitivity and per-wheel surface grip
## - Wheel spin dynamics solved implicitly, so locking and wheelspin are stable at any speed
## - Engine inertia, friction/engine braking, rev limiter, auto clutch and an open front differential
## - Load transfer through a sprung body (pitch and roll lag behind the tyre forces)
## - Front-biased brakes with optional ABS, traction and stability control, Ackermann steering, aero drag and lift
## All chassis figures come from the CarSpec resource.
class_name Physics
extends RefCounted

const G := 9.81 ## gravity, m/s²

# surface ids returned by Env.surface: grip multiplier and extra rolling drag (fraction of the wheel load)
enum { SURF_TRACK, SURF_ASPHALT, SURF_GRASS, SURF_GRAVEL }
const SURF_GRIP := [1.0, 0.9, 0.5, 0.42]
const SURF_DRAG := [0.0, 0.004, 0.07, 0.22]

# Magic Formula curves, normalised to a peak of 1. Longitudinal in slip ratio, lateral in slip angle.
const TX_B := 16.0
const TX_C := 1.5
const TX_E := 0.3
const TY_B := 13.0
const TY_C := 1.6
const TY_E := 0.1

# handbrake: rear brake torque (times the rear brake bias), the rear grip it leaves and how fast that grip returns
const HB_TORQUE := 0.45
const HB_GRIP_MIN := 0.7
# drift assist: slide angle (between the nose and the velocity) left to the driver, then a yaw acceleration (rad/s² per rad past it)
# that turns the nose back along the velocity, and a damping on the yaw rate (1/s)
const DRIFT_BETA_MAX := 0.5
const DRIFT_RESTORE := 14.0
const DRIFT_DAMP := 2.5
const HB_GRIP_RECOVER := 1.5 ## per second

## Everything the car needs from the world for one step.
class Env:
	var mu := 1.0
	var mass := 900.0
	var gx := 0.0 ## gravity along the road, world frame
	var gy := 0.0
	var drag_mul := 1.0
	var power := 1.0 ## engine output factor (the fuel mix, Strategy.MIXES)
	var abs_on := true
	var tc_on := true
	var esc_on := true
	var surface: Callable ## (x, y) -> SURF_* id
	var drift_assist := 0.0 ## 0..1: how hard the car helps the driver keep a slide in check (yaw restoring and damping past DRIFT_BETA_MAX)
	var rear_grip := 1.0 ## extra factor on the rear tyres' grip (open-world modifiers; 1.0 everywhere else)

## Driver input, with throttle/brake already routed for reverse.
class Controls:
	var throttle := 0.0
	var brake := 0.0
	var steer := 0.0
	var handbrake := 0.0 ## 0..1: locks the rear wheels and lets the rear end go

var spec: CarSpec
var car_model: CarModel
# derived geometry
var a := 0.0 ## CG to front axle
var b := 0.0 ## CG to rear axle
var wb := 0.0
var KPK := 0.0 ## slip ratio at peak force
var APK := 0.0 ## slip angle at peak force (rad)
var TAPK := 0.0
var WX := PackedFloat64Array()
var WY := PackedFloat64Array()

# tyre() results
var _fl := 0.0
var _ft := 0.0
var _rho := 0.0
# per-wheel scratch, reused every substep
var _vl := PackedFloat64Array([0, 0, 0, 0])
var _vt := PackedFloat64Array([0, 0, 0, 0])
var _mu := PackedFloat64Array([0, 0, 0, 0])
var _drag := PackedFloat64Array([0, 0, 0, 0])
var _cw := PackedFloat64Array([0, 0, 0, 0])
var _dw := PackedFloat64Array([0, 0, 0, 0])
var _esc := PackedFloat64Array([0, 0, 0, 0])
var _dW := PackedFloat64Array([0, 0, 0, 0])
var _cd := PackedFloat64Array([0, 0, 0, 0])
var _sd := PackedFloat64Array([0, 0, 0, 0])
var _surf := PackedInt32Array([0, 0, 0, 0])

## Outputs of the last step().
var engine_power := 0.0
var slide_power := 0.0

func _init(model: CarModel) -> void:
	car_model = model
	spec = model.spec
	a = spec.wheelbase * (1.0 - spec.front_weight)
	b = spec.wheelbase * spec.front_weight
	wb = a + b
	KPK = _peak_of(TX_B, TX_C, TX_E)
	APK = _peak_of(TY_B, TY_C, TY_E)
	TAPK = tan(APK)
	WX = PackedFloat64Array([a, a, -b, -b])
	WY = PackedFloat64Array([-spec.track_front / 2, spec.track_front / 2, -spec.track_rear / 2, spec.track_rear / 2])

static func mf(B: float, C: float, E: float, x: float) -> float:
	var bx := B * x
	return sin(C * atan(bx - E * (bx - atan(bx))))

static func _peak_of(B: float, C: float, E: float) -> float:
	var best := 0.0
	var bx := 0.0
	var x := 0.001
	while x < 1.0:
		var f := mf(B, C, E, x)
		if f > best:
			best = f
			bx = x
		x += 0.0005
	return bx

## Tyre forces in the wheel frame. vl/vt: contact patch velocity along/across the wheel, w: wheel spin.
## Sets _fl, _ft and _rho (combined slip relative to peak, 1 = at the limit).
func tyre(w: float, vl: float, vt: float, fz: float, mu: float) -> void:
	var vr := maxf(absf(vl), spec.v_ref)
	var sx := (w * spec.wheel_radius - vl) / vr / KPK
	var sy := vt / vr / TAPK
	var rho := sqrt(sx * sx + sy * sy)
	_rho = rho
	if rho < 1e-9 or fz <= 0.0:
		_fl = 0.0
		_ft = 0.0
		return
	var fm := mu * fz
	_fl = fm * mf(TX_B, TX_C, TX_E, rho * KPK) * sx / rho
	_ft = -fm * mf(TY_B, TY_C, TY_E, atan(rho * TAPK)) * sy / rho

func ratio_of(car: RaceCar) -> float:
	return (-spec.reverse_ratio if car.rev else spec.gears[car.gear]) * spec.final_drive

static func rpm_of(w: float) -> float:
	return w * 30.0 / PI

static func engine_friction(rpm: float) -> float:
	return 7.0 + 0.0022 * rpm

## Fresh drivetrain state for a car that has just been handed to physics (race start, leaving the pits…).
func init_car(car: RaceCar) -> PhysState:
	var ch := cos(car.heading)
	var sh := sin(car.heading)
	var vF := car.vx * ch + car.vy * sh
	var wW := vF / spec.wheel_radius
	var ph := PhysState.new()
	ph.w = PackedFloat64Array([wW, wW, wW, wW])
	ph.we = maxf(car.rpm * PI / 30.0, absf(wW * ratio_of(car)))
	ph.clutch = 1.0 if absf(vF) > 3.0 else 0.0
	car.phys = ph
	car.rev = false
	return ph

## Speed-sensitive steering limit: enough lock to reach the tyres' peak slip, not so much that a
## keyboard tap throws the car past it. Scaled by the steering input.
func max_steer(v: float, mu: float) -> float:
	var v2 := maxf(1.0, v * v)
	return minf(spec.steer_lock, (wb * mu * G / v2 + 1.35 * APK) * spec.steer_gain)

## Advance the car by dt.
## Hot path (every car, 8 substeps per tick): the tyre model is inlined and the car/drivetrain state
## lives in locals for the whole step. The arithmetic matches tyre() and mf() term for term, so the
## results are bit-identical to the straightforward version (the parity tests check 1e-14).
func step(car: RaceCar, input: Controls, env: Env, dt: float) -> void:
	var ph: PhysState = car.phys if car.phys else init_car(car)
	var m := env.mass
	var iz := m * (spec.length * spec.length + spec.width * spec.width) / 12.0
	var sub := spec.substeps
	var h := dt / sub
	var R := spec.wheel_radius
	var wn := TAU * spec.susp_hz
	var ratio := ratio_of(car)
	var cg_h := spec.cg_height
	var tf := spec.track_front
	var tr := spec.track_rear
	var roll_f := spec.roll_front
	var idle := spec.idle_rpm
	var limiter := spec.limiter
	var brake_f := spec.brake_front
	var brake_r := spec.brake_rear
	var eng_i := spec.engine_inertia
	var wheel_i := spec.wheel_inertia
	var eff := spec.efficiency
	var load_sens := spec.load_sensitivity
	var grip_k := spec.grip_k
	var v_ref := spec.v_ref
	var crr := spec.crr
	var offroad := spec.offroad_drag
	var lift_a := spec.lift_a
	var cd_a := spec.cd_a
	var zeta := spec.susp_zeta
	var clutch_cap := spec.clutch_capacity
	var awd := spec.awd
	var n_driven := 4.0 if spec.awd else 2.0
	var kpk := KPK
	var tapk := TAPK
	var fuel_w := 0.0
	var slide_w := 0.0
	var max_rho_f := 0.0
	var max_rho_r := 0.0
	var slide_v := 0.0
	var v0 := sqrt(car.vx * car.vx + car.vy * car.vy)
	var delta := input.steer * max_steer(v0, env.mu)
	var drift_k := env.drift_assist
	car.steer = delta
	# Ackermann: the inside wheel turns tighter
	var dW := _dW
	dW[0] = delta
	dW[1] = delta
	dW[2] = 0.0
	dW[3] = 0.0
	if absf(delta) > 1e-4:
		var rt := wb / tan(delta)
		dW[0] = delta + (atan(wb / (rt - WY[0])) - delta) * spec.ackermann
		dW[1] = delta + (atan(wb / (rt - WY[1])) - delta) * spec.ackermann
	var cd := _cd
	var sd := _sd
	for i in 4:
		cd[i] = cos(dW[i])
		sd[i] = sin(dW[i])
	var vl := _vl
	var vt := _vt
	var mu := _mu
	var drag := _drag
	var cw := _cw
	var dw := _dw
	var esc := _esc
	var surf := _surf
	var fz := ph.fz
	var w := ph.w
	var rho_a := ph.rho
	var abs_k := ph.abs_k
	var brk := input.brake
	var thr_in := input.throttle
	var env_mu := env.mu
	var abs_on := env.abs_on
	var tc_on := env.tc_on
	var esc_on := env.esc_on
	var gx := env.gx
	var gy := env.gy
	var drag_mul := env.drag_mul
	var power := env.power
	var shifting := car.shift_t > 0.0
	var hb := input.handbrake
	var hb_grip := ph.hb_grip
	var rear_grip := env.rear_grip
	# body and drivetrain state, written back after the substeps
	var c_heading := car.heading
	var c_vx := car.vx
	var c_vy := car.vy
	var c_yaw := car.yaw_rate
	var c_x := car.x
	var c_y := car.y
	var ax_f := ph.ax_f
	var ay_f := ph.ay_f
	var ax_d := ph.ax_d
	var ay_d := ph.ay_d
	var p_tc := ph.tc
	var p_clutch := ph.clutch
	var p_we := ph.we
	var p_fx0 := ph.fx0

	for k in sub:
		var ch := cos(c_heading)
		var sh := sin(c_heading)
		var vx := c_vx * ch + c_vy * sh
		var vy := -c_vx * sh + c_vy * ch
		var r := c_yaw
		var v2 := vx * vx + vy * vy

		# ---- loads: static + aero lift + pitch/roll transfer from the lagged body accelerations
		var lift := 0.5 * 1.2 * lift_a * v2
		var W := m * G
		var d_long := m * ax_f * cg_h / wb
		var front := W * b / wb - d_long - lift * 0.55
		var rear := W * a / wb + d_long - lift * 0.45
		var d_lat_f := m * ay_f * cg_h / tf * roll_f
		var d_lat_r := m * ay_f * cg_h / tr * (1.0 - roll_f)
		fz[0] = maxf(0.0, front / 2 + d_lat_f)
		fz[1] = maxf(0.0, front / 2 - d_lat_f)
		fz[2] = maxf(0.0, rear / 2 + d_lat_r)
		fz[3] = maxf(0.0, rear / 2 - d_lat_r)
		var fz0 := W / 4
		if hb > 0.0 or hb_grip < 1.0:
			hb_grip += clampf((HB_GRIP_MIN if hb > 0.0 else 1.0) - hb_grip, -h * 8.0, h * HB_GRIP_RECOVER)

		# ---- per-wheel kinematics, surface and grip
		for i in 4:
			var wx := vx - r * WY[i]
			var wy := vy + r * WX[i]
			vl[i] = wx * cd[i] + wy * sd[i]
			vt[i] = -wx * sd[i] + wy * cd[i]
			if k == 0:
				surf[i] = env.surface.call(c_x + WX[i] * ch - WY[i] * sh, c_y + WX[i] * sh + WY[i] * ch)
				drag[i] = crr + SURF_DRAG[surf[i]] * offroad
			var sens := clampf(1.0 - load_sens * (fz[i] / fz0 - 1.0), 0.75, 1.15)
			mu[i] = env_mu * grip_k * SURF_GRIP[surf[i]] * sens
			if i >= 2:
				mu[i] *= hb_grip * rear_grip

		# ---- driver aids
		var thr := thr_in
		# traction control trims the throttle in proportion to how far the driven wheels are past peak slip
		var spin := maxf(rho_a[0], rho_a[1])
		if awd:
			spin = maxf(spin, maxf(rho_a[2], rho_a[3]))
		var tc_want := 1.0
		if tc_on and vx > 1.0 and p_fx0 > 0.0 and spin > 1.1:
			tc_want = maxf(0.35, 1.0 - (spin - 1.1) * 1.5)
		p_tc += clampf(tc_want - p_tc, -h * 10.0, h * 5.0)
		thr *= p_tc

		# ---- engine, clutch and gearbox
		var rpm := p_we * 30.0 / PI
		var wc := (w[0] + w[1]) / 2
		var wheel_rpm := absf(wc * ratio * 30.0 / PI)
		var bite: float
		if shifting:
			bite = 0.0
		elif wheel_rpm < 1250.0:
			# pulling away or rolling to a stop: slip the clutch, never stall
			bite = clampf((rpm - 1150.0) / 1500.0, 0.0, 1.0) if thr > 0.02 else 0.0
		else:
			bite = 0.0 if rpm < 780.0 else 1.0
		p_clutch += clampf(bite - p_clutch, -h * 25.0, h * (25.0 if shifting else 7.0))
		if shifting:
			# throttle lifts on upshifts; the box blips on downshifts to match revs
			var target := absf(wc * ratio * 30.0 / PI)
			thr = 1.0 if target > rpm + 150.0 else 0.0
		if rpm < idle + 60.0:
			thr = maxf(thr, clampf((idle + 180.0 - rpm) / 400.0, 0.0, 0.35))
		if rpm >= limiter:
			thr = 0.0
		var fr := 7.0 + 0.0022 * rpm
		var te := thr * (car_model.torque_at(rpm) * power + fr) - fr

		# ---- stability control: brake the outside front wheel when the car yaws faster than the steering asks
		esc[0] = 0.0
		esc[1] = 0.0
		esc[2] = 0.0
		esc[3] = 0.0
		if esc_on and vx > 5.0 and hb_grip > 0.95:
			# reference: the neutral-steer yaw rate, capped at what the grip allows
			var lim := env_mu * G * 1.1 / vx
			var target := clampf(vx * delta / wb, -lim, lim)
			var over := r - target
			var band := 0.05 + 0.1 * absf(target)
			if absf(over) > band and signf(over) == signf(r):
				esc[0 if r > 0.0 else 1] = minf(1.0, (absf(over) - band) * 4.0) * brake_f * 0.7
				thr *= 0.3

		# ---- wheel spin: linearised backward Euler so stiff tyres can't blow up
		# (only the longitudinal force and combined slip of tyre() are needed here)
		for i in 4:
			var wi := w[i]
			var vli := vl[i]
			var vti := vt[i]
			var fzi := fz[i]
			var vr := maxf(absf(vli), v_ref)
			var sy := vti / vr / tapk
			# tyre(wi, …)
			var sx := (wi * R - vli) / vr / kpk
			var rho0 := sqrt(sx * sx + sy * sy)
			var fl0 := 0.0
			if not (rho0 < 1e-9 or fzi <= 0.0):
				var bx := TX_B * (rho0 * kpk)
				fl0 = mu[i] * fzi * sin(TX_C * atan(bx - TX_E * (bx - atan(bx)))) * sx / rho0
			# tyre(wi + eps, …)
			var eps := 0.02
			var sx2 := ((wi + eps) * R - vli) / vr / kpk
			var rho2 := sqrt(sx2 * sx2 + sy * sy)
			var fl2 := 0.0
			if not (rho2 < 1e-9 or fzi <= 0.0):
				var bx2 := TX_B * (rho2 * kpk)
				fl2 = mu[i] * fzi * sin(TX_C * atan(bx2 - TX_E * (bx2 - atan(bx2)))) * sx2 / rho2
			var kx := maxf(0.0, (fl2 - fl0) / eps)
			rho_a[i] = rho0
			# ABS: back off a wheel's pressure when it is heading for a lock
			var kappa := (wi * R - vli) / maxf(absf(vli), v_ref)
			if abs_on and (brk > 0.0 or esc[i] > 0.0) and absf(vli) > 2.0 and kappa * signf(vli) < -kpk * 1.2:
				abs_k[i] = maxf(0.1, abs_k[i] - h * 30.0)
			else:
				abs_k[i] = minf(1.0, abs_k[i] + h * 10.0)
			var tb := (brk * (brake_f if i < 2 else brake_r) + esc[i]) * abs_k[i] + (hb * brake_r * HB_TORQUE if i >= 2 else 0.0)
			var roll := drag[i] * fzi * R
			var w0 := 1.5
			var sgn := clampf(wi / w0, -1.0, 1.0)
			cw[i] = R * fl0 + (tb + roll) * sgn
			dw[i] = wheel_i / h + R * kx + ((tb + roll) / w0 if absf(wi) < w0 else 0.0)
		var tau := 0.0
		var ad := ratio * eff / n_driven
		if p_clutch > 0.001:
			# clutch torque that would lock engine and differential together this substep, limited by capacity
			var inv_dw := 1.0 / dw[0] + 1.0 / dw[1]
			var w_sum := w[0] + w[1]
			var cw_dw := cw[0] / dw[0] + cw[1] / dw[1]
			if awd:
				inv_dw += 1.0 / dw[2] + 1.0 / dw[3]
				w_sum += w[2] + w[3]
				cw_dw += cw[2] / dw[2] + cw[3] / dw[3]
			var lhs := h / eng_i + (ratio / n_driven) * ad * inv_dw
			var rhs := p_we + h * te / eng_i - (ratio / n_driven) * w_sum + (ratio / n_driven) * cw_dw
			var cap := p_clutch * clutch_cap
			tau = clampf(rhs / lhs, -cap, cap)
		p_we += h * (te - tau) / eng_i
		p_we = clampf(p_we, 600.0 * PI / 30.0, (limiter + 250.0) * PI / 30.0)
		for i in 4:
			w[i] += ((tau * ad if (i < 2 or awd) else 0.0) - cw[i]) / dw[i]
		p_fx0 = tau * ratio
		fuel_w += maxf(0.0, te) * p_we * h

		# ---- tyre forces with the updated wheel speeds, summed on the body
		var fxB := 0.0
		var fyB := 0.0
		var mz := 0.0
		for i in 4:
			var wi := w[i]
			var vli := vl[i]
			var vti := vt[i]
			var fzi := fz[i]
			# tyre(w[i], vl[i], vt[i], fz[i], mu[i])
			var vr := maxf(absf(vli), v_ref)
			var sx := (wi * R - vli) / vr / kpk
			var sy := vti / vr / tapk
			var rho := sqrt(sx * sx + sy * sy)
			var Fl := 0.0
			var Ft := 0.0
			if not (rho < 1e-9 or fzi <= 0.0):
				var fm := mu[i] * fzi
				var bx := TX_B * (rho * kpk)
				Fl = fm * sin(TX_C * atan(bx - TX_E * (bx - atan(bx)))) * sx / rho
				var by_ := TY_B * atan(rho * tapk)
				Ft = -fm * sin(TY_C * atan(by_ - TY_E * (by_ - atan(by_)))) * sy / rho
			rho_a[i] = rho
			var bx := Fl * cd[i] - Ft * sd[i]
			var by := Fl * sd[i] + Ft * cd[i]
			fxB += bx
			fyB += by
			mz += WX[i] * by - WY[i] * bx
			var slx := wi * R - vli
			var sv := sqrt(slx * slx + vti * vti)
			slide_w += sqrt(Fl * Fl + Ft * Ft) * sv * h
			slide_v = maxf(slide_v, sv)
			if i < 2:
				max_rho_f = maxf(max_rho_f, rho)
			else:
				max_rho_r = maxf(max_rho_r, rho)
		var vmag := sqrt(v2)
		var fa := 0.5 * 1.2 * cd_a * drag_mul * vmag
		fxB -= fa * vx
		fyB -= fa * vy

		# ---- integrate the body (world frame) and the lagged suspension
		var axB := fxB / m
		var ayB := fyB / m
		c_vx += (axB * ch - ayB * sh + gx) * h
		c_vy += (axB * sh + ayB * ch + gy) * h
		c_yaw += mz / iz * h
		if drift_k > 0.0 and vx > 3.0:
			var slide_beta := atan2(vy, vx)
			var over_beta := absf(slide_beta) - DRIFT_BETA_MAX
			if over_beta > 0.0:
				c_yaw += (signf(slide_beta) * DRIFT_RESTORE * over_beta - DRIFT_DAMP * c_yaw) * drift_k * h
		# parked with the brakes on: stop creeping
		if brk > 0.2 and v2 < 0.01 and absf(c_yaw) < 0.05:
			c_vx *= 0.9
			c_vy *= 0.9
			c_yaw *= 0.9
		c_heading += c_yaw * h
		c_x += c_vx * h
		c_y += c_vy * h
		ax_d += (wn * wn * (axB - ax_f) - 2.0 * zeta * wn * ax_d) * h
		ay_d += (wn * wn * (ayB - ay_f) - 2.0 * zeta * wn * ay_d) * h
		ax_f += ax_d * h
		ay_f += ay_d * h

	car.heading = c_heading
	car.vx = c_vx
	car.vy = c_vy
	car.yaw_rate = c_yaw
	car.x = c_x
	car.y = c_y
	ph.ax_f = ax_f
	ph.ay_f = ay_f
	ph.ax_d = ax_d
	ph.ay_d = ay_d
	ph.tc = p_tc
	ph.hb_grip = hb_grip
	ph.clutch = p_clutch
	ph.we = p_we
	ph.fx0 = p_fx0
	var ch := cos(car.heading)
	var sh := sin(car.heading)
	var vF := car.vx * ch + car.vy * sh
	car.speed = vF
	car.v = absf(vF)
	car.rpm = rpm_of(ph.we)
	car.throttle = input.throttle
	car.brake_on = input.brake > 0.05
	# tyre noise cues: fronts past their peak (understeer) and how far any tyre is past ~80 % of its grip
	car.understeer = max_rho_f
	car.slip = maxf(0.0, maxf(max_rho_f, max_rho_r) - 0.8) * 3.0 + maxf(0.0, slide_v - 4.0) * 0.2
	car.body_roll = clampf(-ph.ay_f / G * spec.roll_gradient, -0.12, 0.12)
	car.body_pitch = clampf(ph.ax_f / G * spec.pitch_gradient, -0.06, 0.06)
	ph.slide = slide_w / dt # W dissipated in the contact patches
	engine_power = fuel_w / dt
	slide_power = ph.slide

## Impulse on the body at a point (rx, ry from the CG, world axes), given as the velocity change of the CG.
func kick(car: RaceCar, ix: float, iy: float, rx: float, ry: float, at_point := true) -> void:
	var k2 := (spec.length * spec.length + spec.width * spec.width) / 12.0 # yaw radius of gyration squared
	car.vx += ix
	car.vy += iy
	if at_point:
		car.yaw_rate += (rx * iy - ry * ix) / k2

## Rigid-body contact with a barrier: n points out of the track, (rx, ry) is the contact point from the CG.
## Returns the closing speed.
func barrier_hit(car: RaceCar, nx: float, ny: float, rx: float, ry: float, mass: float) -> float:
	var iz := mass * (spec.length * spec.length + spec.width * spec.width) / 12.0
	var vcx := car.vx - car.yaw_rate * ry
	var vcy := car.vy + car.yaw_rate * rx
	var vn := vcx * nx + vcy * ny
	if vn <= 0.0:
		return 0.0
	var rn := rx * ny - ry * nx
	var jn := -(1.0 + 0.25) * vn / (1.0 / mass + rn * rn / iz)
	var tx := -ny
	var ty := nx
	var vt := vcx * tx + vcy * ty
	var rt := rx * ty - ry * tx
	var jt_max := 0.45 * absf(jn)
	var jt := clampf(-vt / (1.0 / mass + rt * rt / iz), -jt_max, jt_max)
	var jx := jn * nx + jt * tx
	var jy := jn * ny + jt * ty
	car.vx += jx / mass
	car.vy += jy / mass
	car.yaw_rate += (rx * jy - ry * jx) / iz
	return vn
