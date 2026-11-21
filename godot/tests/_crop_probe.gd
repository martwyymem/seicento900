## Headless probe: measures farmland crops in the open world (maize/corn, wheat, ploughed) across Wola and the whole
## play area: field areas (ha), mesh dimensions & triangle counts, instances per hectare per crop kind, plant
## height/width, nearest-neighbour & row gaps, active-ring and whole-map instance counts, draw calls, and draw ranges.
##   godot --headless --path godot -s tests/_crop_probe.gd
extends SceneTree

const VEG_SCRIPT := preload("res://scripts/world/vegetation.gd")

func _initialize() -> void:
	var map := TownMap.load_map("brzeszcze")
	if map == null:
		print("ERROR: failed to load brzeszcze map")
		quit(1)
		return
	var veg: Node3D = VEG_SCRIPT.new()
	if not veg.setup(map):
		print("ERROR: vegetation setup failed")
		quit(1)
		return
	root.add_child(veg)

	# 1. Mesh geometry audit (size, triangles, surfaces, projected silhouette)
	print("=== CROP MESHES (roadside.glb) ===")
	var mesh_info := {}
	for kind in veg.meshes:
		var m: Mesh = veg.meshes[kind]
		var aabb := m.get_aabb()
		var tris := 0
		var area_xz := 0.0 # upward projected area
		var area_side := 0.0 # lateral projected area (avg X and Z)
		var mats: Array[String] = []
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var mat := m.surface_get_material(s)
			mats.append(mat.resource_name if mat else "none")
			var n_idx := idx.size() if not idx.is_empty() else verts.size()
			tris += n_idx / 3
			for t in range(0, n_idx, 3):
				var a := verts[idx[t]] if not idx.is_empty() else verts[t]
				var b := verts[idx[t + 1]] if not idx.is_empty() else verts[t + 1]
				var c := verts[idx[t + 2]] if not idx.is_empty() else verts[t + 2]
				var cr := (b - a).cross(c - a) * 0.5
				area_xz += absf(cr.y)
				area_side += (absf(cr.x) + absf(cr.z)) * 0.5
		mesh_info[kind] = {"aabb": aabb, "tris": tris, "area_xz": area_xz, "area_side": area_side}
		if kind.begins_with("Corn") or kind.begins_with("Wheat"):
			print("  %-14s size=(%.2f x %.2f x %.2f)m  tris=%4d  surfs=%d %s  proj_top=%.2fm2  proj_side=%.2fm2" % [
				kind, aabb.size.x, aabb.size.y, aabb.size.z, tris, m.get_surface_count(), mats, area_xz, area_side])

	# 2. Find Wola and survey farmland pixels across the whole play area
	var wola := Vector2.ZERO
	for pl in map.places:
		if String(pl.name) == "Wola":
			wola = Vector2(float(pl.x), float(pl.y))
			break
	var crop_px := [0, 0, 0] # 0=maize, 1=wheat, 2=ploughed (field pixels with G >= FIELD_MIN)
	var all_field_px := 0
	var wola_corn_best := Vector2.INF
	var wola_corn_best_d := INF
	var wola_wheat_best := Vector2.INF
	var wola_wheat_best_d := INF
	var corn_cells_in_play := {}
	var wheat_cells_in_play := {}
	var any_crop_cells_in_play := {}
	var px_area: float = veg.LAND_RES * veg.LAND_RES
	# Check play polygon bounds in land map pixels
	var lx0 := 0
	var ly0 := 0
	var lx1: int = veg.land_w
	var ly1: int = veg.land_h
	for v in range(ly0, ly1):
		var wy: float = map.ty0 + (v + 0.5) * veg.LAND_RES
		for u in range(lx0, lx1):
			var i: int = (v * veg.land_w + u) * 4
			if veg.land[i + 1] < veg.FIELD_MIN:
				continue
			var wx: float = map.tx0 + (u + 0.5) * veg.LAND_RES
			if not map.in_play(Vector2(wx, wy)):
				continue
			all_field_px += 1
			var c: int = veg._crop_at(i)
			crop_px[c] += 1
			if c == 0 or c == 1:
				var cx := floori(wx / veg.CELL)
				var cy := floori(wy / veg.CELL)
				var ck := Vector2i(cx, cy)
				any_crop_cells_in_play[ck] = true
				if c == 0:
					corn_cells_in_play[ck] = true
					var d := Vector2(wx, wy).distance_to(wola)
					if d < wola_corn_best_d and _is_interior_crop(veg, wx, wy, 0, 12.0):
						wola_corn_best_d = d
						wola_corn_best = Vector2(wx, wy)
				else:
					wheat_cells_in_play[ck] = true
					var d := Vector2(wx, wy).distance_to(wola)
					if d < wola_wheat_best_d and _is_interior_crop(veg, wx, wy, 1, 12.0):
						wola_wheat_best_d = d
						wola_wheat_best = Vector2(wx, wy)

	var maize_ha: float = float(crop_px[0]) * px_area / 10000.0
	var wheat_ha: float = float(crop_px[1]) * px_area / 10000.0
	var plough_ha: float = float(crop_px[2]) * px_area / 10000.0
	print("\n=== PLAYABLE FARMLAND SURVEY ===")
	print("  Wola centre: (%.0f, %.0f)" % [wola.x, wola.y])
	print("  Nearest interior maize field to Wola: (%.0f, %.0f) [%.0f m from Wola]" % [wola_corn_best.x, wola_corn_best.y, wola_corn_best_d])
	print("  Nearest interior wheat field to Wola: (%.0f, %.0f) [%.0f m from Wola]" % [wola_wheat_best.x, wola_wheat_best.y, wola_wheat_best_d])
	print("  Farmland in play: total=%.1f ha | maize=%.1f ha (%d cells) | wheat=%.1f ha (%d cells) | ploughed/rim=%.1f ha" % [
		all_field_px * px_area / 10000.0, maize_ha, corn_cells_in_play.size(), wheat_ha, wheat_cells_in_play.size(), plough_ha])

	# 3. Whole-map crop instance & draw-call count at High quality (q=2)
	print("\n=== WHOLE-MAP CROP PLANTING (quality=2 High, all %d crop cells in play) ===" % any_crop_cells_in_play.size())
	veg.set_quality(2)
	var whole_counts := {}
	var whole_draws := {}
	var whole_far_counts := {}
	var whole_far_draws := {}
	var far_cells_seen := {}
	for ck: Vector2i in any_crop_cells_in_play:
		var tmp := Node3D.new()
		tmp.set_meta("counts", {})
		veg._plant_wheat(tmp, ck.x * veg.CELL, ck.y * veg.CELL)
		veg._plant_corn(tmp, ck.x * veg.CELL, ck.y * veg.CELL)
		for ch in tmp.get_children():
			var mmi := ch as MultiMeshInstance3D
			if mmi == null:
				continue
			var k := String(mmi.name)
			whole_counts[k] = int(whole_counts.get(k, 0)) + mmi.multimesh.instance_count
			whole_draws[k] = int(whole_draws.get(k, 0)) + 1
		tmp.free()
		# Also check far cells if vegetation plants crops in far layers
		var fcx := floori((ck.x * veg.CELL) / veg.FAR_CELL)
		var fcy := floori((ck.y * veg.CELL) / veg.FAR_CELL)
		far_cells_seen[Vector2i(fcx, fcy)] = true
	if veg.FAR_LAYERS > 2:
		for fck: Vector2i in far_cells_seen:
			var tmp := Node3D.new()
			tmp.set_meta("counts", {})
			for layer in range(2, veg.FAR_LAYERS):
				veg._plant(tmp, fck.x, fck.y, layer, true)
			for ch in tmp.get_children():
				var mmi := ch as MultiMeshInstance3D
				if mmi == null:
					continue
				var k := String(mmi.name)
				whole_far_counts[k] = int(whole_far_counts.get(k, 0)) + mmi.multimesh.instance_count
				whole_far_draws[k] = int(whole_far_draws.get(k, 0)) + 1
			tmp.free()

	var total_whole_inst := 0
	var total_whole_draws := 0
	for k: String in whole_counts:
		var n: int = whole_counts[k]
		var dc: int = whole_draws[k]
		var ha := maize_ha if k.begins_with("Corn") else wheat_ha
		total_whole_inst += n
		total_whole_draws += dc
		print("  %-14s total=%8d  draws=%5d  per_ha=%6.0f/ha  (%.2f/m2)" % [k, n, dc, n / maxf(ha, 0.01), n / maxf(ha * 10000.0, 1.0)])
	for k: String in whole_far_counts:
		var n: int = whole_far_counts[k]
		var dc: int = whole_far_draws[k]
		var ha := maize_ha if k.begins_with("Corn") else wheat_ha
		total_whole_inst += n
		total_whole_draws += dc
		print("  %-14s total=%8d  draws=%5d  per_ha=%6.0f/ha  (%.2f/m2) [far]" % [k, n, dc, n / maxf(ha, 0.01), n / maxf(ha * 10000.0, 1.0)])
	print("  WHOLE-MAP CROP TOTAL: instances=%d, draw_calls=%d (note: cells stream around camera, not all drawn at once)" % [total_whole_inst, total_whole_draws])

	# 4. Active camera-ring probe at Wola cornfield, Wola road next to cornfield, and wheat field across all qualities
	var wola_road_spot := wola_corn_best
	var nr := map.nearest_road(wola_corn_best, 400.0, 1)
	if not nr.is_empty():
		wola_road_spot = nr.pos as Vector2
	var spots := {
		"wola_corn": wola_corn_best,
		"wola_road": wola_road_spot,
		"wola_wheat": wola_wheat_best,
		"wheat_a": Vector2(-1640.0, -60.0),
	}
	print("\n=== ACTIVE CAMERA RING PER SPOT & QUALITY ===")
	for q in [0, 1, 2, 3]:
		veg.set_quality(q)
		print("--- quality %d (radius=%.0fm far_radius=%.0fm) ---" % [q, veg.radius(), veg.far_radius()])
		for sname: String in spots:
			var p: Vector2 = spots[sname]
			_reset_veg(veg)
			veg.recorded = {}
			veg.record = true
			var t0 := Time.get_ticks_usec()
			veg.update_around(p)
			veg.plant_all()
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			veg.record = false
			var per_inst := {}
			var per_draws := {}
			var per_range := {}
			var total_inst := 0
			var total_draws := 0
			var total_tris := 0
			var crop_inst := 0
			var crop_draws := 0
			var crop_tris := 0
			for k in veg.cells:
				for ch in (veg.cells[k] as Node3D).get_children():
					var mmi := ch as MultiMeshInstance3D
					if mmi == null:
						continue
					var kind := String(mmi.name)
					var cnt := mmi.multimesh.instance_count
					per_inst[kind] = int(per_inst.get(kind, 0)) + cnt
					per_draws[kind] = int(per_draws.get(kind, 0)) + 1
					per_range[kind] = "%.0f-%.0fm" % [mmi.visibility_range_begin, mmi.visibility_range_end]
					total_inst += cnt
					total_draws += 1
					var t := cnt * int(mesh_info.get(kind, {}).get("tris", 0))
					total_tris += t
					if kind.begins_with("Corn") or kind.begins_with("Wheat"):
						crop_inst += cnt
						crop_draws += 1
						crop_tris += t
			var parts: Array[String] = []
			for kind in per_inst:
				if kind.begins_with("Corn") or kind.begins_with("Wheat"):
					parts.append("%s=%d(%dd,%s)" % [kind, per_inst[kind], per_draws[kind], per_range[kind]])
			print("  %-11s %5.0fms | total=%6d inst %3d draws %4dk tris | crops=%5d inst %3d draws %4dk tris | %s" % [
				sname, ms, total_inst, total_draws, total_tris / 1000, crop_inst, crop_draws, crop_tris / 1000, ", ".join(parts)])

	# 5. Detailed spacing / gap / coverage analysis in interior of Wola cornfield and wheat field (quality 2)
	print("\n=== SPACING, ROW GAPS & COVERAGE (quality=2, interior 32x32m cell) ===")
	veg.set_quality(2)
	_analyze_field_spacing(veg, wola_corn_best, 0, "Corn", mesh_info)
	_analyze_field_spacing(veg, wola_wheat_best, 1, "Wheat", mesh_info)

	# 6. Check draw_scale plumbing on TownBuilder + Vegetation
	print("\n=== DRAW SCALE CHECK ===")
	print("  Vegetation has set_draw_scale: ", veg.has_method("set_draw_scale"))
	if veg.has_method("set_draw_scale"):
		veg.set_quality(2)
		_reset_veg(veg)
		veg.update_around(wola_corn_best)
		veg.plant_all()
		var corn_full := _first_range(veg, "Corn")
		var cfar_full := _first_range(veg, "CornFar")
		veg.set_draw_scale(0.6)
		var corn_low := _first_range(veg, "Corn")
		var cfar_low := _first_range(veg, "CornFar")
		veg.set_draw_scale(1.25)
		var corn_ultra := _first_range(veg, "Corn")
		var cfar_ultra := _first_range(veg, "CornFar")
		veg.set_draw_scale(1.0)
		print("  Corn range_end: scale 1.0=%.1fm | 0.6=%.1fm | 1.25=%.1fm" % [corn_full, corn_low, corn_ultra])
		print("  CornFar range_end: scale 1.0=%.1fm | 0.6=%.1fm | 1.25=%.1fm" % [cfar_full, cfar_low, cfar_ultra])

	# 7. Check road clearance for crops around Wola road & wheat field
	var crop_on_road := 0
	var crop_checked := 0
	veg.set_quality(2)
	_reset_veg(veg)
	veg.recorded = {}
	veg.record = true
	veg.update_around(wola_road_spot)
	veg.plant_all()
	veg.update_around(wola_wheat_best)
	veg.plant_all()
	veg.record = false
	for kind in ["Corn", "CornFar", "WheatPatchLow", "WheatFar"]:
		for o: Vector3 in veg.recorded.get(kind, PackedVector3Array()):
			crop_checked += 1
			var hit := map.road_at(o.x, o.z, -INF, 0.75)
			if (not hit.is_empty() and float(hit.deck) < 1.0) or map.kerb_at(o.x, o.z) > 0.0:
				crop_on_road += 1
	print("  Crop road-clearance check: %d / %d on road or pavement" % [crop_on_road, crop_checked])

	veg.free()
	quit()


static func _first_range(veg: Node3D, kind: String) -> float:
	for k in veg.cells:
		for ch in (veg.cells[k] as Node3D).get_children():
			if ch is MultiMeshInstance3D and String(ch.name) == kind:
				return (ch as MultiMeshInstance3D).visibility_range_end
	return -1.0


static func _is_interior_crop(veg: Node3D, x: float, y: float, want: int, r: float) -> bool:
	for dx in [-r, 0.0, r]:
		for dy in [-r, 0.0, r]:
			if veg._crop_at(veg._px(x + dx, y + dy)) != want:
				return false
	return true


static func _reset_veg(veg: Node3D) -> void:
	for k in veg.cells.keys():
		veg._free_cell(k)
	veg.queue.clear()
	veg.queued.clear()
	veg._last_cell = Vector2i(1 << 30, 1 << 30)


static func _analyze_field_spacing(veg: Node3D, centre: Vector2, crop_id: int, label: String, mesh_info: Dictionary) -> void:
	_reset_veg(veg)
	veg.recorded = {}
	veg.record = true
	veg.update_around(centre)
	veg.plant_all()
	veg.record = false
	# Collect positions within a 24x24m interior box around centre (pure crop)
	var box_r := 12.0
	var crop_area := 0.0
	for gx in range(-12, 12):
		for gy in range(-12, 12):
			if veg._crop_at(veg._px(centre.x + gx + 0.5, centre.y + gy + 0.5)) == crop_id:
				crop_area += 1.0
	var kinds: Array[String] = []
	for k in veg.recorded:
		if k.begins_with(label):
			kinds.append(k)
	kinds.sort()
	print("  %s @ (%.0f, %.0f) [interior crop area=%.0f / 576 m2]:" % [label, centre.x, centre.y, crop_area])
	for kind in kinds:
		var pts: Array[Vector2] = []
		for o: Vector3 in veg.recorded[kind]:
			if absf(o.x - centre.x) <= box_r and absf(o.z - centre.y) <= box_r:
				pts.append(Vector2(o.x, o.z))
		if pts.size() < 4:
			print("    %-14s only %d pts in interior box" % [kind, pts.size()])
			continue
		var nn: Array[float] = []
		var k4: Array[float] = [] # 4th nearest neighbour (cross-row / grid spacing proxy)
		for i in pts.size():
			var d1 := INF
			var ds: Array[float] = []
			for j in pts.size():
				if i == j:
					continue
				var d := pts[i].distance_to(pts[j])
				if d < d1:
					d1 = d
				if d < 8.0:
					ds.append(d)
			nn.append(d1)
			ds.sort()
			if ds.size() >= 4:
				k4.append(ds[3])
		nn.sort()
		k4.sort()
		var nn_mean := 0.0
		for v in nn:
			nn_mean += v
		nn_mean /= nn.size()
		var k4_mean := 0.0
		for v in k4:
			k4_mean += v
		k4_mean = k4_mean / maxf(k4.size(), 1)
		var aabb: AABB = mesh_info[kind].aabb
		var eff_w := (aabb.size.x + aabb.size.z) * 0.5
		var per_ha := float(pts.size()) / maxf(crop_area, 1.0) * 10000.0
		var density := float(pts.size()) / maxf(crop_area, 1.0)
		# Horizontal optical opacity looking horizontally through a 10 m deep strip of crop: 1 - exp(-density * proj_side * 10)
		var proj_side: float = mesh_info[kind].area_side
		var proj_top: float = mesh_info[kind].area_xz
		# Approximate average height for vertical wall opacity per metre depth
		var depth_1m_cover := 1.0 - exp(-density * (proj_side / maxf(aabb.size.y, 0.1)))
		var depth_6m_cover := 1.0 - exp(-density * (proj_side / maxf(aabb.size.y, 0.1)) * 6.0)
		var top_cover := minf(1.0, density * proj_top)
		var avg_gap := maxf(0.0, k4_mean - eff_w)
		print("    %-14s %5.0f/ha (%.2f/m2) | mesh W=%.2fm H=%.2fm | nn=%.2fm (p90=%.2fm max=%.2fm) | row/4nn=%.2fm | gap=%.2fm | top_cov=%.0f%% side_1m=%.0f%% side_6m=%.0f%%" % [
			kind, per_ha, density, eff_w, aabb.size.y, nn_mean, nn[int(nn.size() * 0.9)], nn[nn.size() - 1],
			k4_mean, avg_gap, top_cover * 100.0, depth_1m_cover * 100.0, depth_6m_cover * 100.0])
