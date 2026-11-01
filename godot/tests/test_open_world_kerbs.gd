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

## A street edge with a pavement beyond it, clear of junctions and buildings: {edge, out}.
func _find_pavement(map: TownMap) -> Dictionary:
	for ri in map.road_pts.size():
		if map.road_pave[ri] != 1:
			continue
		var pts := map.road_pts[ri]
		for i in range(1, pts.size() - 1):
			if map.road_jd[ri][i - 1] < 12.0 or map.road_jd[ri][i] < 12.0 or map.road_jd[ri][i + 1] < 12.0:
				continue
			var nrm := (pts[i + 1] - pts[i - 1]).normalized().orthogonal()
			var edge := pts[i] + nrm * map.road_w[ri] * 0.5
			if map.kerb_at(edge.x + nrm.x * 0.8, edge.y + nrm.y * 0.8) > 0.0 \
					and map.road_at(edge.x - nrm.x * 8.0, edge.y - nrm.y * 8.0).is_empty() == false \
					and not map.inside_building(edge + nrm * 5.0) and map.road_at(edge.x + nrm.x * 5.0, edge.y + nrm.y * 5.0).is_empty():
				return {"edge": edge, "out": nrm}
	return {}
