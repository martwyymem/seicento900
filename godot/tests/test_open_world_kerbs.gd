## Kerbs and pavements in the open world are solid: the car rides up onto them and is jolted and slowed doing it,
## while the carriageway stays flat.
extends RefCounted

var completed := false
const DT := 1.0 / 120.0

func run() -> Array:
	var errors: Array[String] = []
	var map := TownMap.load_map("brzeszcze")
	if map == null:
		errors.append("data/world/brzeszcze.json did not load")
		completed = true
		return errors
	var spot := _find_pavement(map)
	if spot.is_empty():
		errors.append("no pavement found in the town")
		completed = true
		return errors
	var edge: Vector2 = spot.edge
	var out: Vector2 = spot.out
	if map.kerb_at(edge.x - out.x * 0.5, edge.y - out.y * 0.5) != 0.0:
		errors.append("the carriageway reads as kerb")
	if absf(map.kerb_at(edge.x + out.x * 0.8, edge.y + out.y * 0.8) - TownMap.KERB_H) > 1e-4:
		errors.append("the pavement does not read as a kerb height")
	# roll at the kerb at 40 km/h, square on
	var fc := FreeCar.new(map)
	fc.place(edge - out * 8.0, atan2(out.y, out.x))
	fc.car.vx = out.x * 11.0
	fc.car.vy = out.y * 11.0
	fc.car.gear = 1
	var struck := false
	var peak_z := -INF
	var base_z := fc.z
	for i in int(1.0 / DT):
		fc.step(DT, 0.0, 0.0, 0.0)
		peak_z = maxf(peak_z, fc.z)
		if not fc.hits.is_empty():
			struck = true
			fc.hits.clear()
	if not struck:
		errors.append("driving into a kerb at 40 km/h made no impact")
	if peak_z - base_z < TownMap.KERB_H * 0.8:
		errors.append("the car did not rise onto the kerb (%.2f m)" % (peak_z - base_z))
	completed = true
	return errors

## An edge of a pavement shape that borders a carriageway, with open pavement beyond it: {edge, out}.
func _find_pavement(map: TownMap) -> Dictionary:
	for poly in map.pave_polys:
		if poly.size() < 4:
			continue
		for k in poly.size():
			var a := poly[k]
			var b := poly[(k + 1) % poly.size()]
			var d := b - a
			if d.length() < 6.0:
				continue
			var mid := (a + b) * 0.5
			var nrm := d.normalized().orthogonal()
			for sgn in [1.0, -1.0]:
				var o: Vector2 = nrm * sgn
				if map.kerb_at(mid.x + o.x * 0.8, mid.y + o.y * 0.8) > 0.0 and map.kerb_at(mid.x - o.x * 0.5, mid.y - o.y * 0.5) == 0.0 \
						and not map.road_at(mid.x - o.x * 1.0, mid.y - o.y * 1.0).is_empty() \
						and map.road_at(mid.x - o.x * 8.0, mid.y - o.y * 8.0).is_empty() == false \
						and map.kerb_at(mid.x + o.x * 1.3, mid.y + o.y * 1.3) > 0.0:
					return {"edge": mid, "out": o}
	return {}
