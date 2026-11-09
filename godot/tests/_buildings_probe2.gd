extends SceneTree
func _initialize() -> void:
	var map := TownMap.load_map("brzeszcze")
	var tb := TownBuilder.new(map, Node3D.new())
	var t_cover := 0.0
	var t_runs := 0.0
	var t_parse := 0.0
	var n_edges := 0
	var n_cand := 0
	var n_open_calls := 0
	var n_candidate_empty := 0
	for bi in map.buildings.size():
		var b: Array = map.buildings[bi]
		var extra: Dictionary = b[6] if b.size() > 6 and b[6] is Dictionary else {}
		if not extra.has("rs"): continue
		var ring := map.bld_rings[bi]
		var a := Time.get_ticks_usec()
		TownBuilder._lod2_cover(extra.get("rs", []), ring)
		var c := Time.get_ticks_usec()
		t_cover += c - a
		var polys: Array[PackedVector3Array] = []
		for face in extra.rs:
			if not face is Array or face.size() < 9: continue
			var poly := PackedVector3Array()
			for j in range(0, face.size() - 2, 3):
				poly.append(Vector3(face[j], face[j + 2], face[j + 1]))
			polys.append(poly)
		var d := Time.get_ticks_usec()
		t_parse += d - c
		var boxes := TownBuilder._plane_boxes(polys)
		for pi in polys.size():
			var poly := polys[pi]
			for k in poly.size():
				var a3 := poly[k]
				var c3 := poly[(k + 1) % poly.size()]
				var e2 := Vector2(c3.x - a3.x, c3.z - a3.z)
				if e2.length() < 0.05: continue
				n_edges += 1
				var cands := TownBuilder._edge_candidates(polys, boxes, pi, a3, c3)
				n_cand += cands.size() / 3
				if cands.is_empty(): n_candidate_empty += 1
		t_runs += Time.get_ticks_usec() - d
	print("cover %.0f ms  parse %.0f  edges+cands %.0f ms; edges %d, cand segs %d, edges w/o cands %d" % [t_cover/1000, t_parse/1000, t_runs/1000, n_edges, n_cand, n_candidate_empty])
	quit()
