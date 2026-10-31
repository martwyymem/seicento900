## Damage policy: circuit races (quick race, championship, campaign) are cosmetic-only by default, for every car alike;
## mechanical damage is opt-in (RaceSettings.mechanical_damage) and always on in a rally stage.
extends RefCounted

var completed := false
var errors: Array[String] = []

func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		errors.append("%s %s" % [what, detail])

func _race(mechanical: bool, rally := false) -> Race:
	var st := RaceSettings.new()
	st.track = "gp"
	st.opponents = 3
	st.race_control = true
	st.mechanical_damage = mechanical
	if rally:
		Rally.configure_stage(st, {"track": "fiat", "from": 0.0, "to": 0.0, "surface": "tarmac", "weather": "dry", "hour": 9.0})
	return Race.new(st, null, 1)

func run() -> Array:
	check("mechanical damage is opt-in", not RaceSettings.new().mechanical_damage)
	# default circuit race: a hard hit only dents, for the player and an AI car alike
	var race := _race(false)
	check("a circuit race has race control but no mechanical damage", race.rc != null and not race.mechanical_damage)
	for car: RaceCar in [race.player, race.cars[1]]:
		var wrecked := race.rc.hurt(car, 25.0, true, 0.9) # a huge head-on barrier hit
		check("car %d is not wrecked by a hit" % car.id, not wrecked and not car.wrecked and not car.dnf)
		check("car %d takes no mechanical damage" % car.id, car.damage == 0.0 and car.parts.is_empty() and not car.fx_on)
		check("car %d is only scuffed and dented" % car.id, car.scuff > 0.5 and float(car.dents.front) > 0.5)
	check("player and AI scuff alike", is_equal_approx(race.player.scuff, race.cars[1].scuff))
	race.dispose()
	# opt-in: the same hit costs every car the same
	race = _race(true)
	check("opt-in turns mechanical damage on", race.mechanical_damage)
	race.rc.hurt(race.player, 4.0, true, 0.9)
	race.rc.hurt(race.cars[1], 4.0, true, 0.9)
	check("opt-in: the player is damaged", race.player.damage > 0.0 and not race.player.parts.is_empty())
	check("opt-in: an AI car is damaged exactly as much", is_equal_approx(race.player.damage, race.cars[1].damage), "(%.3f vs %.3f)" % [race.player.damage, race.cars[1].damage])
	race.dispose()
	# a rally stage always has it, whatever the setting
	race = _race(false, true)
	check("a rally stage always has mechanical damage", race.mechanical_damage)
	race.rc.hurt(race.player, 4.0, true, 0.9)
	check("rally: a hit costs the car", race.player.damage > 0.0)
	race.dispose()
	completed = true
	return errors
