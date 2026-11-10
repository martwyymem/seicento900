## The open world's points of interest, free of the 3D scene so the tests can run them: the speed traps and the
## discoverable landmarks of the Brzeszcze map, what state each is in for a save (unknown, known, discovered), the
## marker dictionaries the HUD draws on the satnav and the big map, the one-line explanation shown when one is
## selected, and the counts for the progress summary.
##
## A new kind of point (drift zones, mission beacons) is an entry in KINDS, a finder that returns Poi objects
## and a `match` arm in state() / info() / label_text(); the HUD draws any kind from the marker's colour and shape.
class_name Poi
extends RefCounted

enum State { UNKNOWN, KNOWN, DISCOVERED }

const TRAP := "trap"
const LANDMARK := "landmark"
const DISCOVER_RADIUS := 70.0 ## m from a landmark that finds it
const MERGE_RADIUS := 80.0 ## places this close (a churchyard's chapels, a station's three platforms) are one landmark
const LANDMARK_FANS := 1000
const TRAP_COUNT := 9
const TRAP_SPACING := 600.0 ## m between two traps
const TRAP_STARS := [80.0, 100.0, 120.0] ## km/h for one, two and three stars
const UNKNOWN_COLOR := Color(0.72, 0.75, 0.82, 0.85)

## What a place of the map is called when found, and the order in which a cluster picks its name.
const LANDMARK_LABELS := {
	"museum": "Museum", "mineshaft": "Mine shaft", "stadium": "Stadium", "church": "Church", "monument": "Monument",
	"station": "Railway station", "cinema": "Cinema", "water_tower": "Water tower", "chimney": "Chimney",
}

## Per kind: the title on the info line, the plural for the counts, the marker colour and shape ("diamond",
## "square"), the one-line rule, and the first-time explanation (shown once, inside the first banner).
const KINDS := {
	TRAP: {
		"title": "SPEED TRAP", "plural": "Speed traps", "color": Color("#4aa3ff"), "shape": "diamond",
		"how": "drive through as fast as you can",
		"intro": "Signed stretches of road: drive through as fast as you can. 80, 100 and 120 km/h earn stars, every new best pays fans.",
	},
	LANDMARK: {
		"title": "LANDMARK", "plural": "Landmarks", "color": Color("#52d6b2"), "shape": "square",
		"how": "drive there to find out what it is",
		"intro": "Places that make Brzeszcze. A ? on the map is one you have not found: drive up to it to see what it is.",
	},
}

var kind := ""
var id := "" ## the key in WorldProgress (traps: the trap id; landmarks: the name, with the place added when two share it)
var name := ""
var pos := Vector2.ZERO
var dir := Vector2.RIGHT ## traps: the direction of the road
var sub := "" ## landmarks: what kind of place it is
var members := PackedStringArray() ## landmarks: the names of every map place merged into this one

# ================================================================================================ building the list

## Every point of interest of a map: the speed traps (as `OpenWorld.traps` lists them) first, then the landmarks.
static func build(map: TownMap, traps: Array) -> Array[Poi]:
	var list: Array[Poi] = []
	for t in traps:
		var p := Poi.new()
		p.kind = TRAP
		p.id = String(t.id)
		p.name = String(t.name)
		p.pos = t.pos
		p.dir = t.dir
		list.append(p)
	list.append_array(find_landmarks(map))
	return list

## The long straights of the main roads, at least TRAP_SPACING apart, longest first:
## [{id, pos, dir, name, road}] (OpenWorld stands a sign at each).
static func find_traps(map: TownMap) -> Array:
	var cands := []
	for ri in map.road_pts.size():
		if not map.road_kind[ri] in ["secondary", "tertiary", "primary", "unclassified"]:
			continue
		var pts := map.road_pts[ri]
		var i := 0
		while i < pts.size() - 1:
			var j := i
			var run := 0.0
			var d0 := (pts[i + 1] - pts[i]).normalized()
			while j < pts.size() - 1 and (pts[j + 1] - pts[j]).normalized().dot(d0) > 0.995:
				run += pts[j].distance_to(pts[j + 1])
				j += 1
			if run > 220.0:
				cands.append([run, pts[i].lerp(pts[j], 0.5), d0, ri])
			i = maxi(j, i + 1)
	cands.sort_custom(func(a, b): return a[0] > b[0])
	var traps := []
	for c in cands:
		var ok := true
		for t in traps:
			if (t.pos as Vector2).distance_to(c[1]) < TRAP_SPACING:
				ok = false
		if ok:
			var street: String = map.road_name[c[3]]
			traps.append({"id": "trap_%d_%d" % [int(c[1].x), int(c[1].y)], "pos": c[1], "dir": c[2], "road": c[3],
				"name": OpenWorld.street_label(street) if street != "" else "Speed trap"})
		if traps.size() >= TRAP_COUNT:
			break
	return traps

## The discoverable places of the map inside the playable area, with places within MERGE_RADIUS of each other
## merged into one (the museum before the chapel beside it). Deterministic: the same map gives the same list.
static func find_landmarks(map: TownMap) -> Array[Poi]:
	var cands := []
	var rank := LANDMARK_LABELS.keys()
	for pl in map.places:
		var k := String(pl.k)
		var n := String(pl.name).strip_edges()
		if not LANDMARK_LABELS.has(k) or n == "":
			continue
		var at := Vector2(float(pl.x), float(pl.y))
		if map.play.size() > 2 and not Geometry2D.is_point_in_polygon(at, map.play):
			continue
		cands.append([rank.find(k) + (100 if n.begins_with("Kaplica") else 0), n, at, k])
	cands.sort_custom(func(a, b):
		if a[0] != b[0]:
			return a[0] < b[0]
		if a[1] != b[1]:
			return a[1] < b[1]
		return a[2].x < b[2].x or (a[2].x == b[2].x and a[2].y < b[2].y))
	var list: Array[Poi] = []
	for c in cands:
		var merged := false
		for p in list:
			if p.pos.distance_to(c[2]) <= MERGE_RADIUS:
				p.members.append(c[1])
				merged = true
				break
		if merged:
			continue
		var p := Poi.new()
		p.kind = LANDMARK
		p.name = c[1]
		p.pos = c[2]
		p.sub = "Chapel" if (c[1] as String).begins_with("Kaplica") else String(LANDMARK_LABELS[c[3]])
		p.members = PackedStringArray([c[1]])
		list.append(p)
	# the key is the name; two sites that share one (seven "Kaplica") get their place added
	var seen := {}
	for p in list:
		seen[p.name] = int(seen.get(p.name, 0)) + 1
	for p in list:
		p.id = p.name if seen[p.name] == 1 else "%s @%d,%d" % [p.name, roundi(p.pos.x / 10.0) * 10, roundi(p.pos.y / 10.0) * 10]
	return list

# ================================================================================================ state

static func stars(kmh: float) -> int:
	var n := 0
	for t in TRAP_STARS:
		if kmh >= float(t):
			n += 1
	return n

static func star_text(n: int) -> String:
	return "★".repeat(clampi(n, 0, 3)) + "☆".repeat(3 - clampi(n, 0, 3))

## The best speed through a trap (km/h); 0 when it was never driven.
func best_kmh(prog: WorldProgress) -> float:
	return float(prog.traps.get(id, 0.0)) if kind == TRAP else 0.0

func is_discovered(prog: WorldProgress) -> bool:
	match kind:
		TRAP:
			return prog.traps.has(id)
		LANDMARK:
			# saves from before the cluster merge keyed a landmark by its bare name
			return prog.landmarks.has(id) or (id == name and prog.landmarks.has(name))
	return false

## UNKNOWN: a landmark not found yet (the map shows a ?). KNOWN: a speed trap not driven yet (it is signed in the
## world, so its kind is no secret). DISCOVERED: found / driven.
func state(prog: WorldProgress) -> int:
	if is_discovered(prog):
		return State.DISCOVERED
	return State.KNOWN if kind == TRAP else State.UNKNOWN

# ================================================================================================ text and markers

## The line at the foot of the big map when this point is selected: what it is and what to do.
func info(prog: WorldProgress) -> String:
	match kind:
		TRAP:
			var best := best_kmh(prog)
			var head := "SPEED TRAP · %s · %s" % [name, KINDS[TRAP].how]
			if best <= 0.0:
				return "%s · not driven yet (%s %d · %s %d · %s %d km/h)" % [head, star_text(1), TRAP_STARS[0], star_text(2), TRAP_STARS[1], star_text(3), TRAP_STARS[2]]
			var n := stars(best)
			var tail := " · best %d km/h %s" % [int(best), star_text(n)]
			if n < 3:
				tail += " (%d km/h for %s)" % [TRAP_STARS[n], star_text(n + 1)]
			return head + tail
		LANDMARK:
			if is_discovered(prog):
				return "LANDMARK · %s · %s · discovered" % [name, sub.to_lower()]
			return "UNDISCOVERED · %s" % KINDS[LANDMARK].how
	return name

## The short text beside the marker on the big map; empty draws none.
func label_text(prog: WorldProgress) -> String:
	match kind:
		TRAP:
			var best := best_kmh(prog)
			return "Speed trap" if best <= 0.0 else "%d km/h %s" % [int(best), star_text(stars(best))]
		LANDMARK:
			return name if is_discovered(prog) else ""
	return name

## The dictionary the HUD draws: a dim ? for an unknown landmark, the kind's colour and shape otherwise. `routed`
## marks the one the GPS route runs to.
func marker(prog: WorldProgress, routed := false) -> Dictionary:
	var st := state(prog)
	var k: Dictionary = KINDS[kind]
	return {"pos": pos, "color": UNKNOWN_COLOR if st == State.UNKNOWN else k.color, "label": label_text(prog),
		"info": info(prog), "kind": "poi", "poi": kind, "id": id, "shape": k.shape, "state": st,
		"unknown": st == State.UNKNOWN, "routed": routed}

static func markers(list: Array, prog: WorldProgress, routed_id := "") -> Array:
	var out := []
	for p: Poi in list:
		out.append(p.marker(prog, routed_id != "" and p.id == routed_id))
	return out

## How many of each kind are found: {kind: [found, total]}, in the order of KINDS.
static func counts(list: Array, prog: WorldProgress) -> Dictionary:
	var c := {}
	for k in KINDS:
		c[k] = [0, 0]
	for p: Poi in list:
		c[p.kind][1] += 1
		if p.is_discovered(prog):
			c[p.kind][0] += 1
	return c

## "Speed traps 3/9 · Landmarks 5/14 · Roads 212/1830": the progress line of the big map.
static func summary(list: Array, prog: WorldProgress, roads_found: int, roads_total: int) -> String:
	var c := counts(list, prog)
	var parts := PackedStringArray()
	for k in KINDS:
		parts.append("%s %d/%d" % [KINDS[k].plural, c[k][0], c[k][1]])
	parts.append("Roads %d/%d" % [roads_found, roads_total])
	return " · ".join(parts)

static func find(list: Array, poi_id: String) -> Poi:
	for p: Poi in list:
		if p.id == poi_id:
			return p
	return null

# ================================================================================================ discovery

## The landmarks the car at `at` finds just now: marked in the save and returned.
static func discover_near(list: Array, prog: WorldProgress, at: Vector2) -> Array[Poi]:
	var found: Array[Poi] = []
	for p: Poi in list:
		if p.kind == LANDMARK and not p.is_discovered(prog) and p.pos.distance_to(at) < DISCOVER_RADIUS:
			prog.landmarks[p.id] = true
			found.append(p)
	return found

## A trap driven at `kmh`: the best speed is kept (and the trap counts as driven). Returns true on a new best.
func record_run(prog: WorldProgress, kmh: float) -> bool:
	if kind != TRAP:
		return false
	var best := best_kmh(prog)
	if kmh > best or not prog.traps.has(id):
		prog.traps[id] = snappedf(maxf(kmh, 0.1), 0.1)
		return kmh > best
	return false

## The first-time explanation of a kind: the text once, then "" (remembered in the save).
static func take_intro(prog: WorldProgress, poi_kind: String) -> String:
	if prog.tips.has(poi_kind):
		return ""
	prog.tips[poi_kind] = true
	return String(KINDS[poi_kind].intro)

# ================================================================================================ the minimap

## The markers shown on the satnav disc: only points (kind "poi") within `reach` of the disc's radius, nearest
## first, at most `limit` of them, so the disc never turns to confetti.
static func minimap_pois(marker_list: Array, car_pos: Vector2, radius: float, limit := 8, reach := 0.9) -> Array:
	var near := []
	for m in marker_list:
		if m.get("kind", "") != "poi":
			continue
		var d := (m.pos as Vector2).distance_to(car_pos)
		if d <= radius * reach:
			near.append([d, m])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var out := []
	for e in near.slice(0, limit):
		out.append(e[1])
	return out
