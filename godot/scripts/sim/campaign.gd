## Campaign mode ("The Seicento Odyssey"): A 9-stage narrative racing career
## tracing a grassroots Polish racer's journey from Silesian village lanes to Tokyo.
class_name Campaign
extends RefCounted

const SAVE_FILE := "campaign.json"
static var save_file := SAVE_FILE ## tests point this at a file of their own (the dev sandbox is shared)

const STAGES := [
	{
		"id": "stage_1",
		"act": 1,
		"act_name": "Act I: Silesian Grassroots",
		"title": "Stage 1: Rookie Shakedown",
		"track": "wilamowice",
		"laps": 2,
		"weather": "dry",
		"time_of_day": 14.0,
		"start_hour": 14.0,
		"wear_mult": 2.0,
		"fuel_mult": 1.0,
		"opponents": 5,
		"difficulty": "easy",
		"target_pos": 3,
		"grid": "p3",
		"trophy": "Wilamowice Bronze Piston",
		"desc": "Your mechanic uncle handed you the keys to a stock 1998 Fiat Seicento 900 (39 bhp). Prove your racecraft round Wilamowice: from the Rynek past Holy Trinity church, down Kęcka and Krakowska into Hecznarowice, back through the fields and the esses by the pond.",
		"tip": "The lefts at Hecznarowice and Handlowa are sharp: brake early, then carry momentum along the open field lane."
	},
	{
		"id": "stage_2",
		"act": 1,
		"act_name": "Act I: Silesian Grassroots",
		"title": "Stage 2: Coal & Crossroads",
		"track": "brzeszcze",
		"laps": 2,
		"weather": "fog",
		"time_of_day": 8.0,
		"start_hour": 8.0,
		"wear_mult": 2.0,
		"fuel_mult": 1.0,
		"opponents": 7,
		"difficulty": "easy",
		"target_pos": 3,
		"grid": "p3",
		"trophy": "Mining Headframe Cup",
		"desc": "Dense morning fog blankets the mining town: up ul. Ofiar Oświęcimia past the Andrzej shafts, round Leśna, Kościuszki and Piastowska, and back by Daszyńskiego.",
		"tip": "The town's right-angle junctions loom out of the fog late: brake while the corner is still a guess, not when you see it."
	},
	{
		"id": "stage_3",
		"act": 1,
		"act_name": "Act I: Silesian Grassroots",
		"title": "Stage 3: The Forest of Bór",
		"track": "bor",
		"laps": 4,
		"weather": "variable",
		"time_of_day": 16.5,
		"start_hour": 16.5,
		"wear_mult": 2.0,
		"fuel_mult": 1.0,
		"opponents": 8,
		"difficulty": "easy",
		"target_pos": 3,
		"grid": "p3",
		"trophy": "Bór Forester Pine",
		"desc": "Blast through the pine woods of Brzeszcze Bór: past the OSP Bór fire station, over the railway twice at the Borska and Lachowicka level crossings, and past the fishponds back to ul. Bór.",
		"tip": "Guardrail lines the road and the verges are only grass: a mistake ends on the steel, so keep your throttle smooth between the trees."
	},
	{
		"id": "stage_4",
		"act": 1,
		"act_name": "Act I: Silesian Grassroots",
		"title": "Stage 4: Castle Park Trophy",
		"track": "pszczyna",
		"laps": 2,
		"weather": "dry",
		"time_of_day": 18.0,
		"start_hour": 18.0,
		"wear_mult": 2.0,
		"fuel_mult": 1.0,
		"opponents": 9,
		"difficulty": "medium",
		"target_pos": 3,
		"grid": "p3",
		"trophy": "Princess Daisy Crown",
		"desc": "Sunset battle over the setts of Piastowska and the Rynek, past the castle and the wisent enclosure on Żorska, then in through the park gate: the alley by the big pond, the hairpin under the castle, the bridges between the ponds and the gravel of the western lobe.",
		"tip": "Setts offer less bite than asphalt, and the park alleys are barely wider than the car: brake early for the hairpin and the narrow bridges."
	},
	{
		"id": "stage_5",
		"act": 2,
		"act_name": "Act II: Regional Championship",
		"title": "Stage 5: Factory Homecoming",
		"track": "bielsko",
		"laps": 2,
		"weather": "variable",
		"time_of_day": 12.0,
		"start_hour": 12.0,
		"wear_mult": 2.0,
		"fuel_mult": 1.0,
		"opponents": 9,
		"difficulty": "medium",
		"target_pos": 2,
		"grid": "p2",
		"trophy": "Bielsko FSM Golden Gear",
		"desc": "Back in the Seicento's home town, at the foot of Szyndzielnia. Climb al. Armii Krajowej to the cable-car car park at Rondo Fieldorfa, then plunge 70 m down Karbowa past the Dębowiec ski slope, over the Kamieniczanka and home along Gościnna.",
		"tip": "Use the draft up the long Armii Krajowej drag, then brake hard for Rondo Fieldorfa at the top: the descent to Karpacka comes at you fast."
	},
	{
		"id": "stage_6",
		"act": 2,
		"act_name": "Act II: Regional Championship",
		"title": "Stage 6: Riverbank Grand Prix",
		"track": "oswiecim",
		"laps": 2,
		"weather": "wet",
		"time_of_day": 15.0,
		"start_hour": 15.0,
		"wear_mult": 2.0,
		"fuel_mult": 1.0,
		"opponents": 9,
		"difficulty": "medium",
		"target_pos": 3,
		"grid": "p3",
		"trophy": "Piast Shield",
		"desc": "Torrential rain over the Soła. Two laps of the old town: up ul. Legionów, over Most Piastowski, up past the castle hill, along the setts of Plebańska and round the Rynek, down ul. Jagiełły, and back over Most Jagielloński.",
		"tip": "The setts of Plebańska and the Rynek are slick in the wet: brake in a straight line before you reach them, and keep it tidy through Rondo Płonki onto the bridge."
	},
	{
		"id": "stage_7",
		"act": 2,
		"act_name": "Act II: Regional Championship",
		"title": "Stage 7: The Royal Crown",
		"track": "krakow",
		"laps": 4,
		"weather": "dry",
		"time_of_day": 19.5,
		"start_hour": 19.5,
		"wear_mult": 2.0,
		"fuel_mult": 1.0,
		"opponents": 11,
		"difficulty": "medium",
		"target_pos": 3,
		"grid": "p3",
		"trophy": "Wawel Dragon Sceptre",
		"desc": "Dusk falls over Kraków as the championship roars round the ring road outside the Planty: Basztowa past the Barbakan and Brama Floriańska, Podwale and Straszewskiego, then the setts of Podzamcze and św. Idziego under Wawel.",
		"tip": "Tram rails run along half the lap. Brake before the setts under Wawel, and tuck into the slipstream on the long run along św. Gertrudy over the line."
	},
	{
		"id": "stage_8",
		"act": 3,
		"act_name": "Act III: Global Legends",
		"title": "Stage 8: Proving Grounds Trial",
		"track": "fiat",
		"laps": 6,
		"weather": "dry",
		"time_of_day": 13.0,
		"start_hour": 13.0,
		"wear_mult": 2.0,
		"fuel_mult": 1.0,
		"opponents": 11,
		"difficulty": "medium",
		"target_pos": 3,
		"grid": "p3",
		"trophy": "Tor Fiata Test Cup",
		"desc": "An exclusive invitation to the factory test track (Tor Fiata in Tychy) to battle factory test drivers in tuned machinery.",
		"tip": "The slipstream is strongest on the kilometre-long back straight: time your pass before the West Turn, a long, flat 185° right-hander."
	},
	{
		"id": "stage_9",
		"act": 3,
		"act_name": "Act III: Global Legends",
		"title": "Stage 9: Midnight Showdown",
		"track": "tokyo",
		"laps": 1,
		"weather": "dry",
		"time_of_day": 0.0,
		"start_hour": 0.0,
		"wear_mult": 2.0,
		"fuel_mult": 1.0,
		"opponents": 11,
		"difficulty": "hard",
		"target_pos": 1,
		"grid": "pole",
		"trophy": "Tokyo Midnight Emperor",
		"desc": "The international grand finale! One midnight lap of the Shuto C1 inner loop: the viaducts over the Nihonbashi river, the tunnels under the Imperial Palace moats, Hamazakibashi JCT and the Ginza trench.",
		"tip": "Two lanes between concrete walls. Lift for the blind left at Miyakezaka in the tunnel, and carry speed round the Hamarikyu Spiral: it drops two full turns into the Ginza trench."
	},
	{
		"id": "stage_10",
		"act": 4,
		"act_name": "Finale: Seicento Legend",
		"title": "Stage 10: The Goliath",
		"track": "goliath",
		"laps": 1,
		"weather": "dry",
		"time_of_day": 18.5,
		"start_hour": 18.5,
		"wear_mult": 1.0,
		"fuel_mult": 1.0,
		"opponents": 11,
		"difficulty": "hard",
		"target_pos": 1,
		"grid": "pole",
		"trophy": "The Goliath Crown",
		"car_class": "hypercar",
		"fan_lock": true,
		"desc": "One lap, 27 km, the whole of Brzeszcze closed for the night: the town, the S1 flat out, the villages and the Bór ponds, and back down the east side. Twelve Hypercar Seicentos in AF Corse yellow, and you on pole with eleven Legends behind you for 27 km.",
		"tip": "The S1 is where races are won: 340 km/h, then the hardest stop of the lap into the junction. Save the tyres in town."
	}
]

static func load_progress() -> Dictionary:
	var path := SaveData.read_path(save_file)
	if not FileAccess.file_exists(path):
		return {"unlocked": 0, "best_pos": {}, "trophies": []}
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return {"unlocked": 0, "best_pos": {}, "trophies": []}
	var json = JSON.parse_string(f.get_as_text())
	if json is Dictionary:
		return json
	return {"unlocked": 0, "best_pos": {}, "trophies": []}

static func save_progress(data: Dictionary) -> void:
	var path := SaveData.path(save_file)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))

## Wipes the campaign: unlocked stages, results, trophies, failed tries and the carried car.
static func reset_progress() -> void:
	save_progress({"unlocked": 0, "best_pos": {}, "trophies": []})

const LEVELS := ["easy", "medium", "hard", "alien"]
const FAILS_PER_EASE := 1 ## failed tries on a stage before its field drops one difficulty level

## A stage as it will be raced: after every FAILS_PER_EASE failed tries the field drops a difficulty level
## (down to Easy), so a stage that keeps beating the player gets kinder instead of blocking the campaign.
## base_difficulty is the stage's own level, eased says how many steps it came down.
static func get_stage(index: int) -> Dictionary:
	if Missions.is_mission(index):
		return Missions.as_stage(index) # a mission (Missions.BASE + k) reads like a stage
	var st: Dictionary = (STAGES[index] if index >= 0 and index < STAGES.size() else STAGES[0]).duplicate()
	var base: String = st.get("difficulty", "medium")
	var fails := int(load_progress().get("fails", {}).get(str(index), 0))
	var at := LEVELS.find(base)
	var eased := mini(fails / FAILS_PER_EASE, at)
	st["base_difficulty"] = base
	st["difficulty"] = LEVELS[at - eased]
	st["eased"] = eased
	st["fails"] = fails
	if not st.has("start_hour"):
		st["start_hour"] = st.get("time_of_day", 14.0)
	if not st.has("wear_mult"):
		st["wear_mult"] = 2.0
	if not st.has("fuel_mult"):
		st["fuel_mult"] = 1.0
	return st

## fans: the player's fan total (read from the open-world save when not given). A "fan_lock" stage (the Goliath)
## opens at the top fan level instead of after the stage before it.
static func is_unlocked(stage_idx: int, fans := -1) -> bool:
	if Missions.is_mission(stage_idx):
		return Missions.is_unlocked(stage_idx)
	if stage_idx >= 0 and stage_idx < STAGES.size() and STAGES[stage_idx].get("fan_lock", false):
		return FanLevels.hypercar_unlocked(fans if fans >= 0 else WorldProgress.load_progress().fans)
	var prog := load_progress()
	return stage_idx <= int(prog.get("unlocked", 0))

static func record_result(stage_idx: int, pos: int) -> Dictionary:
	if Missions.is_mission(stage_idx): # a place-only result (the game judges missions with Missions.judge)
		var st := get_stage(stage_idx)
		return Missions.record(stage_idx, {"pos": pos, "success": pos <= int(st.target_pos), "tier": 0, "score": 0})
	var stage := get_stage(stage_idx)
	var prog := load_progress()
	var unlocked: int = int(prog.get("unlocked", 0))
	var best_pos: Dictionary = prog.get("best_pos", {})
	var trophies: Array = prog.get("trophies", [])
	
	var sid := str(stage_idx)
	var prev_best: int = int(best_pos.get(sid, 999))
	if pos < prev_best:
		best_pos[sid] = pos
		
	var target_pos: int = stage.target_pos
	var success: bool = pos <= target_pos
	var newly_unlocked := false
	
	var first_clear := false
	if success:
		var t_name: String = stage.trophy
		if t_name not in trophies:
			trophies.append(t_name)
			first_clear = true
		if stage_idx == unlocked and unlocked < STAGES.size() - 1 and not STAGES[unlocked + 1].get("fan_lock", false):
			unlocked += 1
			newly_unlocked = true
			
	var fails: Dictionary = prog.get("fails", {})
	if success:
		fails.erase(sid)
	else:
		fails[sid] = int(fails.get(sid, 0)) + 1
	prog["fails"] = fails
	prog["unlocked"] = unlocked
	prog["best_pos"] = best_pos
	prog["trophies"] = trophies
	save_progress(prog)
	
	return {
		"success": success,
		"newly_unlocked": newly_unlocked,
		"unlocked_stage": unlocked,
		"trophy": stage.trophy if success else "",
		"first_clear": first_clear,
		"fans": FanLevels.stage_reward(stage_idx, pos, target_pos, first_clear),
	}

## The car carried from one stage to the next ({parts, pull, used, serviced}, see Service): what the crew
## doesn't repair in the service area between stages is still broken at the next one.
static func load_car() -> Dictionary:
	var car = load_progress().get("car", {})
	return car if car is Dictionary else {}

static func save_car(car: Dictionary) -> void:
	var prog := load_progress()
	prog["car"] = car
	save_progress(prog)
