## Open-world traffic driving (scripts/world/traffic.gd): cars follow without touching, slow for bends and smoothly
## (no heading snaps), signal their turns, give way at junctions, go round a parked car, and give up on a jam that
## never moves.
extends RefCounted

var completed := false
var map: TownMap
var player: FreeCar
const DT := 1.0 / 60.0

func run() -> Array:
	var errors: Array[String] = []
	map = TownMap.load_map(OpenWorld.MAP_KEY)
	if map == null:
		errors.append("no open-world map")
		completed = true
		return errors
	player = FreeCar.new(map)
	player.place(Vector2(100000.0, 100000.0), 0.0)
	_follow(errors)
	_smooth_and_signal(errors)
	_give_way(errors)
	_go_round(errors)
	_crossing(errors)
	_signals(errors)
	completed = true
	return errors

## A traffic car on edge e, s metres along it, at speed v (no mesh).
func _car(tr: Traffic, from: String, e: Array, s: float, v: float, kind := "CarHatch") -> Dictionary:
	var pts := tr._edge_points(e)
	var c := {"node": Node3D.new(), "from": from, "edge": e, "pts": pts, "len": Traffic._poly_len(pts), "s": s,
		"i0": int(e[2]), "istep": 1 if int(e[3]) >= int(e[2]) else -1, "v": v, "want": 0.0, "pos": Vector2.ZERO,
		"dir": Vector2.RIGHT, "heading": 0.0, "knock": 0.0, "push": Vector2.ZERO, "spin": 0.0, "near": false,
		"kind": kind, "y": 0.0}
	c.drv = tr._driver(kind)
	c.want = tr._want_on(c, int(e[1]))
	tr._bind_parts(c)
	tr._choose_next(c)
	tr._place(c)
	tr.cars.append(c)
	return c

## Long, nearly straight, two-way edges of ordinary streets: [from node, edge].
func _straights(min_len: float) -> Array:
	var out := []
	for nid in map.node_edges:
		for e in map.node_edges[nid]:
			if not e[5] or float(e[4]) < min_len or map.road_oneway[e[1]] or map.road_rank[e[1]] < 3 or not map.road_z[e[1]].is_empty():
				continue
			var pts := map.road_pts[e[1]]
			var a: Vector2 = pts[e[2]]
			var b: Vector2 = pts[e[3]]
			if a.distance_to(b) > float(e[4]) * 0.97:
				out.append([nid, e])
	return out

func _free(tr: Traffic) -> void:
	for c in tr.cars:
		(c.node as Node3D).free()
	tr.cars.clear()

## A car comes up behind a slower one and settles behind it: never closer than a car's length, no hard braking.
func _follow(errors: Array[String]) -> void:
	var st := _straights(220.0)
	if st.is_empty():
		errors.append("no straight edge for the follow test")
		return
	var tr := Traffic.new(map, Node3D.new(), null)
	var pick: Array = st[0]
	var lead := _car(tr, pick[0], pick[1], 70.0, 4.0)
	lead.want = 4.0
	var back := _car(tr, pick[0], pick[1], 5.0, 12.0)
	var min_gap := INF
	var settled := false
	for i in int(14.0 / DT):
		for c in tr.cars:
			tr._drive(c, DT, player)
		if not is_same(back.edge, lead.edge):
			break
		var gap := float(lead.s) - float(back.s)
		min_gap = minf(min_gap, gap)
		if absf(float(back.v) - float(lead.v)) < 0.6 and gap < 25.0:
			settled = true
	if min_gap < Traffic.CAR_LEN + 1.0:
		errors.append("follower closed to %.1f m centre to centre" % min_gap)
	if not settled:
		errors.append("follower never settled behind the slower car (gap %.1f m)" % (float(lead.s) - float(back.s)))
	_free(tr)

## Cars driven round the town for a while: the drawn heading turns smoothly, the brake lamps come on when they slow,
## and a car approaching a turn signals the right way.
func _smooth_and_signal(errors: Array[String]) -> void:
	var tr := Traffic.new(map, Node3D.new(), null)
	var st := _straights(60.0)
	for k in mini(12, st.size()):
		var pick: Array = st[k * maxi(1, st.size() / 12)]
		_car(tr, pick[0], pick[1], 2.0, 8.0)
	var max_rate := 0.0
	var signalled := 0
	var wrong := 0
	var braked := 0
	var prev := {}
	for i in int(60.0 / DT):
		for c in tr.cars:
			tr._drive(c, DT, player)
			var id := (c.node as Node3D).get_instance_id()
			if prev.has(id):
				max_rate = maxf(max_rate, absf(wrapf(float(c.heading) - float(prev[id]), -PI, PI)) / DT)
			prev[id] = c.heading
			var turn: float = c.get("turn", 0.0)
			if float(c.len) - float(c.s) < 20.0 and absf(turn) > 0.6 and float(c.get("dodge", 0.0)) == 0.0:
				if int(c.blink) == 0 or signf(float(c.blink)) != signf(turn):
					wrong += 1
				else:
					signalled += 1
			if bool(c.get("braking", false)):
				braked += 1
	if max_rate > 3.0:
		errors.append("a traffic car's heading snapped at %.1f rad/s" % max_rate)
	if signalled == 0 or wrong > signalled / 10:
		errors.append("turn signals: %d right, %d missing or wrong" % [signalled, wrong])
	if braked == 0:
		errors.append("no traffic car ever lit its brake lamps")
	_free(tr)

## A junction where a smaller road meets a bigger one: a car on the small road waits at its line while a car on the
## big road goes through, then pulls out.
func _give_way(errors: Array[String]) -> void:
	var tested := 0
	for nid in map.node_edges:
		if tested >= 3:
			break
		var inc: Array = map.node_edges[nid]
		if inc.size() < 3:
			continue
		# edges arriving at this node: the reverse of each incident edge
		var minor: Array = []
		var major: Array = []
		var minor_from := ""
		var major_from := ""
		var top := 0
		for n in inc:
			top = maxi(top, map.road_rank[n[1]])
		for n in inc:
			for r in map.node_edges.get(n[0], []):
				if String(r[0]) == String(nid) and int(r[1]) == int(n[1]) and r[5] and float(r[4]) > 60.0 \
						and map.road_z[r[1]].is_empty():
					if map.road_rank[r[1]] == top and major.is_empty():
						major = r
						major_from = n[0]
					elif map.road_rank[r[1]] < top and map.road_rank[r[1]] >= 2 and minor.is_empty():
						minor = r
						minor_from = n[0]
		if minor.is_empty() or major.is_empty():
			continue
		var tr := Traffic.new(map, Node3D.new(), null)
		var npos: Vector2 = map.node_pos[nid]
		var m := _car(tr, minor_from, minor, float(minor[4]) - 35.0, 6.0)
		var b := _car(tr, major_from, major, float(major[4]) - 32.0, 9.0)
		b.want = 9.0
		var minor_in_box_while_major_near := false
		var major_through := false
		var minor_out := false
		for i in int(30.0 / DT):
			for c in tr.cars:
				tr._drive(c, DT, player)
			var b_near := not major_through and (b.pos as Vector2).distance_to(npos) < 10.0
			if String(b.from) == String(nid):
				major_through = true
			if b_near and (m.pos as Vector2).distance_to(npos) < 3.0 and is_same(m.edge, minor):
				minor_in_box_while_major_near = true
			if not is_same(m.edge, minor):
				minor_out = true
				break
		if minor_in_box_while_major_near:
			errors.append("at junction %s the side-road car pulled out in front of the main-road car" % nid)
		if not minor_out:
			errors.append("at junction %s the side-road car never pulled out (s %.1f of %.1f, line %.1f)" % [nid, float(m.s), float(m.len), float(m.get("line", INF))])
		_free(tr)
		tested += 1
	if tested == 0:
		errors.append("no give-way junction found")

## A parked car in the lane: the car behind pulls out, passes it and gets back into its lane; a jam that never moves
## (the player stopped in the lane, cars coming the other way) ends with the car turning back.
func _go_round(errors: Array[String]) -> void:
	var st := _straights(200.0)
	if st.is_empty():
		return
	var tr := Traffic.new(map, Node3D.new(), null)
	var pick: Array = st[mini(3, st.size() - 1)]
	var c := _car(tr, pick[0], pick[1], 10.0, 8.0)
	var pk := _car(tr, pick[0], pick[1], 60.0, 0.0)
	pk.parked = true
	pk.v = 0.0
	tr._place(pk)
	var passed := false
	var max_off := 0.0
	for i in int(30.0 / DT):
		for k in tr.cars:
			tr._drive(k, DT, player)
		max_off = maxf(max_off, absf(float(c.get("dodge_now", 0.0))))
		if (c.pos as Vector2).distance_to(pk.pos) < 2.4:
			errors.append("the car drove into the parked car it was passing")
			break
		if not is_same(c.edge, pk.edge) or float(c.s) > float(pk.s) + 15.0:
			passed = true
			break
	if not passed:
		errors.append("stuck behind a parked car (s %.1f, parked at %.1f, dodge %.1f)" % [float(c.s), float(pk.s), float(c.get("dodge_now", 0.0))])
	elif max_off < 1.5:
		errors.append("passed a parked car without pulling out (%.1f m)" % max_off)
	_free(tr)
	# the player parked across the lane with traffic streaming the other way: the car eventually turns back
	tr = Traffic.new(map, Node3D.new(), null)
	var c2 := _car(tr, pick[0], pick[1], 20.0, 0.0)
	var blocker := FreeCar.new(map)
	var at := Traffic._point_on(c2.pts, 40.0)
	var side := Vector2(-(at[1] as Vector2).y, (at[1] as Vector2).x)
	blocker.place((at[0] as Vector2) + side * tr._lane(int(pick[1][1])), (at[1] as Vector2).angle())
	var rev: Array = []
	for r in map.node_edges.get(pick[1][0], []):
		if int(r[1]) == int(pick[1][1]) and String(r[0]) == String(pick[0]):
			rev = r
	var turned := false
	var spawn_t := 0.0
	for i in int(60.0 / DT):
		spawn_t -= DT
		if spawn_t <= 0.0 and not rev.is_empty():
			spawn_t = 2.5
			_car(tr, pick[1][0], rev, maxf(0.0, float(rev[4]) - 110.0), 10.0).want = 10.0 # 70 m past the blocker
		for k in tr.cars:
			tr._drive(k, DT, blocker)
		if not is_same(c2.edge, pick[1]):
			turned = true
			break
	if not turned:
		errors.append("a car stuck behind the stopped player never went round or turned back (s %.1f v %.1f lead %s stuck %.1f blocked %.1f rev %d cars %d)" % [float(c2.s), float(c2.v), str(typeof(c2.get("lead"))), float(c2.get("stuck_t", 0.0)), float(c2.get("blocked", 0.0)), rev.size(), tr.cars.size()])
	_free(tr)

## A closed level crossing 50 m ahead: the car stops short of the boom, and goes once it opens.
func _crossing(errors: Array[String]) -> void:
	var st := _straights(200.0)
	if st.is_empty():
		return
	var tr := Traffic.new(map, Node3D.new(), null)
	var pick: Array = st[mini(5, st.size() - 1)]
	var c := _car(tr, pick[0], pick[1], 10.0, 11.0)
	var at := Traffic._point_on(c.pts, 60.0)
	var d: Vector2 = at[1]
	var side := Vector2(-d.y, d.x)
	var mid: Vector2 = at[0]
	var boom := [mid + side * 6.0, mid - side * 6.0, true, 0.0]
	map.booms.append(boom)
	var stopped := false
	for i in int(20.0 / DT):
		tr._drive(c, DT, player)
		if float(c.s) > 60.0:
			errors.append("traffic drove through a closed crossing")
			break
		if float(c.v) < 0.05:
			stopped = true
	if not stopped:
		errors.append("traffic never stopped for a closed crossing (s %.1f)" % float(c.s))
	boom[2] = false
	for i in int(15.0 / DT):
		tr._drive(c, DT, player)
	if float(c.s) < 65.0 and is_same(c.edge, pick[1]):
		errors.append("traffic did not move off when the crossing opened (s %.1f)" % float(c.s))
	map.booms.erase(boom)
	_free(tr)

## Traffic signals: the junctions' arms that cross are never green together, and a car coming up to a red light stops
## short of its line, then drives on when it goes green.
func _signals(errors: Array[String]) -> void:
	var heads := map.signal_heads()
	if heads.size() < 10:
		errors.append("only %d traffic signal heads" % heads.size())
		return
	for i in heads.size():
		for j in range(i + 1, heads.size()):
			var a: Array = heads[i]
			var b: Array = heads[j]
			if (a[2] as Vector2).distance_to(b[2]) > 80.0 or absf((a[1] as Vector2).dot(b[1])) > 0.7:
				continue
			for k in 88:
				var t := float(k) * 0.5
				if TownMap.signal_state(a, t) == TownMap.SIG_GREEN and TownMap.signal_state(b, t) == TownMap.SIG_GREEN:
					errors.append("crossing signals at %s and %s both green at %.1f s" % [a[2], b[2], t])
					break
	# a head whose stop line a traffic edge runs through, 45 m or more along it
	var tr := Traffic.new(map, Node3D.new(), null)
	var found: Array = []
	for nid in map.node_edges:
		if not found.is_empty():
			break
		for e in map.node_edges[nid]:
			if not e[5] or map.road_rank[e[1]] < 3 or not map.road_z[e[1]].is_empty():
				continue
			var pts := tr._edge_points(e)
			var ln := Traffic._poly_len(pts)
			for h in heads:
				var sl := 45.0
				while sl < ln - 2.0:
					var at := Traffic._point_on(pts, sl)
					if (at[0] as Vector2).distance_to(h[2]) < 1.5 and (at[1] as Vector2).dot(h[1]) > 0.9:
						found = [nid, e, h, sl]
						break
					sl += 1.0
				if not found.is_empty():
					break
			if not found.is_empty():
				break
	if found.is_empty():
		errors.append("no traffic edge runs through a signal's stop line")
		return
	var h: Array = found[2]
	var red_t := -1.0
	for k in 88:
		if TownMap.signal_state(h, float(k) * 0.5) == TownMap.SIG_RED:
			red_t = float(k) * 0.5
			break
	var green_t := float(h[3]) + 1.0
	var c := _car(tr, found[0], found[1], float(found[3]) - 45.0, 10.0)
	map.signal_t = red_t
	for i in int(15.0 / DT):
		tr._drive(c, DT, player)
	var line_s: float = found[3]
	if not is_same(c.edge, found[1]) or float(c.s) > line_s - 1.0 or float(c.v) > 0.3:
		errors.append("on red the car didn't stop short of the line (s %.1f, line at %.1f, v %.1f)" % [float(c.s), line_s, float(c.v)])
	map.signal_t = green_t
	var through := false
	for i in int(12.0 / DT):
		tr._drive(c, DT, player)
		if not is_same(c.edge, found[1]) or float(c.s) > line_s + 3.0:
			through = true
			break
	if not through:
		errors.append("on green the car didn't drive on (s %.1f, line at %.1f)" % [float(c.s), line_s])
	map.signal_t = 0.0
	_free(tr)
