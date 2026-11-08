## The driving cameras' free look (CameraLook): B looks straight back at once and straight forward again, the right
## stick points the view the way it is pushed and springs back when let go, and the chase orbit keeps the camera's
## distance from the car while swinging it round to the side the view turns to.
extends RefCounted

var completed := false
var errors: Array[String] = []

func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		errors.append("%s %s" % [what, detail])

func _key(on: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_B
	ev.keycode = KEY_B
	ev.pressed = on
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func _stick(x: float, y: float) -> void:
	for a: Array in [[JOY_AXIS_RIGHT_X, x], [JOY_AXIS_RIGHT_Y, y]]:
		var ev := InputEventJoypadMotion.new()
		ev.device = 0
		ev.axis = a[0]
		ev.axis_value = a[1]
		Input.parse_input_event(ev)
	Input.flush_buffered_events()

func run() -> Array[String]:
	var look := CameraLook.new()
	look.device = 0
	look.update(0.016)
	check("no input: straight ahead", not look.active(), "yaw %.3f" % look.yaw)

	_key(true)
	look.update(0.016)
	check("B: looks back at once", look.cut and is_equal_approx(absf(look.yaw), PI), "yaw %.3f" % look.yaw)
	_key(false)
	look.update(0.016)
	check("B let go: front again at once", look.cut and look.yaw == 0.0, "yaw %.3f" % look.yaw)

	_stick(1.0, 0.0)
	for i in 60:
		look.update(1.0 / 60.0)
	check("stick right: looks right", absf(look.yaw - PI * 0.5) < 0.05, "yaw %.3f" % look.yaw)
	_stick(0.0, 1.0)
	for i in 60:
		look.update(1.0 / 60.0)
	check("stick down: looks back", absf(absf(look.yaw) - PI) < 0.05, "yaw %.3f" % look.yaw)
	_stick(0.05, 0.05)
	for i in 180:
		look.update(1.0 / 60.0)
	check("stick let go: springs back", not look.active(), "yaw %.3f" % look.yaw)

	# turn and orbit: car at the origin heading +x, camera 6 m behind and 2 m up
	look.yaw = PI * 0.5
	look.pitch = 0.0
	var fwd := Vector3(1, 0, 0)
	var right := fwd.cross(Vector3.UP)
	check("turn right is the camera's right", look.turn(fwd).distance_to(right) < 0.001, str(look.turn(fwd)))
	var behind := Vector3(-6, 2, 0)
	var o := look.orbit(Vector3.ZERO, behind)
	check("orbit keeps the distance", absf(o.length() - behind.length()) < 0.001, str(o))
	check("looking right, the camera sits on the left", o.dot(right) < -5.0, str(o))
	look.yaw = 0.0
	look.pitch = 0.4
	check("pitch lifts the camera", look.orbit(Vector3.ZERO, behind).y > behind.y + 1.0)
	look.reset()
	check("reset", not look.active())
	_stick(0.0, 0.0)
	completed = true
	return errors
