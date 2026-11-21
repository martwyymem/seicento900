## Every car the player can drive: the Fiat Seicento ("stock"), the Hypercar Seicento ("hypercar") and the seven cars won
## in the campaign (Golf IV, Dacia Logan, Volvo V50, Hyundai i20, Dacia Sandero, Ford Focus and Opel Zafira B). One entry
## per car: display name, spec factory, GLB path, how the model is dressed (wheel and decal placement, plate, lamp points),
## and how it is unlocked. RaceSettings.car_class and WorldProgress.car_class (an index into
## KEYS: keep the order, saved settings store it) name a car by its key. Add a car here, in RaceSettings' car_class enum and in
## KEYS; the CAR pickers, RaceCarVisual and the strategist follow.
class_name CarCatalog
extends RefCounted

## Index = the saved picker/open-world number: "stock" 0 and "hypercar" 1 as before, then cars in the order they were added.
const KEYS: Array[String] = ["stock", "hypercar", "golf4", "logan", "v50", "i20", "sandero", "focus", "zafira"]

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
	"roof_number": Vector3(0.0, 1.444, 0.55), "brake_light": Vector3(0.0, 0.6, 2.25), "tailpipe": Vector3(0.35, 0.24, 2.08),
	"fx_axle": Vector3(0.0, 0.03, 1.2555), "contact": Vector2(2.1, 4.5),
	# the plates' bottom edges (front bumper, tailgate recess) and a top limit for car_plate.gdshader; 512 x 105 mm as the Seicento's
	"plate_y": Vector3(0.398, 0.644, 0.8),
	# the big tail lamps (car_taillamp.gdshader and the lamp body behind the lens): a deeper, more opaque red lens by day
	# with less sky in its sheen, so they read red rather than smoky (a stronger glow burnt out to yellow under ACES)
	"tail_lamp": {"tint": Color(0.70, 0.01, 0.015), "alpha_off": 0.86, "alpha_lit": 0.93, "glow_gain": 0.6, "sheen": 0.3,
		"reflect": 0.3, "albedo": Color("#5a0404"), "energy": 0.9},
	# the nose is 2.12 m ahead of the origin and the cowl at 0.90 m (build_golf4.py): the Seicento's 1.78 / 0.62 put the
	# cameras inside the bumper and the dashboard (2026-11-10 QA)
	"bumper_cam": Vector2(2.15, 0.45), "bonnet_cam": Vector2(0.89, 1.14),
	"chase_back": 0.46, ## the chase cameras stand this much further back: the tail is 2.03 m behind the origin, the Seicento's 1.58
	# the front door, the top of the windscreen, the bonnet and the sill under the front door
	"decal_aims": {
		"DoorDecalL": {"from": Vector3(-1.5, 0.74, -0.39), "dir": Vector3(1, 0, 0), "up": Vector3.UP},
		"DoorDecalR": {"from": Vector3(1.5, 0.74, -0.39), "dir": Vector3(-1, 0, 0), "up": Vector3.UP},
		"Sunstrip": {"from": Vector3(0.0, 1.85, -0.66), "dir": Vector3(0.0, -0.88, 0.47), "up": Vector3(0.0, 0.47, 0.88)},
		"HoodDecal": {"from": Vector3(0.0, 1.4, -1.35), "dir": Vector3(0, -1, 0), "up": Vector3.FORWARD},
		"SillDecalL": {"from": Vector3(-1.5, 0.40, 0.0), "dir": Vector3(1, 0, 0), "up": Vector3.UP},
		"SillDecalR": {"from": Vector3(1.5, 0.40, 0.0), "dir": Vector3(-1, 0, 0), "up": Vector3.UP},
	},
}

const LOGAN_VISUAL := {
	"model": "res://models/logan.glb", "wheel_radius": 0.3108, "wheelbase": 2.630, "half_track_front": 0.733, "half_track_rear": 0.728,
	"roof_number": Vector3(0.0, 1.530, 0.30), "brake_light": Vector3(0.0, 0.85, 2.36), "tailpipe": Vector3(0.40, 0.262, 2.142),
	"fx_axle": Vector3(0.0, 0.03, 1.315), "contact": Vector2(2.05, 4.6),
	# the plates' bottom edges (front bumper, boot lid recess between the tail lamps) and a top limit (build_logan.py)
	"plate_y": Vector3(0.445, 0.722, 0.9),
	# the Golf's deeper red lens: the Logan's upright lamps are red above, amber and clear below
	"tail_lamp": {"tint": Color(0.70, 0.01, 0.015), "alpha_off": 0.86, "alpha_lit": 0.93, "glow_gain": 0.6, "sheen": 0.3,
		"reflect": 0.3, "albedo": Color("#5a0404"), "energy": 0.9},
	# the nose is 2.115 m ahead of the origin and the cowl at 0.895 m, 0.95 m up
	"bumper_cam": Vector2(2.14, 0.48), "bonnet_cam": Vector2(0.89, 1.17),
	"chase_back": 0.58, ## the tail is 2.13 m behind the origin (the Seicento's 1.58) and the roof 1.525 m up
	# the front door, the top of the windscreen, the bonnet and the sill under the B-pillar
	"decal_aims": {
		"DoorDecalL": {"from": Vector3(-1.5, 0.72, -0.32), "dir": Vector3(1, 0, 0), "up": Vector3.UP},
		"DoorDecalR": {"from": Vector3(1.5, 0.72, -0.32), "dir": Vector3(-1, 0, 0), "up": Vector3.UP},
		"Sunstrip": {"from": Vector3(0.0, 1.95, -0.62), "dir": Vector3(0.0, -0.88, 0.47), "up": Vector3(0.0, 0.47, 0.88)},
		"HoodDecal": {"from": Vector3(0.0, 1.4, -1.50), "dir": Vector3(0, -1, 0), "up": Vector3.FORWARD},
		"SillDecalL": {"from": Vector3(-1.5, 0.42, 0.0), "dir": Vector3(1, 0, 0), "up": Vector3.UP},
		"SillDecalR": {"from": Vector3(1.5, 0.42, 0.0), "dir": Vector3(-1, 0, 0), "up": Vector3.UP},
	},
}

const V50_VISUAL := {
	"model": "res://models/v50.glb", "wheel_radius": 0.3160, "wheelbase": 2.640, "half_track_front": 0.7675, "half_track_rear": 0.7655,
	"roof_number": Vector3(0.0, 1.418, 0.30), "brake_light": Vector3(0.0, 0.95, 2.55), "tailpipe": Vector3(0.42, 0.268, 2.32),
	"fx_axle": Vector3(0.0, 0.03, 1.32), "contact": Vector2(2.1, 4.85),
	# the plates' bottom edges (front bumper under the grille, tailgate between the lamps) and a top limit (build_v50.py)
	"plate_y": Vector3(0.445, 0.700, 0.9),
	# the Golf's deeper red lens: the V50's tall lamps run up the D-pillars
	"tail_lamp": {"tint": Color(0.70, 0.01, 0.015), "alpha_off": 0.86, "alpha_lit": 0.93, "glow_gain": 0.6, "sheen": 0.3,
		"reflect": 0.3, "albedo": Color("#5a0404"), "energy": 0.9},
	# the nose is 2.20 m ahead of the origin and the cowl at 0.80 m, 0.97 m up
	"bumper_cam": Vector2(2.23, 0.50), "bonnet_cam": Vector2(0.80, 1.13),
	"chase_back": 0.74, ## the tail is 2.315 m behind the origin (the Seicento's 1.58)
	# the front door, the top of the windscreen, the bonnet and the sill under the B-pillar
	"decal_aims": {
		"DoorDecalL": {"from": Vector3(-1.5, 0.70, -0.22), "dir": Vector3(1, 0, 0), "up": Vector3.UP},
		"DoorDecalR": {"from": Vector3(1.5, 0.70, -0.22), "dir": Vector3(-1, 0, 0), "up": Vector3.UP},
		"Sunstrip": {"from": Vector3(0.0, 1.85, -0.47), "dir": Vector3(0.0, -0.88, 0.47), "up": Vector3(0.0, 0.47, 0.88)},
		"HoodDecal": {"from": Vector3(0.0, 1.4, -1.45), "dir": Vector3(0, -1, 0), "up": Vector3.FORWARD},
		"SillDecalL": {"from": Vector3(-1.5, 0.38, 0.0), "dir": Vector3(1, 0, 0), "up": Vector3.UP},
		"SillDecalR": {"from": Vector3(1.5, 0.38, 0.0), "dir": Vector3(-1, 0, 0), "up": Vector3.UP},
	},
}

const I20_VISUAL := {
	"model": "res://models/i20.glb", "wheel_radius": 0.3015, "wheelbase": 2.525, "half_track_front": 0.7525, "half_track_rear": 0.7515,
	"roof_number": Vector3(0.0, 1.494, 0.45), "brake_light": Vector3(0.0, 1.00, 2.08), "tailpipe": Vector3(0.36, 0.254, 1.897),
	"fx_axle": Vector3(0.0, 0.03, 1.2625), "contact": Vector2(2.05, 4.30),
	# the plates' bottom edges (front hexagonal grille bar, rear bumper recess) and a top limit (build_i20.py)
	"plate_y": Vector3(0.425, 0.440, 0.65),
	# the Golf's deeper red lens: the i20's high stacked tail lamps flank the rear glass
	"tail_lamp": {"tint": Color(0.70, 0.01, 0.015), "alpha_off": 0.86, "alpha_lit": 0.93, "glow_gain": 0.6, "sheen": 0.3,
		"reflect": 0.3, "albedo": Color("#5a0404"), "energy": 0.9},
	# the nose is 2.0475 m ahead of the origin and the cowl at 0.9675 m, 0.962 m up
	"bumper_cam": Vector2(2.08, 0.46), "bonnet_cam": Vector2(0.96, 1.15),
	"chase_back": 0.32, ## the tail is 1.8925 m behind the origin (the Seicento's 1.58)
	# the front door, the top of the windscreen, the bonnet and the sill under the B-pillar
	"decal_aims": {
		"DoorDecalL": {"from": Vector3(-1.5, 0.72, -0.43), "dir": Vector3(1, 0, 0), "up": Vector3.UP},
		"DoorDecalR": {"from": Vector3(1.5, 0.72, -0.43), "dir": Vector3(-1, 0, 0), "up": Vector3.UP},
		"Sunstrip": {"from": Vector3(0.001, 1.90, -0.54), "dir": Vector3(0.0, -0.88, 0.47), "up": Vector3(0.0, 0.47, 0.88)},
		"HoodDecal": {"from": Vector3(0.0, 1.4, -1.45), "dir": Vector3(0, -1, 0), "up": Vector3.FORWARD},
		"SillDecalL": {"from": Vector3(-1.5, 0.38, 0.0), "dir": Vector3(1, 0, 0), "up": Vector3.UP},
		"SillDecalR": {"from": Vector3(1.5, 0.38, 0.0), "dir": Vector3(-1, 0, 0), "up": Vector3.UP},
	},
}

const SANDERO_VISUAL := {
	"model": "res://models/sandero.glb", "wheel_radius": 0.310, "wheelbase": 2.588, "half_track_front": 0.740, "half_track_rear": 0.7345,
	"roof_number": Vector3(0.0, 1.538, 0.45), "brake_light": Vector3(0.0, 0.96, 2.10), "tailpipe": Vector3(0.38, 0.270, 1.917),
	"fx_axle": Vector3(0.0, 0.03, 1.294), "contact": Vector2(2.08, 4.38),
	# the plates' bottom edges (front bumper beam, tailgate recess) and a top limit (build_sandero.py)
	"plate_y": Vector3(0.435, 0.615, 0.80),
	# deeper red lens for the tall vertical-wedge tail lamps flanking the rear window
	"tail_lamp": {"tint": Color(0.70, 0.01, 0.015), "alpha_off": 0.86, "alpha_lit": 0.93, "glow_gain": 0.6, "sheen": 0.3,
		"reflect": 0.3, "albedo": Color("#5a0404"), "energy": 0.9},
	# nose is 2.109 m ahead of origin and cowl at 0.979 m, 0.988 m up
	"bumper_cam": Vector2(2.14, 0.47), "bonnet_cam": Vector2(0.97, 1.18),
	"chase_back": 0.34, ## tail is 1.911 m behind the origin (the Seicento's 1.58)
	"decal_aims": {
		"DoorDecalL": {"from": Vector3(-1.5, 0.72, -0.42), "dir": Vector3(1, 0, 0), "up": Vector3.UP},
		"DoorDecalR": {"from": Vector3(1.5, 0.72, -0.42), "dir": Vector3(-1, 0, 0), "up": Vector3.UP},
		"Sunstrip": {"from": Vector3(0.001, 1.95, -0.56), "dir": Vector3(0.0, -0.88, 0.47), "up": Vector3(0.0, 0.47, 0.88)},
		"HoodDecal": {"from": Vector3(0.0, 1.45, -1.48), "dir": Vector3(0, -1, 0), "up": Vector3.FORWARD},
		"SillDecalL": {"from": Vector3(-1.5, 0.40, 0.0), "dir": Vector3(1, 0, 0), "up": Vector3.UP},
		"SillDecalR": {"from": Vector3(1.5, 0.40, 0.0), "dir": Vector3(-1, 0, 0), "up": Vector3.UP},
	},
}

const FOCUS_VISUAL := {
	"model": "res://models/focus.glb", "wheel_radius": 0.321, "wheelbase": 2.648, "half_track_front": 0.772, "half_track_rear": 0.767,
	"roof_number": Vector3(0.0, 1.488, 0.40), "brake_light": Vector3(0.0, 0.90, 2.30), "tailpipe": Vector3(0.40, 0.248, 2.138),
	"fx_axle": Vector3(0.0, 0.03, 1.324), "contact": Vector2(2.15, 4.70),
	# the plates' bottom edges (front hexagonal grille plinth, rear tailgate) and a top limit (build_focus.py)
	"plate_y": Vector3(0.382, 0.625, 0.80),
	# deep red tail-lamp lens shader matching Golf4/V50/i20
	"tail_lamp": {"tint": Color(0.70, 0.01, 0.015), "alpha_off": 0.86, "alpha_lit": 0.93, "glow_gain": 0.6, "sheen": 0.3,
		"reflect": 0.3, "albedo": Color("#5a0404"), "energy": 0.9},
	# nose is 2.244 m ahead of the origin and the cowl at 0.914 m, 0.962 m up
	"bumper_cam": Vector2(2.27, 0.46), "bonnet_cam": Vector2(0.91, 1.15),
	"chase_back": 0.54, ## tail is 2.114 m behind the origin (the Seicento's 1.58)
	"decal_aims": {
		"DoorDecalL": {"from": Vector3(-1.5, 0.70, -0.38), "dir": Vector3(1, 0, 0), "up": Vector3.UP},
		"DoorDecalR": {"from": Vector3(1.5, 0.70, -0.38), "dir": Vector3(-1, 0, 0), "up": Vector3.UP},
		"Sunstrip": {"from": Vector3(0.001, 1.90, -0.45), "dir": Vector3(0.0, -0.88, 0.47), "up": Vector3(0.0, 0.47, 0.88)},
		"HoodDecal": {"from": Vector3(0.0, 1.4, -1.52), "dir": Vector3(0, -1, 0), "up": Vector3.FORWARD},
		"SillDecalL": {"from": Vector3(-1.5, 0.36, 0.0), "dir": Vector3(1, 0, 0), "up": Vector3.UP},
		"SillDecalR": {"from": Vector3(1.5, 0.36, 0.0), "dir": Vector3(-1, 0, 0), "up": Vector3.UP},
	},
}

const ZAFIRA_VISUAL := {
	"model": "res://models/zafira.glb", "wheel_radius": 0.3160, "wheelbase": 2.703, "half_track_front": 0.744, "half_track_rear": 0.755,
	"roof_number": Vector3(0.0, 1.620, 0.50), "brake_light": Vector3(0.0, 1.00, 2.42), "tailpipe": Vector3(0.40, 0.264, 2.231),
	"fx_axle": Vector3(0.0, 0.03, 1.3515), "contact": Vector2(2.15, 4.80),
	# front bumper beam plate (0.440) and tailgate recess plate (0.695), 512 x 105 mm (build_zafira.py)
	"plate_y": Vector3(0.440, 0.695, 0.90),
	# deeper red lens for the tall vertical wrap-around tail lamps
	"tail_lamp": {"tint": Color(0.70, 0.01, 0.015), "alpha_off": 0.86, "alpha_lit": 0.93, "glow_gain": 0.6, "sheen": 0.3,
		"reflect": 0.3, "albedo": Color("#5a0404"), "energy": 0.9},
	# nose is 2.2415 m ahead of origin; cowl is at 1.1015 m ahead, 1.058 m high
	"bumper_cam": Vector2(2.27, 0.50), "bonnet_cam": Vector2(1.08, 1.24),
	"chase_back": 0.66, ## tail is 2.2255 m behind origin (vs Seicento's 1.58)
	"decal_aims": {
		"DoorDecalL": {"from": Vector3(-1.5, 0.72, -0.38), "dir": Vector3(1, 0, 0), "up": Vector3.UP},
		"DoorDecalR": {"from": Vector3(1.5, 0.72, -0.38), "dir": Vector3(-1, 0, 0), "up": Vector3.UP},
		"Sunstrip": {"from": Vector3(0.001, 2.00, -0.58), "dir": Vector3(0.0, -0.88, 0.47), "up": Vector3(0.0, 0.47, 0.88)},
		"HoodDecal": {"from": Vector3(0.001, 1.5, -1.60), "dir": Vector3(0, -1, 0), "up": Vector3.FORWARD},
		"SillDecalL": {"from": Vector3(-1.5, 0.38, 0.0), "dir": Vector3(1, 0, 0), "up": Vector3.UP},
		"SillDecalR": {"from": Vector3(1.5, 0.38, 0.0), "dir": Vector3(-1, 0, 0), "up": Vector3.UP},
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
		"logan":
			return "Dacia Logan 1.4"
		"v50":
			return "Volvo V50 2.4i"
		"i20":
			return "Hyundai i20 1.4"
		"sandero":
			return "Dacia Sandero 1.6"
		"focus":
			return "Ford Focus 1.5"
		"zafira":
			return "Opel Zafira B 1.8"
	return "Seicento 900"

## The car's physics spec (a fresh duplicate for every car but the stock one's shared resource).
static func spec(key: String) -> CarSpec:
	match key:
		"hypercar":
			return Hypercar.spec()
		"golf4":
			return Golf4.spec()
		"logan":
			return Logan.spec()
		"v50":
			return V50.spec()
		"i20":
			return I20.spec()
		"sandero":
			return Sandero.spec()
		"focus":
			return Focus.spec()
		"zafira":
			return Zafira.spec()
	return load("res://data/seicento.tres")

static func model(key: String) -> CarModel:
	return CarModel.new(spec(key)) if key != "stock" else CarModel.new()

## How RaceCarVisual dresses this car (see STOCK_VISUAL); the hypercar is the stock body in another livery.
static func visual(key: String) -> Dictionary:
	match key:
		"golf4":
			return GOLF4_VISUAL
		"logan":
			return LOGAN_VISUAL
		"v50":
			return V50_VISUAL
		"i20":
			return I20_VISUAL
		"sandero":
			return SANDERO_VISUAL
		"focus":
			return FOCUS_VISUAL
		"zafira":
			return ZAFIRA_VISUAL
	return STOCK_VISUAL

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

## Factory paints, after each car's real colour chart: [name, sRGB]. The player picks one in the garage and the AI field
## and the street rivals wear the rest. The hypercar's first entry is its fixed AF Corse livery (the player's car always
## wears it); the others are Ferrari's own paints for its field. A new car only adds an entry here.
const PALETTES := {
	"stock": [ # Fiat Seicento 1998-2010 (Tychy)
		["Rosso Corsa", "#b5121b"], ["Giallo Ginestra", "#f2c400"], ["Bianco Banchisa", "#ecedea"], ["Blu Sprint", "#1f3f8f"],
		["Azzurro Capri", "#3d8fcf"], ["Verde Bosco", "#1f4a33"], ["Grigio Alluminio", "#a6abb0"], ["Nero Tenore", "#16171a"],
		["Rosso Granata", "#6e1a22"],
	],
	"hypercar": [ # AF Corse no. 83, then Ferrari's colour chart for the field
		["AF Corse Giallo", "#ffd400"], ["Rosso Corsa", "#c4121a"], ["Rosso Scuderia", "#e0261c"], ["Nero Daytona", "#121316"],
		["Bianco Avus", "#eef0ee"], ["Grigio Silverstone", "#5d6267"], ["Blu Pozzi", "#1c3466"], ["Argento Nürburgring", "#b6b9bc"],
	],
	"golf4": [ # Volkswagen Golf IV 1997-2004
		["Candy White", "#f0f0eb"], ["Reflex Silver", "#b7bcc0"], ["Satin Silver", "#9a9fa2"], ["Black Magic Pearl", "#121214"],
		["Tornado Red", "#c4161c"], ["Jazz Blue Pearl", "#1d2a5a"], ["Indigo Blue Pearl", "#2b2f55"], ["Galactic Blue", "#1a2140"],
		["Imola Yellow", "#f2cf00"], ["Cool Water Blue", "#5b84a6"], ["Mojave Beige", "#b5a588"],
	],
	"logan": [ # Dacia Logan I 2004-2012
		["Blanc Glacier", "#eef0ee"], ["Gris Platine", "#a8acaf"], ["Gris Comète", "#6c7075"], ["Noir Nacré", "#17181b"],
		["Bleu Minéral", "#3a5c82"], ["Bleu Navy", "#1d2a45"], ["Rouge de Feu", "#b8161b"], ["Beige Toundra", "#b6a68a"],
	],
	"v50": [ # Volvo V50 2004-2007
		["Ice White", "#eceeec"], ["Silver Metallic", "#aeb2b5"], ["Titanium Grey", "#73777a"], ["Black Sapphire", "#141518"],
		["Barents Blue", "#24344f"], ["Magic Blue", "#2f4f78"], ["Passion Red", "#9c1a22"], ["Willow Green", "#5d6f5c"],
		["Sandstone Beige", "#b9ad94"],
	],
	"i20": [ # Hyundai i20 PB 2008-2012
		["Crystal White", "#f0f1ee"], ["Sleek Silver", "#b4b9be"], ["Dark Grey", "#55595e"], ["Black Diamond", "#151619"],
		["Spark Blue", "#25589c"], ["Blueberry Blue", "#1c3358"], ["Berry Red", "#a81824"], ["Electric Red", "#cc1b22"],
		["Champagne Silver", "#c4baaa"],
	],
	"sandero": [ # Dacia Sandero I 2008-2012
		["Glacier White", "#eef0ee"], ["Platine Silver", "#a8acaf"], ["Comète Grey", "#686c71"], ["Pearl Black", "#16171a"],
		["Passion Red", "#b81820"], ["Mineral Blue", "#3a5c82"], ["Mahogany Brown", "#5a3426"], ["Marina Blue", "#1f3e6e"],
	],
	"focus": [ # Ford Focus Mk3.5 2015
		["Frozen White", "#f0f2f0"], ["Moondust Silver", "#b6bcc0"], ["Magnetic Grey", "#4f5459"], ["Shadow Black", "#141518"],
		["Deep Impact Blue", "#183c7a"], ["Race Red", "#c4161c"], ["Candy Red", "#8e121e"], ["Tangerine Scream", "#e89c10"],
		["Tectonic Silver", "#a59f93"],
	],
	"zafira": [ # Opel Zafira B 2005-2011
		["Casablanca White", "#eff1ee"], ["Star Silver", "#b7bcc1"], ["Moonland Grey", "#6f7479"], ["Black Sapphire", "#14161a"],
		["Ultra Blue", "#1c5ca8"], ["Metro Blue", "#4e6273"], ["Power Red", "#b8171e"], ["Pannacotta", "#c2b7a3"],
		["Royal Blue", "#1b2d59"],
	],
}
## Measured with tests/_car_probe.gd (and test_hypercar.gd): [0-100 km/h s, top km/h], for the garage's bars.
const FIGURES := {"stock": [20.4, 137.0], "hypercar": [3.0, 346.0], "golf4": [13.9, 171.0], "logan": [13.3, 162.0], "v50": [8.3, 211.0], "i20": [11.6, 180.0], "sandero": [11.6, 174.0], "focus": [8.8, 210.0], "zafira": [11.4, 197.0]}
const PAINT_SAVE := "garage.cfg" ## the paint last picked for each car (SaveData)

## The car's factory paints: [{name, color}], the stock Seicento's for an unknown key.
static func palette(key: String) -> Array:
	var out: Array = []
	for e in PALETTES.get(key, PALETTES.stock):
		out.append({"name": String(e[0]), "color": Color(String(e[1]))})
	return out

## The palette entry closest to a colour (an old free colour from a settings file lands on its nearest factory paint).
static func nearest_paint(key: String, c: Color) -> int:
	var pal := palette(key)
	var best := 0
	var gap := INF
	for i in pal.size():
		var p: Color = pal[i].color
		# weighted RGB distance with a lightness term, so a dark blue stays blue and a silver stays silver
		var d := 2.0 * pow(p.r - c.r, 2) + 4.0 * pow(p.g - c.g, 2) + 3.0 * pow(p.b - c.b, 2) + 2.0 * pow(p.get_luminance() - c.get_luminance(), 2)
		if d < gap:
			gap = d
			best = i
	return best

static func paint_name(key: String, c: Color) -> String:
	return String(palette(key)[nearest_paint(key, c)].name)

## The colour of the AI car at grid index `i` in a field of `key` cars: the palette in order from a seed, with the paint
## nearest the player's left out (when there are three or more), so neighbours differ and nobody matches the player.
static func field_color(key: String, i: int, avoid: Color, seed := 0) -> Color:
	var pal := palette(key)
	var skip := nearest_paint(key, avoid) if pal.size() >= 3 else -1
	var pool: Array = []
	for k in pal.size():
		if k != skip:
			pool.append(pal[k].color)
	return pool[posmod(i + seed, pool.size())]

## The paint the player last picked for this car (the garage), else the palette entry nearest `fallback`; always a
## factory paint, and the livery's colour for a car with a fixed livery.
static func saved_paint(key: String, fallback: Color) -> Color:
	var liv := livery(key)
	if not liv.is_empty():
		return liv.color
	var cfg := ConfigFile.new()
	if cfg.load(SaveData.read_path(PAINT_SAVE)) == OK and cfg.has_section_key("paint", key):
		var name := String(cfg.get_value("paint", key))
		for e in palette(key):
			if String(e.name) == name:
				return e.color
	return palette(key)[nearest_paint(key, fallback)].color

static func save_paint(key: String, c: Color) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SaveData.read_path(PAINT_SAVE))
	cfg.set_value("paint", key, paint_name(key, c))
	cfg.save(SaveData.path(PAINT_SAVE))
