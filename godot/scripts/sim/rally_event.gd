## One rally being run: the event (Rally.EVENTS), the rivals entered, every stage's times and penalties, the
## overall classification, and the car's condition carried from stage to stage (Service parts) with the
## service halts in between. Save it with to_dict / from_dict (JSON-safe).
##
## Flow, per stage i = stage_index:
##   var st := ev.settings_for_stage(base_settings)   # a RaceSettings for the stage (Rally.configure_stage)
##   var race := Race.new(st, null, -1, models)
##   ev.begin_stage(race)                              # damage carried in, the rivals' runs simulated
##   ... drive until race.phase == "finished" ...
##   var rows := ev.finish_stage(race)                  # stage results; the car's parts kept for service
##   if ev.service_minutes() > 0: show service, then ev.apply_service(parts, minutes_used)
##   ev.standings()                                     # overall classification
class_name RallyEvent
extends RefCounted

var key := ""
var def: Dictionary = {}
var seed := 0
var difficulty := "medium"
var player_name := "You"
var player_number := 9
var player_color := Color("#b3121d")
var rivals: Array = [] ## Rally.make_rivals
var stage_index := 0 ## the next stage to run
var results: Array = [] ## per stage run: {player: {time, penalty, penalties, dnf, splits}, rivals: [simulate_rivals rows]}
var service_penalty := 0.0 ## s added to the player's overall for service overruns
var service_log: Array = [] ## [{before_stage, minutes, used, penalty}]
var parts := {} ## the car's damage carried into the next stage (Service.snapshot)
var pull := 0.0 ## Service.pull_rate, so the steering pull keeps its side
var _pending: Array = [] ## the rivals' runs on the stage being driven

func _init(event_key := "", seed_ := -1, difficulty_ := "") -> void:
	if event_key == "":
		return
	key = event_key
	def = Rally.event(event_key)
	assert(not def.is_empty(), "unknown rally event %s" % event_key)
	seed = seed_ if seed_ >= 0 else randi() & 0x7fffff
	difficulty = difficulty_ if difficulty_ != "" else def.get("difficulty", "medium")
	rivals = Rally.make_rivals(difficulty, seed)

func stage_count() -> int:
	return def.get("stages", []).size()

func stage_def(i := -1) -> Dictionary:
	return def.stages[stage_index if i < 0 else i]

func is_over() -> bool:
	return stage_index >= stage_count()

## Minutes of service before stage i (default: the next one), 0 for none.
func service_minutes(i := -1) -> int:
	var j := stage_index if i < 0 else i
	return int(def.stages[j].get("service", 0)) if j < stage_count() else 0

## The RaceSettings for stage i (default: the next): a copy of base (the player's name, paint, gearbox, aids,
## set-up) turned into the stage.
func settings_for_stage(base: RaceSettings = null, i := -1) -> RaceSettings:
	var st: RaceSettings = base.duplicate(true) if base else RaceSettings.new()
	Rally.configure_stage(st, stage_def(i), difficulty)
	return st

## Call once the stage's Race is built, before driving it: fits the damage carried in and simulates the
## rivals' runs on this stage (deterministic for the event's seed). The first stage on a circuit runs the
## lap model's co-driver calibration (Qualifying.coach_scale), so call it behind the loading screen.
func begin_stage(race: Race) -> void:
	player_name = race.s.player_name
	player_number = race.s.player_number
	player_color = race.s.player_color
	if not parts.is_empty():
		Service.fit(race.player, parts, pull)
	var wet := race.weather.wet
	var paces := rivals.map(func(r: Dictionary) -> float: return float(r.skill) * (1.0 + (float(r.wet) - 1.0) * minf(1.0, wet * 2.0)))
	var model := Rally.base_times(race, paces)
	_pending = simulate(stage_index, model.times, model.splits)
	if race.stage:
		race.stage.event = self
		race.stage.index = stage_index
		race.stage.rivals = _pending
		for r in rivals:
			race.stage.names[r.id] = r.name

## The rivals' runs on stage i from their clean times (Rally.simulate_rivals with this event's seed).
func simulate(i: int, base: Array, split_frac: Array) -> Array:
	return Rally.simulate_rivals(rivals, base, split_frac, seed, i, stage_def(i).get("surface", "tarmac"))

## Call when the stage's race is over (race.phase == "finished", or the player quits it: then it is a DNF).
## Keeps the car's damage for the service and returns the stage's results (stage_results).
func finish_stage(race: Race) -> Array:
	var p := race.player
	var st: Rally.Stage = race.stage
	var done: bool = st != null and st.time != null and not p.dnf
	var pens: Array = st.penalties.duplicate(true) if st else []
	record_stage(float(st.time) if done else 0.0, pens, not done, st.split_times.duplicate() if st else [], _pending)
	parts = Service.snapshot(p)
	pull = Service.pull_rate(p)
	_pending = []
	return stage_results(stage_index - 1)

## Store the player's run on the next stage and move on (finish_stage does this from a race; tests call it).
func record_stage(time: float, penalties: Array, dnf: bool, splits: Array, rival_rows: Array) -> void:
	var pen := 0.0
	for x in penalties:
		pen += float(x[1])
	results.append({"player": {"time": time, "penalty": pen, "penalties": penalties, "dnf": dnf, "splits": splits},
		"rivals": rival_rows})
	stage_index += 1

## After a service halt: the parts as the crew left them and the minutes they took; going over the
## allocation costs SERVICE_LATE s a minute. Returns that penalty.
func apply_service(parts_after: Dictionary, minutes_used: int) -> float:
	var allowed := service_minutes()
	var late := maxi(0, minutes_used - allowed)
	var pen := late * Rally.SERVICE_LATE
	parts = {}
	for part in parts_after:
		if float(parts_after[part]) >= 0.01:
			parts[part] = float(parts_after[part])
	service_penalty += pen
	service_log.append({"before_stage": stage_index, "minutes": allowed, "used": minutes_used, "penalty": pen})
	return pen

## The slowest finisher's time on stage i (for the superrally time of those who didn't finish).
func _slowest(i: int) -> float:
	var r: Dictionary = results[i]
	var worst := 0.0
	if not r.player.dnf:
		worst = r.player.time + r.player.penalty
	for x in r.rivals:
		if x.time != null:
			worst = maxf(worst, x.time)
	return worst

## Stage i's classification: [{pos, id, name, number, color, is_player, time (with penalties), penalty, gap,
## dnf, note}], fastest first. A car that didn't finish is classified at the slowest time + Rally.SUPERRALLY.
func stage_results(i: int) -> Array:
	var r: Dictionary = results[i]
	var slow := _slowest(i)
	var rows := []
	var me: Dictionary = r.player
	rows.append({"id": 0, "name": player_name, "number": player_number, "color": player_color, "is_player": true,
		"time": slow + Rally.SUPERRALLY if me.dnf else me.time + me.penalty, "penalty": me.penalty, "dnf": me.dnf,
		"note": "did not finish" if me.dnf else ", ".join(me.penalties.map(func(x): return "%s +%d s" % [x[0], roundi(x[1])]))})
	for x in r.rivals:
		var who := _rival(x.id)
		rows.append({"id": x.id, "name": who.name, "number": who.number, "color": Color(who.color), "is_player": false,
			"time": slow + Rally.SUPERRALLY if x.dnf else x.time, "penalty": 0.0, "dnf": x.dnf, "note": x.note})
	return _rank(rows)

## Overall after the stages run so far (or the first `upto`): [{pos, id, name, number, color, is_player,
## time (total), gap, stage_wins, dnf_stages}].
func standings(upto := -1) -> Array:
	var n := results.size() if upto < 0 else mini(upto, results.size())
	var total := {}
	var wins := {}
	var dnfs := {}
	for i in n:
		var rows := stage_results(i)
		for row in rows:
			total[row.id] = float(total.get(row.id, 0.0)) + float(row.time)
			if row.pos == 1:
				wins[row.id] = int(wins.get(row.id, 0)) + 1
			if row.dnf:
				dnfs[row.id] = int(dnfs.get(row.id, 0)) + 1
	total[0] = float(total.get(0, 0.0)) + service_penalty
	var out := []
	out.append({"id": 0, "name": player_name, "number": player_number, "color": player_color, "is_player": true,
		"time": total[0], "stage_wins": wins.get(0, 0), "dnf_stages": dnfs.get(0, 0)})
	for who in rivals:
		out.append({"id": who.id, "name": who.name, "number": who.number, "color": Color(who.color), "is_player": false,
			"time": float(total.get(who.id, 0.0)), "stage_wins": wins.get(who.id, 0), "dnf_stages": dnfs.get(who.id, 0)})
	return _rank(out)

## The player's overall position (1-based) after the stages run.
func player_position() -> int:
	for row in standings():
		if row.is_player:
			return row.pos
	return 0

func _rival(id: int) -> Dictionary:
	for r in rivals:
		if int(r.id) == id:
			return r
	return {"name": "?", "number": 0, "color": "#888888"}

static func _rank(rows: Array) -> Array:
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.time != b.time:
			return a.time < b.time
		return int(a.id) < int(b.id))
	var lead: float = rows[0].time if rows.size() else 0.0
	for k in rows.size():
		rows[k].pos = k + 1
		rows[k].gap = rows[k].time - lead
	return rows

# ---------------- saving ----------------
func to_dict() -> Dictionary:
	return {"key": key, "seed": seed, "difficulty": difficulty, "stage_index": stage_index, "results": results,
		"service_penalty": service_penalty, "service_log": service_log, "parts": parts, "pull": pull,
		"player": {"name": player_name, "number": player_number, "color": player_color.to_html()}}

static func from_dict(d: Dictionary) -> RallyEvent:
	var ev := RallyEvent.new(str(d.get("key", "")), int(d.get("seed", 0)), str(d.get("difficulty", "")))
	ev.stage_index = int(d.get("stage_index", 0))
	ev.results = d.get("results", [])
	# JSON hands numbers back as floats and keeps nulls: the rows are read with float()/int() throughout
	for r in ev.results:
		for x in r.rivals:
			x.id = int(x.id)
	ev.service_penalty = float(d.get("service_penalty", 0.0))
	ev.service_log = d.get("service_log", [])
	ev.parts = d.get("parts", {})
	ev.pull = float(d.get("pull", 0.0))
	var pl: Dictionary = d.get("player", {})
	ev.player_name = str(pl.get("name", "You"))
	ev.player_number = int(pl.get("number", 9))
	ev.player_color = Color(str(pl.get("color", "b3121d")))
	return ev
