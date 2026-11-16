## Audit probe (headless): every campaign mission and every live-event kind driven start -> finish by a scripted
## driver in the real FreeCar on the real Brzeszcze map, plus the start placement, the grid, the checkpoints and the
## rivals. Prints one block per event with every anomaly it found ("!!" lines).
##   timeout 600 godot --headless --path godot -s tests/_live_audit.gd     (ONLY=drag_quarter,sprint,... to pick)
extends SceneTree

const DT := 1.0 / 120.0
const MAX_T := 900.0

var map: TownMap
var anomalies := 0

func _initialize() -> void:
	map = TownMap.load_map(OpenWorld.MAP_KEY)
	var only := OS.get_environment("ONLY")
	var want := func(k: String) -> bool: return only == "" or k in only.split(",")
	for k in Missions.MISSIONS.size():
		var m: Dictionary = Missions.MISSIONS[k]
		if want.call(String(m.id)):
			_audit(MapMissions.event(Missions.BASE + k), String(m.id))
	var s: Array = map.spots.get("festival", [0.0, 0.0, 0.0])
	var home := Vector2(s[0], s[1])
	for kind in LiveEvents.KINDS:
		if not want.call(kind):
			continue
		for seed_value in ([11, 22, 33, 44] if kind == "drift_zone" else [11, 22]):
			var live := LiveEvents.new(map, seed_value)
			var ev := live.generate(home, PackedVector2Array(), kind)
			if ev.is_empty():
				print("!! %s seed %d: none generated" % [kind, seed_value])
				anomalies += 1
				continue
			_audit(ev, "%s/%d" % [kind, seed_value])
	print("\n%d anomalies" % anomalies)
	quit()

func _bad(what: String) -> void:
	print("   !! " + what)
	anomalies += 1

func _audit(ev: Dictionary, label: String) -> void:
	if ev.is_empty():
		print("\n== %s: NO EVENT" % label)
		anomalies += 1
		return
	print("\n== %s  kind %s  %.0f m  %d cps" % [label, ev.kind, float(ev.length), (ev.cps as PackedVector2Array).size()])
	var live := LiveEvents.new(map, 5)
	live.board.append(ev)
	live.begin(ev, "stock")
	var tiers: Array = live.run.tiers
	print("   tiers %s  ref %.1f s" % [str(tiers), LiveEvents.pace_time(ev.path, "stock")])
	# start placement
	var g := live.grid_pose(ev)
	var gp: Vector2 = g[0]
	var road := map.road_at(gp.x, gp.y, -INF, 0.0)
	if road.is_empty():
		_bad("player grid spot %s is off the road (nearest %.1f m)" % [gp, _road_dist(gp)])
	var near := map.nearest_road(gp, 20.0)
	if not near.is_empty():
		var d: Vector2 = near.dir
		if absf(d.dot(Vector2.from_angle(float(g[1])))) < 0.8:
			_bad("player faces %.0f deg off the road's direction" % rad_to_deg(acos(absf(d.dot(Vector2.from_angle(float(g[1])))))))
	var rv := live.rivals()
	if rv:
		for k in rv.rivals.size():
			var ps: Array = rv.pose(float(rv.rivals[k].s), float(rv.rivals[k].lat))
			if map.road_at(ps[0].x, ps[0].y, -INF, 0.3).is_empty():
				_bad("rival %d grid spot off the road (%.1f m)" % [k, _road_dist(ps[0])])
			if (ps[0] as Vector2).distance_to(gp) < 1.95:
				_bad("rival %d starts %.1f m from the player" % [k, (ps[0] as Vector2).distance_to(gp)])
	# checkpoints
	var cps: PackedVector2Array = ev.cps
	for i in cps.size():
		var dd := _road_dist(cps[i])
		if dd > 4.0:
			_bad("checkpoint %d is %.1f m off the road" % [i, dd])
	if ev.kind == "rally":
		for st in ev.stages:
			for c in st.cps:
				if _road_dist(c) > 4.0:
					_bad("rally %s checkpoint %.1f m off the road" % [st.name, _road_dist(c)])
	# drive it
	_drive(live, ev, gp, float(g[1]))

func _road_dist(p: Vector2) -> float:
	var h := map.nearest_road(p, 60.0)
	return INF if h.is_empty() else (h.pos as Vector2).distance_to(p)

## A scripted driver: pure pursuit on the event's path (the current stage's for a rally), speed from the path's
## curvature at 80 % of the car's grip, liaisons driven along a map route.
func _drive(live: LiveEvents, ev: Dictionary, p0: Vector2, h0: float) -> void:
	var car := FreeCar.new(map)
	car.place(p0, h0)
	var path: PackedVector2Array = ev.path if ev.kind != "rally" else ev.stages[0].path
	var pts := LiveEvents.resample(path, 2.0)
	var env := _env(pts)
	var s := 0.0
	var t := 0.0
	var events := {}
	var stuck := 0.0
	var hb_t := 0.0
	var dstat := {"t": 0.0, "slide": 0.0, "off": 0.0, "crash": 0, "slip": 0.0}
	var style := OS.get_environment("STYLE") if OS.get_environment("STYLE") != "" else "flick"
	var resets := 0
	var max_dev := 0.0
	var prev_rv := {}
	var teleports := 0
	var rival_off := 0
	var rival_samples := 0
	var overlap := 0
	var result := ""
	var stage := 0
	while t < MAX_T:
		t += DT
		if ev.kind == "rally" and live.is_running() and int(live.run.stage) != stage:
			stage = int(live.run.stage)
			path = ev.stages[stage].path
			pts = LiveEvents.resample(path, 2.0)
			env = _env(pts)
			s = 0.0
		var cp := Vector2(car.car.x, car.car.y)
		var follow := pts
		var fenv := env
		if live.is_running() and live.run.state == "liaison":
			# drive to the next stage start by road (rebuilt once), stop on it
			if not live.run.has("_liaison"):
				live.run["_liaison"] = LiveEvents.resample(map.route(cp, live.next_target()), 2.0)
				s = 0.0
			follow = live.run["_liaison"]
			if not live.run.has("_lenv"):
				live.run["_lenv"] = _env(follow)
			fenv = live.run["_lenv"]
		s = _project(follow, cp, s)
		var i := clampi(int(s / 2.0), 0, follow.size() - 1)
		max_dev = maxf(max_dev, follow[i].distance_to(cp)) if not (live.is_running() and live.run.state == "liaison") else max_dev
		var look := clampi(i + 2 + int(absf(car.car.speed) * 0.18), 0, follow.size() - 1)
		var aim := follow[look]
		var want := (aim - cp).angle()
		var err := wrapf(want - car.car.heading, -PI, PI)
		var v := absf(car.car.speed)
		var target := fenv[clampi(i + 2, 0, fenv.size() - 1)]
		if i >= follow.size() - 3:
			target = 0.0 if (live.is_running() and live.run.state == "liaison") else 30.0
		var thr := 1.0 if v < target else 0.0
		var brk := clampf((v - target) * 0.3, 0.0, 1.0) if v > target + 1.0 else 0.0
		var hb := 0.0
		var steer_cmd := clampf(err * 2.5, -1.0, 1.0)
		if ev.kind == "drift_zone" and style != "none" and live.is_running() and live.run.state == "running":
			# a sliding driver: into each bend a little quicker than grip allows, a handbrake flick to rotate the car,
			# throttle on to hold the slide, steering at the direction of travel (the counter-steer comes by itself)
			var kk := 0.0
			for ahead in [5, 10, 15]:
				var a2 := follow[clampi(i + ahead - 3, 0, follow.size() - 1)]
				var b2 := follow[clampi(i + ahead, 0, follow.size() - 1)]
				var c2 := follow[clampi(i + ahead + 3, 0, follow.size() - 1)]
				kk = maxf(kk, absf(wrapf((c2 - b2).angle() - (b2 - a2).angle(), -PI, PI)) / 12.0)
			# the Seicento is front-wheel drive: the path-following driver as everywhere else, into the bends a little over
			# the grip, with a short handbrake tap to kick the tail out whenever the slide has died down
			var push := {"tidy": 1.05, "flick": 1.15, "hard": 1.25}.get(style, 1.15) as float
			var want_slip := {"tidy": 0.3, "flick": 0.45, "hard": 0.6}.get(style, 0.45) as float
			var tap := {"tidy": 0.08, "flick": 0.12, "hard": 0.18}.get(style, 0.12) as float
			target = fenv[clampi(i + 2, 0, fenv.size() - 1)] * push
			thr = 1.0 if v < target else 0.0
			brk = clampf((v - target) * 0.3, 0.0, 1.0) if v > target + 1.5 else 0.0
			var vel := Vector2(car.car.vx, car.car.vy)
			var slip_now := absf(wrapf(vel.angle() - car.car.heading, -PI, PI)) if vel.length() > 3.0 else 0.0
			if kk > 0.012 and v > 9.0 and slip_now < want_slip * 0.7 and hb_t < -0.4:
				hb_t = tap
			hb = 1.0 if hb_t > 0.0 else 0.0
			hb_t -= DT
			if slip_now > 0.15 and vel.length() > 5.0:
				# sliding: steer the travel along the route and catch the tail (counter-steer towards the travel), power on
				steer_cmd = clampf(wrapf(want - vel.angle(), -PI, PI) * 1.6 + wrapf(vel.angle() - car.car.heading, -PI, PI) * 1.1, -1.0, 1.0)
				thr = 1.0 if v < target * 1.1 else 0.5
				brk = 0.0
		if live.holding():
			thr = 0.0
			brk = 0.0
		car.step(DT, thr, brk, steer_cmd, false, false, 1.0 if live.holding() else hb)
		var crash := false
		for hh in car.hits:
			if float(hh[2]) > 6.0:
				crash = true
		car.hits.clear()
		cp = Vector2(car.car.x, car.car.y)
		var speed := Vector2(car.car.vx, car.car.vy).length()
		var slip := absf(wrapf(atan2(car.car.vy, car.car.vx) - car.car.heading, -PI, PI)) if speed > 1.0 else 0.0
		var off := LiveEvents.off_road(map, cp, car.z)
		if ev.kind == "drift_zone" and live.is_running() and live.run.state == "running":
			dstat.t += DT
			if speed > DriftScore.SPEED_MIN and slip > DriftScore.ANGLE_MIN and slip < DriftScore.ANGLE_MAX:
				dstat.slide += DT
			if off:
				dstat.off += DT
				if OS.get_environment("OFFDBG") != "" and int(dstat.off * 2.0) != int((dstat.off - DT) * 2.0):
					var any := map.road_at(cp.x, cp.y, -INF, LiveEvents.VERGE)
					var nr := map.nearest_road(cp, 30.0)
					print("      off at %s z %.2f ground %.2f any-height road %s (h %s) nearest %s at %.1f m half %s" % [cp, car.z, map.ground(cp.x, cp.y),
						any.get("road", -1), any.get("height", "-"), nr.get("road", -1), (nr.get("pos", cp) as Vector2).distance_to(cp), map.road_w[int(nr.get("road", 0))] * 0.5])
			if crash:
				dstat.crash += 1
			dstat.slip = maxf(float(dstat.slip), slip)
		var r := live.tick(DT, cp, speed, slip, off, crash, car.z)
		if r != "":
			events[r] = int(events.get(r, 0)) + 1
			if r == "stage":
				var sp := live.stage_pose(int(live.run.stage))
				car.place(sp[0], float(sp[1]))
				live.run.erase("_liaison")
				s = 0.0
				live.run.erase("_lenv")
			if r == "warn":
				print("      warn %s at t %.0f cp %d" % [live.run.notice, t, int(live.run.cp)])
		if live.is_running() and live.run.state == "running" and speed < 1.0:
			stuck += DT
			if stuck > 6.0:
				# Forza's reset: back to the last checkpoint gate (5 at most before it counts as a dead end)
				resets += 1
				if resets > 5:
					_bad("bot stuck at %s (t %.0f s, checkpoint %d) after 5 resets" % [cp, t, int(live.run.cp)])
					result = "stuck"
					break
				var pose := live.reset_to_checkpoint()
				if pose.is_empty():
					_bad("no reset pose at %s" % cp)
					result = "stuck"
					break
				car.place(pose[0], float(pose[1]))
				s = float(live.run.s) if ev.kind != "rally" else float(live.run.s)
				stuck = 0.0
		else:
			stuck = 0.0
		var rv := live.rivals()
		if rv and live.run.state == "running":
			for k in rv.rivals.size():
				var rr: Dictionary = rv.rivals[k]
				if bool(rr.out):
					continue
				var ps: Array = rv.pose(float(rr.s), float(rr.lat))
				var q: Vector2 = ps[0]
				if prev_rv.has(k) and q.distance_to(prev_rv[k]) > float(rr.v) * DT * 3.0 + 0.5:
					teleports += 1
				prev_rv[k] = q
				if int(t * 2.0) != int((t - DT) * 2.0):
					rival_samples += 1
					if map.road_at(q.x, q.y, -INF, 0.5).is_empty():
						rival_off += 1
					for o in range(k + 1, rv.rivals.size()):
						var ro: Dictionary = rv.rivals[o]
						if bool(ro.out):
							continue
						if (rv.pose(float(ro.s), float(ro.lat))[0] as Vector2).distance_to(q) < 2.2:
							overlap += 1
		if OS.get_environment("TRACE") != "" and int(t * 0.2) != int((t - DT) * 0.2):
			print("      t %.0f p %s s %.0f/%.0f v %.1f dev %.1f state %s cp %d off %s surf %d" % [t, cp, s, follow.size() * 2.0, speed,
				follow[i].distance_to(cp), live.run.get("state", "-"), int(live.run.get("cp", -1)), off, car.surface])
		if r in ["done", "fail"]:
			result = r
			break
	var res := live.last_result
	print("   resets %d" % resets)
	if ev.kind == "drift_zone":
		print("   drift: %.0f s in the zone, sliding %.1f s, off the road %.1f s, %d crashes, max slip %.2f rad, lost %s" % [dstat.t,
			dstat.slide, dstat.off, dstat.crash, dstat.slip, str(live.last_result.get("lost", "-"))])
	print("   bot: %s after %.1f s  events %s  max off-path %.1f m  line '%s' tier %d pos %s" % [result, t, str(events),
		max_dev, String(res.get("line", "")), int(res.get("tier", 0)), str(res.get("pos", "-"))])
	if result == "":
		_bad("never finished in %.0f s" % MAX_T)
	if result == "fail":
		_bad("bot failed: %s" % res.get("line", ""))
	if teleports > 0:
		_bad("%d rival teleports" % teleports)
	if rival_samples > 0:
		print("   rivals: %.0f%% of samples off the road, %d overlaps" % [100.0 * rival_off / rival_samples, overlap])
		if rival_off * 10 > rival_samples:
			_bad("rivals off the road %.0f%% of the time" % (100.0 * rival_off / rival_samples))
	if ev.kind == "race" and res.has("pos"):
		var rv2: StreetRivals = live.run.get("rivals") if live.is_running() else null
	if ev.has("mission") and not res.is_empty():
		print("   outcome %s" % str(MapMissions.outcome(res)))

## Target speed at each point, planned like LiveEvents.pace_time: corners at 70 % of the car's grip on that point's
## surface (the map's road under it), braked into at 70 % of its braking, the tightest of the next few metres.
func _env(pts: PackedVector2Array) -> PackedFloat32Array:
	var n := pts.size()
	var prof := LiveEvents.route_profile(map, pts, 2.0)
	var gr: PackedFloat32Array = prof.grip
	var env := PackedFloat32Array()
	env.resize(n)
	for i in n:
		var a := pts[maxi(i - 3, 0)]
		var b := pts[i]
		var c := pts[mini(i + 3, n - 1)]
		var turn := absf(wrapf((c - b).angle() - (b - a).angle(), -PI, PI))
		var k := turn / maxf(a.distance_to(b) + b.distance_to(c), 1.0)
		var g := gr[mini(i, gr.size() - 1)] if gr.size() > 0 else 1.0
		env[i] = minf(40.0, sqrt(8.4 * 0.7 * g / maxf(k, 1e-5)))
	for i in range(n - 2, -1, -1):
		var g := gr[mini(i, gr.size() - 1)] if gr.size() > 0 else 1.0
		env[i] = minf(env[i], sqrt(env[i + 1] * env[i + 1] + 2.0 * 7.4 * 0.7 * g * 2.0))
	return env

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
