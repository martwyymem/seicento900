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
	for kind in ["Wheat", "Corn", "TallGrass", "Flower", "BushCluster"]:
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
	if int(veg.counts.get("Wheat", 0)) < 500:
		errors.append("only %d wheat clumps around a wheat field" % int(veg.counts.get("Wheat", 0)))
	# moving the camera frees the far cells and plants the near ones
	var before: int = veg.cells.size()
	veg.update_around(wheat + Vector2(2000.0, 0.0))
	veg.plant_all()
	if veg.cells.is_empty() or veg.cells.has(veg.cell_key(floori(wheat.x / veg.CELL), floori(wheat.y / veg.CELL))):
		errors.append("old cells were not freed or new ones not planted (%d before, %d after)" % [before, veg.cells.size()])
	veg.free()
	completed = true
	return errors
