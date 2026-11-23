## The player's DIFFICULTY & ASSISTS profile (Options → Difficulty & Assists): one rival level that shifts every
## event against its authored baseline, the driving aids, and the accessibility switches (fuel use, tyre wear,
## damage, auto-recover). Saved to difficulty.cfg as plain values only.
##
## Rivals: seven steps. Each step moves an event's own level (Race.DIFFICULTY: easy 0, medium 1, hard 2,
## alien 3) by SHIFT levels, so a campaign stage authored "hard" stays exactly as authored at Average, is
## two levels kinder at Novice and two harder (alien) at Unbeatable. The race sim never reads this class:
## the game turns it into RaceSettings.difficulty / difficulty_shift / aids / fuel_mult / wear_mult /
## damage_mode / auto_rejoin, so a race built from its own settings (the parity race) is untouched.
## The open world's events (LiveEvents, MapMissions, StreetRivals) and the fan payouts read `current`.
class_name DifficultyProfile
extends RefCounted

const FILE := "difficulty.cfg"
const STEPS := ["Novice", "Casual", "Average", "Skilled", "Expert", "Pro", "Unbeatable"]
const AVERAGE := 2
## Each step's shift of an event's authored level, in Race.DIFFICULTY levels. Against Quick Race's baseline
## (medium) Casual is Easy, Average Medium, Expert Hard and Unbeatable Alien; Novice sits a level under Easy.
const SHIFT := [-2.0, -1.0, 0.0, 0.5, 1.0, 1.5, 2.0]
const STEP_NOTES := [
	"Rivals well below each event's level: relaxed, forgiving and slow to punish a mistake.",
	"Rivals a level below each event's own: room to learn the tracks.",
	"Every event exactly as it was designed.",
	"Rivals half a level above each event's own.",
	"Rivals a full level above: every event a real fight.",
	"Rivals a level and a half above: little room for mistakes.",
	"Rivals two levels above each event, up to Alien pace: for the few.",
]
## Fans an event pays at each step (Forza-style reward multiplier): lower steps pay a little less, never nothing.
const STEP_FANS := [0.8, 0.9, 1.0, 1.1, 1.2, 1.35, 1.5]
## Extra fans for each aid turned off (and manual shifting, a harder racing line, full damage).
const AID_FANS := 0.05
const LINE_FANS := {"full": 0.0, "braking": 0.02, "off": 0.05}
const LEVELS := ["easy", "medium", "hard", "alien"]
const LEVEL_MIN := -1.0 ## a level under easy (Novice on an easy event)
const LEVEL_MAX := 3.0 ## alien is the ceiling
## Race.DIFFICULTY's row a level under easy, for Novice on an easy event (the easy-medium slope carried on).
const NOVICE_RACE := {"skill": 0.905, "spread": 0.042, "mistakes": 0.17, "band": 0.065}

const AID_KEYS := ["abs", "tc", "esc", "steer", "brake"]
const AID_NAMES := {"abs": "Anti-lock brakes", "tc": "Traction control", "esc": "Stability control",
	"steer": "Steering assist", "brake": "Braking assist"}
const LINE_MODES := ["full", "braking", "off"]
const LINE_NAMES := ["Full line", "Braking only", "Off"]
const DAMAGE_MODES := ["event", "off", "cosmetic", "full"]
const DAMAGE_NAMES := ["Event rules", "Off", "Cosmetic only", "Full mechanical"]
const PRESET_KEYS := ["beginner", "default", "pro"]
const PRESET_NAMES := ["Beginner", "Default", "Pro", "Custom"]
## The aid presets. Beginner is the game's own "Full assists" (as every race had by default before the
## profile), Default the usual middle (ABS and traction control), Pro everything off.
const PRESETS := {
	"beginner": {"abs": true, "tc": true, "esc": true, "steer": true, "brake": true, "shifting": "auto", "line": "full"},
	"default": {"abs": true, "tc": true, "esc": false, "steer": false, "brake": false, "shifting": "auto", "line": "full"},
	"pro": {"abs": false, "tc": false, "esc": false, "steer": false, "brake": false, "shifting": "manual", "line": "off"},
}
## RaceSettings.assists' three tiers as aids (the set-up page's DRIVING AIDS picker: 0 full, 1 abs, 2 off).
const TIERS := ["full", "abs", "off"]
const TIER_AIDS := {
	"full": {"abs": true, "tc": true, "esc": true, "steer": true, "brake": true},
	"abs": {"abs": true, "tc": false, "esc": false, "steer": false, "brake": false},
	"off": {"abs": false, "tc": false, "esc": false, "steer": false, "brake": false},
}
## Old saves' 4-step difficulty index (Easy, Medium, Hard, Alien) as a step of the ladder.
const LEGACY_STEP := [1, 2, 4, 6]

static var current: Dictionary = defaults()

## The profile a new player (or an old save without difficulty.cfg) starts on: Average and the game's behaviour
## before the profile existed (full assists, automatic, the full racing line, fuel, wear and the events' damage).
static func defaults() -> Dictionary:
	return {"step": AVERAGE, "abs": true, "tc": true, "esc": true, "steer": true, "brake": true, "shifting": "auto",
		"line": "full", "fuel": true, "wear": true, "damage": "event", "recover": true}

## A profile with every key present and of the right plain type (anything else falls back to the default).
static func clean(d) -> Dictionary:
	var out := defaults()
	if not d is Dictionary:
		return out
	var src: Dictionary = d
	if src.get("step") is int or src.get("step") is float:
		out.step = clampi(int(src.step), 0, STEPS.size() - 1)
	for k in AID_KEYS + ["fuel", "wear", "recover"]:
		if src.get(k) is bool:
			out[k] = src[k]
	if src.get("shifting") is String and String(src.shifting) in ["auto", "manual"]:
		out.shifting = String(src.shifting)
	if src.get("line") is String and String(src.line) in LINE_MODES:
		out.line = String(src.line)
	if src.get("damage") is String and String(src.damage) in DAMAGE_MODES:
		out.damage = String(src.damage)
	return out

## Whether the profile is the default one (nothing changes for the player until they choose).
static func is_default(p: Dictionary) -> bool:
	return clean(p) == defaults()

# ---------------------------------------------------------------- saving

## Loads difficulty.cfg into `current`. False (and `current` left alone) when there is no file yet, so the
## game can build the first profile from the set-up page's old choices.
static func load_profile(file := "") -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(file if file != "" else SaveData.path(FILE)) != OK:
		return false
	var d := {}
	if cfg.has_section("profile"):
		for k in cfg.get_section_keys("profile"):
			var v = cfg.get_value("profile", k)
			if v is bool or v is int or v is float or v is String:
				d[k] = v # plain values only
	current = clean(d)
	return true

static func save_profile(file := "") -> void:
	var cfg := ConfigFile.new()
	var p := clean(current)
	for k in p:
		cfg.set_value("profile", k, p[k])
	cfg.save(file if file != "" else SaveData.path(FILE))

## The first profile of a save made before the profile existed: the set-up page's own choices (DRIVING AIDS
## index 0 full / 1 abs / 2 off, TRANSMISSION 0 auto / 1 manual, the old 4-step DIFFICULTY index), so nothing
## changes for an existing player. The rival step stays Average: the old picker only ever set Quick Race.
static func from_setup(assists_idx: int, gearbox_idx: int) -> Dictionary:
	var p := defaults()
	var aids: Dictionary = TIER_AIDS[TIERS[clampi(assists_idx, 0, 2)]]
	for k in aids:
		p[k] = aids[k]
	p.shifting = "manual" if gearbox_idx == 1 else "auto"
	return p

# ---------------------------------------------------------------- rivals

static func level_of(name: String) -> float:
	return float(maxi(LEVELS.find(name), 0)) if LEVELS.has(name) else 1.0

static func shift_of(step: int) -> float:
	return float(SHIFT[clampi(step, 0, SHIFT.size() - 1)])

## An event authored at `base` raced at ladder step `step`: {difficulty: the nearest Race.DIFFICULTY name,
## shift: the rest in levels (0 at Average, so the event is exactly as authored), level: the absolute level}.
static func resolve(base: String, step: int) -> Dictionary:
	var lv := clampf(level_of(base) + shift_of(step), LEVEL_MIN, LEVEL_MAX)
	var at := clampi(int(round(lv)), 0, LEVELS.size() - 1)
	if step == AVERAGE and LEVELS.has(base):
		return {"difficulty": base, "shift": 0.0, "level": level_of(base)}
	return {"difficulty": LEVELS[at], "shift": lv - float(at), "level": lv}

## The current profile's shift (levels) for the open world's events.
static func event_shift() -> float:
	return shift_of(int(current.get("step", AVERAGE)))

## Race.DIFFICULTY's row for `name` moved by `shift` levels, interpolated between the rows (and NOVICE_RACE
## under easy). With no shift it is the row itself, value for value.
static func race_params(name: String, shift := 0.0) -> Dictionary:
	var table: Dictionary = Race.DIFFICULTY
	var base: Dictionary = table.get(name, table.medium)
	if shift == 0.0:
		return base
	var lv := clampf(level_of(name) + shift, LEVEL_MIN, LEVEL_MAX)
	var rows := [NOVICE_RACE, table.easy, table.medium, table.hard, table.alien] # levels -1 .. 3
	var i := clampi(int(floor(lv + 1.0)), 0, rows.size() - 2)
	var f := clampf(lv + 1.0 - float(i), 0.0, 1.0)
	var out := {}
	for k in base:
		out[k] = lerpf(float(rows[i][k]), float(rows[i + 1][k]), f)
	return out

## A per-level table (some of easy/medium/hard/alien keyed, values float or Vector2) read at `name` moved by
## `shift` levels: linear between the table's levels and carried on along the nearest two past its ends.
## With no shift it is the entry itself.
static func band(table: Dictionary, name: String, shift := 0.0):
	var fallback = table.get("medium", table.values()[0])
	if shift == 0.0 or table.size() < 2:
		return table.get(name, fallback)
	var lv := clampf(level_of(name) + shift, LEVEL_MIN, LEVEL_MAX)
	var keys: Array = []
	for l in LEVELS:
		if table.has(l):
			keys.append(l)
	var i := 0
	while i < keys.size() - 2 and lv > level_of(String(keys[i + 1])):
		i += 1
	var a := level_of(String(keys[i]))
	var b := level_of(String(keys[i + 1]))
	var f := (lv - a) / (b - a)
	var va = table[keys[i]]
	var vb = table[keys[i + 1]]
	return va + (vb - va) * f

## Drift point tiers scale with the rivals: a fifth easier a level down, a fifth harder a level up.
static func tier_scale(shift: float) -> float:
	return clampf(1.0 + 0.2 * shift, 0.6, 1.4)

# ---------------------------------------------------------------- aids

## The aids as RaceSettings.aids takes them ({abs, tc, esc, steer, brake}).
static func aids(p: Dictionary) -> Dictionary:
	var out := {}
	for k in AID_KEYS:
		out[k] = bool(p.get(k, true))
	return out

## The DRIVING AIDS tier the aids are (0 full, 1 abs, 2 off), or 3 when they match none (custom).
static func tier_index(p: Dictionary) -> int:
	var a := aids(p)
	for i in TIERS.size():
		if a == TIER_AIDS[TIERS[i]]:
			return i
	return 3

## The closest tier's name, for what reads RaceSettings.assists as a label (lap records).
static func tier_name(p: Dictionary) -> String:
	var i := tier_index(p)
	if i < 3:
		return TIERS[i]
	return "abs" if bool(p.get("abs", true)) else "off"

static func preset(key: String) -> Dictionary:
	return PRESETS.get(key, PRESETS.default)

## Which preset the aids (with shifting and the racing line) are: an index into PRESET_NAMES (3 custom).
static func preset_index(p: Dictionary) -> int:
	for i in PRESET_KEYS.size():
		var pr: Dictionary = PRESETS[PRESET_KEYS[i]]
		var same := true
		for k in pr:
			if p.get(k) != pr[k]:
				same = false
				break
		if same:
			return i
	return 3

## The profile with a preset's aids, shifting and racing line put on.
static func with_preset(p: Dictionary, key: String) -> Dictionary:
	var out := clean(p)
	var pr := preset(key)
	for k in pr:
		out[k] = pr[k]
	return out

# ---------------------------------------------------------------- the race's settings

## The accessibility switches on a race's settings (after its mode has set its own): fuel use off (no burn, no
## refuelling), tyre wear off, the damage mode and auto-recover. The default profile changes nothing.
static func apply_sim(st: RaceSettings, p: Dictionary) -> void:
	if not bool(p.get("fuel", true)):
		st.fuel_mult = 0.0
		st.refuel = false
	if not bool(p.get("wear", true)):
		st.wear_mult = 0.0
	st.damage_mode = String(p.get("damage", "event"))
	match st.damage_mode:
		"full":
			st.mechanical_damage = true
		"off", "cosmetic":
			st.mechanical_damage = false
	st.auto_rejoin = bool(p.get("recover", true))

## Whether the switches change how a race has to be planned (fuel or wear off).
static func alters_strategy(p: Dictionary) -> bool:
	return not bool(p.get("fuel", true)) or not bool(p.get("wear", true))

# ---------------------------------------------------------------- fans

## Fans an event pays against the default: the rival step's share plus AID_FANS for each aid off, manual
## shifting and full damage, and a little for a reduced racing line. Fuel and wear switches never cost fans.
static func fan_multiplier(p: Dictionary = {}) -> float:
	if p.is_empty():
		p = current
	var m := float(STEP_FANS[clampi(int(p.get("step", AVERAGE)), 0, STEP_FANS.size() - 1)])
	for k in AID_KEYS:
		if not bool(p.get(k, true)):
			m += AID_FANS
	if String(p.get("shifting", "auto")) == "manual":
		m += AID_FANS
	m += float(LINE_FANS.get(String(p.get("line", "full")), 0.0))
	if String(p.get("damage", "event")) == "full":
		m += AID_FANS
	return m

## Fans scaled by the profile's multiplier (exactly the same number at 1.0).
static func scale_fans(fans: float, p: Dictionary = {}) -> float:
	var m := fan_multiplier(p)
	return fans if m == 1.0 else fans * m

## "+20% fans" / "-10% fans" / "standard fans", for the page and the cards.
static func fan_text(p: Dictionary = {}) -> String:
	var pct := int(round((fan_multiplier(p) - 1.0) * 100.0))
	if pct == 0:
		return "Standard fans"
	return "%+d%% fans" % pct
