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

static func load_progress() -> WorldProgress:
	var w := WorldProgress.new()
	var path := SaveData.read_path(SAVE_FILE)
	if not FileAccess.file_exists(path):
		return w
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return w
	var p: Array = data.get("pos", [])
	if p.size() >= 3:
		w.pos = Vector2(p[0], p[1])
		w.heading = p[2]
		w.has_pos = true
	w.hour = float(data.get("hour", 18.5))
	for r in data.get("roads", []):
		w.roads[int(r)] = true
	for n in data.get("landmarks", []):
		w.landmarks[str(n)] = true
	var t = data.get("traps", {})
	if t is Dictionary:
		w.traps = t
	w.fans = int(data.get("fans", 0))
	w.best_chain = int(data.get("best_chain", 0))
	w.odometer = float(data.get("odometer", 0.0))
	return w

func save() -> void:
	var f := FileAccess.open(SaveData.path(SAVE_FILE), FileAccess.WRITE)
	if not f:
		return
	f.store_string(JSON.stringify({
		"pos": [snappedf(pos.x, 0.1), snappedf(pos.y, 0.1), snappedf(heading, 0.001)],
		"hour": snappedf(hour, 0.01),
		"roads": roads.keys(),
		"landmarks": landmarks.keys(),
		"traps": traps,
		"fans": fans,
		"best_chain": best_chain,
		"odometer": snappedf(odometer, 1.0),
	}))
