## Free-roam weather (WorldWeather, OpenWorld._update_weather): deterministic in the seed, continuous, mostly dry with
## occasional showers and a rare dawn fog, snow off by default, the road's wetness lagging the rain and the car's grip
## following the wetness as Race.grip does; a mission's weather wins while it runs and free roam's carries on after;
## Always dry stays dry; the seed, the day and the switch survive a save.
extends RefCounted

var completed := false

func run() -> Array:
	var errors: Array[String] = []
	_model(errors)
	_hail(errors)
	_grip(errors)
	var map := TownMap.load_map(OpenWorld.MAP_KEY)
	if map == null:
		errors.append("data/world/%s.json did not load" % OpenWorld.MAP_KEY)
	else:
		await _world(map, errors)
	completed = true
	return errors

## The first game hour in [from, to] at which the seed's rain is at least `level`, or -1.
static func _rain_peak(w: WorldWeather, from: float, to: float, level := 0.9) -> float:
	var t := from
	while t < to:
		if float(w.target(t).rain) >= level:
			return t
		t += 0.05
	return -1.0

## The first game hour in [from, to] at which the seed's hail is at least `level`, or -1.
static func _hail_peak(w: WorldWeather, from: float, to: float, level := 0.5) -> float:
	var t := from
	while t < to:
		if float(w.target(t).hail) >= level:
			return t
		t += 0.05
	return -1.0

func _model(errors: Array[String]) -> void:
	# deterministic in the seed: the same plan, a different one for another seed
	var a := WorldWeather.new(12345, 0.0)
	var b := WorldWeather.new(12345, 0.0)
	var c := WorldWeather.new(54321, 0.0)
	var differ := false
	var t := 0.0
	while t < 24.0 * 12.0:
		var ta := a.target(t)
		var tb := b.target(t)
		var tc := c.target(t)
		if ta.rain != tb.rain or ta.fog != tb.fog or ta.snow != tb.snow or ta.hail != tb.hail:
			errors.append("two weathers of one seed differ at hour %.2f" % t)
			break
		if absf(float(ta.rain) - float(tc.rain)) > 0.01:
			differ = true
		t += 0.1
	if not differ:
		errors.append("two seeds gave the same twelve days")
	# stepping on and settling at the new clock land on the same weather (a reload, the time skip)
	var s := WorldWeather.new(777, 30.0)
	var peak := _rain_peak(s, 24.0, 24.0 * 40.0)
	if peak < 0.0:
		errors.append("no heavy shower in 40 days of seed 777")
		return
	s.settle(peak - 1.0)
	var stepped := WorldWeather.new(777, peak - 1.0)
	var dh := 1.0 / 60.0 / 80.0
	var left := 1.6
	while left > 0.0:
		stepped.advance(dh)
		left -= dh
	var fresh := WorldWeather.new(777, stepped.clock)
	if absf(stepped.rain - fresh.rain) > 1e-6 or absf(stepped.wet - fresh.wet) > 0.02 or absf(stepped.fog - fresh.fog) > 1e-6:
		errors.append("stepping to hour %.2f gave rain %.3f wet %.3f, settling there %.3f / %.3f" % [stepped.clock, stepped.rain, stepped.wet, fresh.rain, fresh.wet])
	# the shape of a year: mostly dry, showers 1-3 h, fog rare, no snow unless asked for
	var days := 360
	var rain_hours := 0.0
	var dry_days := 0
	var fog_days := 0
	var snow_events := 0
	var shower_min := 99.0
	var shower_max := 0.0
	var year := WorldWeather.new(2024, 0.0)
	for d in days:
		var shows := 0
		for ev in year.events_for(d):
			match String(ev.kind):
				"rain":
					shows += 1
					var len := float(ev.end) - float(ev.start)
					shower_min = minf(shower_min, len)
					shower_max = maxf(shower_max, len)
				"fog":
					fog_days += 1
					var h := fposmod(float(ev.start), 24.0)
					if h < 3.4 or h > 5.6:
						errors.append("a fog starts at %.2f h, not at dawn" % h)
				"snow":
					snow_events += 1
		if shows == 0:
			dry_days += 1
	var t2 := 0.0
	while t2 < float(days) * 24.0:
		if float(year.target(t2).rain) > 0.05:
			rain_hours += 0.1
		t2 += 0.1
	var rain_share := rain_hours / (float(days) * 24.0)
	if rain_share < 0.02 or rain_share > 0.12:
		errors.append("it rains %.1f %% of the time (wanted 2-12 %%)" % (rain_share * 100.0))
	if dry_days < days * 0.35 or dry_days > days * 0.55:
		errors.append("%d of %d days without a shower (wanted 35-55 %%)" % [dry_days, days])
	if fog_days < 5 or fog_days > 50:
		errors.append("%d foggy mornings in %d days (rare, not none)" % [fog_days, days])
	if snow_events != 0:
		errors.append("snow fell with snow off (%d events)" % snow_events)
	if shower_min < 0.99 or shower_max > 3.01:
		errors.append("showers last %.2f-%.2f h (wanted 1-3)" % [shower_min, shower_max])
	var snowy := WorldWeather.new(2024, 0.0, true)
	var snows := 0
	for d in days:
		for ev in snowy.events_for(d):
			if String(ev.kind) == "snow":
				snows += 1
	if snows < 10:
		errors.append("snow switched on gave only %d snowfalls in %d days" % [snows, days])
	# continuous in time: rain, fog, hail, wetness and grip never jump (the ramps are minutes of game time)
	for seed_v in [3, 99, 777, 2024]:
		var w := WorldWeather.new(seed_v, 0.0)
		var prev: Dictionary = w.state()
		var worst := {"rain": 0.0, "fog": 0.0, "hail": 0.0, "wet": 0.0, "mu": 0.0}
		var step := 0.004
		var n := int(24.0 * 6.0 / step)
		for _i in n:
			w.advance(step)
			var cur: Dictionary = w.state()
			for k in worst:
				worst[k] = maxf(worst[k], absf(float(cur[k]) - float(prev[k])))
			prev = cur
		# a step of 0.004 h: shower ramp 7.5/h (0.03), hail ramp 12.5/h (0.05), wetness 1/0.45/h (0.009)
		if worst.rain > 0.03 or worst.fog > 0.01 or worst.hail > 0.055 or worst.wet > 0.012 or worst.mu > 0.025:
			errors.append("seed %d is not continuous: biggest steps %s" % [seed_v, worst])

## Free-roam hail squalls: rare (~5 % of days), brief (0.35-0.75 h), deterministic, avoiding dawn fog, wetting the
## road, cutting grip, driving mode/word ("hail"/"HAIL") and force("hail").
func _hail(errors: Array[String]) -> void:
	var days := 1000
	var w := WorldWeather.new(2024, 0.0)
	var snowy := WorldWeather.new(2024, 0.0, true)
	var hail_count := 0
	var hail_min := 99.0
	var hail_max := 0.0
	var level_min := 99.0
	var level_max := 0.0
	var fog_overlap := 0
	var snow_mismatch := false
	for d in days:
		var evs := w.events_for(d)
		var sevs := snowy.events_for(d)
		var fogs: Array = []
		var hails: Array = []
		for ev in evs:
			if String(ev.kind) == "fog":
				fogs.append(ev)
			elif String(ev.kind) == "hail":
				hails.append(ev)
				hail_count += 1
				var dur := float(ev.end) - float(ev.start)
				hail_min = minf(hail_min, dur)
				hail_max = maxf(hail_max, dur)
				level_min = minf(level_min, float(ev.level))
				level_max = maxf(level_max, float(ev.level))
		for h in hails:
			for f in fogs:
				if float(h.start) < float(f.end) + WorldWeather.FOG_RAMP and float(h.end) > float(f.start) - WorldWeather.FOG_RAMP:
					fog_overlap += 1
		var shails: Array = []
		for ev in sevs:
			if String(ev.kind) == "hail":
				shails.append(ev)
		if shails.size() != hails.size():
			snow_mismatch = true
	if hail_count < 25 or hail_count > 85:
		errors.append("%d hail squalls in %d days (wanted ~5 %%: 25-85)" % [hail_count, days])
	if hail_count > 0:
		if hail_min < WorldWeather.HAIL_HOURS.x - 1e-4 or hail_max > WorldWeather.HAIL_HOURS.y + 1e-4:
			errors.append("hail duration %.3f-%.3f h outside [%.2f, %.2f]" % [hail_min, hail_max, WorldWeather.HAIL_HOURS.x, WorldWeather.HAIL_HOURS.y])
		if level_min < WorldWeather.HAIL_LEVEL.x - 1e-4 or level_max > WorldWeather.HAIL_LEVEL.y + 1e-4:
			errors.append("hail level %.3f-%.3f outside [%.2f, %.2f]" % [level_min, level_max, WorldWeather.HAIL_LEVEL.x, WorldWeather.HAIL_LEVEL.y])
	if fog_overlap > 0:
		errors.append("%d hail squalls overlapped dawn fog" % fog_overlap)
	if snow_mismatch:
		errors.append("enabling snow changed the hail schedule")
	# determinism across stepping vs reload/settle, continuity across a squall, road wetting, mode and word
	var peak := _hail_peak(w, 24.0, 24.0 * 200.0)
	if peak < 0.0:
		errors.append("no hail squall found in 200 days of seed 2024")
		return
	var stepped := WorldWeather.new(2024, peak - 0.5)
	var prev_st := stepped.state()
	var max_dhail := 0.0
	var max_dmu := 0.0
	var saw_hail_mode := false
	var saw_hail_word := false
	var peak_wet := 0.0
	var min_mu := 1.0
	var step := 0.004
	for _i in int(1.0 / step):
		stepped.advance(step)
		var cur_st := stepped.state()
		max_dhail = maxf(max_dhail, absf(float(cur_st.hail) - float(prev_st.hail)))
		max_dmu = maxf(max_dmu, absf(float(cur_st.mu) - float(prev_st.mu)))
		if String(cur_st.mode) == "hail":
			saw_hail_mode = true
		if WorldWeather.word(cur_st) == "HAIL":
			saw_hail_word = true
		peak_wet = maxf(peak_wet, float(cur_st.wet))
		min_mu = minf(min_mu, float(cur_st.mu))
		prev_st = cur_st
	var settled := WorldWeather.new(2024, stepped.clock)
	if absf(stepped.hail - settled.hail) > 1e-6 or absf(stepped.wet - settled.wet) > 0.02 or absf(float(stepped.state().mu) - float(settled.state().mu)) > 0.01:
		errors.append("stepping across hail gave hail=%.3f wet=%.3f mu=%.3f, settling there gave %.3f / %.3f / %.3f" % [stepped.hail, stepped.wet, float(stepped.state().mu), settled.hail, settled.wet, float(settled.state().mu)])
	if max_dhail > 0.055 or max_dmu > 0.025:
		errors.append("hail squall was not continuous: dhail=%.4f dmu=%.4f" % [max_dhail, max_dmu])
	if not saw_hail_mode or not saw_hail_word:
		errors.append("hail squall did not report mode='hail' and word='HAIL' (mode=%s word=%s)" % [saw_hail_mode, saw_hail_word])
	if peak_wet < 0.25:
		errors.append("hail squall barely wetted the road: peak wet %.3f" % peak_wet)
	if not (min_mu < 0.78):
		errors.append("hail squall did not drop grip enough: min mu %.3f" % min_mu)
	# force("hail", hours, level) and priority (snow > hail > rain)
	var fw := WorldWeather.new(1, 12.0)
	fw.force("hail", 1.5, 0.9)
	fw.advance(0.2)
	var fst := fw.state()
	if fw.hail < 0.85 or String(fst.mode) != "hail" or WorldWeather.word(fst) != "HAIL":
		errors.append("force('hail') did not reach hail state: hail=%.3f mode=%s word=%s" % [fw.hail, fst.mode, WorldWeather.word(fst)])
	if fw.wet < 0.1 or float(fst.mu) > 0.72:
		errors.append("force('hail') did not wet the road and cut grip: wet=%.3f mu=%.3f" % [fw.wet, float(fst.mu)])
	# priority: hail beats rain, snow beats hail
	var p_hr := WorldWeather.new(1, 12.0)
	p_hr.forced.append({"kind": "rain", "start": 11.5, "end": 14.0, "level": 0.8})
	p_hr.forced.append({"kind": "hail", "start": 11.5, "end": 14.0, "level": 0.7})
	p_hr.advance(0.1)
	if String(p_hr.state().mode) != "hail" or WorldWeather.word(p_hr.state()) != "HAIL":
		errors.append("hail did not take priority over rain: mode=%s word=%s" % [p_hr.state().mode, WorldWeather.word(p_hr.state())])
	p_hr.forced.append({"kind": "snow", "start": 11.5, "end": 14.0, "level": 0.6})
	p_hr.advance(0.1)
	if String(p_hr.state().mode) != "snow" or WorldWeather.word(p_hr.state()) != "SNOW":
		errors.append("snow did not take priority over hail: mode=%s word=%s" % [p_hr.state().mode, WorldWeather.word(p_hr.state())])
	fw.force("clear")
	fw.advance(0.05)
	if fw.hail > 0.05:
		errors.append("force('clear') did not clear forced hail: %.3f" % fw.hail)

## The grip against the wetness, as Race.grip with road tyres.
func _grip(errors: Array[String]) -> void:
	var w := WorldWeather.new(1, 0.0)
	if w.grip(0.0, 0.0, 0.0) != 1.0:
		errors.append("a dry road is not full grip: %.4f" % w.grip(0.0, 0.0, 0.0))
	var last := 1.0
	for i in 21:
		var g := w.grip(float(i) / 20.0, 0.0, 0.0)
		if g > last + 1e-9:
			errors.append("grip rose from %.4f to %.4f as the road got wetter (%.2f)" % [last, g, float(i) / 20.0])
		last = g
	var wet := MapMissions.weather_state("wet")
	if absf(w.grip(float(wet.wet), 0.0, 0.0) - float(wet.mu)) > 1e-6:
		errors.append("grip at a mission's wet (%.2f) is %.4f, the mission's %.4f" % [wet.wet, w.grip(float(wet.wet), 0.0, 0.0), wet.mu])
	var fog := MapMissions.weather_state("fog")
	if absf(w.grip(float(fog.wet), 0.0, 1.0) - float(fog.mu)) > 1e-6:
		errors.append("grip in a mission's fog is %.4f, the mission's %.4f" % [w.grip(float(fog.wet), 0.0, 1.0), fog.mu])
	var snow := MapMissions.weather_state("snow")
	if absf(w.grip(float(snow.wet), float(snow.snow), 0.0) - float(snow.mu)) > 1e-6:
		errors.append("grip in a mission's snow is %.4f, the mission's %.4f" % [w.grip(float(snow.wet), float(snow.snow), 0.0), snow.mu])
	var hail := MapMissions.weather_state("hail")
	if absf(w.grip(float(hail.wet), 0.0, 0.0, float(hail.hail)) - float(hail.mu)) > 1e-6:
		errors.append("grip in a mission's hail is %.4f, the mission's %.4f" % [w.grip(float(hail.wet), 0.0, 0.0, float(hail.hail)), hail.mu])
	if float(hail.mu) < 0.50 or float(hail.mu) > 0.62:
		errors.append("wet+hail grip %.4f outside expected ~0.55-0.60 band" % float(hail.mu))
	if absf(w.grip(0.5, 0.2, 0.3) - w.grip(0.5, 0.2, 0.3, 0.0)) > 1e-9:
		errors.append("3-arg grip() does not match 4-arg grip(..., 0.0)")
	var last_h := 1.0
	for i in 11:
		var gh := w.grip(0.0, 0.0, 0.0, float(i) / 10.0)
		if gh > last_h + 1e-9:
			errors.append("grip rose from %.4f to %.4f as hail intensified" % [last_h, gh])
		last_h = gh
	if absf(last_h - (1.0 - WorldWeather.HAIL_GRIP)) > 1e-6:
		errors.append("full dry hail grip is %.4f, expected %.4f" % [last_h, 1.0 - WorldWeather.HAIL_GRIP])
	# through a shower the wetness lags the rain and dries slowly; the grip follows the wetness
	var s := WorldWeather.new(777, 30.0)
	var peak := _rain_peak(s, 24.0, 24.0 * 40.0)
	if peak < 0.0:
		return
	var run := WorldWeather.new(777, peak - 1.0)
	var rain_end := -1.0
	var wet_at_end := 0.0
	var mu_min := 1.0
	var dry_at := -1.0
	var consistent := true
	var t := run.clock
	while t < peak + 14.0:
		run.advance(0.02)
		t = run.clock
		var st: Dictionary = run.state()
		mu_min = minf(mu_min, float(st.mu))
		if absf(float(st.mu) - run.grip(run.wet, run.snow, run.fog, run.hail)) > 1e-9:
			consistent = false
		if rain_end < 0.0 and t > peak and run.rain < 0.05:
			rain_end = t
			wet_at_end = run.wet
		if rain_end > 0.0 and dry_at < 0.0 and run.wet < 0.02:
			dry_at = t
	if not consistent:
		errors.append("the state's grip is not the grip of its wetness")
	if rain_end < 0.0:
		errors.append("the shower never ended")
		return
	if wet_at_end < 0.3:
		errors.append("the road was barely wet (%.2f) when the shower stopped" % wet_at_end)
	if dry_at >= 0.0 and dry_at - rain_end < 1.0:
		errors.append("the road dried within %.2f h of the rain stopping (it should dry slowly)" % (dry_at - rain_end))
	if not (mu_min < 0.9):
		errors.append("grip never dropped in a heavy shower (min %.3f)" % mu_min)

func _world(map: TownMap, errors: Array[String]) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var ow := OpenWorld.new()
	ow.size = Vector2(1600, 900)
	tree.root.add_child(ow)
	await tree.process_frame
	var s: Array = map.spots.get("festival", [0.0, 0.0, 0.0])
	var home := Vector2(s[0], s[1])
	ow.map = map
	ow.progress = WorldProgress.new()
	ow.world = Node3D.new()
	ow.add_child(ow.world)
	ow.route_mesh = MeshInstance3D.new()
	ow.world.add_child(ow.route_mesh)
	ow.builder = TownBuilder.new(map, ow.world)
	ow.drive = FreeCar.new(map)
	ow.drive.place(home, 0.0)
	ow.live = LiveEvents.new(map, 4242)
	ow._build_environment()
	# a seed with a heavy shower on day 1: start an hour ahead of it
	var seed_v := 777
	var probe := WorldWeather.new(seed_v, 0.0)
	var peak := _rain_peak(probe, 24.0, 24.0 * 40.0)
	if peak < 0.0:
		errors.append("no shower to drive through")
		ow.queue_free()
		await tree.process_frame
		return
	var day := int(floorf(peak / 24.0))
	ow.progress.weather_seed = seed_v
	ow.progress.weather_day = day
	ow.hour = fposmod(peak - 1.5, 24.0)
	if peak - 1.5 < float(day) * 24.0:
		ow.progress.weather_day = day - 1 # the lead-in is before midnight
	ow._start_weather()
	if ow.wx == null or absf(ow.wx.clock - (peak - 1.5)) > 1e-6:
		errors.append("the cycle did not start at the saved clock (%s vs %.3f)" % [ow.wx.clock if ow.wx else "none", peak - 1.5])
	var dh := 1.0 / 60.0 / 80.0 * 20.0 # a frame of the game clock, sped up twenty times to cross the shower
	var prev := ow.weather_state()
	var worst_rain := 0.0
	var worst_mu := 0.0
	var max_rain := 0.0
	var max_wet := 0.0
	var min_mu := 1.0
	var mu_wet_ok := true
	for _i in int(4.0 / dh):
		ow.hour = fposmod(ow.hour + dh, 24.0)
		ow._update_weather()
		var cur := ow.weather_state()
		worst_rain = maxf(worst_rain, absf(float(cur.rain) - float(prev.rain)))
		worst_mu = maxf(worst_mu, absf(float(cur.mu) - float(prev.mu)))
		max_rain = maxf(max_rain, float(cur.rain))
		max_wet = maxf(max_wet, float(cur.wet))
		min_mu = minf(min_mu, float(cur.mu))
		if absf(float(cur.mu) - ow.wx.grip(float(cur.wet), float(cur.snow), float(cur.fog), float(cur.hail))) > 1e-9 or absf(ow.drive.mu - float(cur.mu)) > 1e-9:
			mu_wet_ok = false
		prev = cur
	if max_rain < 0.85 or max_wet < 0.6:
		errors.append("the shower never reached the map: rain %.2f wet %.2f" % [max_rain, max_wet])
	if not (min_mu < 0.9):
		errors.append("the car's grip stayed at %.3f in a downpour" % min_mu)
	if not mu_wet_ok:
		errors.append("the car's grip (drive.mu) is not the grip of the road's wetness")
	if worst_rain > 0.2 or worst_mu > 0.03:
		errors.append("the weather jumped between frames: rain %.3f grip %.3f" % [worst_rain, worst_mu])
	if absf(float(ow.weather_state().mu) - ow.drive.mu) > 1e-9:
		errors.append("weather_state() and the car's grip disagree")
	# the clock word
	ow.wx.force("rain")
	var rainy := false
	for _i in 200:
		ow.hour = fposmod(ow.hour + 0.01, 24.0)
		ow._update_weather()
		if WorldWeather.word(ow.weather_state()) in ["RAIN", "HEAVY RAIN"]:
			rainy = true
	if not rainy:
		errors.append("forced rain gave no RAIN on the clock (%s)" % WorldWeather.word(ow.weather_state()))
	ow.wx.force("hail", 2.0, 0.9)
	var haily := false
	for _i in 60:
		ow.hour = fposmod(ow.hour + 0.01, 24.0)
		ow._update_weather()
		if ow.weather == "hail" and WorldWeather.word(ow.weather_state()) == "HAIL" and ow.drive.mu < 0.75:
			haily = true
	if not haily:
		errors.append("forced hail did not put HAIL on the open world: mode=%s word=%s mu=%.3f" % [ow.weather, WorldWeather.word(ow.weather_state()), ow.drive.mu])
	ow.wx.force("clear")
	# a mission's weather wins while it runs, and free roam's resumes after
	ow.wx.force("rain", 6.0)
	for _i in 120:
		ow.hour = fposmod(ow.hour + 0.01, 24.0)
		ow._update_weather()
	var before := ow.weather_state()
	var clock_before := ow.wx.clock
	var hour_before := ow.hour
	var ri := Missions.index_of("rally_bor")
	if not ow._begin_mission(ri):
		errors.append("Rajd Borów did not start on the map")
	else:
		var fog := MapMissions.weather_state("fog")
		for _i in 60:
			ow.hour = fposmod(ow.hour + 0.01, 24.0)
			ow._update_weather()
		if ow.weather != "fog" or ow.fog < 0.99 or ow.rain != 0.0 or absf(ow.drive.mu - float(fog.mu)) > 1e-6:
			errors.append("free-roam weather overrode the mission's fog: %s fog %.2f rain %.2f grip %.3f" % [ow.weather, ow.fog, ow.rain, ow.drive.mu])
		if absf(ow.wx.clock - clock_before) > 1e-9:
			errors.append("the cycle ran on during the mission (%.3f h)" % (ow.wx.clock - clock_before))
		ow._pause_action("abandon_live")
		var after := ow.weather_state()
		for k in ["rain", "wet", "fog", "mu"]:
			if absf(float(after[k]) - float(before[k])) > 1e-6:
				errors.append("free-roam %s after the mission is %.4f, was %.4f" % [k, after[k], before[k]])
		if absf(ow.hour - hour_before) > 0.01:
			errors.append("the mission left the clock at %.2f, not %.2f" % [ow.hour, hour_before])
		ow.hour = fposmod(ow.hour + 0.05, 24.0)
		ow._update_weather()
		if absf(ow.wx.clock - clock_before - 0.05) > 1e-6:
			errors.append("the cycle did not resume from the run's hour: advanced %.4f, expected 0.05" % (ow.wx.clock - clock_before))
		if float(ow.weather_state().rain) < 0.2:
			errors.append("the rain did not resume after the mission: %.2f" % float(ow.weather_state().rain))
	# the medals of a live event run on the grip it is raced in
	ow.live.update(0.1, 0.0, home, PackedVector2Array(), true)
	var lev := {}
	for ev in ow.live.board:
		if String(ev.kind) == "race" and int(ev.get("rivals", 0)) > 0:
			lev = ev
			break
	if lev.is_empty():
		errors.append("no live race on the board to start in the rain")
	else:
		ow._begin_live_ev(lev)
		if absf(float(lev.get("mu", 1.0)) - ow.drive.mu) > 1e-9 or not (float(lev.get("mu", 1.0)) < 1.0):
			errors.append("a live event in the rain carries grip %s, the car's is %.3f" % [lev.get("mu"), ow.drive.mu])
		ow._pause_action("abandon_live")
	ow.wx.force("clear")
	# Always dry stays dry while the cycle goes through a shower; switching it back on shows the weather as it is
	ow.progress.weather_dynamic = false
	ow.set_weather(MapMissions.weather_state("dry"))
	var dry_ok := true
	var peak_mid := 0.0
	var dry_wx := WorldWeather.new(seed_v, 0.0)
	ow.progress.weather_day = day
	ow.hour = fposmod(peak - 1.0, 24.0)
	ow._start_weather()
	for _i in int(3.0 / dh):
		ow.hour = fposmod(ow.hour + dh, 24.0)
		ow._update_weather()
		peak_mid = maxf(peak_mid, ow.wx.rain)
		if ow.weather != "dry" or ow.rain != 0.0 or ow.wet != 0.0 or ow.drive.mu != 1.0:
			dry_ok = false
	if not dry_ok:
		errors.append("Always dry rained: %s rain %.2f wet %.2f grip %.3f" % [ow.weather, ow.rain, ow.wet, ow.drive.mu])
	if peak_mid < 0.8:
		errors.append("the cycle did not run behind Always dry (rain peaked at %.2f)" % peak_mid)
	ow.wx.force("rain", 4.0)
	ow.hour = fposmod(ow.hour + 0.4, 24.0)
	ow._update_weather()
	ow.set_weather_dynamic(true)
	if not ow.progress.weather_dynamic or not (ow.rain > 0.1) or not (ow.drive.mu < 1.0):
		errors.append("switching Dynamic back on did not bring the weather back: rain %.2f grip %.3f" % [ow.rain, ow.drive.mu])
	ow.set_weather_dynamic(false)
	if ow.rain != 0.0 or ow.wet != 0.0 or ow.drive.mu != 1.0:
		errors.append("switching to Always dry left rain %.2f wet %.2f grip %.3f" % [ow.rain, ow.wet, ow.drive.mu])
	# the seed, the day and the switch survive the save, and a reload continues the same weather
	var saved := WorldProgress.from_dict(JSON.parse_string(JSON.stringify(ow.progress.to_dict())))
	if saved.weather_seed != seed_v or saved.weather_day != ow.progress.weather_day or saved.weather_dynamic:
		errors.append("the weather save lost its seed, day or switch: %d / %d / %s" % [saved.weather_seed, saved.weather_day, saved.weather_dynamic])
	var old_save := WorldProgress.from_dict({"hour": 12.0})
	if old_save.weather_seed != 0 or old_save.weather_day != 0 or not old_save.weather_dynamic:
		errors.append("an old save does not default to Dynamic with no seed")
	# a day counted across midnight: clock - hour is a whole number of days
	ow.progress.weather_dynamic = true
	ow.progress.weather_day = 3
	ow.hour = 23.9
	ow._start_weather()
	for _i in 6:
		ow.hour = fposmod(ow.hour + 0.05, 24.0)
		ow._update_weather()
	var days_run := (ow.wx.clock - ow.hour) / 24.0
	if absf(days_run - 4.0) > 1e-6:
		errors.append("across midnight the cycle's day is %.4f, not 4" % days_run)
	ow.queue_free()
	await tree.process_frame
