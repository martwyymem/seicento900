## Street-stage content: Krakow's baked tram rails and the TramRails mesh, and the Wilamowice church landmark.
extends RefCounted

var completed := false
var errors: Array[String] = []

func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		errors.append("%s %s" % [what, detail])

## Stands in for race_world.gd: TramRails only asks it for the world centre and the road height.
class StubWorld extends Node3D:
	var world_center := Vector2.ZERO
	func _road_y(_s: float) -> float:
		return 2.0

func _env(key: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/tracks/%s_env.json" % key))

func run() -> Array:
	var kr := _env("krakow")
	var runs: Array = kr.get("tram_rails", [])
	check("krakow bakes tram rails", runs.size() > 5, "(%d runs)" % runs.size())
	var cfg := load("res://data/tracks/krakow.tres") as TrackDef
	for run_ in runs:
		check("a rail run is [s, d] pairs", run_.size() % 2 == 0 and run_.size() >= 12)
		for i in range(1, run_.size(), 2):
			if absf(float(run_[i])) > cfg.width * 0.5:
				check("rails stay on the carriageway", false, "(d %.1f)" % float(run_[i]))
				break
	# the mesh: two surfaces (bed, rails), every vertex a little above the road
	var t := Track.new(cfg)
	var w := StubWorld.new()
	var root := Node3D.new()
	var mi := TramRails.build(root, w, t, runs)
	check("TramRails builds a mesh", mi != null and mi.mesh != null and mi.mesh.get_surface_count() == 2)
	if mi != null and mi.mesh != null:
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		check("the rail bed has vertices", verts.size() > 100)
		var lo := INF
		var hi := -INF
		for v in verts:
			lo = minf(lo, v.y)
			hi = maxf(hi, v.y)
		check("the rails sit just above the road", lo >= 2.0 and hi < 2.2, "(%.3f..%.3f)" % [lo, hi])
	check("no runs, no mesh", TramRails.build(root, w, t, []) == null)
	root.free()
	w.free()
	# Wilamowice: the church is a landmark (and no longer a plain block on the same footprint)
	var wil := _env("wilamowice")
	var found := false
	for lm in wil.get("landmarks", []):
		if lm[0] == "WilamowiceChurch":
			found = true
			check("the church keeps its mapped size", absf(float(lm[3]) - 49.7) < 1.0 and absf(float(lm[4]) - 23.2) < 1.0)
	check("wilamowice has the church landmark", found)
	check("surroundings knows the church's nominal size", FileAccess.get_file_as_string("res://scripts/ui/surroundings.gd").contains("\"WilamowiceChurch\": Vector2("))
	completed = true
	return errors
