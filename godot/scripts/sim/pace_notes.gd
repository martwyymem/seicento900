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
## A crest is a jump where the car, at the speed its profile gives it there, has its wheels unloaded by at least this
## many g (v² k >= JUMP_G g). No circuit or stage reaches 1 g at profile speed (the highest is 0.94 g, Tokyo), so 0.5 g.
const JUMP_G := 0.5
const NARROW_DROP := 0.25 ## a road that loses this share of its half width (Track.HW) ...
const NARROW_M := 50.0 ## ... within this many metres is called "narrows" ahead of the narrow
const FINISH_CALLS := [[200.0, "200 to finish", "200 TO FINISH"], [100.0, "flying finish", "FLYING FINISH"]] ## [m before the line, say, tag]
const V_TOP := 39.0 ## m/s: about a Seicento's top speed, for the caution calls
const BRAKE_REACTION := 2.5 ## s of reaction time added before a corner's braking point for early callouts
const LEAD_CAP := 650.0 ## m: upper bound on dynamic callout lead distance
const BRAKE_MARGIN := 1.12 ## safety factor on braking distance when lighting the BRAKE cue
const BRAKE_MIN_DROP := 3.5 ## m/s: ignore tiny speed trims where a lift is enough

## [{s, e, apex, dir (+1 right / -1 left, 0 straight: crest, jump, narrows or a finish call), grade, turn (rad),
##   radius (m), mods: [String], caution, link ("into" | "and" | ""), dist (m, 0 = none)}] sorted by s, the start of the corner.
## The straight calls also carry say (spoken) and tag (HUD label).
var notes: Array = []
var track: Track

func _init(track_: Track, build := true) -> void:
	track = track_
	if build:
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
	_add_narrows()
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
## a straight (only where the car is quick enough for it to matter). A crest the car leaves the road over (JUMP_G)
## at the speed the profile carries it is a "jump" instead.
func _add_crests(k: PackedFloat64Array) -> void:
	var n := track.n
	var step := track.step
	var span := CREST_WIN * step
	var kv := PackedFloat64Array()
	kv.resize(n)
	for i in n:
		kv[i] = (track.H[(i + CREST_WIN) % n] - 2.0 * track.H[i] + track.H[(i - CREST_WIN + n) % n]) / (span * span)
	var crests: Array = [] ## [s, jump]
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
			var c_s := track.wrap_s(best * step)
			var v_top := track.sample(track.PROF, c_s)
			crests.append([c_s, v_top * v_top * -kv[best % n] >= JUMP_G * G])
			i = j + 1
		else:
			i += 1
	var added: Array = []
	for c in crests:
		var c_s: float = c[0]
		var jump: bool = c[1]
		var corner := _corner_at(c_s)
		if not corner.is_empty():
			var word := "jump" if jump else "over crest"
			if not corner.mods.has(word):
				corner.mods.append(word)
			continue
		# a crest on a straight only gets called where the car is going quickly and it's clear of the last one
		var fast: bool = absf(k[int(c_s / step) % n]) < K_ON and track.sample(track.PROF, c_s) > 30.0
		if fast and (added.is_empty() or track.rel(c_s - added[-1]) > 150.0):
			added.append(c_s)
			notes.append(_straight_note(c_s, "jump" if jump else "crest", "jump" if jump else "over crest", "JUMP" if jump else "CREST"))
	notes.sort_custom(func(a, b): return a.s < b.s)

## Where the road narrows by NARROW_DROP or more within NARROW_M: called "narrows" ahead of the narrow, on the
## corner there or on a straight. Needs the road's half width per sample (Track.HW); a track without it has none.
func _add_narrows() -> void:
	var n := track.n
	if track.HW.size() != n:
		return
	var span := maxi(1, roundi(NARROW_M / track.step))
	var starts: Array = []
	var inside := _drop(n - 1, span) >= NARROW_DROP
	for i in n:
		var narrow := _drop(i, span) >= NARROW_DROP
		if narrow and not inside:
			starts.append(i)
		inside = narrow
	var added := NAN ## where the last straight narrows call was made
	for i in starts:
		var s_n: float = i * track.step
		var corner := _corner_at(s_n)
		if not corner.is_empty():
			if not corner.mods.has("narrows"):
				corner.mods.append("narrows")
			continue
		if is_nan(added) or track.rel(s_n - added) > 150.0:
			added = s_n
			notes.append(_straight_note(s_n, "narrows", "narrows", "NARROWS"))
	notes.sort_custom(func(a, b): return a.s < b.s)

## The share of the road's half width lost between sample i and span samples on.
func _drop(i: int, span: int) -> float:
	var n := track.n
	return 1.0 - track.HW[(i + span) % n] / maxf(track.HW[i], 1e-6)

## The corner (a note that turns) whose run, from 30 m before it starts to 10 m past its end, takes in s; {} if none.
func _corner_at(s: float) -> Dictionary:
	for note in notes:
		if note.dir == 0:
			continue
		var into := track.rel(s - note.s)
		if into >= -30.0 and into <= track.rel(note.e - note.s) + 10.0:
			return note
	return {}

## A call on a straight at s (m): a 20 m note with what it says and the HUD tag. call: the distance (m) ahead at
## which it is called (0 = as the car reaches it).
func _straight_note(s: float, grade: String, say: String, tag: String, call := -1.0) -> Dictionary:
	var note := {"s": track.wrap_s(s - 10.0), "e": track.wrap_s(s + 10.0), "apex": track.wrap_s(s), "dir": 0,
		"grade": grade, "turn": 0.0, "radius": INF, "mods": [], "caution": false, "link": "", "dist": 0,
		"say": say, "tag": tag}
	if call >= 0.0:
		note["call"] = call
	return note

## The notes of a rally stage that finishes finish_m (m from the start line): the track's notes plus "200 to
## finish" and "flying finish" called before the line. A copy with its own links, so the cached track notes
## stay as they are.
static func with_finish(base: PaceNotes, finish_m: float) -> PaceNotes:
	var pn := PaceNotes.new(base.track, false)
	for note in base.notes:
		var c: Dictionary = note.duplicate(true)
		c.link = ""
		c.dist = 0
		c.caution = false
		pn.notes.append(c)
	for fc in FINISH_CALLS:
		# called as the car reaches its mark, so the note starts on the mark (not 10 m before it, as a crest's does)
		var fnote := pn._straight_note(finish_m - fc[0], "finish", fc[1], fc[2], 0.0)
		fnote.s = pn.track.wrap_s(finish_m - fc[0])
		fnote.e = pn.track.wrap_s(finish_m - fc[0] + 10.0)
		pn.notes.append(fnote)
	pn.notes.sort_custom(func(a, b): return a.s < b.s)
	pn._link()
	return pn

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
	if note.dir == 0 and note.has("say"):
		return note.say
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
	if note.dir == 0 and note.has("tag"):
		return note.tag
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
	if dist_to <= 0 or (note.dir == 0 and note.has("tag")):
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

## Braking-cue state for a corner `dist_to_corner` metres ahead: returns {brake, brake_dist, urgency, countdown}.
## `brake` is true only when the car is faster than the corner allows (by BRAKE_MIN_DROP) and at or past its braking point.
static func brake_cue(dist_to_corner: float, v: float, v_corner: float, decel: float) -> Dictionary:
	var spd := maxf(0.0, v)
	var d_brake := braking_distance(spd, v_corner, decel)
	var too_fast := is_finite(v_corner) and spd > v_corner + BRAKE_MIN_DROP and d_brake > 0.0
	var trigger := d_brake * BRAKE_MARGIN
	var at_point := too_fast and dist_to_corner <= trigger
	var urgency := 0.0
	if at_point:
		urgency = clampf((trigger - dist_to_corner) / maxf(25.0, d_brake * 0.4) + 0.25, 0.25, 1.0)
	return {"brake": at_point, "brake_dist": d_brake, "urgency": urgency, "countdown": countdown_metres(dist_to_corner)}

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
