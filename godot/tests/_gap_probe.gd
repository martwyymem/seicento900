## Levitating-road audit (dev tool): for each circuit, how far the ground lies below the road just outside the barrier.
## Env: TRACKS (comma list, default all)
##   godot --path godot -s tests/_gap_probe.gd
extends SceneTree

const KEYS := ["gp", "nordschleife", "spa", "monaco", "lemans", "monza", "silverstone", "suzuka", "zandvoort", "indy", "fiat"]

func _initialize() -> void:
	var keys: PackedStringArray = OS.get_environment("TRACKS").split(",") if OS.get_environment("TRACKS") != "" else PackedStringArray(KEYS)
	root.size = Vector2i(640, 360)
	for key in keys:
		var world = load("res://ui/race_world.tscn").instantiate()
		root.add_child(world)
		await process_frame
		var rs := RaceSettings.new()
		rs.track = key
		rs.opponents = 1
		world.set_race(Race.new(rs))
		await process_frame
		world.set_process(false)
		_audit(world, key)
		world.queue_free()
		await process_frame
	quit()

func _audit(world: Node, key: String) -> void:
	var tr: Track = world.track
	var sur = world.surroundings
	var bd := tr.half + tr.cfg.runoff + 0.3
	var offs := [0.0, 3.0, 8.0, 15.0]
	var worst := PackedFloat32Array([0, 0, 0, 0])
	var count := PackedInt32Array([0, 0, 0, 0])
	var n := 0
	var spans := []
	var run_start := -1.0
	for i in range(0, tr.n, 2):
		var s := i * tr.step
		var road: float = world._road_y(s) + tr.bank_rise(s, 0.0)
		var bad := false
		for side in [-1.0, 1.0]:
			for k in offs.size():
				var p: PackedFloat64Array = tr.pos(s, side * (bd + offs[k]))
				var g: float = sur.ground_height(p[0], p[1]) if sur else world._ground_y(p[0], p[1], s, bd + offs[k])
				var gap := road + tr.bank_rise(s, side * (bd + offs[k])) - g
				if gap > worst[k]:
					worst[k] = gap
				if gap > 1.5:
					count[k] += 1
					if k == 1:
						bad = true
		n += 2
		if bad and run_start < 0.0:
			run_start = s
		elif not bad and run_start >= 0.0:
			if s - run_start > 20.0:
				spans.append("%d-%d" % [run_start, s])
			run_start = -1.0
	print("%s: L=%.0f  worst gap at +0/+3/+8/+15 m beyond the barrier: %.1f %.1f %.1f %.1f   samples >1.5 m: %d %d %d %d of %d  spans(+3m): %s" % [
		key, tr.L, worst[0], worst[1], worst[2], worst[3], count[0], count[1], count[2], count[3], n * 2, ", ".join(spans.slice(0, 12))])
