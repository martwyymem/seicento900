## Headless probe: measures every catalogue car in FreeCar on the real Brzeszcze map:
##   1. S1 quarter mile (402 m) and 1 km (1000 m) standing-start drags (drag_quarter / drag_kilometre lines)
##      both dry (mu = 1.0) and wet (MapMissions.weather_state("wet").mu)
##   2. A live town sprint route driven by the scripted driver (from _live_audit.gd, using each car's PACE envelope)
##      compared against LiveEvents.pace_time() and the Seicento anchor.
##   timeout 300 godot --headless --path godot -s tests/_pace_probe.gd
extends SceneTree

const DT := 1.0 / 120.0
const BEHIND_M := 10.0

var map: TownMap

func _initialize() -> void:
	map = TownMap.load_map(OpenWorld.MAP_KEY)
	var cars := ["stock", "golf4", "logan", "v50", "hypercar"]
	var wet_mu := float(MapMissions.weather_state("wet").mu)

	var dq := MapMissions.event(Missions.index_of("drag_quarter"))
	var dk := MapMissions.event(Missions.index_of("drag_kilometre"))
	var s: Array = map.spots.get("festival", [0.0, 0.0, 0.0])
	var home := Vector2(s[0], s[1])
	var live := LiveEvents.new(map, 11)
	var sprint := live.generate(home, PackedVector2Array(), "sprint")
	var sprint_grip := live.grip_of(sprint) if not sprint.is_empty() else 1.0

	print("=== S1 DRAG MEASUREMENTS (FreeCar auto, dk len=%.1f m, dq len=%.1f m, dry mu=1.00, wet mu=%.3f) ===" % [float(dk.length), float(dq.length), wet_mu])
	print("car       | cur 402  cur 1k  | meas 402 meas 1k | wet 402 (model)  wet 1k (model)  | pace 402  pace 1k")
	print("----------+------------------+------------------+----------------------------------+------------------")
	var straight402 := PackedVector2Array([Vector2.ZERO, Vector2(402.0, 0.0)])
	var straight1k := PackedVector2Array([Vector2.ZERO, Vector2(1000.0, 0.0)])
	for key in cars:
		var m402 := _drag_run(dk.path, key, 402.0, 1.0)
		var m1k := _drag_run(dk.path, key, 1000.0, 1.0)
		var w402 := _drag_run(dk.path, key, 402.0, wet_mu)
		var w1k := _drag_run(dk.path, key, 1000.0, wet_mu)
		var cur: Array = LiveEvents.DRAG_TIMES[key]
		var p402 := LiveEvents.pace_time(straight402, key)
		var p1k := LiveEvents.pace_time(straight1k, key)
		var mw402 := LiveEvents.drag_time(key, 402.0, wet_mu)
		var mw1k := LiveEvents.drag_time(key, 1000.0, wet_mu)
		print("%-9s | %6.2f s %6.2f s | %6.2f s %6.2f s | %6.2f s (%5.2f)  %6.2f s (%5.2f) | %6.2f s  %6.2f s" % [
			key, cur[0], cur[1], m402, m1k, w402, mw402, w1k, mw1k, p402, p1k])

	var s1s := MapMissions.event(Missions.index_of("sprint_s1"))
	for pair in [[sprint, "TOWN SPRINT"], [s1s, "S1 SPRINT"]]:
		var ev: Dictionary = pair[0]
		var label: String = pair[1]
		if ev.is_empty():
			continue
		var sg := live.grip_of(ev)
		print("\n=== %s (%s, %.0f m, grip %.3f) ===" % [label, ev.get("title", "-"), float(ev.get("length", 0.0)), sg])
		print("car       | PACE [vmax, acc, lat, brk]        | pace_time | bot dry  | ratio (bot/pace) | pace wet | bot wet  | wet/dry bot")
		print("----------+-----------------------------------+-----------+----------+------------------+----------+----------+------------")
		for key in cars:
			var pc: Array = LiveEvents.PACE[key]
			var pt_dry := LiveEvents.pace_time(ev.path, key, 0.0, sg)
			var pt_wet := LiveEvents.pace_time(ev.path, key, 0.0, sg * wet_mu)
			var bt_dry := _sprint_run(ev, key, 1.0)
			var bt_wet := _sprint_run(ev, key, wet_mu)
			print("%-9s | [%5.1f, %4.1f, %4.1f, %4.1f]         | %7.2f s | %6.2f s | %16.3f | %6.2f s | %6.2f s | %11.3f" % [
				key, pc[0], pc[1], pc[2], pc[3], pt_dry, bt_dry, bt_dry / maxf(pt_dry, 0.01), pt_wet, bt_wet, bt_wet / maxf(bt_dry, 0.01)])

	quit()

func _drag_run(path: PackedVector2Array, car_key: String, dist: float, mu: float) -> float:
	var car := FreeCar.new(map, CarCatalog.model(car_key))
	car.mu = mu
	var pts := LiveEvents.resample(path, 2.0)
	var total := LiveEvents.path_length(pts)
	var goal := minf(dist, total - 1.0)
	var h0 := (pts[mini(3, pts.size() - 1)] - pts[0]).angle()
	car.place(pts[0], h0)
	var s := 0.0
	var t := 0.0
	while t < 90.0:
		t += DT
		var cp := Vector2(car.car.x, car.car.y)
		s = _project(pts, cp, s)
		if s >= goal:
			var v := maxf(absf(car.car.speed), 1.0)
			return t + (dist - s) / v
		var i := clampi(int(s / 2.0), 0, pts.size() - 1)
		var look := clampi(i + 4 + int(absf(car.car.speed) * 0.25), 0, pts.size() - 1)
		var want := (pts[look] - cp).angle()
		var err := wrapf(want - car.car.heading, -PI, PI)
		car.step(DT, 1.0, 0.0, clampf(err * 2.0, -1.0, 1.0), false, false, 0.0)
	return INF

func _sprint_run(ev: Dictionary, car_key: String, mu: float) -> float:
	var car := FreeCar.new(map, CarCatalog.model(car_key))
	car.mu = mu
	var pts := LiveEvents.resample(ev.path, 2.0)
	var pc: Array = LiveEvents.PACE[car_key]
	var env := _env(pts, pc, mu)
	var h0 := (pts[mini(3, pts.size() - 1)] - pts[0]).angle()
	car.place(pts[0], h0)
	var s := 0.0
	var t := 0.0
	var total := float(pts.size() - 1) * 2.0
	while t < 600.0:
		t += DT
		var cp := Vector2(car.car.x, car.car.y)
		s = _project(pts, cp, s)
		if s >= total - 12.0:
			return t
		var i := clampi(int(s / 2.0), 0, pts.size() - 1)
		var v := absf(car.car.speed)
		var look := clampi(i + 2 + int(v * 0.18), 0, pts.size() - 1)
		var want := (pts[look] - cp).angle()
		var err := wrapf(want - car.car.heading, -PI, PI)
		var target := _ahead_min(env, i, v)
		var thr := 1.0 if v < target else 0.0
		var brk := clampf((v - target) * 0.3, 0.0, 1.0) if v > target + 1.0 else 0.0
		car.step(DT, thr, brk, clampf(err * 2.5, -1.0, 1.0), false, false, 0.0)
	return INF

func _env(pts: PackedVector2Array, pc: Array, mu: float) -> PackedFloat32Array:
	var n := pts.size()
	var prof := LiveEvents.route_profile(map, pts, 2.0)
	var gr: PackedFloat32Array = prof.grip
	var env := PackedFloat32Array()
	env.resize(n)
	var vmax: float = pc[0]
	var lat: float = pc[2]
	var brk: float = pc[3]
	for i in n:
		var a := pts[maxi(i - 3, 0)]
		var b := pts[i]
		var c := pts[mini(i + 3, n - 1)]
		var turn := absf(wrapf((c - b).angle() - (b - a).angle(), -PI, PI))
		var k := turn / maxf(a.distance_to(b) + b.distance_to(c), 1.0)
		var g := (gr[mini(i, gr.size() - 1)] if gr.size() > 0 else 1.0) * mu
		env[i] = minf(vmax, sqrt(lat * 0.7 * g / maxf(k, 1e-5)))
	for i in range(n - 2, -1, -1):
		var g := (gr[mini(i, gr.size() - 1)] if gr.size() > 0 else 1.0) * mu
		env[i] = minf(env[i], sqrt(env[i + 1] * env[i + 1] + 2.0 * brk * 0.7 * g * 2.0))
	return env

func _ahead_min(env: PackedFloat32Array, i: int, v: float) -> float:
	var n := env.size()
	var to := mini(i + 3 + int((v * 0.6 + 6.0) / 2.0), n - 1)
	var m := INF
	for j in range(clampi(i - int(BEHIND_M / 2.0), 0, n - 1), to + 1):
		m = minf(m, env[j])
	return m if is_finite(m) else 0.0

func _project(pts: PackedVector2Array, p: Vector2, near_s: float) -> float:
	var lo := clampi(int((near_s - 20.0) / 2.0), 0, pts.size() - 1)
	var hi := clampi(int((near_s + 60.0) / 2.0), 0, pts.size() - 1)
	var best := INF
	var bs := near_s
	for i in range(lo, hi):
		var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
		var d := q.distance_squared_to(p)
		if d < best:
			best = d
			bs = i * 2.0 + pts[i].distance_to(q)
	return bs
