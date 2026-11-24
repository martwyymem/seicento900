## StreetRivals (scripts/world/street_rivals.gd), the drag field, on synthetic paths, no map: the drag grid (own lanes,
## every body on the tarmac), its launch calibrated to the car's standing start by level, and the degenerate inputs.
## (Every other race on the map runs the race sim's bots: tests/test_event_field.gd.)
extends RefCounted

var completed := false
const DT := 0.1

func run() -> Array:
	var errors: Array[String] = []
	_drag(errors)
	_drag_kerbs(errors)
	_edges(errors)
	_drag_calibration(errors)
	completed = true
	return errors

static func _line(len: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2.ZERO, Vector2(len, 0.0)])

## A rounded rectangle (~3.3 km round), resampled; `laps` of it concatenated into one path.
## A player standing at the start of the route.
func _idle_run(sr: StreetRivals, limit: float) -> void:
	var p: Vector2 = sr.pose(0.0, 0.0)[0]
	var n := int(limit / DT)
	for i in n:
		sr.step(DT, p, 0.0)
		if sr.finished_count() == sr.rivals.size():
			break

func _drag(errors: Array[String]) -> void:
	var sr := StreetRivals.new(_line(402.0), "stock", 3, 5, {"grid": "drag"})
	var pg := sr.player_grid()
	# four abreast across an 8 m road: the player second from the right, a lane's width apart
	if not pg.is_equal_approx(Vector2(0.0, -0.5 * sr.drag_lane)) or sr.drag_lane < 2.0 or sr.drag_lane * 3.0 + 1.7 > 8.01:
		errors.append("drag player_grid() is %s with lanes %.2f m apart" % [pg, sr.drag_lane])
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
	_idle_run(sr, 14.0)
	for k in sr.rivals.size():
		var r: Dictionary = sr.rivals[k]
		if float(r.t_done) < 0.0 and absf(float(r.lat) - float(lats[k + 1])) > 0.001:
			errors.append("drag rival %d changed lane while racing (%.2f -> %.2f)" % [k, float(lats[k + 1]), float(r.lat)])
	_idle_run(sr, 26.0)
	if sr.finished_count() != 3:
		errors.append("drag: %d of 3 rivals finished" % sr.finished_count())

## A player that follows the route at `speed` from the start; returns the knockout run's rivals and the player
## state after the player is home, out, or the time runs out.
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
	var empty := StreetRivals.new(PackedVector2Array(), "stock", 2, 1)
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

## On a road profile: the rivals' line is moved onto the road's centre and kept inside its half width; the pose
## turns smoothly (no jump at a vertex); a finished rival rolls on past the line instead of stopping on it.
## A drag field calibrated to the car's own standing start: the quickest rival within the band of drag_time.
func _drag_calibration(errors: Array[String]) -> void:
	for diff in ["easy", "hard"]:
		var want := LiveEvents.drag_time("stock", 402.0)
		var sr := StreetRivals.new(_line(402.0), "stock", 3, 5, {"grid": "drag", "drag_time": want, "difficulty": diff})
		_idle_run(sr, 60.0)
		var best := sr.best_time()
		var band: Vector2 = StreetRivals.DRAG_BANDS[diff]
		if best < want * band.y * 0.98 or best > want * band.y * 1.03:
			errors.append("%s drag: quickest rival %.2f s against the car's %.2f s (band %.3f)" % [diff, best, want, band.y])

## A crawling player on a lane too narrow to pass does not hold the whole field up.
## Harder difficulty, quicker rivals.
## A drag grid on a narrow street keeps every car's body on the tarmac (2026-11-21 QA: the outer pair of four, 2 m
## apart, hung over the kerbs of a 6.2 m street): three abreast there, four on a 7.4 m road, no closer than CAR_W.
func _drag_kerbs(errors: Array[String]) -> void:
	var path := LiveEvents.resample(_line(402.0), StreetRivals.STEP)
	for hw: float in [3.1, 3.4, 3.75, 5.0]:
		var half := PackedFloat32Array()
		half.resize(path.size())
		half.fill(hw)
		var n := mini(3, StreetRivals.drag_rivals_fit(hw))
		var sr := StreetRivals.new(path, "stock", n, 5, {"grid": "drag", "profile": {"half": half}})
		var lats: Array = [sr.player_grid().y]
		for r in sr.rivals:
			lats.append(float(r.lat))
		lats.sort()
		for k in lats.size():
			if absf(float(lats[k])) > hw - StreetRivals.EDGE + 0.01:
				errors.append("drag on a %.2f m half street: a car %.2f m off centre hangs over the kerb" % [hw, float(lats[k])])
			if k > 0 and float(lats[k]) - float(lats[k - 1]) < StreetRivals.CAR_W - 0.01:
				errors.append("drag on a %.2f m half street: cars %.2f m apart" % [hw, float(lats[k]) - float(lats[k - 1])])
		if hw >= 3.7 and n != 3 or hw < 3.6 and n != 2:
			errors.append("drag on a %.2f m half street: %d rivals" % [hw, n])
