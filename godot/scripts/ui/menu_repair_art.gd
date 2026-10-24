## Technical line drawing of the selected repair component, on the cream panel, like the sketches on
## CMR 2.0's service screen. One drawing per part in Service.PARTS.
extends Control

var INK: Color:
	get: return CmrStyle.INK
## the sketch's fills, a shade under the panel's paper (cream in CMR, the skin's paper elsewhere)
var FILL: Color:
	get: return CmrStyle.PAPER.darkened(0.05)
var SHADE: Color:
	get: return CmrStyle.PAPER.darkened(0.11)
const W := 2.6 ## line width

var part := "Body":
	set(value):
		part = value
		queue_redraw()

func _draw() -> void:
	# drawn in a 2:1 box of unit height, centred in the panel
	var h := size.y * 0.8
	var o := Vector2(size.x * 0.5 - h, size.y * 0.1)
	var u := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * h
	match part:
		"Body": _body(u)
		"Suspension": _suspension(u, h)
		"Steering": _steering(u, h)
		"Engine": _engine(u, h)
		"Gearbox": _gearbox(u, h)
		"Brakes": _brakes(u, h)
		"Exhaust": _exhaust(u, h)
		"Electrics": _electrics(u, h)

func _poly(pts: PackedVector2Array, fill := FILL) -> void:
	draw_colored_polygon(pts, fill)
	draw_polyline(pts + PackedVector2Array([pts[0]]), INK, W, true)

func _pts(u: Callable, xy: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, xy.size(), 2):
		out.append(u.call(xy[i], xy[i + 1]))
	return out

## A Seicento in side view: the short bonnet, the tall glasshouse and the cut-off tail.
func _body(u: Callable) -> void:
	_poly(_pts(u, [0.12, 0.72, 0.14, 0.52, 0.42, 0.44, 0.7, 0.16, 1.42, 0.14, 1.66, 0.22, 1.86, 0.5, 1.88, 0.72]))
	_poly(_pts(u, [0.76, 0.22, 1.08, 0.2, 1.08, 0.42, 0.56, 0.44]), SHADE)
	_poly(_pts(u, [1.14, 0.2, 1.4, 0.2, 1.58, 0.42, 1.14, 0.42]), SHADE)
	draw_line(u.call(1.1, 0.46), u.call(1.1, 0.72), INK, W, true)
	for x in [0.5, 1.5]:
		var c: Vector2 = u.call(x, 0.74)
		var r: float = (u.call(0.16, 0.0) - u.call(0.0, 0.0)).x
		draw_circle(c, r, FILL)
		draw_arc(c, r, 0.0, TAU, 40, INK, W, true)
		draw_arc(c, r * 0.5, 0.0, TAU, 28, INK, W * 0.8, true)

## A MacPherson strut: the coil spring round the damper, the top mount and the lower arm.
func _suspension(u: Callable, h: float) -> void:
	_poly(_pts(u, [0.92, 0.04, 1.08, 0.04, 1.08, 0.86, 0.92, 0.86]))
	var coil := PackedVector2Array()
	for k in 61:
		var t := k / 60.0
		coil.append(u.call(1.0 + 0.2 * sin(t * TAU * 6.0), 0.14 + 0.58 * t))
	draw_polyline(coil, INK, W * 1.3, true)
	_poly(_pts(u, [0.74, 0.06, 1.26, 0.06, 1.26, 0.12, 0.74, 0.12]), SHADE)
	_poly(_pts(u, [0.4, 0.86, 1.2, 0.84, 1.24, 0.94, 0.42, 0.96]), SHADE)
	draw_circle(u.call(0.44, 0.91), h * 0.04, FILL)
	draw_arc(u.call(0.44, 0.91), h * 0.04, 0.0, TAU, 20, INK, W, true)

## The steering wheel and column down to the rack, with the track rods out to the wheels.
func _steering(u: Callable, h: float) -> void:
	var c: Vector2 = u.call(0.6, 0.42)
	draw_arc(c, h * 0.34, 0.0, TAU, 56, INK, W * 2.2, true)
	draw_circle(c, h * 0.08, SHADE)
	draw_arc(c, h * 0.08, 0.0, TAU, 28, INK, W, true)
	for a in [PI * 0.5, PI * 1.15, PI * 1.85]:
		draw_line(c + Vector2.RIGHT.rotated(a) * h * 0.08, c + Vector2.RIGHT.rotated(a) * h * 0.32, INK, W * 1.6, true)
	draw_line(u.call(0.82, 0.58), u.call(1.3, 0.86), INK, W * 1.5, true)
	_poly(_pts(u, [1.0, 0.82, 1.8, 0.82, 1.8, 0.9, 1.0, 0.9]), SHADE)
	draw_line(u.call(1.8, 0.86), u.call(1.94, 0.72), INK, W, true)
	draw_line(u.call(1.0, 0.86), u.call(0.9, 0.96), INK, W, true)

## The four-cylinder FIRE engine: block, head and cam cover, the radiator in front of it.
func _engine(u: Callable, h: float) -> void:
	_poly(_pts(u, [0.12, 0.1, 0.36, 0.1, 0.36, 0.92, 0.12, 0.92]))
	for k in 9:
		var y := 0.16 + k * 0.088
		draw_line(u.call(0.15, y), u.call(0.33, y), INK, W * 0.6, true)
	_poly(_pts(u, [0.6, 0.38, 1.6, 0.38, 1.6, 0.92, 0.6, 0.92]))
	_poly(_pts(u, [0.64, 0.2, 1.56, 0.2, 1.6, 0.38, 0.6, 0.38]), SHADE)
	_poly(_pts(u, [0.72, 0.08, 1.44, 0.08, 1.48, 0.2, 0.68, 0.2]))
	for k in 4:
		var c: Vector2 = u.call(0.78 + k * 0.22, 0.64)
		draw_arc(c, h * 0.09, 0.0, TAU, 28, INK, W, true)
	var pulley: Vector2 = u.call(1.74, 0.72)
	draw_circle(pulley, h * 0.1, SHADE)
	draw_arc(pulley, h * 0.1, 0.0, TAU, 28, INK, W, true)
	draw_line(u.call(1.6, 0.6), u.call(1.74, 0.62), INK, W, true)

## Two meshing gears and the shaft through the casing.
func _gearbox(u: Callable, h: float) -> void:
	_gear(u.call(0.72, 0.5), h * 0.34, 14)
	_gear(u.call(1.3, 0.56), h * 0.24, 10)
	draw_line(u.call(0.1, 0.5), u.call(0.6, 0.5), INK, W * 1.6, true)
	draw_line(u.call(1.42, 0.56), u.call(1.9, 0.56), INK, W * 1.6, true)

func _gear(c: Vector2, r: float, teeth: int) -> void:
	var pts := PackedVector2Array()
	for k in teeth * 4:
		var a := TAU * k / (teeth * 4)
		var rr := r if (k % 4) < 2 else r * 0.82
		pts.append(c + Vector2.RIGHT.rotated(a) * rr)
	_poly(pts)
	draw_circle(c, r * 0.28, SHADE)
	draw_arc(c, r * 0.28, 0.0, TAU, 24, INK, W, true)

## A vented disc with its caliper.
func _brakes(u: Callable, h: float) -> void:
	var c: Vector2 = u.call(0.9, 0.5)
	var r := h * 0.44
	draw_circle(c, r, FILL)
	draw_arc(c, r, 0.0, TAU, 56, INK, W, true)
	draw_arc(c, r * 0.4, 0.0, TAU, 36, INK, W, true)
	for k in 4:
		draw_circle(c + Vector2.RIGHT.rotated(TAU * k / 4.0 + 0.4) * r * 0.24, r * 0.05, INK)
	for k in 18:
		var a := TAU * k / 18.0
		draw_line(c + Vector2.RIGHT.rotated(a) * r * 0.52, c + Vector2.RIGHT.rotated(a) * r * 0.88, Color(INK, 0.45), 1.2, true)
	_poly(_pts(u, [1.2, 0.16, 1.5, 0.22, 1.56, 0.52, 1.44, 0.8, 1.2, 0.84, 1.28, 0.5]), SHADE)
	draw_line(u.call(1.5, 0.3), u.call(1.86, 0.18), INK, W, true)

## Downpipe, silencer box and the tailpipe.
func _exhaust(u: Callable, h: float) -> void:
	var pipe := _pts(u, [0.08, 0.18, 0.3, 0.2, 0.42, 0.5, 0.62, 0.56])
	draw_polyline(pipe, INK, h * 0.08, true)
	draw_polyline(pipe, FILL, h * 0.08 - W * 2.0, true)
	_poly(_pts(u, [0.62, 0.38, 1.38, 0.38, 1.46, 0.48, 1.46, 0.66, 1.38, 0.76, 0.62, 0.76, 0.56, 0.66, 0.56, 0.48]))
	for x in [0.82, 1.18]:
		draw_line(u.call(x, 0.4), u.call(x, 0.74), INK, W * 0.7, true)
	var tail := _pts(u, [1.46, 0.57, 1.86, 0.57])
	draw_polyline(tail, INK, h * 0.08, true)
	draw_polyline(tail, FILL, h * 0.08 - W * 2.0, true)
	draw_arc(u.call(1.86, 0.57), h * 0.04, 0.0, TAU, 20, INK, W, true)

## A headlamp unit with its lens and the loom behind it.
func _electrics(u: Callable, h: float) -> void:
	_poly(_pts(u, [0.3, 0.2, 1.0, 0.14, 1.08, 0.5, 0.96, 0.86, 0.3, 0.82, 0.22, 0.5]))
	var c: Vector2 = u.call(0.64, 0.5)
	draw_circle(c, h * 0.24, SHADE)
	draw_arc(c, h * 0.24, 0.0, TAU, 40, INK, W, true)
	for k in 4:
		var x := -0.18 + k * 0.12
		draw_line(c + Vector2(x, -0.2) * h, c + Vector2(x, 0.2) * h, Color(INK, 0.4), 1.2, true)
	var loom := PackedVector2Array()
	for k in 31:
		var t := k / 30.0
		loom.append(u.call(1.08 + 0.8 * t, 0.5 + 0.18 * sin(t * TAU * 1.5)))
	draw_polyline(loom, INK, W * 1.4, true)
	_poly(_pts(u, [1.8, 0.56, 1.92, 0.56, 1.92, 0.7, 1.8, 0.7]), SHADE)
