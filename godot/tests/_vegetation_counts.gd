## Headless probe: what the open world plants, counted from the plant records (headless reads MultiMesh transforms
## back as identity, so nothing here reads instance data back). For each spot and graphics preset: the planted cells,
## the instances per kind, the grass blades they make (patches x blades in the mesh), instances per cell and the draw
## ranges the cells get, and the blades standing round the camera (all round, before frustum culling: a blade counts
## while it is nearer than the middle of its sink band); then the trees (baked + generated) and the fence-line shrubs
## of the town builder.
##   godot --headless --path godot -s tests/_vegetation_counts.gd [-- res://path/to/another/vegetation.gd]
extends SceneTree

const SPOTS := {"meadow": Vector2(1500, -1200), "wheat": Vector2(-1640, -60), "town": Vector2(0, 0), "festival": Vector2.INF}
const GRASS_KINDS := ["GrassPatch", "GrassPatchLow", "GrassTuft", "WheatPatch", "WheatPatchLow"]

func _initialize() -> void:
	var map := TownMap.load_map("brzeszcze")
	var args := OS.get_cmdline_user_args()
	var veg: Node3D = load(args[0] if args.size() > 0 else "res://scripts/world/vegetation.gd").new()
	if not veg.setup(map):
		print("vegetation did not set up")
		quit(1)
		return
	root.add_child(veg)
	var blades := {}
	for kind in veg.meshes:
		blades[kind] = _blades(veg.meshes[kind])
	print("blades per mesh ", blades)
	for q in [2, 3, 0]:
		veg.set_quality(q)
		print("== quality %d %s" % [q, veg.GRASS_QUALITY[q]])
		for name in SPOTS:
			var p: Vector2 = SPOTS[name]
			if p == Vector2.INF:
				var sp: Array = map.spots["festival"]
				p = Vector2(sp[0], sp[1])
			# only this spot's plants: free everything, plant from empty
			for k in veg.cells.keys():
				veg._free_cell(k)
			veg.queue.clear()
			veg.queued.clear()
			veg._last_cell = Vector2i(1 << 30, 1 << 30)
			veg.recorded = {}
			veg.record = true
			var t0 := Time.get_ticks_usec()
			veg.update_around(p)
			veg.plant_all()
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			veg.record = false
			var per := {}
			var ranges := {}
			for k in veg.cells:
				for c in (veg.cells[k] as Node3D).get_children():
					var mmi := c as MultiMeshInstance3D
					if mmi == null:
						continue
					var kind := String(mmi.name)
					if not per.has(kind):
						per[kind] = [0, 0, 0] # cells, instances, max per cell
					per[kind][0] += 1
					per[kind][1] += mmi.multimesh.instance_count
					per[kind][2] = maxi(per[kind][2], mmi.multimesh.instance_count)
					ranges[kind] = "%.0f-%.0f m%s" % [mmi.visibility_range_begin, mmi.visibility_range_end,
						" fade %.0f" % mmi.visibility_range_end_margin if mmi.visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED else ""]
			var total_blades := 0
			var qd: Dictionary = veg.GRASS_QUALITY[q]
			var near := float(qd.near)
			var far := float(qd.far) - minf(veg.FAR_FADE, float(qd.far) * 0.5) * 0.5
			var tuft := float(qd.get("tuft", 0.0)) - 30.0
			var standing := 0
			var bushes := 0
			for kind in veg.recorded:
				for o in veg.recorded[kind]:
					var d := Vector2(o.x, o.z).distance_to(p)
					var b := int(blades.get(kind, 0))
					if kind == "GrassPatch" or kind == "WheatPatch":
						standing += b if d < near - veg.HANDOVER * 0.5 else 0
					elif kind == "GrassPatchLow" or kind == "WheatPatchLow":
						standing += b if d < far and d >= near - veg.HANDOVER * 0.5 else 0
					elif kind == "GrassTuft":
						standing += b if d < tuft else 0
					elif kind == "BushCluster":
						bushes += 1 if d < float(qd.get("bush", 80.0)) else 0
			var line := []
			for kind in per:
				var n: int = per[kind][1]
				if kind in GRASS_KINDS:
					total_blades += n * int(blades.get(kind, 0))
				line.append("%s %d (%d cells, avg %d max %d, %s)" % [kind, n, per[kind][0], n / maxi(1, per[kind][0]), per[kind][2], ranges[kind]])
			print("%-9s %3d cells %6.0f ms  blades planted %.2f M, standing round the camera %.2f M (grass and wheat), %d bushes in range" % [name, veg.cells.size(), ms, total_blades / 1e6, standing / 1e6, bushes])
			for l in line:
				print("            ", l)
			print("            radius %.0f m, far radius %.0f m" % [veg.radius() if veg.has_method("radius") else veg.RADIUS, veg.far_radius() if veg.has_method("far_radius") else 0.0])
	# driving: 140 km/h at 40 fps across the meadow, BUDGET_USEC of planting a frame as in the game. For every cell
	# planted, how far its nearest plant still was from where its plants first show (negative: it popped in view)
	for q in [2, 3]:
		veg.set_quality(q)
		var qd: Dictionary = veg.GRASS_QUALITY[q]
		var p := Vector2(600.0, -1200.0)
		veg.update_around(p)
		veg.plant_all()
		var worst := INF
		var worst_far := INF
		var frames := 0
		var slow := 0.0
		var max_layer := 0.0
		var seen := {}
		for k in veg.cells:
			seen[k] = true
		var step := 140.0 / 3.6 / 40.0
		while p.x < 2400.0:
			p.x += step
			frames += 1
			var t0 := Time.get_ticks_usec()
			veg.update_around(p)
			var t1 := Time.get_ticks_usec()
			while not veg.queue.is_empty():
				var l0 := Time.get_ticks_usec()
				veg.run_queue(1)
				max_layer = maxf(max_layer, (Time.get_ticks_usec() - l0) / 1000.0)
				if Time.get_ticks_usec() - t1 >= veg.BUDGET_USEC:
					break
			slow = maxf(slow, (Time.get_ticks_usec() - t0) / 1000.0)
			for k in veg.cells:
				if seen.has(k) or veg.queued.has(k):
					continue
				seen[k] = true
				var far: bool = k >= veg.FAR_KEY
				var size: float = veg.FAR_CELL if far else veg.CELL
				var c: Vector2 = veg.cells[k].get_meta("centre")
				var d := maxf(0.0, c.distance_to(p) - size * 0.7071)
				var m := d - (maxf(float(qd.tuft), float(qd.bush)) if far else float(qd.far))
				if m < 0.0 and OS.get_environment("VEG_DEBUG") != "":
					print("  late: %s cell %s centre %s at %s, %.0f m short, queue %d" % ["far" if far else "near", k, c, p, m, veg.queue.size()])
				if far:
					worst_far = minf(worst_far, m)
				else:
					worst = minf(worst, m)
		print("drive q%d: %d frames, worst frame %.1f ms, slowest layer %.1f ms; a planted cell's nearest plant was at least %.0f m (near) / %.0f m (far) beyond where it shows" % [q, frames, slow, max_layer, worst, worst_far])
	veg.free()
	# trees and fence shrubs of the town builder
	var b := TownBuilder.new(map, Node3D.new())
	var t0 := Time.get_ticks_usec()
	var recs: Array = b._tree_records(preload("res://scripts/ui/surroundings.gd").tree_meshes())
	var near := 0
	var cards := 0
	var extra := 0
	for rec in recs:
		if String(rec[0]) == "":
			cards += int(rec[2])
		elif String(rec[0]).begins_with("#"):
			extra += int(rec[2])
		else:
			near += int(rec[2])
	print("trees: %d full-mesh instances, %d impostor cards, %d of them generated (%d baked) in %.0f ms" % [near, cards, extra, map.raw.get("trees", []).size() / 3, (Time.get_ticks_usec() - t0) / 1000.0])
	t0 = Time.get_ticks_usec()
	var fr: Array = b._fence_records(b._model("Fence", b._fallback_fence))
	var shrubs := 0
	for cell in fr[2]:
		shrubs += int(cell[1])
	var panels := 0
	for cell in fr[0]:
		panels += int(cell[1])
	print("fences: %d panels, %d fence-line shrubs in %d cells, in %.0f ms" % [panels, shrubs, (fr[2] as Array).size(), (Time.get_ticks_usec() - t0) / 1000.0])
	b.root.free()
	quit()

## Blades in a grass mesh: its tip vertices (vertex colour G, the height along the blade, is 1 at a tip).
static func _blades(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var cols = arr[Mesh.ARRAY_COLOR]
		if cols == null or (cols as PackedColorArray).is_empty():
			return 0
		for c in cols as PackedColorArray:
			if c.g > 0.99 and c.b < 0.5:
				n += 1
	return n
