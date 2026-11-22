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

# surface ids returned by Env.surface: grip multiplier and extra rolling drag (fraction of the wheel load).
# SURF_GRAVEL is the gravel trap (a run-off that stops cars); SURF_COBBLE is cobbled/sett road (TrackDef.cobbles zones);
# SURF_DIRT (hard-packed dirt track) and SURF_GRAVEL_ROAD (a loose gravel road, a gravel rally stage) are roads:
# less grip and a little drag, still drivable. The first four are parity-tested: never change their values.
# SURF_DIRT and SURF_GRAVEL_ROAD stay adjacent (world_audio indexes by surf - SURF_DIRT).
enum { SURF_TRACK, SURF_ASPHALT, SURF_GRASS, SURF_GRAVEL, SURF_COBBLE, SURF_DIRT, SURF_GRAVEL_ROAD }
const COBBLE_GRIP := 0.85 ## grip of cobbled/sett road; the one tunable, same for the player and the AI
const SURF_GRIP := [1.0, 0.9, 0.5, 0.42, COBBLE_GRIP, 0.72, 0.62]
const SURF_DRAG := [0.0, 0.004, 0.07, 0.22, 0.004, 0.015, 0.03]
## Factor on the steering limit (max_steer) when the front wheels are on the surface: on a loose road the
## driver needs more lock for the slip angles the surface asks for and to catch a slide.
const SURF_STEER := [1.0, 1.0, 1.0, 1.0, 1.0, 1.1, 1.15]

# Magic Formula curves, normalised to a peak of 1. Longitudinal in slip ratio, lateral in slip angle.
const TX_B := 16.0
const TX_C := 1.5
const TX_E := 0.3
const TY_B := 13.0
const TY_C := 1.6
const TY_E := 0.1

# handbrake: rear brake torque (times the rear brake bias), the rear grip it leaves and how fast that grip returns
const HB_TORQUE := 0.45
const HB_GRIP_MIN := 0.55 ## (0.7 before the player's drift tuning, 2026-11-22: a tap now swings a front-driver's tail out)
# drift assist: slide angle (between the nose and the velocity) left to the driver, then a yaw acceleration (rad/s² per rad past it)
# that turns the nose back along the velocity, and a damping on the yaw rate (1/s)
const DRIFT_BETA_MAX := 0.5
const DRIFT_RESTORE := 14.0
const DRIFT_DAMP := 2.5
const HB_GRIP_RECOVER := 1.5 ## per second

# ---- the player's drift handling (Env.drift_handling: 1 for the player's car in races and the open world, 0 for every
# AI car, whose physics stays bit-identical for the parity tests). Measured with tests/_drift_probe.gd.
static var player_drift_handling := 1.0 ## what Race and FreeCar put in the player's Env.drift_handling (probes set 0 to compare)
const DH_CONTACT_HOLD := 0.6 ## s after a wall or car contact with none of it: a car shoved along a wall is not drifting
const DH_MIN_SPEED := 6.0 ## m/s: below this nothing of it acts (slip angles at a crawl are the bend's geometry, not a slide)
## Counter-steer lock: steering towards a slide past DH_LOCK_FROM (rad), full input turns the front wheels to DH_LOCK_GAIN
## times the slide angle (when that is more than the normal limit), so they can follow the velocity and catch the car
## without a full key press snapping it back; never past DH_LOCK_CAP (rad, road wheel).
const DH_LOCK_FROM := 0.04
const DH_LOCK_GAIN := 1.0
const DH_LOCK_CAP := 0.7
## Slide-rate damping (1/s): the yaw rate is pulled towards the rate the velocity itself turns, so the slide angle settles
## where the driver holds it. While the slide closes (the car straightening itself, or snapping back after a catch)
## DH_SLIP_DAMP holds it; while it opens it is left alone, unless the driver is counter-steering: then DH_CATCH_DAMP catches
## it. Off while the handbrake is pulled; fades in between DH_SLIP_FROM and DH_SLIP_FULL of the rear axle's slip angle (rad;
## the rear tyres peak at ~0.115), so grip driving, even at the limit, never feels it.
const DH_SLIP_DAMP := 8.0
const DH_CATCH_DAMP := 4.0
const DH_SLIP_FROM := 0.12
const DH_SLIP_FULL := 0.25
## Progressive rear grip: past their peak the rear tyres keep this share of the force the Magic Formula would shed
## (it falls to ~60 % of the peak at a full slide), so a slide builds and fades instead of snapping. Only for sideways
## slip (times the lateral share of the slip, squared): a locked (handbrake) or spinning wheel lets go as before.
const DH_REAR_HOLD := 0.2
## Drift scrub: on the throttle (no brake, no handbrake) this share of the drag the sideways tyre forces put on the
## car's speed is handed back, fading in between DH_SCRUB_FROM and DH_SCRUB_FULL of the rear axle's slip angle (rad): a held
## drift through a corner loses little more time than the grip line.
const DH_SCRUB_REFUND := 0.55
const DH_SCRUB_FROM := 0.15
const DH_SCRUB_FULL := 0.35
## Keyboard steering (key_steer): the ramp towards a key (1/s) at low speed, at high speed, and towards centre or
## when the key steers into a slide (counter-steer comes at the fast rate all the way to full lock).
const KEY_RATE_SLOW := 4.4
const KEY_RATE_FAST := 2.6
const KEY_RATE_BACK := 8.0
const KEY_SLIDE_FROM := 0.12 ## rad of rear slip (rear_slide) above which a key towards the slide counts as counter-steer

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
	var drift_handling := 0.0 ## 0..1: the player's drift handling (DH_* constants); 0 for the AI cars

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
var _brk_mul := PackedFloat64Array([1.0, 1.0, 1.0, 1.0])
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
## k: the surface's SURF_STEER (1 on tarmac).
func max_steer(v: float, mu: float, k := 1.0) -> float:
	var v2 := maxf(1.0, v * v)
	if spec.steer_fast != 1.0:
		# a car far quicker than the Seicento: calmer at speed, where a full key press would otherwise throw the fronts
		# past their peak in a few tenths (CarSpec.steer_fast)
		var calm := lerpf(1.0, spec.steer_fast, smoothstep(spec.steer_fast_from, spec.steer_fast_to, absf(v)))
		return minf(spec.steer_lock, (wb * mu * G / v2 + 1.35 * APK * calm) * spec.steer_gain * k)
	return minf(spec.steer_lock, (wb * mu * G / v2 + 1.35 * APK) * spec.steer_gain * k)

## The steering limit for an input of sign `steer` with the player's drift handling (dh, Env.drift_handling): max_steer,
## opened while counter-steering a slide so that a full input points the front wheels DH_LOCK_GAIN of the way along
## the velocity (DH_LOCK_*).
func steer_limit(car: RaceCar, steer: float, mu: float, k := 1.0, dh := 1.0) -> float:
	var v := sqrt(car.vx * car.vx + car.vy * car.vy)
	var lock := max_steer(v, mu, k)
	var beta := slide_angle(car)
	if dh <= 0.0 or v < DH_MIN_SPEED or signf(steer) != signf(beta) or absf(beta) <= DH_LOCK_FROM:
		return lock
	return maxf(lock, minf(maxf(lock, DH_LOCK_CAP), dh * DH_LOCK_GAIN * absf(beta)))

## The car's slide angle (rad, between the nose and the velocity; the sign a counter-steering input has).
static func slide_angle(car: RaceCar) -> float:
	var ch := cos(car.heading)
	var sh := sin(car.heading)
	return atan2(-car.vx * sh + car.vy * ch, maxf(car.vx * ch + car.vy * sh, 0.5))

## The rear axle's slip angle (rad, same sign as slide_angle): a few degrees at the grip limit, large once the tail is out
## (a tight bend at low speed turns the car's middle across its nose, not the rear axle).
func rear_slide(car: RaceCar) -> float:
	var ch := cos(car.heading)
	var sh := sin(car.heading)
	return atan2(-car.vx * sh + car.vy * ch - car.yaw_rate * b, maxf(car.vx * ch + car.vy * sh, 0.5))

## Keyboard steering ramp (Game and OpenWorld): eases the steering towards the key (st: -1, 0, 1) instead of snapping,
## slower at speed; back to centre, and towards a slide (beta: rear_slide) once the car is sliding, at the fast rate.
static func key_steer(steer: float, st: float, kmh: float, beta: float, dt: float) -> float:
	var back := st == 0.0 or signf(st) != signf(steer)
	var catch := st != 0.0 and kmh > 15.0 and absf(beta) > KEY_SLIDE_FROM and signf(st) == signf(beta)
	var rate := KEY_RATE_SLOW if kmh < 40.0 else lerpf(KEY_RATE_SLOW, KEY_RATE_FAST, clampf((kmh - 40.0) / 80.0, 0.0, 1.0))
	return move_toward(steer, st, (KEY_RATE_BACK if back or catch else rate) * dt)

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
	var ebd_f := spec.brake_front_grip
	var ebd := spec.brake_rear_grip
	var brake_stab := spec.brake_stab
	var abs_slip := spec.abs_slip
	var eng_i := spec.engine_inertia
	var wheel_i := spec.wheel_inertia
	var eff := spec.efficiency
	var load_sens := spec.load_sensitivity
	var grip_k := spec.grip_k
	var v_ref := spec.v_ref
	var crr := spec.crr
	var offroad := spec.offroad_drag
	var lift_a := spec.lift_a
	var aero_f := spec.aero_front
	var esc_grip := spec.esc_grip
	var esc_aero := spec.esc_aero
	var aero_r := spec.aero_rear
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
	# the surface under each wheel, once per step (the substeps keep it), before the steering: the front
	# wheels' surface sets how much lock the driver gets
	var surf := _surf
	var drag := _drag
	var ch0 := cos(car.heading)
	var sh0 := sin(car.heading)
	for i in 4:
		surf[i] = env.surface.call(car.x + WX[i] * ch0 - WY[i] * sh0, car.y + WX[i] * sh0 + WY[i] * ch0)
		drag[i] = crr + SURF_DRAG[surf[i]] * offroad
	var steer_k: float = (SURF_STEER[surf[0]] + SURF_STEER[surf[1]]) * 0.5
	var dh := env.drift_handling
	var dh_on := dh > 0.0 and v0 > DH_MIN_SPEED
	var delta := input.steer * (steer_limit(car, input.steer, env.mu, steer_k, dh) if dh_on else max_steer(v0, env.mu, steer_k))
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
	var cw := _cw
	var dw := _dw
	var esc := _esc
	var brk_mul := _brk_mul
	var fz := ph.fz
	var w := ph.w
	var rho_a := ph.rho
	var abs_k := ph.abs_k
	var brk := input.brake
	var thr_in := input.throttle * (spec.reverse_power if car.rev else 1.0)
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
		var front := W * b / wb - d_long - lift * aero_f
		var rear := W * a / wb + d_long - lift * aero_r
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

		# ---- stability control: brake the outside front wheel when the car yaws faster than the steering asks;
		# on cars with brake-by-wire YMC (CarSpec.brake_stab > 0), braking stability eases spin-side brake pressure
		# instead of adding torque onto an already-braking outside wheel (which collapses its ABS on split-mu)
		esc[0] = 0.0
		esc[1] = 0.0
		esc[2] = 0.0
		esc[3] = 0.0
		if brake_stab > 0.0:
			brk_mul[0] = 1.0
			brk_mul[1] = 1.0
			brk_mul[2] = 1.0
			brk_mul[3] = 1.0
			if (abs_on or esc_on) and brk > 0.05 and vx > 4.0 and hb_grip > 0.95:
				var lim_b := env_mu * G * 1.1 / vx * (esc_grip + esc_aero * v2)
				var target_b := clampf(vx * delta / wb, -lim_b, lim_b)
				var beta_b := atan2(vy, vx)
				var over_b := (r - target_b) - beta_b * 2.5
				var band_b := 0.02 + 0.08 * absf(target_b)
				if absf(over_b) > band_b and (absf(delta) < 0.01 or signf(over_b) == signf(r) or signf(over_b) == signf(-beta_b)):
					var u := clampf((absf(over_b) - band_b) * brake_stab, 0.0, 1.0)
					if over_b > 0.0:
						brk_mul[1] = 1.0 - 0.9 * u
						brk_mul[3] = 1.0 - u
						if esc_on:
							esc[0] = maxf(0.0, (1.0 - brk) * u) * brake_f * 0.7
					else:
						brk_mul[0] = 1.0 - 0.9 * u
						brk_mul[2] = 1.0 - u
						if esc_on:
							esc[1] = maxf(0.0, (1.0 - brk) * u) * brake_f * 0.7
		if esc_on and vx > 5.0 and hb_grip > 0.95 and not (brake_stab > 0.0 and brk > 0.05):
			# reference: the neutral-steer yaw rate, capped at what the grip allows
			var lim := env_mu * G * 1.1 / vx * (esc_grip + esc_aero * v2)
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
			if abs_on and (brk > 0.0 or esc[i] > 0.0) and absf(vli) > 2.0 and kappa * signf(vli) < -kpk * abs_slip:
				abs_k[i] = maxf(0.1, abs_k[i] - h * 30.0)
			else:
				abs_k[i] = minf(1.0, abs_k[i] + h * 10.0)
			var bt := brake_f if i < 2 else brake_r
			if (ebd_f > 0.0 and abs_on and i < 2) or (ebd > 0.0 and i >= 2):
				# brake-by-wire: match the wheel's grip plus the torque needed to spin down the wheel and coupled flywheel
				var spin_t := (wheel_i + (eng_i * ratio * ratio * p_clutch / n_driven if (i < 2 or awd) else 0.0)) * maxf(0.0, -ax_f) / R
				if i < 2:
					bt = minf(brake_f, ebd_f * mu[i] * fzi * R + spin_t)
				else:
					var r_lat := maxf(0.0, 1.0 - 1.5 * sy * sy)
					bt = minf(brake_r, r_lat * (ebd * mu[i] * fzi * R + spin_t))
			var brk_i := brk * brk_mul[i] if brake_stab > 0.0 else brk
			var tb := (brk_i * bt + esc[i]) * abs_k[i] + (hb * brake_r * HB_TORQUE if i >= 2 else 0.0)
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
				var fy := sin(TY_C * atan(by_ - TY_E * (by_ - atan(by_))))
				if dh_on and i >= 2 and rho > 1.0:
					# progressive rear grip past the peak, for a sideways slide (not a locked or spinning wheel)
					var lat := sy / rho
					fy += dh * DH_REAR_HOLD * lat * lat * (1.0 - fy)
				Ft = -fm * fy * sy / rho
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
		var dh_slip := 0.0 # how far into a slide the car is, 0..1 (DH_SLIP_*)
		if dh_on and vx > DH_MIN_SPEED:
			# the rear axle's slip angle: a few degrees at the grip limit, large only once the tail is out
			var beta_s := absf(atan2(vy - r * b, vx))
			dh_slip = smoothstep(DH_SLIP_FROM, DH_SLIP_FULL, beta_s)
			# drift scrub: hand back part of the drag the sideways tyre forces put on the speed (DH_SCRUB_*)
			var side_drag := fyB * vy
			if side_drag < 0.0 and thr_in > 0.2 and brk < 0.05 and hb <= 0.0:
				var refund := -side_drag / v2 * DH_SCRUB_REFUND * dh * smoothstep(DH_SCRUB_FROM, DH_SCRUB_FULL, beta_s) * minf(1.0, thr_in)
				fxB += refund * vx
				fyB += refund * vy
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
		if dh_slip > 0.0 and hb <= 0.0:
			# slide-rate damping: the slide angle changes at (the rate the velocity turns) - (the yaw rate); pull the yaw
			# rate towards the velocity's (DH_SLIP_DAMP, DH_CATCH_DAMP)
			var beta_dot := (vx * ayB - vy * axB) / v2 - r
			var damp := DH_SLIP_DAMP # the slide closing: it holds
			if beta_dot * vy > 0.0:
				# the slide opening: left alone, unless the driver is counter-steering (the catch)
				damp = DH_CATCH_DAMP if signf(delta) == signf(vy) else 0.0
			c_yaw += beta_dot * damp * dh * dh_slip * h
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
