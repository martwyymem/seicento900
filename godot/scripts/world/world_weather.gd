## The open world's free-roam weather (Forza Horizon style): mostly dry, now and then a shower, a rare fog at dawn,
## snow only when switched on. A pure function of a seed and the game clock, so a reload that keeps the seed and the
## clock continues the same weather. Times are game hours (OpenWorld.DAY_RATE turns a real second into 1/80 of one).
##
## The day's plan (`events_for`): 45 % of days have no shower, 35 % one, 20 % two; a shower starts at any hour, lasts
## 1-3 h and peaks at 0.4-1.0 rain; a day has a 7 % chance of a dawn fog (starts 3:30-5:30, 2-3.5 h) that never
## overlaps a shower. Rain and fog ramp in and out (RAIN_RAMP 12 game minutes, FOG_RAMP 30). The road's wetness lags the
## rain (reaches full in about WET_RISE_HOURS under a full shower) and dries slowly (WET_DRY_HOURS from fully wet), and
## the car's grip follows the wetness as Race.grip does with road tyres (`grip`).
class_name WorldWeather
extends RefCounted

const RAIN_RAMP := 0.2 ## game hours a shower takes to build up and to die away
const FOG_RAMP := 0.5
const WET_RISE_HOURS := 0.45 ## game hours for the road to wet fully under full rain
const WET_DRY_HOURS := 2.5 ## game hours for a fully wet road to dry
const SHOWER_CHANCE := [0.45, 0.80] ## cumulative: below the first no shower in a day, below the second one, else two
const SHOWER_HOURS := Vector2(1.0, 3.0)
const SHOWER_LEVEL := Vector2(0.4, 1.0)
const FOG_DAY_CHANCE := 0.07
const FOG_START := Vector2(3.5, 5.5)
const FOG_HOURS := Vector2(2.0, 3.5)
const SNOW_DAY_CHANCE := 0.15 ## per day, when snow is switched on
const SNOW_HOURS := Vector2(3.0, 6.0)
const SETTLE_HOURS := 8.0 ## `settle` replays this long before the clock to find how wet the road is
const SUBSTEP := 0.05 ## game hours: the longest step the wetness is integrated in
const JUMP_HOURS := 0.25 ## an advance longer than this (skipping the time of day) re-settles instead of integrating
const FOG_GRIP := 0.06 ## grip lost in full fog (Race.grip's 0.94)

var seed_value := 1
var snow_enabled := false
var clock := 0.0 ## game hours since the weather began: day * 24 + the hour of day
var rain := 0.0
var wet := 0.0
var fog := 0.0
var snow := 0.0
var forced: Array = [] ## dev overrides ({kind, start, end, level}); never saved
var _days := {} ## day -> its events
var _tyres := Tyres.new()

func _init(seed_: int = 1, clock_: float = 0.0, snow_on := false) -> void:
	seed_value = seed_
	snow_enabled = snow_on
	settle(clock_)

# ------------------------------------------------------------------------------------------ the plan

## A day's events, {kind: "rain"|"fog"|"snow", start, end, level} in absolute game hours (a shower may run past the
## day's end). Deterministic in the seed and the day.
func events_for(day: int) -> Array:
	if _days.has(day):
		return _days[day]
	var out: Array = _showers(day)
	var rng := _rng(day, 2)
	var base := float(day) * 24.0
	var fu := rng.next()
	var fs := base + lerpf(FOG_START.x, FOG_START.y, rng.next())
	var fl := lerpf(FOG_HOURS.x, FOG_HOURS.y, rng.next())
	var flevel := lerpf(0.6, 1.0, rng.next())
	if fu < FOG_DAY_CHANCE:
		var fe := fs + fl
		var clear := true
		for sh in out + (_showers(day - 1) if day > 0 else []): # (the day before only ever runs into this one)
			if float(sh.start) < fe + FOG_RAMP and float(sh.end) > fs - FOG_RAMP:
				clear = false
		if clear:
			out.append({"kind": "fog", "start": fs, "end": fe, "level": flevel})
	if snow_enabled:
		rng = _rng(day, 3)
		if rng.next() < SNOW_DAY_CHANCE:
			var ss := base + rng.next() * 24.0
			out.append({"kind": "snow", "start": ss, "end": ss + lerpf(SNOW_HOURS.x, SNOW_HOURS.y, rng.next()), "level": lerpf(0.5, 1.0, rng.next())})
	_days[day] = out
	return out

func _rng(day: int, stream: int) -> SimUtil.Rng:
	var rng := SimUtil.Rng.new((seed_value * 2654435761 + (day + 4096) * 40503 + stream * 7919 + 977) & 0xffffffff)
	for _i in 3:
		rng.next()
	return rng

## The day's showers alone: none 45 %, one 35 %, two 20 %.
func _showers(day: int) -> Array:
	var rng := _rng(day, 1)
	var out: Array = []
	var u := rng.next()
	var n := 0 if u < SHOWER_CHANCE[0] else (1 if u < SHOWER_CHANCE[1] else 2)
	for _i in n:
		var start := float(day) * 24.0 + rng.next() * 24.0
		var length := lerpf(SHOWER_HOURS.x, SHOWER_HOURS.y, rng.next())
		out.append({"kind": "rain", "start": start, "end": start + length, "level": lerpf(SHOWER_LEVEL.x, SHOWER_LEVEL.y, rng.next())})
	return out

static func _ramp(t: float, ev: Dictionary, ramp: float) -> float:
	return float(ev.level) * SimUtil.smooth01((t - float(ev.start)) / ramp) * SimUtil.smooth01((float(ev.end) - t) / ramp)

## What the plan asks for at game hour `t`: {rain, fog, snow}, each 0..1 and continuous in `t`.
func target(t: float) -> Dictionary:
	var r := 0.0
	var f := 0.0
	var s := 0.0
	var day := int(floorf(t / 24.0))
	var evs: Array = []
	if day > 0:
		evs.append_array(events_for(day - 1))
	evs.append_array(events_for(day))
	evs.append_array(forced)
	for ev in evs:
		match String(ev.kind):
			"rain": r = maxf(r, _ramp(t, ev, RAIN_RAMP))
			"fog": f = maxf(f, _ramp(t, ev, FOG_RAMP))
			"snow": s = maxf(s, _ramp(t, ev, RAIN_RAMP))
	return {"rain": r, "fog": f, "snow": s}

# ------------------------------------------------------------------------------------------ the state

## Replays the SETTLE_HOURS before `c` from a dry road and leaves the weather as it is at `c`. Deterministic in the
## seed and `c`, so a reload (and a skip of the clock) land on the same weather as playing through would.
func settle(c: float) -> void:
	var from := maxf(c - SETTLE_HOURS, 0.0)
	clock = from
	rain = 0.0
	wet = 0.0
	fog = 0.0
	snow = 0.0
	_apply_target(from)
	while clock < c - 1e-9:
		_integrate(minf(SUBSTEP, c - clock))

## Moves the clock on by `dh` game hours (a long jump re-settles).
func advance(dh: float) -> void:
	if dh <= 0.0:
		return
	if dh > JUMP_HOURS:
		settle(clock + dh)
		return
	var left := dh
	while left > 1e-9:
		var d := minf(SUBSTEP, left)
		_integrate(d)
		left -= d

func _apply_target(t: float) -> void:
	var tg := target(t)
	rain = tg.rain
	fog = tg.fog
	snow = tg.snow

func _integrate(dh: float) -> void:
	clock += dh
	_apply_target(clock)
	var precip := maxf(rain, snow * 0.7)
	var goal := minf(1.0, precip * 1.2)
	var floor_wet := 0.15 * fog
	if precip > 0.05 and goal > wet:
		wet = minf(goal, wet + precip * dh / WET_RISE_HOURS)
	else:
		wet = maxf(maxf(floor_wet, goal if precip > 0.05 else 0.0), wet - dh / WET_DRY_HOURS)

## The car's grip against a dry road: Race.grip with road tyres (the better of the medium and the wet compound at that
## wetness against a dry medium), less the snow and, in a smooth way, the fog.
func grip(wet_: float, snow_: float, fog_: float) -> float:
	var g := maxf(_tyres.compound_grip("M", wet_), _tyres.compound_grip("W", wet_)) / _tyres.compound_grip("M", 0.0)
	g *= 1.0 - snow_ * 0.42
	g *= 1.0 - FOG_GRIP * fog_
	return minf(g, 1.0)

## The weather now in MapMissions.weather_state's form, for OpenWorld.set_weather.
func state() -> Dictionary:
	var mode := "dry"
	if snow > 0.05:
		mode = "snow"
	elif rain > 0.05 or wet > 0.15:
		mode = "wet"
	elif fog > 0.05:
		mode = "mist" # (a mission's "fog" mode adds a fixed amount of wisps; free roam's follow the level alone)
	return {"mode": mode, "wet": wet, "rain": rain, "snow": snow, "hail": 0.0, "fog": fog, "mu": grip(wet, snow, fog)}

## A dev override: `kind` ("rain", "fog", "snow") from now for `hours`; "clear" drops the overrides.
func force(kind: String, hours := 2.0, level := 1.0) -> void:
	forced.clear()
	if kind == "clear":
		return
	forced.append({"kind": kind, "start": clock, "end": clock + hours, "level": level})

## A word for the clock on the HUD for a weather state ({mode, wet, rain, snow, fog}): "" when it is fine.
static func word(st: Dictionary) -> String:
	var r := float(st.get("rain", 0.0))
	if float(st.get("snow", 0.0)) > 0.05:
		return "SNOW"
	if float(st.get("hail", 0.0)) > 0.05:
		return "HAIL"
	if r > 0.7:
		return "HEAVY RAIN"
	if r > 0.05:
		return "RAIN"
	if float(st.get("fog", 0.0)) > 0.3:
		return "FOG"
	if float(st.get("wet", 0.0)) > 0.25:
		return "WET ROAD"
	return ""
