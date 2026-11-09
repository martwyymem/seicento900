## The baker's generated street lamps (tools/build_open_world.py): about a lamp every 30-40 m along built-up streets,
## each on a verge (not on the road, in a building, on the S1 or a track), solid to the car, and the lamp grid the open
## world's real lights use finds the nearest ones.
extends RefCounted

var completed := false

func run() -> Array:
	var errors: Array[String] = []
	var map := TownMap.load_map("brzeszcze")
	if map == null:
		errors.append("data/world/brzeszcze.json did not load")
		completed = true
		return errors
	var lamps := TownMap._flat(map.raw.get("lamps", []))
	if lamps.size() < 3000 or lamps.size() > 9000:
		errors.append("%d street lamps; the baker should place several thousand" % lamps.size())
	var on_road := 0
	var in_building := 0
	var on_s1 := 0
	var on_track := 0
	var not_solid := 0
	var close := 0
	for p in lamps:
		var hit := map.nearest_road(p, 20.0)
		if not hit.is_empty():
			var edge: float = float(hit.dist) - map.road_w[hit.road] * 0.5
			if edge < 0.5:
				on_road += 1
			if edge < 8.0 and map.road_kind[hit.road] in ["motorway", "motorway_link", "trunk"]:
				on_s1 += 1
			if edge < 3.0 and map.road_kind[hit.road] == "track":
				on_track += 1
		if map.inside_building(p):
			in_building += 1
		if map.posts_near(p, 0.1).is_empty():
			not_solid += 1
		close += 1 if _has_lamp_within(map, lamps, p, 10.0) else 0
	if on_road > 0:
		errors.append("%d lamps stand on a road" % on_road)
	if in_building > 0:
		errors.append("%d lamps stand inside a building" % in_building)
	if on_s1 > 0:
		errors.append("%d lamps stand beside the S1" % on_s1)
	if on_track > 10:
		errors.append("%d lamps stand beside a track" % on_track)
	if not_solid > 0:
		errors.append("%d lamps are not solid to the car" % not_solid)
	if close > 0:
		errors.append("%d lamps have another within 10 m" % close)
	_lookup(map, errors)
	completed = true
	return errors

func _has_lamp_within(_map: TownMap, lamps: PackedVector2Array, p: Vector2, r: float) -> bool:
	# a 16 m hash of the lamps, built on first use
	if _grid.is_empty():
		for q in lamps:
			var k := Vector2i(floori(q.x / 16.0), floori(q.y / 16.0))
			if not _grid.has(k):
				_grid[k] = PackedVector2Array()
			(_grid[k] as PackedVector2Array).append(q)
	var c := Vector2i(floori(p.x / 16.0), floori(p.y / 16.0))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for q in _grid.get(Vector2i(c.x + dx, c.y + dy), PackedVector2Array()):
				if q != p and q.distance_to(p) < r:
					return true
	return false

var _grid := {}

## TownBuilder.lamps_near: the nearest lamp heads, nearest first, within the radius, from a grid, equal to a brute-force scan.
func _lookup(map: TownMap, errors: Array[String]) -> void:
	var holder := Node3D.new()
	var b := TownBuilder.new(map, holder)
	b._build_lamps(holder) # fills lamp_spots and the grid, as the town build does
	if b.lamp_spots.size() != TownMap._flat(map.raw.get("lamps", [])).size():
		errors.append("the builder made %d lamp spots for the baked lamps" % b.lamp_spots.size())
	for probe in [Vector2(-1000.0, 2130.0), Vector2(300.0, 500.0), Vector2(1232.0, 308.0), Vector2(-512.0, 2043.0)]:
		var got := b.lamps_near(probe.x, probe.y, 14, 200.0)
		var all := []
		for q in b.lamp_spots:
			var d := Vector2(q.x, q.z).distance_squared_to(probe)
			if d < 40000.0:
				all.append(d)
		all.sort()
		var want: int = mini(14, all.size())
		if got.size() != want:
			errors.append("lamps_near found %d lamps at %s, a scan finds %d" % [got.size(), probe, want])
			continue
		for i in got.size():
			var d := Vector2(got[i].x, got[i].z).distance_squared_to(probe)
			if absf(d - float(all[i])) > 0.01:
				errors.append("lamps_near at %s: lamp %d is %.1f m away, the scan says %.1f" % [probe, i, sqrt(d), sqrt(float(all[i]))])
				break
	holder.free()
