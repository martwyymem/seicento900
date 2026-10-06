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
