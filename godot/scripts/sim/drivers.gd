## The field: fifteen real drivers, each with the car set-up (CarSetup notches) and the racing character
## they were known for. The set-ups follow how each one liked a car to behave: Senna, Schumacher and
## Verstappen with a pointy, loose rear; Prost, Button and Coulthard with a safe, understeering one; Hamilton
## on lots of rear brake; Vettel with a planted rear and the car low and stiff for the blown diffuser;
## Colin McRae with a rally car (soft, high, sideways). Driver.control drives each set-up through the full
## physics, so a loose car really is harder to keep on the road.
##
## Character, all relative to the difficulty level the player picked (Race.DIFFICULTY):
##   pace   -1..1   race pace, scaled by the difficulty's spread
##   quali  -1..1   extra over one lap
##   wet    ±0.03   grip in the rain (rain masters above 1)
##   wear   ×       tyre use (RaceCar.agg): Prost and Button easy on them, Mansell and McRae hard
##   errors ×       the difficulty's mistake rate
##   wets   0..1   how wet the track gets before they call for wets (brave ones stay out on slicks longer)
class_name Drivers
extends RefCounted

## In grid-filling order: a race with fewer opponents takes the first ones, so the order mixes the quick and
## the less quick to keep any short field about as strong as the full one.
const ROSTER := [
	{"name": "Ayrton Senna", "number": 12, "color": "#f2c318",
		"setup": {"brakes": 1, "springs": 1, "roll": 1, "height": -1, "steering": 1},
		"pace": 0.95, "quali": 1.0, "wet": 1.03, "wear": 1.02, "errors": 0.9, "wets": 0.46,
		"style": "A pointy car he balanced on the throttle; the best over one lap, and in the rain."},
	{"name": "Jenson Button", "number": 22, "color": "#9bd13b",
		"setup": {"brakes": -1, "springs": -1, "roll": -2, "height": 0, "steering": -1},
		"pace": 0.35, "quali": -0.3, "wet": 1.02, "wear": 0.88, "errors": 0.8, "wets": 0.42,
		"style": "Silky smooth and lost without a planted rear; easy on tyres and at his best in changing conditions."},
	{"name": "Alain Prost", "number": 2, "color": "#00a6d6",
		"setup": {"brakes": -1, "springs": -1, "roll": -1, "height": 0, "steering": -1},
		"pace": 0.8, "quali": -0.4, "wet": 0.98, "wear": 0.88, "errors": 0.6, "wets": 0.36,
		"style": "The Professor: soft and stable, set up for the race rather than qualifying, kind to his tyres."},
	{"name": "Colin McRae", "number": 4, "color": "#1d4fa3",
		"setup": {"brakes": 2, "springs": -2, "roll": 2, "height": 2, "steering": 2},
		"pace": 0.25, "quali": 0.3, "wet": 1.02, "wear": 1.15, "errors": 1.8, "wets": 0.45,
		"style": "If in doubt, flat out: a rally set-up, soft, high and sideways, and not always on the road."},
	{"name": "Michael Schumacher", "number": 1, "color": "#c9184a",
		"setup": {"brakes": 1, "springs": 1, "roll": 2, "height": -1, "steering": 2},
		"pace": 0.95, "quali": 0.5, "wet": 1.03, "wear": 1.0, "errors": 0.7, "wets": 0.45,
		"style": "A nervous, oversteering car his team-mates couldn't drive; relentless, and a master in the wet."},
	{"name": "David Coulthard", "number": 6, "color": "#404040",
		"setup": {"brakes": -1, "springs": 0, "roll": -1, "height": 0, "steering": -1},
		"pace": 0.15, "quali": 0.0, "wet": 1.0, "wear": 0.96, "errors": 1.0, "wets": 0.4,
		"style": "Prefers a car that understeers, the opposite of his team-mate Häkkinen."},
	{"name": "Lewis Hamilton", "number": 44, "color": "#7b2cbf",
		"setup": {"brakes": 2, "springs": 0, "roll": 1, "height": -1, "steering": 1},
		"pace": 0.9, "quali": 0.8, "wet": 1.025, "wear": 0.94, "errors": 0.7, "wets": 0.44,
		"style": "Brakes late with a lot of rear bias to rotate the car on the way in; superb in the wet."},
	{"name": "Niki Lauda", "number": 11, "color": "#8d6e63",
		"setup": {"brakes": -1, "springs": 0, "roll": -1, "height": 0, "steering": 0},
		"pace": 0.45, "quali": -0.2, "wet": 0.98, "wear": 0.9, "errors": 0.6, "wets": 0.36,
		"style": "Methodical: a safe, predictable car, no risks taken, and no love for the rain."},
	{"name": "Max Verstappen", "number": 33, "color": "#ff7f11",
		"setup": {"brakes": 1, "springs": 1, "roll": 2, "height": -2, "steering": 2},
		"pace": 0.95, "quali": 0.6, "wet": 1.03, "wear": 1.0, "errors": 1.0, "wets": 0.47,
		"style": "Wants the sharpest front end there is and lives with the loose rear that comes with it."},
	{"name": "Kimi Räikkönen", "number": 7, "color": "#f4f4f4",
		"setup": {"brakes": -1, "springs": 1, "roll": 1, "height": -1, "steering": 1},
		"pace": 0.5, "quali": -0.3, "wet": 1.0, "wear": 0.94, "errors": 0.9, "wets": 0.4,
		"style": "Needs a strong front end and a car that stays calm on the brakes; quicker in the race than on Saturday."},
	{"name": "Fernando Alonso", "number": 14, "color": "#2e8b57",
		"setup": {"brakes": 0, "springs": 0, "roll": 1, "height": -1, "steering": 1},
		"pace": 0.85, "quali": 0.2, "wet": 1.015, "wear": 0.94, "errors": 0.6, "wets": 0.42,
		"style": "Throws the car in on a strong front end and drives round whatever it does; almost never errs."},
	{"name": "Nigel Mansell", "number": 27, "color": "#e76f51",
		"setup": {"brakes": 1, "springs": 2, "roll": 1, "height": -1, "steering": 0},
		"pace": 0.5, "quali": 0.4, "wet": 1.0, "wear": 1.1, "errors": 1.4, "wets": 0.4,
		"style": "Brute force on a stiff car: late on the brakes, hard on the tyres, never gives up."},
	{"name": "Sebastian Vettel", "number": 5, "color": "#24356b",
		"setup": {"brakes": -2, "springs": 1, "roll": -1, "height": -2, "steering": 0},
		"pace": 0.6, "quali": 0.5, "wet": 1.0, "wear": 1.0, "errors": 1.2, "wets": 0.4,
		"style": "A planted rear on the way into a corner above all, the car low and stiff as in the blown-diffuser years."},
	{"name": "Charles Leclerc", "number": 16, "color": "#ff66b3",
		"setup": {"brakes": 1, "springs": 0, "roll": 1, "height": -1, "steering": 2},
		"pace": 0.6, "quali": 1.0, "wet": 0.995, "wear": 1.05, "errors": 1.3, "wets": 0.4,
		"style": "Likes the rear moving; a qualifying specialist who can overstep it."},
	{"name": "Mika Häkkinen", "number": 8, "color": "#9aa5b1",
		"setup": {"brakes": 1, "springs": 0, "roll": 1, "height": -1, "steering": 1},
		"pace": 0.65, "quali": 0.7, "wet": 0.995, "wear": 1.0, "errors": 1.0, "wets": 0.4,
		"style": "Left-foot braking into a car that turns in sharply; quick on Saturday."},
]

## The roster entry for a driver's name, or {}.
static func find(driver_name: String) -> Dictionary:
	for d in ROSTER:
		if d.name == driver_name:
			return d
	return {}
