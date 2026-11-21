## G-force and suspension spring for the in-race and open-world HUDs: sways and tilts the speedometer cluster
## and corner panels with the car's lateral, longitudinal and vertical accelerations so the HUD feels attached
## to the car and camera rather than painted flat on the glass. Rest pose is exact zero so layout clearances
## are unchanged; Off leaves every panel static, Reduced halves the amplitude.
class_name HudMotion
extends RefCounted

const MODE_ON := 0
const MODE_REDUCED := 1
const MODE_OFF := 2
const MODE_NAMES := ["On", "Reduced", "Off"]

const G := 9.81
const OMEGA := 13.5 ## rad/s: natural frequency for lateral and longitudinal sway (~0.32 s 2% settle)
const ZETA := 0.90 ## damping ratio (critically-damped-ish, negligible overshoot)
const BUMP_OMEGA := 16.0 ## rad/s: snappier suspension thump for bumps and landings (~0.28 s settle)
const BUMP_ZETA := 0.80
const MAX_SUBSTEP := 1.0 / 120.0

const LAT_REF_G := 1.0 ## g for tanh(1.0) ≈ 0.76 of peak lateral sway
const LON_REF_G := 0.85 ## g for tanh(1.0) ≈ 0.76 of peak longitudinal pitch
const MAX_OFFSET_X := 10.0 ## px on 900p design canvas (12.0 px at 1080p)
const MAX_OFFSET_Y := 7.5 ## px on 900p design canvas (9.0 px at 1080p)
const MAX_BUMP_Y := 6.0 ## px on 900p design canvas (7.2 px at 1080p); total Y still clamped to MAX_OFFSET_X
const MAX_ROT_RAD := 0.02268928 ## 1.3 deg peak speedometer roll
const CORNER_GAIN := 0.50 ## corner panels move at half the speedometer's offset and rotation

const DASH_SKEW_X := 0.032 ## horizontal shear on DashGauge (~1.8 deg)
const DASH_SKEW_Y := 0.018 ## vertical 2.5D yaw-perspective shear on DashGauge (~1.0 deg)
const DASH_SQUASH_X := 0.022 ## subtle horizontal foreshortening in hard corners
const DASH_ZOOM_LON := 0.014 ## subtle depth breath on braking / acceleration

const BUMP_DVZ_DEAD := 0.45 ## m/s per frame deadzone so gentle road slopes do not kick
const BUMP_IMPULSE_GAIN := 1.8 ## vertical velocity impulse gain into bump spring
const REST_POS_EPS := 0.0005
const REST_VEL_EPS := 0.002

## Active setting shared by RaceHud and OpenWorldHud (Options -> Look -> HUD Motion; saved in graphics.cfg).
static var mode := MODE_ON

static func amplitude() -> float:
	if mode == MODE_OFF:
		return 0.0
	if mode == MODE_REDUCED:
		return 0.5
	return 1.0

static func load_from(config: ConfigFile) -> void:
	var raw: Variant = config.get_value("graphics", "hud_motion", MODE_ON)
	if raw is String:
		var idx := MODE_NAMES.find(raw)
		mode = idx if idx >= 0 else MODE_ON
	else:
		mode = clampi(int(raw), MODE_ON, MODE_OFF)

static func save_to(config: ConfigFile) -> void:
	config.set_value("graphics", "hud_motion", mode)

# ---- per-HUD spring state (scalar fields only: zero per-frame allocations)
var lat := 0.0
var lon := 0.0
var bump := 0.0
var _lat_v := 0.0
var _lon_v := 0.0
var _bump_v := 0.0

var _has_prev := false
var _prev_speed := 0.0
var _prev_heading := 0.0
var _prev_pos := Vector2.ZERO
var _prev_vz := 0.0

# ---- computed transforms applied by the HUD
var dash_offset := Vector2.ZERO
var dash_rot := 0.0
var dash_scale := Vector2.ONE
var dash_skew := Vector2.ZERO
var corner_offset := Vector2.ZERO
var corner_rot := 0.0

func reset() -> void:
	lat = 0.0
	lon = 0.0
	bump = 0.0
	_lat_v = 0.0
	_lon_v = 0.0
	_bump_v = 0.0
	_has_prev = false
	_prev_speed = 0.0
	_prev_heading = 0.0
	_prev_pos = Vector2.ZERO
	_prev_vz = 0.0
	_clear_outputs()

func sync_kinematics(speed_mps: float, heading: float, pos: Vector2, vz := 0.0) -> void:
	_prev_speed = speed_mps
	_prev_heading = heading
	_prev_pos = pos
	_prev_vz = vz
	_has_prev = true

## Derives body-frame lateral and longitudinal acceleration (m/s^2) from speed, heading and vertical velocity,
## ignoring teleports / respawns, then advances the spring.
func step_kinematics(speed_mps: float, heading: float, pos: Vector2, dt: float, canvas_h: float, vz := 0.0, has_pos := true) -> void:
	if dt <= 0.0:
		if amplitude() <= 0.0:
			reset()
		return
	if not _has_prev:
		sync_kinematics(speed_mps, heading, pos, vz)
		step_accel(0.0, 0.0, dt, canvas_h, 0.0)
		return
	var dh := wrapf(heading - _prev_heading, -PI, PI)
	var max_step := maxf(15.0, absf(speed_mps) * dt * 4.0)
	if (has_pos and pos.distance_to(_prev_pos) > max_step) or absf(dh) > 1.2:
		sync_kinematics(speed_mps, heading, pos, vz)
		step_accel(0.0, 0.0, dt, canvas_h, 0.0)
		return
	var lon_a := (speed_mps - _prev_speed) / dt
	var avg_v := 0.5 * (speed_mps + _prev_speed)
	var lat_a := avg_v * (dh / dt)
	var dvz := vz - _prev_vz
	sync_kinematics(speed_mps, heading, pos, vz)
	step_accel(lat_a, lon_a, dt, canvas_h, dvz)

## Advances the damped springs from body-frame lateral acceleration (+ right, m/s^2), longitudinal acceleration
## (+ forward, m/s^2) and optional vertical velocity jump (bump_dvz > 0 on landing / upward bump, m/s).
func step_accel(lat_mps2: float, lon_mps2: float, dt: float, canvas_h: float, bump_dvz := 0.0) -> void:
	var amp := amplitude()
	if amp <= 0.0:
		lat = 0.0
		lon = 0.0
		bump = 0.0
		_lat_v = 0.0
		_lon_v = 0.0
		_bump_v = 0.0
		_clear_outputs()
		return
	if dt <= 0.0:
		_update_outputs(canvas_h, amp)
		return
	var step_dt := minf(dt, 0.1)
	var target_lat := tanh(clampf(lat_mps2 / G, -4.0, 4.0) / LAT_REF_G)
	var target_lon := tanh(clampf(lon_mps2 / G, -4.0, 4.0) / LON_REF_G)
	if absf(bump_dvz) > BUMP_DVZ_DEAD:
		var excess := bump_dvz - signf(bump_dvz) * BUMP_DVZ_DEAD
		_bump_v = clampf(_bump_v + clampf(excess, -10.0, 10.0) * BUMP_IMPULSE_GAIN, -18.0, 18.0)

	var steps := maxi(1, ceili(step_dt / MAX_SUBSTEP))
	var h := step_dt / float(steps)
	var w2 := OMEGA * OMEGA
	var c2 := 2.0 * ZETA * OMEGA
	var bw2 := BUMP_OMEGA * BUMP_OMEGA
	var bc2 := 2.0 * BUMP_ZETA * BUMP_OMEGA
	for _i in steps:
		_lat_v += (w2 * (target_lat - lat) - c2 * _lat_v) * h
		lat += _lat_v * h
		_lon_v += (w2 * (target_lon - lon) - c2 * _lon_v) * h
		lon += _lon_v * h
		_bump_v += (-bw2 * bump - bc2 * _bump_v) * h
		bump = clampf(bump + _bump_v * h, -1.0, 1.0)

	if absf(target_lat) < 1e-4 and absf(lat) < REST_POS_EPS and absf(_lat_v) < REST_VEL_EPS:
		lat = 0.0
		_lat_v = 0.0
	if absf(target_lon) < 1e-4 and absf(lon) < REST_POS_EPS and absf(_lon_v) < REST_VEL_EPS:
		lon = 0.0
		_lon_v = 0.0
	if absf(bump) < REST_POS_EPS and absf(_bump_v) < REST_VEL_EPS:
		bump = 0.0
		_bump_v = 0.0
	_update_outputs(canvas_h, amp)

func _clear_outputs() -> void:
	dash_offset = Vector2.ZERO
	dash_rot = 0.0
	dash_scale = Vector2.ONE
	dash_skew = Vector2.ZERO
	corner_offset = Vector2.ZERO
	corner_rot = 0.0

func _update_outputs(canvas_h: float, amp: float) -> void:
	if lat == 0.0 and lon == 0.0 and bump == 0.0:
		_clear_outputs()
		return
	var ui_s := clampf((canvas_h if canvas_h > 1.0 else 900.0) / 900.0, 0.7, 1.5)
	var gain := ui_s * amp
	var dx := -lat * MAX_OFFSET_X * gain
	var dy := clampf(lon * MAX_OFFSET_Y + bump * MAX_BUMP_Y, -MAX_OFFSET_X, MAX_OFFSET_X) * gain
	dash_offset = Vector2(dx, dy)
	dash_rot = -lat * MAX_ROT_RAD * amp
	var sx := 1.0 - absf(lat) * DASH_SQUASH_X * amp - lon * DASH_ZOOM_LON * amp
	var sy := 1.0 - lon * DASH_ZOOM_LON * amp
	dash_scale = Vector2(sx, sy)
	dash_skew = Vector2(lat * DASH_SKEW_X * amp, -lat * DASH_SKEW_Y * amp)
	corner_offset = dash_offset * CORNER_GAIN
	corner_rot = dash_rot * CORNER_GAIN
