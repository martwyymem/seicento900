## Free look for the driving cameras, as in Forza, Gran Turismo or DiRT: the pad's right stick points the view
## the way it is pushed (down looks back) and springs back to the front when let go; holding the right stick in
## (R3) or B looks straight back at once; dragging with the right or middle mouse button swings the view round
## the car and tilts it, and it eases back to the front a moment after the mouse goes still.
## Owners (RaceWorld, OpenWorld) call update() once a frame and turn their camera by yaw and pitch: the chase
## cameras orbit the car (orbit()), the cameras on the car turn on the spot.
class_name CameraLook
extends RefCounted

const STICK_DEAD := 0.22 ## right-stick deflection below which the stick is let go
const STICK_FULL := 0.85 ## deflection at which the view points all the way the stick is pushed
const STICK_EASE := 10.0 ## 1/s: how fast the view follows the stick
const RETURN_EASE := 5.0 ## 1/s: how fast the view swings back to the front once let go
const MOUSE_YAW := 0.0065 ## rad per pixel of horizontal drag
const MOUSE_PITCH := 0.0045 ## rad per pixel of vertical drag
const MOUSE_HOLD := 1.4 ## s a mouse look is held after the mouse goes still, before it eases back
const PITCH_MIN := -0.3 ## rad: how far a drag may tilt the view up (the camera dips towards the road)
const PITCH_MAX := 0.75 ## rad: how far it may tilt down over the car

## rad: how far the view is turned from straight ahead, positive to the right; PI looks back
var yaw := 0.0
## rad: how far the view is tilted down over the car (a chase camera rises), negative to look up
var pitch := 0.0
## whether this frame's yaw jumped rather than swung (look back pressed or let go): chase cameras skip their easing
var cut := false
## the pad to read; -1: the first one connected
var device := -1

var _mouse_yaw := 0.0
var _mouse_pitch := 0.0
var _mouse_idle := MOUSE_HOLD
var _mouse_last := Vector2i.ZERO
var _dragging := false
var _back := false

## Reads the stick, the look-back buttons and the mouse. enabled false (a map or menu open): the view returns
## to the front.
func update(delta: float, enabled := true) -> void:
	cut = false
	var pad := device
	if pad < 0:
		var pads := Input.get_connected_joypads()
		pad = pads[0] if not pads.is_empty() else -1
	var back := false
	var stick := Vector2.ZERO
	if enabled:
		back = Input.is_physical_key_pressed(KEY_B)
		if pad >= 0:
			back = back or Input.is_joy_button_pressed(pad, JOY_BUTTON_RIGHT_STICK)
			stick = Vector2(Input.get_joy_axis(pad, JOY_AXIS_RIGHT_X), Input.get_joy_axis(pad, JOY_AXIS_RIGHT_Y))
	_read_mouse(delta, enabled)

	var want_yaw := 0.0
	var want_pitch := 0.0
	var rate := RETURN_EASE
	var mag := stick.length()
	if back:
		want_yaw = PI
	elif mag > STICK_DEAD:
		# the stick's direction is the view's: right looks right, down looks back
		var amount := smoothstep(STICK_DEAD, STICK_FULL, mag)
		want_yaw = atan2(stick.x, -stick.y) * amount
		rate = STICK_EASE
		_mouse_yaw = 0.0
		_mouse_pitch = 0.0
	elif _dragging or _mouse_idle < MOUSE_HOLD:
		want_yaw = _mouse_yaw
		want_pitch = _mouse_pitch
		rate = 30.0
	else:
		_mouse_yaw = 0.0
		_mouse_pitch = 0.0

	if back != _back:
		# looking back cuts straight there and straight back, as a glance in a real car does
		_back = back
		yaw = want_yaw
		pitch = 0.0 if back else want_pitch
		cut = true
		return
	var k := 1.0 - exp(-delta * rate)
	yaw = wrapf(yaw + wrapf(want_yaw - yaw, -PI, PI) * k, -PI, PI)
	pitch += (want_pitch - pitch) * k
	if absf(yaw) < 0.0005 and absf(pitch) < 0.0005:
		yaw = 0.0
		pitch = 0.0

## Whether the view is turned off the front at all.
func active() -> bool:
	return yaw != 0.0 or pitch != 0.0

## Forgets any look (race start, car reset, mode change).
func reset() -> void:
	yaw = 0.0
	pitch = 0.0
	_mouse_yaw = 0.0
	_mouse_pitch = 0.0
	_mouse_idle = MOUSE_HOLD
	_back = false

## fwd turned by yaw (round the vertical, positive to the right).
func turn(fwd: Vector3) -> Vector3:
	return fwd.rotated(Vector3.UP, -yaw)

## A chase camera at pos behind pivot swung round the car by yaw and lifted or dipped by pitch, at the same distance.
func orbit(pivot: Vector3, pos: Vector3) -> Vector3:
	if not active():
		return pos
	var off := (pos - pivot).rotated(Vector3.UP, -yaw)
	var flat := Vector2(off.x, off.z)
	var dist := off.length()
	if dist < 0.01 or flat.length() < 0.01:
		return pivot + off
	var elev := clampf(atan2(off.y, flat.length()) + pitch, -0.05, 1.35)
	var dir := flat.normalized()
	return pivot + Vector3(dir.x * cos(elev) * dist, sin(elev) * dist, dir.y * cos(elev) * dist)

func _read_mouse(delta: float, enabled: bool) -> void:
	var held := enabled and DisplayServer.window_is_focused() and (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE))
	var at := DisplayServer.mouse_get_position()
	if held and _dragging:
		var d := at - _mouse_last
		if d != Vector2i.ZERO:
			_mouse_yaw = wrapf(_mouse_yaw + d.x * MOUSE_YAW, -PI, PI)
			_mouse_pitch = clampf(_mouse_pitch + d.y * MOUSE_PITCH, PITCH_MIN, PITCH_MAX)
			_mouse_idle = 0.0
	_dragging = held
	_mouse_last = at
	if not held:
		_mouse_idle += delta
	if not enabled:
		_mouse_idle = MOUSE_HOLD
