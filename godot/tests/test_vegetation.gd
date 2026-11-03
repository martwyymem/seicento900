## Open-world vegetation: wheat and maize stand in the fields the land map paints, grass and flowers on the plain
## ground, nothing on a road, and the cells around a moving camera are planted and freed.
extends RefCounted

var completed := false

func run() -> Array:
	var errors: Array[String] = []
	var map := TownMap.load_map("brzeszcze")
	var veg: Node3D = preload("res://scripts/world/vegetation.gd").new()
	if map == null or not veg.setup(map):
		errors.append("vegetation could not set up (map, land map or roadside.glb missing)")
		veg.free()
		completed = true
		return errors
	for kind in ["GrassPatch", "GrassPatchLow", "WheatPatch", "WheatPatchLow", "Corn", "Flower", "BushCluster"]:
		if not veg.meshes.has(kind):
			errors.append("roadside.glb has no %s mesh (rebuild tools/blender/build_roadside.py)" % kind)
	# a wheat field and a maize field found in the land map
	var wheat := Vector2(-1640.0, -60.0)
	var wheat_ok := false
	for dx in range(-40, 41, 8):
		for dy in range(-40, 41, 8):
			if veg._crop_at(veg._px(wheat.x + dx, wheat.y + dy)) == 1:
				wheat_ok = true
	if not wheat_ok:
		errors.append("the land map shows no ripe field near the probe point (map rebaked? move the point)")
	veg.update_around(wheat)
	veg.plant_all()
	if int(veg.counts.get("WheatPatchLow", 0)) < 500:
		errors.append("only %d wheat patches around a wheat field" % int(veg.counts.get("WheatPatchLow", 0)))
	# a meadow carpet: grass patches near the town's open ground, the dense ones only nearest the camera
	veg.update_around(Vector2(1500.0, -1200.0))
	veg.plant_all()
	var low := int(veg.counts.get("GrassPatchLow", 0))
	if low < 2000:
		errors.append("only %d grass patches around open ground" % low)
	if int(veg.counts.get("GrassPatch", 0)) != low:
		errors.append("the dense and sparse grass differ in patch count (%d / %d)" % [int(veg.counts.get("GrassPatch", 0)), low])
	# nothing stands on a road or a pavement (the blurred land map let grass over road edges and dirt tracks): at the
	# festival field's track and along ul. Bór, where it was seen
	var on_road := 0
	var checked := 0
	veg.record = true
	for spot in ["festival", "bor_stage"]:
		var sp: Array = map.spots[spot]
		veg.update_around(Vector2(sp[0], sp[1]))
		veg.plant_all()
	var r := _plants_on_road(veg, map)
	on_road += r[0]
	checked += r[1]
	veg.record = false
	if checked == 0 or on_road > 0:
		errors.append("%d of %d plants stand on a road or pavement" % [on_road, checked])
	veg.update_around(Vector2(1500.0, -1200.0))
	veg.plant_all()
	# Low quality draws no dense patches
	veg.set_quality(0)
	veg.update_around(Vector2(1500.0, -1200.0))
	veg.plant_all()
	if int(veg.counts.get("GrassPatch", 0)) != 0 or int(veg.counts.get("GrassPatchLow", 0)) < 1000:
		errors.append("Low quality: %d dense, %d sparse grass patches" % [int(veg.counts.get("GrassPatch", 0)), int(veg.counts.get("GrassPatchLow", 0))])
	veg.set_quality(2)
	# moving the camera frees the far cells and plants the near ones
	var before: int = veg.cells.size()
	veg.update_around(wheat + Vector2(2000.0, 0.0))
	veg.plant_all()
	if veg.cells.is_empty() or veg.cells.has(veg.cell_key(floori(wheat.x / veg.CELL), floori(wheat.y / veg.CELL))):
		errors.append("old cells were not freed or new ones not planted (%d before, %d after)" % [before, veg.cells.size()])
	veg.free()
	completed = true
	return errors

## [plants within 0.75 m of an at-grade road or on a pavement, plants checked] among the recorded plants.
static func _plants_on_road(veg, map: TownMap) -> Array:
	var on_road := 0
	var checked := 0
	for kind in ["GrassPatchLow", "Flower", "BushCluster"]:
		for o in veg.recorded.get(kind, PackedVector3Array()):
			checked += 1
			var hit: Dictionary = map.road_at(o.x, o.z, -INF, 0.75)
			if (not hit.is_empty() and float(hit.deck) < 1.0) or map.kerb_at(o.x, o.z) > 0.0:
				on_road += 1
	return [on_road, checked]
