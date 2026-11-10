## Probe (headless): facts for picking mission tracks: length, width, loose share, how straight the road runs from the line.
extends SceneTree

func _initialize() -> void:
	for key in ["fiat", "s1_sprint", "bor", "brzeszcze", "pszczyna", "maly_bor", "kolonia_stawowa", "babudy_gora", "rajsko_wilczkowice", "lipowiec_kobylec", "wilamowice", "oswiecim", "bielsko", "gp", "indy"]:
		var t := Race.get_track(key)
		var loose := 0.0
		for z in t.loose:
			loose += z.y - z.x
		# straight run from the start line: first s where the heading departs > 3 deg from the start heading, or the centre drifts > 2 m
		var h0 := t.heading(0.0)
		var straight := 0.0
		var s := 0.0
		while s < t.L:
			if absf(wrapf(t.heading(s) - h0, -PI, PI)) > deg_to_rad(4.0):
				break
			straight = s
			s += 5.0
		# longest straight anywhere (heading within 4 deg over a run)
		var best := 0.0
		var best_at := 0.0
		var a := 0.0
		while a < t.L:
			var ha := t.heading(a)
			var b := a
			while b < a + 3000.0 and absf(wrapf(t.heading(b) - ha, -PI, PI)) < deg_to_rad(4.0):
				b += 5.0
			if b - a > best:
				best = b - a
				best_at = a
			a += 25.0
		var curv := 0.0
		for i in t.n:
			curv += absf(t.KC[i]) * t.step
		print("%-20s L %6.0f m  width %4.1f  loose %3.0f%%  straight from line %5.0f m  longest straight %5.0f m at %5.0f  turning %4.0f deg/km  p2p %s loose_grip %s" % [key, t.L, t.width, 100.0 * loose / t.L, straight, best, best_at, rad_to_deg(curv) / (t.L / 1000.0), t.cfg.point_to_point, t.cfg.loose_grip])
	quit()
