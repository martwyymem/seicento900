## Times live-event generation on the real map (the open world does it on the main thread): ms per generate()
## by kind, and how often a try fails. godot --headless --path godot -s tests/_live_events_probe.gd
extends SceneTree

func _initialize() -> void:
	var map := TownMap.load_map(OpenWorld.MAP_KEY)
	var live := LiveEvents.new(map, 99)
	var spots := ["festival", "industrial_sprint", "bor_stage", "exit_wilamowice"]
	for kind in LiveEvents.KINDS:
		var worst := 0.0
		var total := 0.0
		var ok := 0
		var n := 0
		for sp in spots:
			var s: Array = map.spots.get(sp, [0.0, 0.0, 0.0])
			for k in 4:
				var t0 := Time.get_ticks_usec()
				var ev := live.generate(Vector2(s[0], s[1]), PackedVector2Array(), kind)
				var ms := (Time.get_ticks_usec() - t0) / 1000.0
				worst = maxf(worst, ms)
				total += ms
				n += 1
				if not ev.is_empty():
					ok += 1
					if k == 0:
						print("  %s %s: %.0f m, tiers %s" % [kind, ev.title, ev.length, live.tiers_for(ev, "stock")])
		print("%s: %d/%d made, mean %.1f ms, worst %.1f ms" % [kind, ok, n, total / n, worst])
	quit(0)
