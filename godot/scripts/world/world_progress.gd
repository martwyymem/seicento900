## What the player has done in the open world, saved between sessions (user://open_world.json): where the car
## was left, the roads driven and landmarks found, the best speed at each speed trap, and the fans earned from
## skills (Forza Horizon's popularity, in the Seicento Fest's own currency).
class_name WorldProgress
extends RefCounted

const SAVE_FILE := "open_world.json"

var pos := Vector2.ZERO
var heading := 0.0
var has_pos := false
var hour := 18.5
var roads := {} ## road index (int) -> true
var landmarks := {} ## name -> true
var traps := {} ## trap id -> best km/h
var fans := 0
var best_chain := 0
var odometer := 0.0
var car_class := 0 ## index into CarCatalog.KEYS: 0 the stock Seicento, 1 the Hypercar Seicento, 2 the Golf IV... (each once unlocked)
var mods := {} ## CarMods switched on (id -> true)
var tips := {} ## first-time explanations already shown (Poi kind -> true)
var map_hidden: Array = [] ## the big map's marker categories switched off (MapNav.CATS ids)
var live := {} ## LiveEvents medals: {tries, done, bronze, silver, gold, kinds: {kind: done}}
var weather_seed := 0 ## WorldWeather's seed (0: none yet, OpenWorld picks one the first time and saves it)
var weather_day := 0 ## game days the weather has run (WorldWeather's clock is weather_day * 24 + hour)
var weather_dynamic := true ## free-roam weather: true Dynamic (WorldWeather), false Always dry

static func load_progress() -> WorldProgress:
	var path := SaveData.read_path(SAVE_FILE)
	if not FileAccess.file_exists(path):
		return WorldProgress.new()
	return from_dict(SaveData.read_json(path))

## A save's JSON as a WorldProgress; a key an older save lacks keeps its default.
static func from_dict(data: Variant) -> WorldProgress:
	var w := WorldProgress.new()
	if not data is Dictionary:
		return w
	var p = data.get("pos", [])
	if p is Array and p.size() >= 3:
		w.pos = Vector2(SaveData.to_float(p[0]), SaveData.to_float(p[1]))
		w.heading = SaveData.to_float(p[2])
		w.has_pos = true
	w.hour = SaveData.to_float(data.get("hour", 18.5), 18.5)
	for r in _list(data, "roads"):
		w.roads[SaveData.to_int(r)] = true
	for n in _list(data, "landmarks"):
		w.landmarks[str(n)] = true
	var t = data.get("traps", {})
	if t is Dictionary:
		w.traps = t
	w.fans = SaveData.to_int(data.get("fans", 0))
	w.best_chain = SaveData.to_int(data.get("best_chain", 0))
	w.odometer = SaveData.to_float(data.get("odometer", 0.0))
	w.car_class = SaveData.to_int(data.get("car_class", 0))
	for id in _list(data, "mods"):
		w.mods[str(id)] = true
	for k in _list(data, "tips"):
		w.tips[str(k)] = true
	for id in _list(data, "map_hidden"):
		w.map_hidden.append(str(id))
	var lv = data.get("live", {})
	if lv is Dictionary:
		w.live = lv
	w.weather_seed = SaveData.to_int(data.get("weather_seed", 0))
	w.weather_day = maxi(SaveData.to_int(data.get("weather_day", 0)), 0)
	w.weather_dynamic = SaveData.to_bool(data.get("weather_dynamic", true), true)
	return w

## A save's list under `key`, or an empty one when it is missing or not a list.
static func _list(data: Dictionary, key: String) -> Array:
	var v = data.get(key, [])
	return v if v is Array else []

func to_dict() -> Dictionary:
	return {
		"pos": [snappedf(pos.x, 0.1), snappedf(pos.y, 0.1), snappedf(heading, 0.001)],
		"hour": snappedf(hour, 0.01),
		"roads": roads.keys(),
		"landmarks": landmarks.keys(),
		"traps": traps,
		"fans": fans,
		"best_chain": best_chain,
		"odometer": snappedf(odometer, 1.0),
		"car_class": car_class,
		"mods": mods.keys(),
		"tips": tips.keys(),
		"live": live,
		"map_hidden": map_hidden,
		"weather_seed": weather_seed,
		"weather_day": weather_day,
		"weather_dynamic": weather_dynamic,
	}

func save() -> void:
	var f := FileAccess.open(SaveData.path(SAVE_FILE), FileAccess.WRITE)
	if not f:
		return
	f.store_string(JSON.stringify(to_dict()))

## A new campaign (RESET CAMPAIGN): fans and level, roads driven, landmarks, speed traps, live-event medals and the
## odometer go; the car goes back to the stock Seicento (the cars won are locked again). Where the car stands, the
## clock, modifiers, tips already read and the map's filters stay.
func wipe_campaign() -> void:
	roads = {}
	landmarks = {}
	traps = {}
	fans = 0
	best_chain = 0
	odometer = 0.0
	car_class = 0
	live = {}

## Wipes the whole campaign on disk: the stages, missions, story and cars (Campaign.reset_progress) and the
## open-world progress (wipe_campaign). An OpenWorld already built keeps its own copy: use OpenWorld.reset_campaign.
static func reset_campaign() -> void:
	Campaign.reset_progress()
	var w := load_progress()
	w.wipe_campaign()
	w.save()

## A finished live event (LiveEvents): tier 0 is a try that missed its target. Misses in a row per kind are kept
## in "fails" (the next field of that kind is eased, as a campaign mission's is); a clear forgets them.
func record_live(kind: String, tier: int) -> void:
	live["tries"] = int(live.get("tries", 0)) + 1
	var fails: Dictionary = live.get("fails", {}) if live.get("fails", {}) is Dictionary else {}
	if tier <= 0:
		fails[kind] = int(fails.get(kind, 0)) + 1
		live["fails"] = fails
		return
	fails.erase(kind)
	live["fails"] = fails
	live["done"] = int(live.get("done", 0)) + 1
	var medal: String = ["", "bronze", "silver", "gold"][clampi(tier, 1, 3)]
	live[medal] = int(live.get(medal, 0)) + 1
	var kinds: Dictionary = live.get("kinds", {}) if live.get("kinds", {}) is Dictionary else {}
	kinds[kind] = int(kinds.get(kind, 0)) + 1
	live["kinds"] = kinds
