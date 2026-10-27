## Open-world height: the car rides a bridge deck on the bridge and the ground under it, follows ponds and river
## banks down the drawn terrain (no plane over them), and its height never jumps along a road.
extends RefCounted

var completed := false
const STEP := 0.25 ## m between samples
const MAX_JUMP := 0.3 ## m per sample

func run() -> Array:
	var errors: Array[String] = []
	var map := TownMap.load_map("brzeszcze")
	if map == null:
		errors.append("data/world/%s.json did not load" % "brzeszcze")
		completed = true
		return errors
	_roads(map, errors)
	_bridges(map, errors)
	_banks(map, errors)
	completed = true
	return errors

## A car sitting at rest at (p, z) with the vertical contact run once.
func _settle(map: TownMap, p: Vector2, z: float) -> FreeCar:
	var fc := FreeCar.new(map)
	fc.place(p, 0.0)
	fc.z = z
	return fc

func _tick(fc: FreeCar, p: Vector2) -> void:
	var px := fc.car.x
	var py := fc.car.y
	fc.car.x = p.x
	fc.car.y = p.y
	fc._vertical(0.02, px, py, 900.0)

## Drives every raised road's centreline both ways: the height must not jump, and a bridge's deck is where it says.
func _roads(map: TownMap, errors: Array[String]) -> void:
	var worst := 0.0
	var worst_at := ""
	var checked := 0
	for ri in map.road_pts.size():
		if map.road_z[ri].is_empty() or map.road_len[ri] < 5.0:
			continue
		checked += 1
		for reverse in [false, true]:
			var s0 := map.road_len[ri] if reverse else 0.0
			var a: Array = map.along(ri, s0)
			var fc := _settle(map, a[0], map.ground(a[0].x, a[0].y) + map.deck_at(ri, a[2], a[3]))
			var last := fc.z
			var s := 0.0
			while s < map.road_len[ri]:
				var q: Array = map.along(ri, map.road_len[ri] - s if reverse else s)
				_tick(fc, q[0])
				if absf(fc.z - last) > worst:
					worst = absf(fc.z - last)
					worst_at = "road %d '%s' at %.0f m (%s)" % [ri, map.road_name[ri], s, q[0]]
				last = fc.z
				s += STEP
	if checked < 20:
		errors.append("only %d raised roads to drive" % checked)
	if worst > MAX_JUMP:
		errors.append("height jumps %.2f m in %.2f m on %s" % [worst, STEP, worst_at])

## On a bridge the deck holds the car; stood under it the car rides the ground; past the parapet it falls.
func _bridges(map: TownMap, errors: Array[String]) -> void:
	var tested := 0
	for ri in map.road_pts.size():
		if map.road_bridge[ri] != 1 or map.road_z[ri].is_empty() or map.road_len[ri] < 20.0:
			continue
		var mid: Array = map.along(ri, map.road_len[ri] * 0.5)
		var p: Vector2 = mid[0]
		var deck := map.deck_at(ri, mid[2], mid[3])
		if deck < 1.0:
			continue
		tested += 1
		var g := map.ground(p.x, p.y)
		var on := _settle(map, p, g + deck)
		if absf(on.support(p.x, p.y) - (g + deck)) > 0.05:
			errors.append("bridge %d '%s': car on the deck is held at %.2f, deck is %.2f" % [ri, map.road_name[ri], on.support(p.x, p.y), g + deck])
		var under := _settle(map, p, g)
		if absf(under.support(p.x, p.y) - g) > 0.05 and deck > FreeCar.UNDER_DECK - 1.0:
			errors.append("bridge %d '%s': car under the deck is lifted to %.2f (ground %.2f)" % [ri, map.road_name[ri], under.support(p.x, p.y), g])
		if deck > 1.2 and absf(under.support(p.x, p.y) - g) > 0.05:
			errors.append("bridge %d '%s': car on the ground below is lifted to %.2f (ground %.2f)" % [ri, map.road_name[ri], under.support(p.x, p.y), g])
		# beside the deck, beyond the parapet, no plane holds the car up
		var side := Vector2(-mid[1].y, mid[1].x)
		var beyond := p + side * (map.road_w[ri] * 0.5 + TownMap.PARAPET + 0.6)
		if map.road_at(beyond.x, beyond.y, g + deck, 0.0).is_empty():
			var off := _settle(map, beyond, g + deck)
			var gb := map.terrain(beyond.x, beyond.y)
			if absf(off.support(beyond.x, beyond.y) - gb) > 0.05 and map.decks_at(beyond.x, beyond.y, TownMap.DRIVE_REACH).size() == 1:
				errors.append("bridge %d '%s': a plane at %.2f holds the car beside the parapet (ground %.2f)" % [ri, map.road_name[ri], off.support(beyond.x, beyond.y), gb])
	if tested < 3:
		errors.append("only %d bridges tested" % tested)

## Walks a car across the ponds and river areas away from roads: it must ride exactly the drawn terrain (which slopes
## down the bank), never jump, and never float above it.
func _banks(map: TownMap, errors: Array[String]) -> void:
	var tested := 0
	var worst := 0.0
	var worst_at := ""
	var float_h := 0.0
	var float_at := ""
	for k in map.water_rings.size():
		var r := map.water_rects[k]
		if r.size.x < 60.0 or r.size.y < 60.0 or tested >= 12:
			continue
		var c := r.get_center()
		var from := Vector2(c.x - r.size.x * 0.5 - 40.0, c.y)
		var to := Vector2(c.x, c.y)
		var clear := true # a dyke track across the water stands up out of the bed (a wall to the car), walk elsewhere
		for q in range(0, int(from.distance_to(to)), 4):
			var pq := from.lerp(to, q / from.distance_to(to))
			if not map.road_at(pq.x, pq.y, -INF, 12.0).is_empty():
				clear = false
				break
		if not clear:
			continue
		tested += 1
		var fc := _settle(map, from, map.terrain(from.x, from.y))
		var last := fc.z
		var len := from.distance_to(to)
		var s := 0.0
		while s < len:
			var p := from.lerp(to, s / len)
			_tick(fc, p)
			var t := map.terrain(p.x, p.y)
			if fc.z - t > float_h:
				float_h = fc.z - t
				float_at = "pond %d at %s" % [k, p]
			if absf(fc.z - last) > worst:
				worst = absf(fc.z - last)
				worst_at = "pond %d at %s" % [k, p]
			last = fc.z
			s += STEP
	if tested < 3:
		errors.append("only %d ponds or river areas tested" % tested)
	if float_h > 0.05:
		errors.append("the car floats %.2f m above the terrain at %s" % [float_h, float_at])
	if worst > MAX_JUMP:
		errors.append("the car's height jumps %.2f m in %.2f m going into the water at %s" % [worst, STEP, worst_at])
