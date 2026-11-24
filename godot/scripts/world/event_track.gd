## A race track made on the fly from an open-world event's route (LiveEvents, MapMissions), so the race sim's bots
## (Race, EventField) can drive it as they drive a baked track: the centreline is the road's own centre under the
## route (LiveEvents.route_profile's centre), each sample keeps the map's half width there (Track.HW) and its surface
## (Track.loose: dirt, gravel, the slower asphalt), the height is the road's (bridges and all), and the racing line
## and speed profile come from Track's own relaxation and profile (build_racing_line_span, build_profile).
##
## The race sim's tracks are loops, so the route is closed into one: a straight LEAD m lead-in before the start, the
## route, the road on past the finish (LiveEvents.beyond: where the cars home park), a straight STUB on, and a jump
## back to the lead-in that nobody drives. The bots' walls (Track.REACH) stand VERGE m beyond the road's edges: they
## keep to the road and off the buildings, as the open world's own drawn kerbs and pavements do.
class_name EventTrack
extends RefCounted

const STEP := 2.0 ## m between samples (as the baked tracks)
const LEAD := 40.0 ## m of straight before the start (whole samples)
const STUB := 120.0 ## m of straight past the end of the road beyond the finish
const VERGE := 1.0 ## m beyond the road's edge the bots' wall stands (a kerb and a strip of pavement)
const HALF_MIN := 1.4 ## m: the narrowest half width the bots are given
const HALF_MAX := 12.0
const COARSE := 5 ## the racing line relaxed on every 5th sample, then finished on all (Track.build_racing_line_span)
const ROUND_PASSES := 3 ## smoothing passes over the 5 m route centre (a right-angle junction turn to a ~10 m radius)

var track: Track
var start_s := 0.0 ## m along the loop where the route starts
var finish_s := 0.0 ## where it ends (the finish line)
var park_s := 0.0 ## the end of the road past the finish (the cars home park short of it)
var build_ms := 0.0
var phase_ms := {} ## build time by phase (centre, road, frames, line, profile)

## path: the event's route; beyond: the road on past its finish (may be empty); key: the track's key (cache and
## corner-profile key, unique per event); z0: the height of the start (the deck the route sets off on).
func _init(map: TownMap, path: PackedVector2Array, beyond: PackedVector2Array, key := "event", z0 := -INF) -> void:
	var t0 := Time.get_ticks_usec()
	var route := _on_centre(map, path)
	var more := _on_centre(map, beyond) if beyond.size() >= 2 else PackedVector2Array()
	if route.size() < 2:
		route = path
	var d0 := (route[mini(3, route.size() - 1)] - route[0]).normalized()
	if d0 == Vector2.ZERO:
		d0 = Vector2.RIGHT
	var full := PackedVector2Array([route[0] - d0 * LEAD])
	full.append_array(route)
	var route_len := LiveEvents.path_length(route)
	for i in range(1, more.size()):
		full.append(more[i])
	var e := full[full.size() - 1]
	var de := (e - full[full.size() - 2]).normalized()
	full.append(e + de * STUB)
	phase_ms.centre = (Time.get_ticks_usec() - t0) / 1000.0
	var pts := LiveEvents.resample(full, STEP)
	var n := pts.size()
	start_s = LEAD
	finish_s = LEAD + route_len
	park_s = finish_s + maxf(LiveEvents.path_length(more), 0.0)
	var def := TrackDef.new()
	def.key = key
	def.display_name = key
	def.street_stage = true
	def.runoff = VERGE
	def.runoff_surface = "grass"
	def.loose_grip = true
	def.pit_offset = 0.0
	def.pit_entry = 1e9 # never reached: no pit lane
	def.pit_exit = 1e9 + 1.0
	def.grandstands = false
	def.floodlight_spacing = 0.0
	var tr := Track.new()
	tr.cfg = def
	tr.key = key
	tr.name = key
	tr.n = n
	tr.step = STEP
	tr.L = n * STEP
	tr.X.resize(n)
	tr.Y.resize(n)
	tr.H.resize(n)
	tr.HW.resize(n)
	for i in n:
		tr.X[i] = pts[i].x
		tr.Y[i] = pts[i].y
	# the road under each sample: its half width, surface and height (the deck nearest the last one's height)
	var i_lo := int(LEAD / STEP)
	var i_hi := mini(int(ceilf(park_s / STEP)) + 1, n)
	var kinds := PackedByteArray()
	kinds.resize(n)
	var hw := PackedFloat64Array()
	hw.resize(n)
	var have := PackedByteArray()
	have.resize(n)
	var z := z0
	for i in n:
		var p := pts[i]
		var dir := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		hw[i] = 4.0
		kinds[i] = 0
		var hit := map.road_at(p.x, p.y, z, 3.0) if i >= i_lo and i < i_hi else {}
		if not hit.is_empty():
			var ri := int(hit.road)
			var rp: PackedVector2Array = map.road_pts[ri]
			var rd := (rp[mini(int(hit.i) + 1, rp.size() - 1)] - rp[int(hit.i)]).normalized()
			z = float(hit.height)
			tr.H[i] = z
			have[i] = 1
			if absf(rd.dot(dir)) >= 0.7: # the road the route runs along, not a crossing street
				hw[i] = float(hit.half)
				match int(hit.surface):
					2: kinds[i] = 2 if int(hit.get("gravel", 0)) else 1
					1: kinds[i] = 3
			else:
				hw[i] = -1.0 # a junction: the width of the way on, filled in below
				kinds[i] = 255
		elif i >= i_lo and i < i_hi:
			tr.H[i] = map.ground(p.x, p.y)
			have[i] = 1
			kinds[i] = 1 # off the drawn roads: a track through the woods (as LiveEvents.route_profile has it)
	_fill_gaps(hw, kinds, have, tr.H, n)
	# smoothed (a junction or a slip road alongside should not throw the width about), the narrowest kept
	for i in n:
		var acc := 0.0
		var lo := INF
		var w := 0
		for j in range(maxi(i - 5, 0), mini(i + 6, n)):
			acc += hw[j]
			lo = minf(lo, hw[j])
			w += 1
		tr.HW[i] = clampf(minf(acc / maxf(w, 1), lo + 1.0), HALF_MIN, HALF_MAX)
	var hs := tr.H.duplicate()
	for i in n:
		var acc := 0.0
		var w := 0
		for j in range(maxi(i - 3, 0), mini(i + 4, n)):
			acc += hs[j]
			w += 1
		tr.H[i] = acc / maxf(w, 1)
	# surfaces as spans (Track.loose kinds: 1 dirt, 2 gravel, 3 the map's slower asphalt)
	var k0 := int(kinds[0])
	var a := 0
	for i in range(1, n + 1):
		var k := int(kinds[i]) if i < n else -1
		if k != k0:
			if k0 > 0:
				tr.loose.append(Vector3(a * STEP, i * STEP, k0))
			a = i
			k0 = k
	var med := tr.HW.duplicate()
	med.sort()
	tr.half = med[n / 2] if n > 0 else 4.0
	tr.width = tr.half * 2.0
	def.width = tr.width
	tr.REACH.resize(2 * n)
	tr.VKIND.resize(2 * n)
	for i in n:
		tr.REACH[2 * i] = tr.HW[i] + VERGE
		tr.REACH[2 * i + 1] = tr.HW[i] + VERGE
		tr.VKIND[2 * i] = Track.VERGE_SOLID
		tr.VKIND[2 * i + 1] = Track.VERGE_SOLID
	tr.h_min = INF
	tr.h_max = -INF
	for h in tr.H:
		tr.h_min = minf(tr.h_min, h)
		tr.h_max = maxf(tr.h_max, h)
	tr.GRADE.resize(n)
	var gw := 5
	for i in n:
		tr.GRADE[i] = (tr.H[(i + gw) % n] - tr.H[(i - gw + n) % n]) / (2 * gw * STEP)
	phase_ms.road = (Time.get_ticks_usec() - t0) / 1000.0
	tr.build_frames()
	tr.build_banking()
	tr.build_corner_envelope()
	phase_ms.frames = (Time.get_ticks_usec() - t0) / 1000.0
	tr.build_racing_line_span(maxi(i_lo - 10, 0), i_hi, 1.25, COARSE)
	phase_ms.line = (Time.get_ticks_usec() - t0) / 1000.0
	tr.build_profile()
	tr.build_bounds()
	track = tr
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0

## The route moved onto the road it runs along: every 5 m, the road's centre (LiveEvents.route_profile).
static func _on_centre(map: TownMap, path: PackedVector2Array) -> PackedVector2Array:
	if path.size() < 2:
		return path
	var pts := LiveEvents.resample(path, 5.0)
	var prof := LiveEvents.route_profile(map, path, 5.0)
	var c: PackedFloat32Array = prof.centre
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var d := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var off := c[i] if i < c.size() else 0.0
		out.append(pts[i] + Vector2(-d.y, d.x) * off)
	# the corners where one street meets the next rounded (the router turns on the junction's node; the junction's
	# own tarmac lets a car round it): a few passes of a 3-point average, the ends held
	for pass_i in ROUND_PASSES:
		var prev := out.duplicate()
		for i in range(1, n - 1):
			out[i] = prev[i] * 0.5 + (prev[i - 1] + prev[i + 1]) * 0.25
	return out

## Junction samples (hw < 0) take the width of the road either side of them; samples with no height take the
## nearest one's.
static func _fill_gaps(hw: PackedFloat64Array, kinds: PackedByteArray, have: PackedByteArray, h: PackedFloat64Array, n: int) -> void:
	for i in n:
		if hw[i] >= 0.0:
			continue
		var a := i
		while a > 0 and hw[a] < 0.0:
			a -= 1
		var b := i
		while b < n - 1 and hw[b] < 0.0:
			b += 1
		var wa := hw[a] if hw[a] >= 0.0 else 4.0
		var wb := hw[b] if hw[b] >= 0.0 else 4.0
		hw[i] = maxf(wa, wb)
		kinds[i] = kinds[a] if kinds[a] != 255 else (kinds[b] if kinds[b] != 255 else 0)
	var first := -1
	for i in n:
		if have[i]:
			first = i
			break
	if first < 0:
		return
	var last_h := h[first]
	for i in n:
		if have[i]:
			last_h = h[i]
		else:
			h[i] = last_h

## The road's half width at distance s along the loop.
func half_at(s: float) -> float:
	return track.half_at(s)
