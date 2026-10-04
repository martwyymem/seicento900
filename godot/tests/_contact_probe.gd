## Dev probe: contacts, damage and cautions over the first 150 s, physics bots with and without line smoothing.
## Args: smooth (0/1) track [seeds] [slew per metre] [first seed] [slew m/s]
extends SceneTree
func _init():
	Brain.use_disk = false
	var a := OS.get_cmdline_user_args()
	var smooth := a[0] == "1"
	var key: String = a[1]
	var seeds := int(a[2]) if a.size() > 2 else 8
	var per_m := float(a[3]) if a.size() > 3 else 0.25
	var first := int(a[4]) if a.size() > 4 else 1
	var slew := float(a[5]) if a.size() > 5 else 6.0
	var early := 0.0
	var tot := {"collision_pen": 0, "damage": 0.0, "wrecks": 0, "sc": 0, "yellow_trouble": 0}
	for seed_ in range(first, first + seeds):
		var st := RaceSettings.new()
		st.track = key
		st.laps = 4
		st.opponents = 15
		var race := Race.new(st, null, seed_)
		race.bot_smooth_line = smooth
		race.line_slew_per_m = per_m
		race.line_slew = slew
		race.set_autopilot(true)
		var inp := Race.PlayerInput.new()
		var t := 0
		var mx := 0
		while race.race_time < 150.0 and t < 120 * 200:
			race.step(1.0 / 120.0, inp)
			t += 1
			mx = maxi(mx, race.rc._trouble)
			if t == 120 * 25:
				for c in race.cars:
					early += c.damage
		for c in race.cars:
			tot.damage += c.damage
			if c.wrecked:
				tot.wrecks += 1
		for e in race.events:
			if e.text.contains("collision"):
				tot.collision_pen += 1
			if e.kind == "warn" and e.text.begins_with("SAFETY CAR DEPLOYED"):
				tot.sc += 1
		tot.yellow_trouble += mx
	print("slew=%.0f per_m=%.2f first=%d early(25s) damage %.2f" % [slew, per_m, first, early])
	print("smooth=%s %s seeds=%d  collision penalties %d  damage %.2f  wrecks %d  SC %d  sum max trouble %d" % [smooth, key, seeds, tot.collision_pen, tot.damage, tot.wrecks, tot.sc, tot.yellow_trouble])
	quit()
