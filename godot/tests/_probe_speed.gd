extends SceneTree
func run(track: String, aids: bool):
	var st := RaceSettings.new()
	st.laps = 2
	st.track = track
	st.difficulty = "medium"
	st.assists = "full"
	st.brake_assist = aids
	st.auto_rejoin = aids
	var race := Race.new(st, null, 12345)
	var inp := Race.PlayerInput.new()
	var p := race.player
	var dt := 1.0 / 120.0
	var ticks := 0
	var thr := 0.0; var brk := 0.0; var steer := 0.0
	var buf := []
	var vmax := 0.0; var rejoins := 0; var ouch := 0; var seen := 0
	while race.phase != "finished" and ticks < 120 * 600:
		var up := false; var down := false; var st_key := 0.0
		if race.phase == "racing":
			var c := race.bot_input(p, dt)
			buf.append([c.throttle, c.brake, c.steer])
			var k: Array = buf[0] if buf.size() > 18 else [1.0, 0.0, 0.0]
			if buf.size() > 18: buf.pop_front()
			up = k[0] > 0.5
			down = k[1] > 0.5
			if k[2] > 0.05: st_key = 1.0
			elif k[2] < -0.05: st_key = -1.0
		var back := st_key == 0.0 or signf(st_key) != signf(steer)
		steer = move_toward(steer, st_key, (7.0 if back else 3.2) * dt)
		thr = move_toward(thr, 1.0 if up else 0.0, 6.0 * dt)
		brk = move_toward(brk, 1.0 if down else 0.0, 8.0 * dt)
		inp.throttle = thr; inp.brake = brk; inp.steer = steer
		race.step(dt, inp)
		ticks += 1
		vmax = maxf(vmax, absf(p.speed) * 3.6)
		for e in race.events:
			if e.id > seen:
				seen = e.id
				if "Back on track" in e.text: rejoins += 1
				if "Ouch" in e.text: ouch += 1
	var bots := []
	for c in race.cars:
		if not c.is_player: bots.append(c.best_lap)
	bots.sort()
	print("%s aids=%s vmax=%.1f laps=%d best=%s rejoins=%d walls=%d  bot best=%s median=%s pos=%d phase=%s" % [track, aids, vmax, p.lap, Race.fmt_time(p.best_lap), rejoins, ouch, Race.fmt_time(bots[0]), Race.fmt_time(bots[bots.size()/2]), p.pos, race.phase])
func _init():
	Brain.use_disk = false
	for t in ["indy", "gp"]:
		run(t, false)
		run(t, true)
	quit()
