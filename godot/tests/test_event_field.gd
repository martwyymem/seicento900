## EventField and EventTrack (scripts/world/event_field.gd, event_track.gd): an open-world race run on the race sim.
## On the real map, a live off-road race's field finishes with every bot home and on the road, the track built in
## time; on synthetic roads (no map), the player's car and a bot touch as boxes and the contact pushes them apart and
## reaches the player's car, the bots' pace does not depend on where the player is (no rubber band), and the racing
## line's chevrons and BRAKE call come up along the event's track.
extends RefCounted

var completed := false
const DT := 1.0 / 30.0

func run() -> Array:
	var errors: Array[String] = []
	_on_the_map(errors)
	_contact(errors)
	_no_rubber_band(errors)
	_arrows(errors)
	completed = true
	return errors

static func _line(len: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2.ZERO, Vector2(len, 0.0)])

## A live off-road race round the festival: built quickly, every bot home in reasonable time, on the drawn roads.
func _on_the_map(errors: Array[String]) -> void:
	var map := TownMap.load_map(OpenWorld.MAP_KEY)
	if map == null:
		errors.append("the open-world map did not load")
		return
	var s: Array = map.spots.get("festival", [0.0, 0.0, 0.0])
	var live := LiveEvents.new(map, 11)
	var ev := live.generate(Vector2(s[0], s[1]), PackedVector2Array(), "offroad")
	if ev.is_empty():
		errors.append("no live off-road race generated")
		return
	live.begin(ev, "stock")
	var ef := live.rivals() as EventField
	if ef == null:
		errors.append("a live off-road race has no EventField (%s)" % [live.rivals()])
		return
	if ef.et.build_ms > 400.0:
		errors.append("the event's track took %.0f ms to build" % ef.et.build_ms)
	var ref := LiveEvents.pace_time(ev.path, "stock", 0.0, live.grip_of(ev))
	var far: Vector2 = (ev.path as PackedVector2Array)[0] + Vector2(600.0, 600.0)
	var t := 0.0
	var off := 0
	var samples := 0
	while t < ref * 2.5 and ef.finished_count() < ef.count():
		t += DT
		ef.step(DT, far, 0.0)
		if int(t * 2.0) != int((t - DT) * 2.0):
			for k in ef.count():
				if bool(ef.rivals[k].done):
					continue
				var q: Vector2 = ef.car_pose(k)[0]
				samples += 1
				if map.road_at(q.x, q.y, -INF, 1.0).is_empty():
					off += 1
	if ef.finished_count() < ef.count():
		errors.append("live off-road race: %d of %d bots home after %.0f s (reference %.0f s)" % [ef.finished_count(), ef.count(), t, ref])
	var best := ef.best_time()
	if best > 0.0 and (best < ref * 0.95 or best > ref * 1.4):
		errors.append("live off-road race: the quickest bot home in %.1f s against the reference's %.1f s" % [best, ref])
	if samples > 0 and off * 20 > samples:
		errors.append("live off-road race: bots more than 1 m off the road %.0f%% of the time" % (100.0 * off / samples))
	live.abandon()

## The player's car (a plain RaceCar, as FreeCar's) put overlapping a bot on the grid: the race's box contact pushes
## them apart, counts it and hands the knock to the player's car.
func _contact(errors: Array[String]) -> void:
	var ef := EventField.new(_line(1500.0), "stock", 3, 21)
	var b := ef.bots[0]
	var car := RaceCar.new()
	car.is_player = true
	car.x = b.x + cos(b.heading) * 3.0 # nose into the bot's tail...
	car.y = b.y + sin(b.heading) * 3.0 + 0.4
	car.heading = b.heading
	car.vx = 0.0
	car.vy = 0.0
	var before := Vector2(car.x, car.y)
	var t := 0.0
	var touched := false
	while t < 6.0:
		t += DT
		ef.step(DT, Vector2(car.x, car.y), 0.0, car)
		if ef.contacts > 0:
			touched = true
	if not touched:
		errors.append("a bot driving into the player's car made no contact")
	if ef.player_hits.is_empty():
		errors.append("the contact never reached the player's car (player_hits)")
	if Vector2(car.x, car.y).distance_to(before) < 0.05 and Vector2(car.vx, car.vy).length() < 0.05:
		errors.append("the contact did not move the player's car")
	# and afterwards the two boxes are apart again
	var hit := ef.race.sat(ef.me, b)
	if not hit.is_empty() and hit[2] > 0.3:
		errors.append("the player's car and the bot still overlap %.2f m after the contact" % hit[2])
	ef.dispose()

## Two fields from one seed, the player far ahead in one and far behind in the other (both off the road, out of the
## way): every bot is in the same place after 40 s.
func _no_rubber_band(errors: Array[String]) -> void:
	var path := _line(3000.0)
	var a := EventField.new(path, "stock", 4, 33)
	var b := EventField.new(path, "stock", 4, 33)
	var t := 0.0
	while t < 40.0:
		t += DT
		a.step(DT, Vector2(2900.0, 80.0), 30.0)
		b.step(DT, Vector2(5.0, -80.0), 0.0)
	var worst := 0.0
	for k in a.count():
		worst = maxf(worst, absf(float(a.rivals[k].s) - float(b.rivals[k].s)))
	if worst > 0.01:
		errors.append("the bots' pace depends on where the player is: %.2f m apart after 40 s" % worst)
	if float(a.rivals[0].s) < 300.0:
		errors.append("the bots have barely moved in 40 s (%.0f m)" % float(a.rivals[0].s))
	a.dispose()
	b.dispose()

## The racing line's chevrons ahead of the player along an event's track, red into a right-angle bend at speed, and
## the BRAKE call there; none with the line switched off.
func _arrows(errors: Array[String]) -> void:
	var path := PackedVector2Array([Vector2.ZERO, Vector2(600.0, 0.0), Vector2(600.0, 400.0)])
	var ef := EventField.new(path, "stock", 1, 5)
	var ra := RacingArrows.new()
	ra.set_track(ef.track, ef.et.start_s, ef.et.finish_s, ef.race.brake_k, ef.race.brake_aero, ef.race._loose)
	var s := ef.et.start_s + 100.0
	ra.update(s, 20.0, 1.0)
	if ra.shown() < 10:
		errors.append("the racing line shows %d chevrons on a straight" % ra.shown())
	var bend_s := ef.et.start_s + 600.0 - 70.0
	if not ra.brake_cue(bend_s, 35.0, 1.0):
		errors.append("no BRAKE call 70 m before a right-angle bend at 126 km/h")
	if ra.brake_cue(ef.et.start_s + 100.0, 15.0, 1.0):
		errors.append("a BRAKE call on the straight at 54 km/h, 500 m from the bend")
	ra.mode = "off"
	ra.update(s, 20.0, 1.0)
	if ra.shown() != 0:
		errors.append("the racing line switched off still shows %d chevrons" % ra.shown())
	ra.free()
	ef.dispose()
