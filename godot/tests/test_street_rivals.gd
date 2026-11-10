## StreetRivals (scripts/world/street_rivals.gd) on synthetic paths, no map: the rivals' times against the reference
## pace on a straight quarter mile and on a wiggly 4 km road, the drag grid, the knockout (the last car out at each
## lap), the player's place, a full grid of nine, and the degenerate inputs.
extends RefCounted

var completed := false
const DT := 0.1

func run() -> Array:
	var errors: Array[String] = []
	_straight(errors)
	_wiggly(errors)
	_drag(errors)
	_knockout_fast(errors)
	_knockout_slow(errors)
	_places(errors)
	_grid(errors)
	_edges(errors)
	completed = true
	return errors

static func _line(len: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2.ZERO, Vector2(len, 0.0)])

## A rounded rectangle (~3.3 km round), resampled; `laps` of it concatenated into one path.
static func _loop(laps: int) -> PackedVector2Array:
	var w := 1000.0
	var h := 450.0
	var r := 120.0
	var one := PackedVector2Array()
	var corners := [Vector2(w - r, r), Vector2(w - r, h - r), Vector2(r, h - r), Vector2(r, r)]
	var starts := [-PI * 0.5, 0.0, PI * 0.5, PI]
	for c in 4:
		for j in 13:
			var a: float = float(starts[c]) + PI * 0.5 * float(j) / 12.0
			one.append((corners[c] as Vector2) + Vector2(cos(a), sin(a)) * r)
	one.append(one[0])
	var lap := LiveEvents.resample(one, 5.0)
	var out := PackedVector2Array()
	for k in laps:
		for i in lap.size():
			if k > 0 and i == 0:
				continue
			out.append(lap[i])
	return out

static func _loop_length() -> float:
	var p := _loop(1)
	var l := 0.0
	for i in range(1, p.size()):
		l += p[i - 1].distance_to(p[i])
	return l

static func _wiggle() -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 401:
		var x := float(i) * 10.0
		out.append(Vector2(x, 90.0 * sin(x / 260.0) + 40.0 * sin(x / 95.0)))
	return out

## A player standing at the start of the route.
func _idle_run(sr: StreetRivals, limit: float) -> void:
	var p: Vector2 = sr.pose(0.0, 0.0)[0]
	var n := int(limit / DT)
	for i in n:
		sr.step(DT, p, 0.0)
		if sr.finished_count() == sr.rivals.size():
			break

func _straight(errors: Array[String]) -> void:
	var path := _line(402.0)
	var ref := LiveEvents.pace_time(path, "stock")
	var sr := StreetRivals.new(path, "stock", 3, 7, {"grid": "drag"})
	_idle_run(sr, 60.0)
	if sr.finished_count() != 3:
		errors.append("quarter mile: %d of 3 rivals finished in 60 s" % sr.finished_count())
		return
	var times := []
	for r in sr.rivals:
		var td: float = r.t_done
		times.append(snappedf(td, 0.1))
		if td < 18.0 or td > 25.0:
			errors.append("quarter mile: a rival took %.1f s (18-25 s, reference %.1f s)" % [td, ref])
		if td < ref:
			errors.append("quarter mile: a rival (%.1f s) beat the reference driver (%.1f s)" % [td, ref])
	print("  straight 402 m: pace_time %.2f s, rivals %s" % [ref, times])

func _wiggly(errors: Array[String]) -> void:
	var path := _wiggle()
	var ref := LiveEvents.pace_time(path, "stock")
	var sr := StreetRivals.new(path, "stock", 7, 3)
	# the player sits still at the start, so the rubber band slows the leaders a little: assert loosely
	_idle_run(sr, ref * 2.0)
	if sr.finished_count() != 7:
		errors.append("wiggly 4 km: %d of 7 rivals finished within twice the reference %.0f s" % [sr.finished_count(), ref])
		return
	var times := []
	for r in sr.rivals:
		var td: float = r.t_done
		times.append(snappedf(td / ref, 0.001))
		if td < ref * 1.04 or td > ref * 1.45:
			errors.append("wiggly 4 km: a rival took %.1f s (%.3f x the reference %.1f s, wanted 1.04-1.45)" % [td, td / ref, ref])
	print("  wiggly %.0f m: pace_time %.1f s, rivals / pace_time %s" % [sr.length, ref, times])

func _drag(errors: Array[String]) -> void:
	var sr := StreetRivals.new(_line(402.0), "stock", 3, 5, {"grid": "drag"})
	var pg := sr.player_grid()
	if not pg.is_equal_approx(Vector2(0.0, -1.8)):
		errors.append("drag player_grid() is %s, wanted (0, -1.8)" % pg)
	var plain := StreetRivals.new(_line(402.0), "stock", 3, 5)
	if not plain.player_grid().is_equal_approx(Vector2.ZERO):
		errors.append("default player_grid() is %s, wanted (0, 0)" % plain.player_grid())
	var lats := [pg.y]
	for r in sr.rivals:
		if absf(float(r.s)) > 0.001:
			errors.append("drag rival starts at s=%.2f" % float(r.s))
		if lats.has(float(r.lat)):
			errors.append("drag lane %.1f is shared" % float(r.lat))
		lats.append(float(r.lat))
	# straight lanes all the way, and they get going straight away
	var p: Vector2 = sr.pose(0.0, pg.y)[0]
	for i in 20:
		sr.step(DT, p, 0.0)
	for r in sr.rivals:
		if float(r.s) < 2.0:
			errors.append("drag rival has barely moved after 2 s (s=%.2f)" % float(r.s))
	_idle_run(sr, 40.0)
	for k in sr.rivals.size():
		var r: Dictionary = sr.rivals[k]
		if absf(float(r.lat) - float(lats[k + 1])) > 0.001:
			errors.append("drag rival %d changed lane (%.2f -> %.2f)" % [k, float(lats[k + 1]), float(r.lat)])
	if sr.finished_count() != 3:
		errors.append("drag: %d of 3 rivals finished" % sr.finished_count())

## A player that follows the route at `speed` from the start; returns the knockout run's rivals and the player
## state after the player is home, out, or the time runs out.
func _knock_run(laps: int, speed: float, count: int) -> StreetRivals:
	var lap := _loop_length()
	var sr := StreetRivals.new(_loop(laps), "stock", count, 11, {"knockout": true, "lap_length": lap})
	var ps := 0.0
	var guard := 0
	while guard < 20000 and not sr.player_done():
		guard += 1
		ps += speed * DT
		sr.step(DT, sr.pose(minf(ps, sr.length), 0.0)[0], speed)
	return sr

func _knockout_fast(errors: Array[String]) -> void:
	var sr := _knock_run(6, 70.0, 5)
	if sr.player_out:
		errors.append("knockout: the fastest player was knocked out")
	if sr.out_order.size() != 5:
		errors.append("knockout: %d cars out, wanted 5 (%s)" % [sr.out_order.size(), sr.out_order])
		return
	var seen := {}
	for w in sr.out_order:
		if int(w) < 0 or seen.has(w):
			errors.append("knockout: out order %s repeats or has the player" % [sr.out_order])
			break
		seen[w] = true
	for r in sr.rivals:
		if not bool(r.out):
			errors.append("knockout: a rival is still running after five laps")
	if sr.position() != 1 or sr.field() != 1:
		errors.append("knockout: player place %d of %d at the end, wanted 1 of 1" % [sr.position(), sr.field()])
	if sr.player_lap() != 5:
		errors.append("knockout: player in lap %d at the end, wanted 5 (0-based)" % sr.player_lap())
	# one per completed lap: the 1st elimination only once the leader passed one lap, and an out rival stays put
	var lap := _loop_length()
	for r in sr.rivals:
		if float(r.s) < -40.0 or float(r.s) > lap * 5.0:
			errors.append("knockout: out rival parked at s=%.0f" % float(r.s))
	if sr.lap_of(lap * 2.5) != 2 or sr.lap_of(-5.0) != 0:
		errors.append("knockout: lap_of gives %d / %d" % [sr.lap_of(lap * 2.5), sr.lap_of(-5.0)])

func _knockout_slow(errors: Array[String]) -> void:
	var sr := _knock_run(6, 4.0, 5)
	if not sr.player_out:
		errors.append("knockout: a crawling player was never knocked out")
		return
	if sr.player_out_pos != 6:
		errors.append("knockout: crawling player went out in %d, wanted 6" % sr.player_out_pos)
	if sr.out_order.size() != 1 or sr.out_order[0] != -1:
		errors.append("knockout: first lap boundary should drop the player, got %s" % [sr.out_order])
	var lap := _loop_length()
	var leader := 0.0
	for r in sr.rivals:
		leader = maxf(leader, float(r.s))
	if leader < lap - 1.0 or leader > lap + 80.0:
		errors.append("knockout: player went out with the leader at s=%.0f (lap %.0f)" % [leader, lap])
	if sr.field() != 6 or sr.position() != 6:
		errors.append("knockout: after going out the field is %d / place %d" % [sr.field(), sr.position()])

func _places(errors: Array[String]) -> void:
	var path := _line(1000.0)
	var sr := StreetRivals.new(path, "stock", 5, 9)
	var first := -1
	var last := -1
	# a player sat on the grid for 6 s (last), then flying through the field and out in front
	var ps := 0.0
	for i in int(70.0 / DT):
		ps += (0.0 if i < 60 else 40.0) * DT
		sr.step(DT, sr.pose(ps, 0.0)[0], 40.0)
		if i == 59:
			first = sr.position()
		last = sr.position()
		if sr.player_s >= sr.length:
			break
	if first != 6:
		errors.append("place at the start is %d, wanted 6" % first)
	if last != 1:
		errors.append("place after passing everyone is %d, wanted 1" % last)
	if sr.field() != 6:
		errors.append("field of %d, wanted 6" % sr.field())

func _grid(errors: Array[String]) -> void:
	var sr := StreetRivals.new(_line(1000.0), "stock", 9, 1)
	if sr.rivals.size() != 9:
		errors.append("9 rivals asked for, %d made" % sr.rivals.size())
	var slots := {}
	for r in sr.rivals:
		var key := "%.1f/%.1f" % [float(r.s), float(r.lat)]
		if slots.has(key):
			errors.append("two rivals share the grid slot %s" % key)
		slots[key] = true
		if bool(r.out):
			errors.append("a fresh rival is out")
	if StreetRivals.new(_line(1000.0), "stock", 30, 1).rivals.size() != 9:
		errors.append("more than 9 rivals made")
	# a crowded start runs without going through each other: nobody finishes inside a car length of another
	_idle_run(sr, 5.0)

func _edges(errors: Array[String]) -> void:
	var none := StreetRivals.new(_line(500.0), "stock", 0, 1)
	none.step(DT, Vector2.ZERO, 0.0)
	if none.rivals.size() != 0 or none.position() != 1 or none.field() != 1 or none.best_time() >= 0.0:
		errors.append("count 0: rivals %d, place %d of %d" % [none.rivals.size(), none.position(), none.field()])
	var short := StreetRivals.new(PackedVector2Array([Vector2(3.0, 4.0)]), "stock", 3, 1)
	for i in 5:
		short.step(DT, Vector2.ZERO, 0.0)
	short.pose(10.0, 1.0)
	if short.finished_count() != 0:
		errors.append("a one-point path: rivals finished")
	var empty := StreetRivals.new(PackedVector2Array(), "stock", 2, 1, {"knockout": true, "lap_length": 100.0})
	empty.step(DT, Vector2.ZERO, 0.0)
	empty.pose(1.0, 0.0)
	var sr := StreetRivals.new(_line(402.0), "stock", 3, 1)
	sr.step(0.0, Vector2.ZERO, 0.0)
	sr.step(-1.0, Vector2.ZERO, 0.0)
	if sr.t != 0.0:
		errors.append("a zero step advanced the clock to %.2f" % sr.t)
	for r in sr.rivals:
		if float(r.v) != 0.0 or not is_finite(float(r.s)):
			errors.append("a zero step moved a rival (v=%.2f)" % float(r.v))
