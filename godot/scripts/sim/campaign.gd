## Campaign mode ("The Seicento Odyssey"): A 9-stage narrative racing career
## tracing a grassroots Polish racer's journey from Silesian village lanes to Tokyo.
class_name Campaign
extends RefCounted

const SAVE_FILE := "campaign.json"

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
		"desc": "Your mechanic uncle handed you the keys to a stock 1998 Fiat Seicento 900 (39 bhp). Prove your racecraft on the narrow, undulating village lanes of Wilamowice.",
		"tip": "Maintain momentum through the fast crests — scrub as little speed as possible in corners."
	},
	{
		"id": "stage_2",
		"act": 1,
		"act_name": "Act I: Silesian Grassroots",
		"title": "Stage 2: Coal & Cobblestones",
		"track": "brzeszcze",
		"laps": 4,
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
		"desc": "Dense morning fog blankets the industrial streets past KWK Szyb Andrzej. Watch for the sharp chicane over the railway crossing.",
		"tip": "Brake early for the railway grade crossing — curb-hopping here will unsettle the chassis."
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
		"desc": "Blast through the deep pine forests of Brzeszcze Bór, dodging across the railway line and sweeping along the embankment of Staw Bór.",
		"tip": "Gravel runoffs penalize mistakes heavily. Keep your throttle smooth between the tall trees."
	},
	{
		"id": "stage_4",
		"act": 1,
		"act_name": "Act I: Silesian Grassroots",
		"title": "Stage 4: Castle Park Trophy",
		"track": "pszczyna",
		"laps": 3,
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
		"desc": "Sunset battle through the historic cobblestones of Rynek Pszczyński and the grand avenues of Pałac Pszczyński.",
		"tip": "Cobblestones offer less bite than asphalt — be gentle on the throttle out of the market square."
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
		"desc": "Return to the home of the Fiat 126p and the Seicento, where bus 8 still runs from the factory gates to Szyndzielnia. Climb al. Armii Krajowej to the cable-car car park at Rondo Fieldorfa, then plunge 70 m down Karbowa and Karpacka under Dębowiec.",
		"tip": "Use the draft up the long Armii Krajowej drag, then brake hard for Rondo Fieldorfa at the top: the descent to Karpacka comes at you fast."
	},
	{
		"id": "stage_6",
		"act": 2,
		"act_name": "Act II: Regional Championship",
		"title": "Stage 6: Riverbank Grand Prix",
		"track": "oswiecim",
		"laps": 4,
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
		"desc": "Torrential rain pounds the boulevards along the Soła river and the bridge crossing beneath the medieval Piast Castle.",
		"tip": "Wet tyres are vital here. Brake in a straight line before the Most Piastowski turn."
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
		"desc": "Dusk falls over Kraków as the championship roars around the historic Planty ring and under the ramparts of Wawel Castle.",
		"tip": "The Basztowa straight is your best overtaking opportunity — tuck into the slipstream."
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
		"tip": "Aero slipstream is massive on the back straight — time your pass before the west banking."
	},
	{
		"id": "stage_9",
		"act": 3,
		"act_name": "Act III: Global Legends",
		"title": "Stage 9: Midnight Showdown",
		"track": "tokyo",
		"laps": 4,
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
		"desc": "The international grand finale! Midnight underground racing through the Shuto C1 Expressway's neon viaducts and the Yaesu tunnel.",
		"tip": "Narrow barriers leave zero room for error. Watch for the blind apex at Miyakezaka."
	}
]

static func load_progress() -> Dictionary:
	var path := SaveData.read_path(SAVE_FILE)
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
	var path := SaveData.path(SAVE_FILE)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))

const LEVELS := ["easy", "medium", "hard", "alien"]
const FAILS_PER_EASE := 1 ## failed tries on a stage before its field drops one difficulty level

## A stage as it will be raced: after every FAILS_PER_EASE failed tries the field drops a difficulty level
## (down to Easy), so a stage that keeps beating the player gets kinder instead of blocking the campaign.
## base_difficulty is the stage's own level, eased says how many steps it came down.
static func get_stage(index: int) -> Dictionary:
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

static func is_unlocked(stage_idx: int) -> bool:
	var prog := load_progress()
	return stage_idx <= int(prog.get("unlocked", 0))

static func record_result(stage_idx: int, pos: int) -> Dictionary:
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
	
	if success:
		var t_name: String = stage.trophy
		if t_name not in trophies:
			trophies.append(t_name)
		if stage_idx == unlocked and unlocked < STAGES.size() - 1:
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
		"trophy": stage.trophy if success else ""
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
