## The 400 and 500 m braking boards (trackside_furniture.gd far_board_stations): where the Hypercar brakes from the top
## speed of a long straight, the Goliath's S1 end gets both boards at 400 and 500 m before the bend, and a corner whose
## straight is too short for them gets none.
extends RefCounted

var completed := false
var errors: Array[String] = []

func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		errors.append("%s %s" % [what, detail])

func _has(stations: Array, dist: int, s: float, tol: float) -> bool:
	for st in stations:
		if int(st[0]) == dist and absf(float(st[1]) - s) <= tol:
			return true
	return false

func _in(stations: Array, a: float, b: float) -> int:
	var k := 0
	for st in stations:
		if float(st[1]) >= a and float(st[1]) <= b:
			k += 1
	return k

func run() -> Array:
	var tr := Track.new(Track.load_def("goliath"))
	var f: RefCounted = (load("res://scripts/ui/trackside_furniture.gd") as GDScript).new()
	f.track = tr
	var st: Array = f.far_board_stations(tr.profile_for(Hypercar.model()))
	check("goliath gets far braking boards", st.size() > 0, "(%d)" % st.size())
	# the S1 end: the S1 runs at the Hypercar's top speed from about 3.0 km and brakes for its bend at about 3.52 km
	# (the speed profile falls to about 190 km/h there), so its boards stand 400 m and 500 m before 3520 m
	check("the S1 end gets a 400 m board 400 m before its bend", _has(st, 400, 3120.0, 12.0), str(st))
	check("the S1 end gets a 500 m board 500 m before its bend", _has(st, 500, 3020.0, 12.0), str(st))
	# short approaches: the bend at 4010 m has only 330 m of straight before it, so no far board stands in the 500 m
	# before it; the bend at 11370 m has 210 m, so no far board stands in the 400 m before it
	check("a 330 m approach gets no far board", _in(st, 3500.0, 4010.0) == 0, str(st))
	check("a 210 m approach gets no far board", _in(st, 10955.0, 11370.0) == 0, str(st))
	completed = true
	return errors
