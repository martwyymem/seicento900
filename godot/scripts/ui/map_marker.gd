class_name MapMarker
extends RefCounted
## The projection and clamping behind the open world's map markers and the player's waypoint, kept free of
## drawing so the tests can run them: map metres to the heading-up minimap, the rim clamp for markers beyond
## it, the big map's metres <-> pixels, and keeping a placed waypoint inside the playable area.

## Map metres -> minimap pixels (heading up: what lies ahead of the car is above the centre, the car's
## right-hand side to the right). A radius under a metre is treated as a metre rather than dividing by zero.
static func mini_xy(p: Vector2, car_pos: Vector2, heading: float, radius: float, sz: Vector2) -> Vector2:
	var f := Vector2(cos(heading), sin(heading))
	var rt := Vector2(-f.y, f.x)
	var d := p - car_pos
	var o := Vector2(d.dot(rt), -d.dot(f)) / maxf(radius, 1.0)
	return sz * 0.5 + o * sz * 0.5

## A marker pixel clamped onto the minimap's rim circle (lim_frac of its width from the centre). Returns
## {pos, edge, dir}: edge is true when it was pulled in, dir is the unit direction it lies in from the centre
## (the way an edge marker points). A marker exactly at the centre has no direction and gets "up".
static func rim_clamp(q: Vector2, sz: Vector2, lim_frac := 0.44) -> Dictionary:
	var c := sz * 0.5
	var d := q - c
	var lim := sz.x * lim_frac
	var len := d.length()
	var dir := d / len if len > 0.0001 else Vector2.UP
	if len > lim:
		return {"pos": c + dir * lim, "edge": true, "dir": dir}
	return {"pos": q, "edge": false, "dir": dir}

## Map metres -> big map pixels, for a view centred on `centre` showing `radius` metres up and down; the
## aspect widens the visible span sideways.
static func big_xy(p: Vector2, centre: Vector2, radius: float, aspect: float, sz: Vector2) -> Vector2:
	var o := (p - centre) / maxf(radius, 1.0)
	o.x /= maxf(aspect, 0.01)
	return sz * 0.5 + o * sz * 0.5

## The inverse of big_xy: where a click on the big map lands in map metres.
static func big_world(q: Vector2, centre: Vector2, radius: float, aspect: float, sz: Vector2) -> Vector2:
	var o := (q - sz * 0.5) / (sz * 0.5)
	o.x *= maxf(aspect, 0.01)
	return centre + o * radius

## A waypoint placed outside the playable area (the map picture shows the dimmed ground beyond it) is
## moved to the nearest point of the outline, then 2 m inside it, so the route can end there. Inside points
## and a missing outline come back unchanged.
static func keep_inside(p: Vector2, poly: PackedVector2Array, inset := 2.0) -> Vector2:
	if poly.size() < 3 or Geometry2D.is_point_in_polygon(p, poly):
		return p
	var best := p
	var best_d := INF
	var centre := Vector2.ZERO
	for v in poly:
		centre += v
	centre /= poly.size()
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var dist := p.distance_to(q)
		if dist < best_d:
			best_d = dist
			best = q
	var inward := (centre - best).normalized()
	var inside := best + inward * inset
	return inside if Geometry2D.is_point_in_polygon(inside, poly) else best
