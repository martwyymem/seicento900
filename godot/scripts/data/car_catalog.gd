## Every car the player can drive: the Fiat Seicento ("stock"), the Hypercar Seicento ("hypercar") and the cars won in the
## campaign (the Golf IV, "golf4", first; Volvo V50, Hyundai i20, Dacia Logan and Sandero, Ford Focus and Opel Zafira follow the
## recipe in AGENTS.md). One entry per car: display name, spec factory, GLB path, how the model is dressed (wheel and decal
## placement, plate, lamp points), and how it is unlocked. RaceSettings.car_class and WorldProgress.car_class (an index into
## KEYS: keep the order, saved settings store it) name a car by its key. Add a car here, in RaceSettings' car_class enum and in
## KEYS; the CAR pickers, RaceCarVisual and the strategist follow.
class_name CarCatalog
extends RefCounted

## Index = the saved picker/open-world number: "stock" 0 and "hypercar" 1 as before, then cars in the order they were added.
const KEYS: Array[String] = ["stock", "hypercar", "golf4"]

## How a model is fitted by RaceCarVisual. Positions are in the visual's frame: -Z forward, +X right, +Y up, origin on the
## ground midway between the axles. `decals` (stock only) are measured points {surface, normal, up}; `decal_aims` are rays
## {from, dir, up} cast at the Body mesh, so a new model needs no measuring by hand.
const STOCK_VISUAL := {
	"model": "res://models/seicento.glb", "wheel_radius": 0.2665, "wheelbase": 2.2, "half_track_front": 0.6315, "half_track_rear": 0.6315,
	"roof_number": Vector3(0.0, 1.428, 0.6), "brake_light": Vector3(0.0, 0.5, 2.1), "tailpipe": Vector3(0.30, 0.19, 1.56),
	"fx_axle": Vector3(0.0, 0.03, 1.12), "contact": Vector2(2.0, 3.9),
	# the race's on-car cameras (RaceWorld): m ahead of the visual's origin and up, just past the bumper and over the scuttle
	"bumper_cam": Vector2(1.78, 0.42), "bonnet_cam": Vector2(0.62, 1.08),
}
const GOLF4_VISUAL := {
	"model": "res://models/golf4.glb", "wheel_radius": 0.3172, "wheelbase": 2.511, "half_track_front": 0.7565, "half_track_rear": 0.747,
	"roof_number": Vector3(0.0, 1.444, 0.55), "brake_light": Vector3(0.0, 0.6, 2.25), "tailpipe": Vector3(0.35, 0.24, 2.10),
	"fx_axle": Vector3(0.0, 0.03, 1.2555), "contact": Vector2(2.1, 4.5),
	# the nose is 2.11 m ahead of the origin and the scuttle at 0.89 m (build_golf4.py): the Seicento's 1.78 / 0.62 put the
	# cameras inside the bumper and the dashboard (2026-11-10 QA)
	"bumper_cam": Vector2(2.15, 0.45), "bonnet_cam": Vector2(0.89, 1.14),
	"chase_back": 0.46, ## the chase cameras stand this much further back: the tail is 2.04 m behind the origin, the Seicento's 1.58
	# the front door, the top of the windscreen, the bonnet and the sill under the front door
	"decal_aims": {
		"DoorDecalL": {"from": Vector3(-1.5, 0.74, -0.39), "dir": Vector3(1, 0, 0), "up": Vector3.UP},
		"DoorDecalR": {"from": Vector3(1.5, 0.74, -0.39), "dir": Vector3(-1, 0, 0), "up": Vector3.UP},
		"Sunstrip": {"from": Vector3(0.0, 1.85, -0.62), "dir": Vector3(0.0, -0.88, 0.47), "up": Vector3(0.0, 0.47, 0.88)},
		"HoodDecal": {"from": Vector3(0.0, 1.4, -1.35), "dir": Vector3(0, -1, 0), "up": Vector3.FORWARD},
		"SillDecalL": {"from": Vector3(-1.5, 0.40, 0.0), "dir": Vector3(1, 0, 0), "up": Vector3.UP},
		"SillDecalR": {"from": Vector3(1.5, 0.40, 0.0), "dir": Vector3(-1, 0, 0), "up": Vector3.UP},
	},
}

static func is_key(key: String) -> bool:
	return key in KEYS

static func key_at(index: int) -> String:
	return KEYS[clampi(index, 0, KEYS.size() - 1)]

static func index_of(key: String) -> int:
	return maxi(0, KEYS.find(key))

static func display_name(key: String) -> String:
	match key:
		"hypercar":
			return "Hypercar Seicento"
		"golf4":
			return "VW Golf IV 1.4"
	return "Seicento 900"

## The car's physics spec (a fresh duplicate for every car but the stock one's shared resource).
static func spec(key: String) -> CarSpec:
	match key:
		"hypercar":
			return Hypercar.spec()
		"golf4":
			return Golf4.spec()
	return load("res://data/seicento.tres")

static func model(key: String) -> CarModel:
	return CarModel.new(spec(key)) if key != "stock" else CarModel.new()

## How RaceCarVisual dresses this car (see STOCK_VISUAL); the hypercar is the stock body in another livery.
static func visual(key: String) -> Dictionary:
	return GOLF4_VISUAL if key == "golf4" else STOCK_VISUAL

## The race number, paint and stripes a car always wears (the hypercar is AF Corse's yellow no. 83), or {} for the player's own.
static func livery(key: String) -> Dictionary:
	if key == "hypercar":
		return {"color": Hypercar.PAINT, "number": Hypercar.NUMBER, "stripes": true, "finish": 0}
	return {}

## Whether the car is open. The stock Seicento always; the hypercar at the top fan level (or the dev menu's "unlock everything");
## every other car once the campaign save lists it in its "cars" (the mission that awards it), or with the dev override.
static func unlocked(key: String, fans := -1) -> bool:
	if key == "stock":
		return true
	if FanLevels.dev_unlock:
		return true
	if key == "hypercar":
		return FanLevels.hypercar_unlocked(fans if fans >= 0 else WorldProgress.load_progress().fans)
	return key in Campaign.load_progress().get("cars", [])

## How a locked car is won, for the pickers and the open world's CAR button (reads on from the car's name: "The X <hint>.").
static func unlock_hint(key: String) -> String:
	if key == "hypercar":
		return "opens at fan level %d (%s): earn fans in the open world and the campaign" % [FanLevels.THRESHOLDS.size(), FanLevels.title(FanLevels.THRESHOLDS.size())]
	if key == "stock":
		return "is always open"
	for m in Missions.MISSIONS:
		if String(m.get("reward_car", "")) == key:
			return "is won by clearing the campaign mission %s" % String(m.title)
	return "is won by beating one of the campaign's missions"

## The open cars in picker order.
static func open_keys(fans := -1) -> Array[String]:
	var out: Array[String] = []
	for k in KEYS:
		if unlocked(k, fans):
			out.append(k)
	return out
