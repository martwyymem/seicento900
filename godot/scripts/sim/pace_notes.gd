## The co-driver's pace notes for a circuit, in the vocabulary Colin McRae Rally 2.0's co-driver used:
## each bend graded by how tight it is (flat, fast, easy, medium, tight, square, hairpin) with its direction,
## then what else matters (long, tightens, opens, over crest), a caution where it bites, and how it joins the
## next one: "into" or "and" when they run together, otherwise the distance to it. Built once per track from
## the racing line's curvature and the elevation, so the notes are the same every lap and every race.
class_name PaceNotes
extends RefCounted

const G := 9.81
## Smallest radius (m) on the racing line for each grade, tightest last; hairpin and square are told apart
## from tight by how far the road turns (HAIRPIN_TURN, SQUARE_TURN). Pitched for a Seicento: flat is above
## about 140 km/h at the limit, so the car can't go fast enough to need to lift there.
const GRADES := [["flat", 150.0], ["fast", 85.0], ["easy", 50.0], ["medium", 28.0], ["tight", 0.0]]
const HAIRPIN_TURN := deg_to_rad(130.0)
const SQUARE_TURN := deg_to_rad(65.0)
const K_ON := 1.0 / 320.0 ## curvature (1/m) above which the road counts as turning
const MIN_TURN := deg_to_rad(14.0) ## less than this all told is a kink, not a corner
const FLAT_MIN_TURN := deg_to_rad(28.0) ## a flat bend is only called if it turns this far
const SMOOTH := 5 ## samples either side the curvature is averaged over
const MERGE_GAP := 22.0 ## m: the same way again within this is the same corner
const INTO_GAP := 22.0 ## m to the next corner below which it is "into"
const AND_GAP := 55.0 ## ... and below which it is "and"
const DIST_MIN := 80.0 ## m of straight before the next corner that gets a distance call
const DIST_MAX := 500.0 ## ... and beyond which the straight speaks for itself
const LONG_LEN := 110.0 ## m: a corner at least this long (and turning SQUARE_TURN or more) is long
const CREST_K := 1.0 / 550.0 ## vertical curvature (1/m) over the top of a rise that lightens the car (0.25 g at 38 m/s)
const CREST_WIN := 10 ## samples either side of a point the vertical curvature is measured over
const V_TOP := 39.0 ## m/s: about a Seicento's top speed, for the caution calls
const BRAKE_REACTION := 2.5 ## s of reaction time added before a corner's braking point for early callouts
const LEAD_CAP := 650.0 ## m: upper bound on dynamic callout lead distance
const BRAKE_MARGIN := 1.12 ## safety factor on braking distance when lighting the BRAKE cue / red arrows
const BRAKE_MIN_DROP := 3.5 ## m/s: ignore tiny speed trims where a lift is enough
const YELLOW_LEAD := 0.55 ## s of speed-scaled lift/prepare warning ahead of the red braking point
const YELLOW_MIN_MARGIN := 12.0 ## m minimum yellow lead ahead of a braking zone
const BRAKE_SUFFICIENT_INPUT := 0.55 ## brake pedal share at which the driver counts as actively braking
const BRAKE_SUFFICIENT_RATIO := 0.85 ## actual decel vs required decel (while braking) to keep BRAKE quiet

enum BrakeZone { GREEN, YELLOW, RED }

static var _corner_cache := {} ## track + car key -> PackedFloat64Array steady-state cornering limits (mu = 1)

## [{s, e, apex, dir (+1 right / -1 left, 0 crest), grade, turn (rad), radius (m), mods: [String],
##   caution, link ("into" | "and" | ""), dist (m, 0 = none)}] sorted by s, the start of the corner.
var notes: Array = []
var track: Track

func _init(track_: Track) -> void:
	track = track_
	_build()

# ---------------- building ----------------
func _build() -> void:
	var n := track.n
	var step := track.step
	var k := PackedFloat64Array()
	k.resize(n)
	for i in n:
		var sum := 0.0
		for q in range(-SMOOTH, SMOOTH + 1):
			sum += track.RK[(i + q + n) % n]
		k[i] = sum / (2 * SMOOTH + 1)
	# start the scan on a straight so no corner is cut in two by the wrap
	var i0 := 0
	var quiet := INF
	for i in n:
		if absf(k[i]) < quiet:
			quiet = absf(k[i])
			i0 = i
	var spans: Array = [] ## [first sample, last sample (unwrapped, from i0), dir]
	var cur = null
	for q in n:
		var i := i0 + q
		var kk := k[i % n]
		var dir := 0 if absf(kk) < K_ON else (1 if kk > 0.0 else -1)
		if cur and (dir != cur[2]):
			spans.append(cur)
			cur = null
		if dir != 0 and cur == null:
			cur = [i, i, dir]
		elif cur:
			cur[1] = i
	if cur:
		spans.append(cur)
	# the same way again after a short let-up is still the same corner
	var merged: Array = []
	for sp in spans:
		if not merged.is_empty() and merged[-1][2] == sp[2] and (sp[0] - merged[-1][1]) * step <= MERGE_GAP:
			merged[-1][1] = sp[1]
		else:
			merged.append(sp)
	for sp in merged:
		var turn := 0.0
		var peak := 0.0
		var apex: int = sp[0]
		for i in range(sp[0], sp[1] + 1):
			var a := absf(k[i % n])
			turn += a * step
			if a > peak:
				peak = a
				apex = i
		var radius := 1.0 / maxf(peak, 1e-6)
		if turn < MIN_TURN or (radius >= GRADES[0][1] and turn < FLAT_MIN_TURN):
			continue
		var note := {"s": sp[0] * step, "e": (sp[1] + 1) * step, "apex": apex * step, "dir": sp[2],
			"grade": grade_for(radius, turn), "turn": turn, "radius": radius, "mods": [], "caution": false,
			"link": "", "dist": 0}
		var length: float = note.e - note.s
		if note.grade != "hairpin" and length >= LONG_LEN and (turn >= SQUARE_TURN or length >= 1.8 * LONG_LEN):
			note.mods.append("long")
		# tightens / opens: compare the first and last third of the corner
		if length >= 45.0:
			var third := maxi(1, (sp[1] - sp[0] + 1) / 3)
			var first := 0.0
			var last := 0.0
			for q in third:
				first += absf(k[(sp[0] + q) % n])
				last += absf(k[(sp[1] - q) % n])
			if last > 1.7 * first and 1.0 / (last / third) < 80.0:
				note.mods.append("tightens")
			elif first > 1.7 * last and 1.0 / (first / third) < 80.0:
				note.mods.append("opens")
		notes.append(note)
	for note in notes:
		note.s = track.wrap_s(note.s)
		note.e = track.wrap_s(note.e)
		note.apex = track.wrap_s(note.apex)
	notes.sort_custom(func(a, b): return a.s < b.s)
	_add_crests(k)
	_link()

## The grade for a corner whose tightest radius is radius (m) and that turns turn (rad) all told.
static func grade_for(radius: float, turn: float) -> String:
	for g in GRADES:
		if radius >= g[1] and g[1] > 0.0:
			return g[0]
	if turn >= HAIRPIN_TURN:
		return "hairpin"
	if turn >= SQUARE_TURN:
		return "square"
	return "tight"

## The tops of rises the car goes light over: "over crest" on a corner there, a crest note of its own on
## a straight (only where the car is quick enough for it to matter).
func _add_crests(k: PackedFloat64Array) -> void:
	var n := track.n
	var step := track.step
	var span := CREST_WIN * step
	var kv := PackedFloat64Array()
	kv.resize(n)
	for i in n:
		kv[i] = (track.H[(i + CREST_WIN) % n] - 2.0 * track.H[i] + track.H[(i - CREST_WIN + n) % n]) / (span * span)
	var crests: Array = []
	var i := 0
	while i < n:
		if kv[i] < -CREST_K:
			# the top of this rise: its most convex point
			var best := i
			var j := i
			while j < i + n and kv[j % n] < -CREST_K:
				if kv[j % n] < kv[best % n]:
					best = j
				j += 1
			crests.append(track.wrap_s(best * step))
			i = j + 1
		else:
			i += 1
	var added: Array = []
	for c in crests:
		var on_corner := false
		for note in notes:
			var into := track.rel(c - note.s)
			if into >= -30.0 and into <= track.rel(note.e - note.s) + 10.0:
				if not note.mods.has("over crest"):
					note.mods.append("over crest")
				on_corner = true
				break
		if on_corner:
			continue
		# a crest on a straight only gets called where the car is going quickly and it's clear of the last one
		var fast: bool = absf(k[int(c / step) % n]) < K_ON and track.sample(track.PROF, c) > 30.0
		if fast and (added.is_empty() or track.rel(c - added[-1]) > 150.0):
			added.append(c)
			notes.append({"s": track.wrap_s(c - 10.0), "e": track.wrap_s(c + 10.0), "apex": c, "dir": 0,
				"grade": "crest", "turn": 0.0, "radius": INF, "mods": [], "caution": false, "link": "", "dist": 0})
	notes.sort_custom(func(a, b): return a.s < b.s)

## How each note runs into the next, and where a corner needs a caution.
func _link() -> void:
	var m := notes.size()
	for idx in m:
		var note: Dictionary = notes[idx]
		var nxt: Dictionary = notes[(idx + 1) % m]
		var prev: Dictionary = notes[(idx - 1 + m) % m]
		var gap := track.wrap_s(nxt.s - note.e) if m > 1 else track.L
		if m > 1 and gap < track.L * 0.5:
			if gap < INTO_GAP:
				note.link = "into"
			elif gap < AND_GAP:
				note.link = "and"
			elif gap >= DIST_MIN and gap <= DIST_MAX:
				note.dist = distance_call(gap)
		if note.dir == 0:
			continue
		# caution: a big stop from the speed the straight before allows, or a corner that closes on you
		var run := track.wrap_s(note.s - prev.e) if m > 1 else track.L
		var v_in := minf(V_TOP, sqrt(G * minf(prev.radius, 400.0)) if run < 40.0 else V_TOP)
		var v_at := sqrt(G * note.radius)
		if (v_at < 0.5 * v_in and run > 120.0) or (note.mods.has("tightens") and note.grade in ["medium", "tight", "square", "hairpin"]):
			note.caution = true

## The distance a co-driver would call for gap metres: 100, 150 ... 300, then in hundreds.
static func distance_call(gap: float) -> int:
	if gap < 125.0:
		return 100
	if gap < 325.0:
		return int(roundf(gap / 50.0)) * 50
	return int(roundf(gap / 100.0)) * 100

# ---------------- words ----------------
## What the co-driver says for a note, e.g. "caution, square right, tightens, into".
static func spoken(note: Dictionary) -> String:
	var words: Array = []
	if note.caution:
		words.append("caution")
	if note.dir == 0:
		words.append("over crest")
	else:
		words.append("%s %s" % [note.grade, "right" if note.dir > 0 else "left"])
	for mod in note.mods:
		words.append(mod)
	var said := ", ".join(words)
	if note.link != "":
		said += " " + note.link
	elif note.dist > 0:
		said += ", %d" % note.dist
	return said

## The note as the HUD prints it under the arrow box, e.g. "SQUARE RIGHT · TIGHTENS".
static func label(note: Dictionary) -> String:
	var words: Array = ["CREST" if note.dir == 0 else "%s %s" % [note.grade.to_upper(), "RIGHT" if note.dir > 0 else "LEFT"]]
	for mod in note.mods:
		words.append(mod.to_upper())
	if note.link != "":
		words.append(note.link.to_upper())
	elif note.dist > 0:
		words.append(str(note.dist))
	return " · ".join(words)

## HUD caption with an active distance countdown to the upcoming corner (e.g. "SQUARE LEFT 250"); once inside
## the corner (dist_to <= 0) falls back to label(note) so exit links ("INTO" / "AND") still show.
static func hud_label(note: Dictionary, dist_to := 0) -> String:
	if dist_to <= 0:
		return label(note)
	var words: Array = ["CREST" if note.dir == 0 else "%s %s" % [note.grade.to_upper(), "RIGHT" if note.dir > 0 else "LEFT"]]
	for mod in note.mods:
		words.append(mod.to_upper())
	return "%s %d" % [" · ".join(words), dist_to]

# ---------------- braking lead & cues ----------------
## Effective braking deceleration (m/s²) between current speed v and corner speed v_corner, matching Race's
## brake_k (tyre grip ratio vs stock) and brake_aero (downforce decel per (m/s)²), scaled by surface/tyre mu.
static func brake_decel(v: float, v_corner: float, brake_k := 1.0, brake_aero := 0.0, mu := 1.0) -> float:
	var v0 := maxf(0.0, v)
	var v1 := maxf(0.0, v_corner)
	var v2_avg := 0.5 * (v0 * v0 + v1 * v1)
	return maxf(2.0, (0.92 * G * brake_k + brake_aero * v2_avg) * maxf(0.2, mu))

## Steady-state cornering speed (m/s) for a bend of radius (m) from the car's grip and downforce.
static func corner_speed(radius: float, brake_k := 1.0, brake_aero := 0.0, mu := 1.0) -> float:
	if not is_finite(radius) or radius <= 0.0:
		return INF
	var k := 1.0 / radius
	var m := maxf(0.2, mu)
	var aero := brake_aero * m
	if k <= aero:
		return 120.0
	return minf(120.0, sqrt(G * brake_k * m / (k - aero)))

## Braking distance (m) to slow from v down to v_corner at constant deceleration decel (m/s²).
static func braking_distance(v: float, v_corner: float, decel: float) -> float:
	if v <= v_corner or decel <= 0.0 or not is_finite(v_corner):
		return 0.0
	return (v * v - v_corner * v_corner) / (2.0 * decel)

## How far before a corner (m) the callout must appear so the driver gets `reaction` seconds before the
## braking point. Corners that need no braking keep the normal base_min..base_max window.
static func lead_distance(v: float, v_corner: float, decel: float, base_min := 55.0, base_time := 2.6,
		base_max := 190.0, reaction := BRAKE_REACTION, cap := LEAD_CAP) -> float:
	var spd := maxf(0.0, v)
	var base := clampf(spd * base_time, base_min, base_max)
	var d_brake := braking_distance(spd, v_corner, decel)
	if d_brake <= 0.0:
		return base
	return clampf(maxf(base, d_brake + spd * reaction), base_min, cap)

## Distance countdown rounded to 50 m steps for the HUD caption (0 once within 35 m of the corner).
static func countdown_metres(dist: float) -> int:
	if dist < 35.0:
		return 0
	return maxi(50, int(roundf(dist / 50.0)) * 50)

## Braking-zone distances (m before a corner of speed `v_corner`) for a car currently at speed `v` (m/s)
## with realistic braking deceleration `decel` (m/s²). Returns Vector2(red_dist, yellow_dist); negative
## entries mean that band does not apply. Shared by both the dynamic racing-line arrows and the BRAKE cue.
static func brake_zone_distances(v: float, v_corner: float, decel: float) -> Vector2:
	var spd := maxf(0.0, v)
	if not is_finite(v_corner) or decel <= 0.0 or spd <= v_corner + 0.5:
		return Vector2(-1.0, -1.0)
	var d_brake := braking_distance(spd, v_corner, decel)
	var red_dist := d_brake * BRAKE_MARGIN if spd > v_corner + BRAKE_MIN_DROP and d_brake > 0.0 else -1.0
	var yellow_pad := maxf(YELLOW_MIN_MARGIN, spd * YELLOW_LEAD) if red_dist >= 0.0 else maxf(6.0, d_brake * 0.5)
	var yellow_dist := d_brake * BRAKE_MARGIN + yellow_pad
	return Vector2(red_dist, yellow_dist)

## Pure speed-vs-corner classifier for a point `dist` metres ahead of a corner with target speed `v_corner`,
## given current speed `v` (m/s) and realistic braking decel `decel` (m/s²):
## BrakeZone.GREEN (fine / can accelerate), YELLOW (lift / prepare to brake), RED (must brake now).
static func brake_zone(v: float, dist: float, v_corner: float, decel: float) -> int:
	var lim := brake_zone_distances(v, v_corner, decel)
	var d := maxf(0.0, dist)
	if lim.x >= 0.0 and d <= lim.x:
		return BrakeZone.RED
	if lim.y >= 0.0 and d <= lim.y:
		return BrakeZone.YELLOW
	return BrakeZone.GREEN

## Braking-cue state for a corner `dist_to_corner` metres ahead: returns {brake, brake_dist, urgency, countdown, zone}.
## `brake` is true only when `brake_zone` is RED (stopping distance >= distance left) AND the driver is not
## already braking enough (brake pedal high and deceleration sufficient) or already slow enough.
static func brake_cue(dist_to_corner: float, v: float, v_corner: float, decel: float,
		brake_input := 0.0, actual_decel := NAN) -> Dictionary:
	var spd := maxf(0.0, v)
	var d_brake := braking_distance(spd, v_corner, decel)
	var zone := brake_zone(spd, dist_to_corner, v_corner, decel)
	var at_point := zone == BrakeZone.RED
	var braking_enough := false
	if at_point and brake_input >= BRAKE_SUFFICIENT_INPUT:
		var a_req := (spd * spd - v_corner * v_corner) / (2.0 * maxf(dist_to_corner, 1.0))
		var cur_decel := decel * clampf(brake_input, 0.0, 1.0) if is_nan(actual_decel) else actual_decel
		if cur_decel >= maxf(2.0, a_req * BRAKE_SUFFICIENT_RATIO):
			braking_enough = true
	var show_brake := at_point and not braking_enough
	var trigger := d_brake * BRAKE_MARGIN
	var urgency := 0.0
	if show_brake:
		urgency = clampf((trigger - dist_to_corner) / maxf(25.0, d_brake * 0.4) + 0.25, 0.25, 1.0)
	return {"brake": show_brake, "brake_dist": d_brake, "urgency": urgency,
		"countdown": countdown_metres(dist_to_corner), "zone": zone}

## Cached steady-state cornering speed profile (m/s at mu = 1, without backward braking envelope) for a
## track and car, matching Track.build_profile / profile_for / loose_profile without mutating Track.
static func corner_profile(tr: Track, brake_k := 1.0, brake_aero := 0.0, loose := false) -> PackedFloat64Array:
	var key := "%s:%d:%.4f:%.6f:%d" % [tr.key, tr.get_instance_id(), brake_k, brake_aero, 1 if loose else 0]
	if _corner_cache.has(key):
		return _corner_cache[key]
	var n := tr.n
	var out := PackedFloat64Array()
	out.resize(n)
	var vcap := 60.0 if is_equal_approx(brake_k, 1.0) and is_zero_approx(brake_aero) else 100.0
	for i in n:
		var t := absf(tr.BANK[i])
		var k := maxf(absf(tr.RK[i]), 1e-5)
		var a0 := G * brake_k * (1.0 + t) / (1.0 - t)
		var vc := vcap if k <= brake_aero else minf(vcap, sqrt(a0 / (k - brake_aero)))
		if loose:
			var kind := tr.loose_at(i * tr.step)
			if kind != 0:
				vc *= sqrt(Physics.SURF_GRIP[Physics.SURF_GRAVEL_ROAD if kind == 2 else Physics.SURF_DIRT])
		out[i] = vc
	if _corner_cache.size() > 32:
		_corner_cache.clear()
	_corner_cache[key] = out
	return out

## Minimum cornering speed in corner_v across [s - half_span, s + half_span], so a tight apex is never
## skipped between coarser sampling steps. Zero allocations.
static func _min_corner_at(tr: Track, corner_v: PackedFloat64Array, s: float, half_span: float) -> float:
	var n := tr.n
	var inv_step := 1.0 / tr.step
	var s_lo := tr.wrap_s(s - half_span)
	var i0 := int(floorf(s_lo * inv_step)) % n
	var steps := maxi(1, int(ceilf((half_span * 2.0) * inv_step)))
	var best := corner_v[i0]
	for k in range(1, steps + 1):
		var v := corner_v[(i0 + k) % n]
		if v < best:
			best = v
	return best

## Fills out_zones[0..count-1] with BrakeZone values for `count` arrows starting at `s0` spaced by `step_m`
## along `tr`, given current speed `v`, car braking parameters and grip `mu`. Single O(M) backward pass,
## zero allocations, matching brake_zone(v, dist, vc, decel) for every future point.
static func fill_arrow_zones(tr: Track, corner_v: PackedFloat64Array, s0: float, step_m: float, count: int,
		v: float, brake_k: float, brake_aero: float, mu: float, out_zones: PackedInt32Array) -> void:
	if count <= 0:
		return
	if corner_v.is_empty():
		for i in count:
			out_zones[i] = BrakeZone.GREEN
		return
	var spd := maxf(0.0, v)
	var sqrt_mu := sqrt(maxf(0.2, mu))
	var decel_floor := brake_decel(spd, 0.0, brake_k, brake_aero, mu)
	var max_reach := brake_zone_distances(spd, 0.0, decel_floor).y
	var look_extra := clampf(maxf(max_reach, 0.0) + step_m, 0.0, minf(260.0, tr.L * 0.45))
	var max_total := minf(float(count - 1) * step_m + look_extra, tr.L * 0.48)
	var total_steps := maxi(count, int(ceilf(max_total / step_m)) + 1)
	var half_span := step_m * 0.5
	var red_left := -1.0
	var yellow_left := -1.0
	for m in range(total_steps - 1, -1, -1):
		red_left -= step_m
		yellow_left -= step_m
		var vc := _min_corner_at(tr, corner_v, s0 + float(m) * step_m, half_span) * sqrt_mu
		if spd > vc + 0.5:
			var decel := brake_decel(spd, vc, brake_k, brake_aero, mu)
			var lim := brake_zone_distances(spd, vc, decel)
			if lim.x > red_left:
				red_left = lim.x
			if lim.y > yellow_left:
				yellow_left = lim.y
		if m < count:
			if red_left >= 0.0:
				out_zones[m] = BrakeZone.RED
			elif yellow_left >= 0.0:
				out_zones[m] = BrakeZone.YELLOW
			else:
				out_zones[m] = BrakeZone.GREEN

## Evaluates the HUD BRAKE cue at car position `s` along `tr` using the exact same corner profile and
## brake_zone / brake_cue calculation as the dynamic racing-line chevrons so the two always agree.
static func track_brake_cue(tr: Track, corner_v: PackedFloat64Array, s: float, v: float,
		brake_k: float, brake_aero: float, mu: float, brake_input := 0.0, actual_decel := NAN) -> Dictionary:
	var spd := maxf(0.0, v)
	if spd < 6.0 or corner_v.is_empty():
		return {"brake": false, "zone": BrakeZone.GREEN, "dist": INF, "v_corner": INF, "decel": 0.0, "urgency": 0.0}
	var sqrt_mu := sqrt(maxf(0.2, mu))
	var decel_floor := brake_decel(spd, 0.0, brake_k, brake_aero, mu)
	var lim_max := brake_zone_distances(spd, 0.0, decel_floor)
	var look := clampf(maxf(lim_max.y, 0.0) + 10.0, 20.0, minf(320.0, tr.L * 0.45))
	var step_m := 5.0
	var half_span := step_m * 0.5
	var steps := int(ceilf(look / step_m)) + 1
	var worst_zone := BrakeZone.GREEN
	var worst_req := -1.0
	var worst_dist := INF
	var worst_vc := INF
	var worst_decel := decel_floor
	for m in steps:
		var dist := float(m) * step_m
		var vc := _min_corner_at(tr, corner_v, s + dist, half_span) * sqrt_mu
		if spd <= vc + 0.5:
			continue
		var decel := brake_decel(spd, vc, brake_k, brake_aero, mu)
		var z := brake_zone(spd, dist, vc, decel)
		if z > worst_zone:
			worst_zone = z
		if z == BrakeZone.RED:
			var a_req := (spd * spd - vc * vc) / (2.0 * maxf(dist, 1.0))
			if a_req > worst_req:
				worst_req = a_req
				worst_dist = dist
				worst_vc = vc
				worst_decel = decel
	if worst_zone != BrakeZone.RED:
		return {"brake": false, "zone": worst_zone, "dist": INF, "v_corner": INF, "decel": decel_floor, "urgency": 0.0}
	var cue := brake_cue(worst_dist, spd, worst_vc, worst_decel, brake_input, actual_decel)
	return {"brake": bool(cue.brake), "zone": worst_zone, "dist": worst_dist, "v_corner": worst_vc,
		"decel": worst_decel, "urgency": float(cue.urgency)}

## The index of the next note to start ahead of s (or the one whose corner s is still in, when inside is true).
func next_from(s: float, inside := false) -> int:
	var best := -1
	var best_ahead := INF
	for idx in notes.size():
		var note: Dictionary = notes[idx]
		var ahead := track.wrap_s(note.s - s)
		if inside and track.wrap_s(s - note.s) < track.wrap_s(note.e - note.s):
			ahead = 0.0
		if ahead < best_ahead:
			best_ahead = ahead
			best = idx
	return best
