## Campaign missions: the events beside the ten stages (Campaign.STAGES) that are not plain lap races: a sprint,
## a knockout, a rally, drag races, a drift attack and an off-road race. Each opens once a stage is cleared, so they
## spread over the three acts, and each is a beacon in the open world at the real place it starts (the route's own
## start line, worked out from the track at load). A mission is addressed by a campaign index of BASE + its place
## in MISSIONS, so Campaign.get_stage / is_unlocked / record_result and the game's campaign flow take it like a stage.
## Progress lives in campaign.json under "missions" ({id: {cleared, best, fails, tier, time}}); RESET CAMPAIGN
## clears it with the rest.
class_name Missions
extends RefCounted

const BASE := 100
const KINDS := ["sprint", "knockout", "rally", "drag", "drift", "offroad"]
const KIND_NAMES := {"sprint": "SPRINT", "knockout": "KNOCKOUT", "rally": "RALLY", "drag": "DRAG RACE", "drift": "DRIFT",
	"offroad": "OFF-ROAD"}
const COLOR := Color("#3fd6e6") ## a mission's beacon (stages are orange, gold once done)
const DONE_COLOR := Color("#9fe8c8")
const ACT_NAMES := ["Act I: Silesian Grassroots", "Act II: Regional Championship", "Act III: Global Legends"]

## id, kind, title, after (the stage, 0-based, that must be cleared first), track, laps, opponents, difficulty,
## weather, start_hour, target (a place; drift: tiers [bronze, silver, gold] points), at (m after the start line
## where the beacon stands), reward_car (a car key won on the first clear; filled in with the car catalogue).
const MISSIONS := [
	{
		"id": "drag_quarter", "kind": "drag", "after": 0, "act": 1,
		"title": "Ćwierć Mili na S1",
		"track": "s1_sprint", "finish_distance": 402.0, "laps": 1, "opponents": 3, "difficulty": "easy",
		"weather": "dry", "start_hour": 21.5, "target": 1, "at": 150.0,
		"trophy": "S1 Quarter-Mile Plate", "reward_car": "",
		"desc": "Word in the Fest car park is that the night shift races on the S1 when the lorries have gone. Four Seicentos two abreast on the northbound carriageway, the lights at the Wola junction, a quarter mile to the gantry.",
		"tip": "A Seicento has nothing to spare: wait for the green, keep it straight, and with the manual box change up a little before the limiter: the automatic gets there first otherwise.",
	},
	{
		"id": "sprint_s1", "kind": "sprint", "after": 1, "act": 1,
		"title": "S1 Sprint",
		"track": "s1_sprint", "laps": 1, "opponents": 7, "difficulty": "easy",
		"weather": "dry", "start_hour": 11.0, "target": 3, "at": 0.0,
		"trophy": "Expressway Sprint Cup", "reward_car": "",
		"desc": "One flat-out run of the S1 closed between the Wola and Brzeszcze junctions: up one carriageway, over the dumbbell bridge and back down the other, 9.6 km with eight cars and no second chances.",
		"tip": "The turn-rounds at each end are the only real corners: brake early there, then tuck into a slipstream and hold it all the way.",
	},
	{
		"id": "drift_babudy", "kind": "drift", "after": 2, "act": 1,
		"title": "Drift w Babudach",
		"track": "babudy_gora", "laps": 1, "opponents": 0, "difficulty": "easy", "finish_distance": 2600.0,
		"weather": "dry", "start_hour": 17.5, "tiers": [600, 2500, 6000], "at": 0.0,
		"trophy": "Babudy Sideways Shield", "reward_car": "",
		"desc": "The lads from Góra want to see it sideways. 2.6 km of the lanes from Babudy towards Góra, gravel and tarmac, judged on angle and speed. Link the slides and the score multiplies; touch a fence or leave the road and the combo is gone.",
		"tip": "Flick the handbrake (Space) as you turn in, catch it on the throttle, and let the next bend take the slide over before the combo banks.",
	},
	{
		"id": "offroad_kolonia", "kind": "offroad", "after": 3, "act": 2,
		"title": "Kolonia Stawowa Off-Road",
		"track": "kolonia_stawowa", "laps": 1, "opponents": 5, "difficulty": "easy",
		"weather": "dry", "start_hour": 13.5, "target": 3, "at": 0.0,
		"trophy": "Fishpond Mud Cup", "reward_car": "",
		"desc": "Six cars wheel to wheel on the dykes and forest tracks between the Kolonia Stawowa fishponds: 6 km of gravel and dirt, a hairpin on ul. Oświęcimska and the Bronisław bridge.",
		"tip": "Loose roads punish a late brake twice: slow down early, turn in gently and let the car settle before you get back on the power.",
	},
	{
		"id": "knockout_bor", "kind": "knockout", "after": 4, "act": 2,
		"title": "Bór Knockout",
		"track": "bor", "laps": 5, "opponents": 5, "difficulty": "medium",
		"weather": "dry", "start_hour": 15.5, "target": 2, "at": 0.0,
		"trophy": "Last Man in the Forest", "reward_car": "golf4",
		"desc": "Six cars on the Mały Bór forest lanes next to Bór, one lap cut into five sectors: every time the leader crosses a sector line the last car is out. Make the final two-car sector, or win it.",
		"tip": "The sector lines are the only places that matter: never be last when the leader reaches one, even if it costs you the lead.",
	},
	{
		"id": "rally_bor", "kind": "rally", "after": 5, "act": 2,
		"title": "Rajd Borów",
		"track": "bor", "rally": "bor", "opponents": 9, "difficulty": "medium",
		"weather": "fog", "start_hour": 8.5, "target": 3,
		"trophy": "Rajd Borów Podium", "reward_car": "",
		"desc": "The local rally runs its special stages on the roads round Brzeszcze: Mały Bór, Kolonia Stawowa and Babudy–Góra at dusk. Between them you drive the liaison to the next start yourself; the clock only runs on the stages.",
		"tip": "A rally is won on the stages you don't crash on: drive at nine tenths, listen to the co-driver and keep the car whole for the service.",
	},
	{
		"id": "drag_kilometre", "kind": "drag", "after": 7, "act": 3,
		"title": "Kilometr na S1",
		"track": "s1_sprint", "finish_distance": 1000.0, "laps": 1, "opponents": 3, "difficulty": "hard",
		"weather": "dry", "start_hour": 23.0, "target": 1, "at": 400.0,
		"trophy": "Standing Kilometre Crown", "reward_car": "",
		"desc": "The factory test drivers heard about the quarter mile. Now it is a standing kilometre against three of them, flat out until the Seicento runs out of gears.",
		"tip": "Over a kilometre the slipstream comes back into it: get away first, then stay in the middle of your lane so nobody gets your tow.",
	},
]

static var _poses := {} ## track key + at -> [x, y, heading] (read from the track files once)

# ------------------------------------------------------------------ lookups

static func is_mission(index: int) -> bool:
	return index >= BASE and index < BASE + MISSIONS.size()

static func index_of(id: String) -> int:
	for k in MISSIONS.size():
		if MISSIONS[k].id == id:
			return BASE + k
	return -1

static func get_def(index: int) -> Dictionary:
	return MISSIONS[clampi(index - BASE, 0, MISSIONS.size() - 1)]

static func kind_of(index: int) -> String:
	return String(get_def(index).kind) if is_mission(index) else ""

static func progress(prog: Dictionary, index: int) -> Dictionary:
	var all = prog.get("missions", {})
	if not all is Dictionary:
		return {}
	var p = all.get(String(get_def(index).id), {})
	return p if p is Dictionary else {}

## Whether the stage a mission waits for is cleared (its trophy won, or the chain already past it).
static func is_unlocked(index: int, prog: Dictionary = {}) -> bool:
	if not is_mission(index):
		return false
	if prog.is_empty():
		prog = Campaign.load_progress()
	var after := int(get_def(index).after)
	var trophies: Array = prog.get("trophies", [])
	return int(prog.get("unlocked", 0)) > after or String(Campaign.STAGES[after].trophy) in trophies

static func is_cleared(index: int, prog: Dictionary = {}) -> bool:
	if prog.is_empty():
		prog = Campaign.load_progress()
	return bool(progress(prog, index).get("cleared", false))

## Kinds that race a field ease after a missed try, as the stages do; a drift attack keeps its tiers.
static func eases(kind: String) -> bool:
	return kind != "drift"

## The mission in the shape of a campaign stage (Campaign.get_stage), with its eased difficulty and the extra
## fields the mission flow reads (kind, mission, tiers, finish_distance, rally).
static func as_stage(index: int) -> Dictionary:
	var m: Dictionary = get_def(index)
	var prog := Campaign.load_progress()
	var p := progress(prog, index)
	var fails := int(p.get("fails", 0))
	var base: String = m.get("difficulty", "medium")
	var at := Campaign.LEVELS.find(base)
	var eased := mini(fails / Campaign.FAILS_PER_EASE, at) if eases(String(m.kind)) else 0
	var st := {
		"id": m.id, "mission": index - BASE, "kind": m.kind, "act": m.act, "act_name": ACT_NAMES[clampi(int(m.act) - 1, 0, 2)],
		"title": "%s: %s" % [KIND_NAMES[m.kind].capitalize(), m.title], "track": m.track, "laps": int(m.get("laps", 1)),
		"weather": m.weather, "time_of_day": float(m.start_hour), "start_hour": float(m.start_hour), "wear_mult": 1.0,
		"fuel_mult": 1.0, "opponents": int(m.opponents), "base_difficulty": base, "difficulty": Campaign.LEVELS[at - eased],
		"eased": eased, "fails": fails, "target_pos": int(m.get("target", 3)), "grid": "pole" if m.kind == "drag" else "p%d" % (int(m.opponents) / 2 + 1),
		"trophy": m.trophy, "desc": m.desc, "tip": m.tip, "after": int(m.after), "reward_car": m.get("reward_car", ""),
		"finish_distance": float(m.get("finish_distance", 0.0)), "tiers": m.get("tiers", []), "rally": m.get("rally", ""),
	}
	if m.kind == "knockout":
		st.laps = int(m.opponents) # N cars: the leader completes N-1 laps
	return st

## Turns a campaign race's settings into the mission's rules (a stage index passes through untouched).
static func apply_settings(st: RaceSettings, index: int) -> void:
	if not is_mission(index):
		return
	var m := as_stage(index)
	st.mission = String(m.kind)
	st.mandatory_stop = false # one lap, a sprint or a quarter mile: no pit stop to make
	st.two_compounds = false
	match String(m.kind):
		"knockout":
			st.knockout = true
			st.laps = int(m.laps)
		"drag":
			st.finish_distance = float(m.finish_distance)
			st.laps = 1
			st.grid = "pole"
		"drift":
			st.drift_score = true
			st.drift_tiers = PackedInt32Array(m.tiers)
			st.opponents = 0
			st.finish_distance = float(m.finish_distance)
		"offroad":
			st.loose_spans = true

## The text a mission's target reads as.
static func target_text(index: int) -> String:
	var m := as_stage(index)
	match String(m.kind):
		"drift":
			var t: Array = m.tiers
			return "Score %s for bronze (silver %s, gold %s)" % [_k(int(t[0])), _k(int(t[1])), _k(int(t[2]))]
		"knockout":
			return "Win the knockout" if int(m.target_pos) == 1 else "Survive to the final (top %d)" % int(m.target_pos)
		"rally":
			return "Top %d overall" % int(m.target_pos)
	return "Win" if int(m.target_pos) == 1 else "Finish P%d or better" % int(m.target_pos)

static func length_text(index: int) -> String:
	var m := as_stage(index)
	match String(m.kind):
		"drag":
			return "%d m standing start" % int(m.finish_distance)
		"drift":
			return "%.1f km solo" % (float(m.finish_distance) / 1000.0)
		"knockout":
			return "%d sectors, one car out per sector" % int(m.laps)
		"rally":
			var ev := Rally.event(String(m.rally))
			var on_map: int = ev.get("stages", []).filter(func(sd): return not MapMissions.OFF_MAP.has(String(sd.track))).size()
			return "%d special stages and the liaisons between" % on_map
	return "%d lap%s" % [int(m.laps), "" if int(m.laps) == 1 else "s"]

# ------------------------------------------------------------------ results

## A finished race judged against the mission: {kind, pos, of, dnf, time, score, tier, success, line}.
static func judge(race: Race, index: int) -> Dictionary:
	var m := as_stage(index)
	var kind := String(m.kind)
	var out := {"kind": kind, "pos": 999, "of": race.cars.size(), "dnf": race.player.dnf, "time": null, "score": 0,
		"tier": 0, "success": false, "line": ""}
	if kind == "drift":
		var sc := race.drift.total() if race.drift else 0
		if race.player.dnf:
			sc = race.drift.score if race.drift else 0
		out.score = sc
		out.tier = DriftScore.tier(sc, m.tiers)
		out.success = out.tier >= 1
		out.pos = 4 - int(out.tier) if out.success else 999
		var t: Array = m.tiers
		if out.tier >= 3:
			out.line = "%s points: GOLD (gold is %s)" % [_k(sc), _k(int(t[2]))]
		elif out.success:
			out.line = "%s points: %s · %s more for %s" % [_k(sc), DriftScore.TIER_NAMES[out.tier], _k(int(t[out.tier]) - sc),
				DriftScore.TIER_NAMES[int(out.tier) + 1].to_lower()]
		else:
			out.line = "%s points: missed bronze by %s" % [_k(sc), _k(int(t[0]) - sc)]
		return out
	var rows := race.results()
	var target := int(m.target_pos)
	var mine: Dictionary = {}
	var at_target: Dictionary = {}
	for r in rows:
		if (r.car as RaceCar).is_player:
			mine = r
		if int(r.pos) == target:
			at_target = r
	out.pos = int(mine.pos)
	out.time = mine.total
	var knocked := kind == "knockout" and race.out_order.has(race.player) and race.player.dnf_reason.begins_with("Knocked")
	out.success = out.pos <= target and (not race.player.dnf or (knocked and kind == "knockout" and out.pos <= target))
	var place := "P%d of %d" % [out.pos, rows.size()]
	if race.player.dnf and not knocked:
		out.line = "Did not finish (%s): target %s" % [race.player.dnf_reason, target_text(index).to_lower()]
		out.pos = 999
		out.success = false
		return out
	if knocked:
		place = "%s, knocked out on lap %d" % [place, _ko_lap(race)]
	if out.success:
		var better: int = target - int(out.pos)
		out.line = "%s: cleared%s" % [place, (" with %d place%s to spare" % [better, "" if better == 1 else "s"]) if better > 0 else ""]
	else:
		var short: int = int(out.pos) - target
		out.line = "%s: missed by %d place%s" % [place, short, "" if short == 1 else "s"]
		if mine.total != null and not at_target.is_empty() and at_target.total != null:
			out.line += ", %.3f s behind P%d" % [float(mine.total) - float(at_target.total), target]
	if kind == "drag" and mine.total != null:
		out.line += " · %d m in %.3f s" % [int(m.finish_distance), float(mine.total)]
	return out

static func _ko_lap(race: Race) -> int:
	for e in race.knocked_out:
		if e.car == race.player:
			return int(e.lap)
	return 0

## A finished rally event judged against the mission.
static func judge_rally(ev: RallyEvent, index: int) -> Dictionary:
	var m := as_stage(index)
	var target := int(m.target_pos)
	var table := ev.standings()
	var me: Dictionary = {}
	var at_target: Dictionary = {}
	for r in table:
		if r.is_player:
			me = r
		if int(r.pos) == target:
			at_target = r
	var pos := int(me.get("pos", 999))
	var out := {"kind": "rally", "pos": pos, "of": table.size(), "dnf": false, "time": me.get("time"), "score": 0, "tier": 0,
		"success": pos <= target, "line": ""}
	if out.success:
		out.line = "P%d overall of %d: cleared" % [pos, table.size()]
	else:
		out.line = "P%d overall of %d: missed by %d place%s, %.1f s behind P%d" % [pos, table.size(), pos - target,
			"" if pos - target == 1 else "s", float(me.get("time", 0.0)) - float(at_target.get("time", 0.0)), target]
	return out

## A fresh rally for a rally mission (never saved over the main menu's rally).
static func new_rally(index: int) -> RallyEvent:
	var m := as_stage(index)
	return RallyEvent.new(String(m.rally), -1, String(m.difficulty))

## Writes a judged result into campaign.json: {success, first_clear, fans, trophy, line}.
static func record(index: int, outcome: Dictionary) -> Dictionary:
	var m := as_stage(index)
	var prog := Campaign.load_progress()
	var all = prog.get("missions", {})
	if not all is Dictionary:
		all = {}
	var p: Dictionary = (all.get(String(m.id), {}) as Dictionary).duplicate() if all.get(String(m.id), {}) is Dictionary else {}
	var success: bool = outcome.success
	var first_clear: bool = success and not bool(p.get("cleared", false))
	if String(m.kind) == "drift":
		p["best"] = maxi(int(p.get("best", 0)), int(outcome.score))
		p["tier"] = maxi(int(p.get("tier", 0)), int(outcome.tier))
	else:
		p["best"] = mini(int(p.get("best", 999)), int(outcome.pos))
	if outcome.get("time") != null and String(m.kind) == "drag" and success:
		p["time"] = minf(float(p.get("time", INF)), float(outcome.time)) if p.has("time") else float(outcome.time)
	if success:
		p["cleared"] = true
		p.erase("fails")
	else:
		p["fails"] = int(p.get("fails", 0)) + 1
	p["tries"] = int(p.get("tries", 0)) + 1
	all[String(m.id)] = p
	prog["missions"] = all
	var car := String(m.get("reward_car", ""))
	if success and car != "":
		var cars: Array = prog.get("cars", []) if prog.get("cars", []) is Array else []
		if not car in cars:
			cars.append(car)
		prog["cars"] = cars
	Campaign.save_progress(prog)
	return {"success": success, "first_clear": first_clear, "fans": reward(index, outcome, first_clear),
		"trophy": m.trophy if success else "", "line": outcome.get("line", ""), "reward_car": m.reward_car if first_clear else ""}

## Fans a mission result pays: as the stage it follows pays (FanLevels.stage_reward). A drift tier counts as a
## place (gold first, bronze third, against a target of third).
static func reward(index: int, outcome: Dictionary, first_clear: bool) -> int:
	var m := as_stage(index)
	var target := 3 if String(m.kind) == "drift" else int(m.target_pos)
	var pos := int(outcome.get("pos", 999)) if outcome.get("success", false) else 999
	return FanLevels.stage_reward(int(m.after), pos, target, first_clear)

# ------------------------------------------------------------------ the open world

## Where a mission's beacon stands: [x, y, heading] in the open world's metres (the routes are baked from the same
## map, so the track's own start line is the place), `at` metres after the line; a rally starts where its first
## stage does. [] when the track is not one of the map's routes.
static func beacon_pose(index: int) -> Array:
	var m: Dictionary = get_def(index)
	var key := String(m.track)
	var at := float(m.get("at", 0.0))
	if String(m.kind) == "rally":
		var ev := Rally.event(String(m.rally))
		if not ev.is_empty():
			var sd: Dictionary = ev.stages[0]
			key = String(sd.track)
			at = Rally.span(sd).x + 30.0 if not sd.get("baked", false) else 30.0
	var cache_key := "%s@%d" % [key, int(at)]
	if _poses.has(cache_key):
		return _poses[cache_key]
	var pose := []
	var def := Track.load_def(key)
	var text := FileAccess.get_file_as_string("res://data/tracks/%s.json" % key)
	var raw = JSON.parse_string(text) if text != "" else null
	if def and raw is Dictionary:
		var pts: Array = raw.pts
		var n := pts.size() / 2
		var step := float(raw.step)
		var off := SimUtil.js_round(def.start_offset / step)
		var i := posmod(int(round(at / step)) + off, n)
		var j := (i + 1) % n
		pose = [float(pts[2 * i]), float(pts[2 * i + 1]),
			atan2(float(pts[2 * j + 1]) - float(pts[2 * i + 1]), float(pts[2 * j]) - float(pts[2 * i]))]
	_poses[cache_key] = pose
	return pose

## The beacon's pose on the open world's own roads: beacon_pose snapped onto the nearest road within 40 m (the
## older circuits such as Bór were drawn from OSM on their own and sit a few metres off the map's road lines).
static func place(index: int, map: TownMap) -> Array:
	var pose := beacon_pose(index)
	if pose.is_empty():
		return []
	var p := Vector2(pose[0], pose[1])
	if map.road_at(p.x, p.y, -INF, 1.0).is_empty():
		var near := map.nearest_road(p, 40.0)
		if near.is_empty():
			return []
		p = near.pos
	return [p.x, p.y, float(pose[2])]

## The briefing card in the open world: [subtitle, title, body, hint].
static func card(index: int, fans_level: int) -> Array:
	var m := as_stage(index)
	var prog := Campaign.load_progress()
	var p := progress(prog, index)
	var tr_key := String(MapMissions.OFF_MAP.get(String(m.track), m.track)) # as raced on the map
	var tr_name := Track.load_def(tr_key).display_name if String(m.kind) != "rally" else String(Rally.event(String(m.rally)).get("name", ""))
	var field := "solo" if int(m.opponents) == 0 else "%d rivals (%s)" % [int(m.opponents), String(m.difficulty).capitalize()]
	var best := ""
	if String(m.kind) == "drift" and int(p.get("best", 0)) > 0:
		best = " · Best %s" % _k(int(p.best))
	elif int(p.get("best", 999)) < 999:
		best = " · Best P%d" % int(p.best)
	if int(m.get("eased", 0)) > 0:
		field += ", eased after %d tries" % int(m.fails)
	var body := "%s\n\n%s · %s · %s · %s\nTarget: %s%s\nUp to %s fans on a first clear (fan level %d)" % [m.desc, tr_name,
		length_text(index), String(m.weather).capitalize(), field, target_text(index), best,
		OpenWorldHud._thousands(reward(index, {"success": true, "pos": 1, "tier": 3}, true)), fans_level]
	var sub := "%s MISSION · %s" % [KIND_NAMES[m.kind], String(m.act_name).to_upper()]
	return [sub, String(m.title), body, "ENTER / B  ▸  START MISSION HERE ON THE MAP"]

static func _k(n: int) -> String:
	return OpenWorldHud._thousands(n)
