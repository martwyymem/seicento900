## Race-control scenarios, headless: godot --headless --path godot -s tests/smoke_rc.gd -- [scenario] [track]
## scenario: clean (just race and report incidents) | sc (a bot stops on the track) | red (red flag)
extends SceneTree

func _init():
	Brain.use_disk = false
	var args := OS.get_cmdline_user_args()
	var scenario: String = args[0] if args.size() > 0 else "sc"
	var st := RaceSettings.new()
	st.track = args[1] if args.size() > 1 else "gp"
	st.laps = int(args[2]) if args.size() > 2 else 6
	var race := Race.new(st, null, 777)
	var rc := race.rc
	var inp := Race.PlayerInput.new()
	race.set_autopilot(true)
	var dt := 1.0 / 120.0
	var ticks := 0
	var fired := false
	var next_print := 0.0
	var seen := 0
	while race.phase != "finished" and ticks < 120 * 3600:
		race.step(dt, inp)
		ticks += 1
		if not fired and race.race_time > 90.0:
			fired = true
			if scenario == "sc":
				var v: RaceCar = race.order[5]
				rc.wreck(v, 12.0, false)
				v.vx *= 0.3
				v.vy *= 0.3
				print("## wrecked ", v.name, " at s=%.0f d=%.1f" % [v.s, v.d])
			elif scenario == "red":
				rc.red_flag("test")
		for e in race.events:
			if e.id > seen:
				seen = e.id
				if e.kind != "pit" and e.kind != "purple":
					print("%7.1f [%s] %s" % [race.race_time, e.kind, e.text])
		if race.race_time >= next_print and race.phase == "racing":
			next_print += 10.0
			var lead := race.order[0]
			var in_pit := 0
			for c in race.cars:
				if c.mode == "pit":
					in_pit += 1
			var pf := rc.player_flag()
			print("%7.1f flag=%s/%s sc=%s sc_s=%.0f v=%.1f lead=%s L%d s=%.0f v=%.1f pit=%d stranded=%d yellow=%s player=%s" % [
				race.race_time, rc.flag, rc.red_state, rc.sc_state, rc.sc.s, rc.sc.v, lead.name.substr(0, 8), lead.lap, lead.s,
				lead.v, in_pit, rc._stranded(), str(Array(rc.yellow).filter(func(x): return x > 0).size()), pf.get("title", "")])
	print("done phase=%s t=%.0f" % [race.phase, race.race_time])
	for r in race.results():
		print("%2d %-24s laps %d %s dmg %.2f pen %.0f %s" % [r.pos, r.car.name, r.laps, Race.fmt_time(r.total), r.car.damage, r.car.penalty, r.status])
	quit()
