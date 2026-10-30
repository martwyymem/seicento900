## Modifiers that fan levels unlock (TASKS.md 6b): toggled on the open world's pause menu (MODIFIERS) or the race set-up's
## Car page, saved in the open-world save, and used in every mode on the player's car (Race.set_mods); Monster
## Truck also puts every other car on giant wheels. Level 10's reward is the Hypercar Seicento
## (the CAR button), not a modifier.
class_name CarMods
extends RefCounted

## id, the fan level that unlocks it, the name shown and a one-line note.
const LIST := [
	["rainbow", 2, "RAINBOW PAINT", "The paint cycles through every colour"],
	["monster", 3, "MONSTER TRUCK", "Giant wheels on everything; climbs kerbs, flattens traffic"],
	["moon", 4, "MOON GRAVITY", "A sixth of the pull: long, floaty jumps"],
	["ice", 5, "ICE RINK", "Every road is a frozen lake"],
	["drift", 6, "DRIFT KING", "A loose rear end and a strong drift assist; chains bank 60%"],
	["tiny", 7, "TINY SEICENTO", "Half the size, same engine"],
	["bullet", 8, "BULLET TIME", "Slow motion in big drifts and jumps"],
	["nitro", 9, "NITROUS", "Hold Shift or L3 for N2O; skills refill the bottle"],
]

const MOON_GRAVITY := 1.62 / 9.81
const ICE_GRIP := 0.3
const DRIFT_REAR_GRIP := 0.72
const MONSTER_WHEELS := 2.2
const TINY_SCALE := 0.5
const BULLET_RATE := 0.4 ## simulation speed while bullet time runs
const DRIFT_FANS := 0.6 ## Drift King makes slides easy, so its chains pay less
const MONSTER_STEP := 1.8 ## m: a monster truck drives up a step this high (a plain car stops at FreeCar.WALL_STEP)
const MONSTER_SHRUG := 0.25 ## share of a traffic car's mass the truck feels in a collision
const NITRO_POWER := 1.7 ## engine output while the bottle is open
const NITRO_BURN := 0.25 ## bottle per second (a full one lasts 4 s)
const NITRO_REFILL := 1.0 / 2500.0 ## bottle per skill point
const RACE_NITRO_REFILL := 25.0 ## s for an empty bottle to refill in a race (no skill chains there)

static func level_of(id: String) -> int:
	for m in LIST:
		if m[0] == id:
			return m[1]
	return 99

static func unlocked(id: String, fans: int) -> bool:
	var lvl := level_of(id)
	return lvl <= FanLevels.THRESHOLDS.size() and (FanLevels.dev_unlock or FanLevels.level(fans) >= lvl)

## The ids switched on that the fans still unlock (a save edited down, or a dev unlock switched off, drops the rest).
static func active(on: Dictionary, fans: int) -> Dictionary:
	var out := {}
	for id in on:
		if on[id] and unlocked(id, fans):
			out[id] = true
	return out

## Applies the physics side to the player's open-world car.
static func apply_to(car: FreeCar, on: Dictionary) -> void:
	car.grav_mul = MOON_GRAVITY if on.has("moon") else 1.0
	car.grip_mul = ICE_GRIP if on.has("ice") else 1.0
	car.rear_grip = DRIFT_REAR_GRIP if on.has("drift") else 1.0
	car.drift_king = on.has("drift")
	car.monster = on.has("monster")
