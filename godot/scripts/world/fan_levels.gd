## Fan levels: the Seicento Fest's popularity ladder. Fans come from skills in the open world (drifts, jumps, near
## misses, speed traps, discoveries) and from campaign stages. The level only gives a name and a goal; each
## campaign stage names the level it is meant for, but nothing is locked behind it.
class_name FanLevels
extends RefCounted

## Fans needed for level 1, 2, 3, ...
const THRESHOLDS := [0, 2500, 7500, 17500, 35000, 65000, 110000, 180000, 280000, 420000]
const TITLES := ["Local Hopeful", "Street Regular", "Town Favourite", "Silesian Name", "Regional Star", "Fest Headliner",
	"National Name", "Poland's Pride", "Fest Icon", "Seicento Legend"]
static var dev_unlock := false ## the dev menu (§ + 1) unlocks everything the top level would

const STAGE_BASE := 3000 ## fans for clearing stage 1, times the stage's number for the later ones
const REPEAT_SHARE := 0.25 ## a stage that was cleared before pays this much again
const FAIL_SHARE := 0.1 ## the crowd still cheers a try that missed the objective

static func level(fans: int) -> int:
	var lv := 1
	for i in THRESHOLDS.size():
		if fans >= THRESHOLDS[i]:
			lv = i + 1
	return lv

static func title(lv: int) -> String:
	return TITLES[clampi(lv, 1, TITLES.size()) - 1]

static func is_max(fans: int) -> bool:
	return level(fans) >= THRESHOLDS.size()

## Fans still missing for the next level, or -1 at the top.
static func to_next(fans: int) -> int:
	var lv := level(fans)
	return -1 if lv >= THRESHOLDS.size() else THRESHOLDS[lv] - fans

## How far through the current level (0..1; 1 at the top).
static func progress(fans: int) -> float:
	var lv := level(fans)
	if lv >= THRESHOLDS.size():
		return 1.0
	var lo: int = THRESHOLDS[lv - 1]
	var hi: int = THRESHOLDS[lv]
	return clampf(float(fans - lo) / float(hi - lo), 0.0, 1.0)

## The level a campaign stage (0-based) is meant for: the first two share level 1, then one level per stage.
static func stage_level(stage_idx: int) -> int:
	if stage_idx >= 0 and stage_idx < Campaign.STAGES.size() and Campaign.STAGES[stage_idx].get("fan_lock", false):
		return THRESHOLDS.size()
	return clampi(stage_idx, 1, THRESHOLDS.size())

## Fans a campaign result pays. pos: finishing place (999 for a retirement), target: the place the stage asks for.
static func stage_reward(stage_idx: int, pos: int, target: int, first_clear: bool) -> int:
	var base := float(STAGE_BASE * (stage_idx + 1))
	if pos > target:
		return int(base * FAIL_SHARE)
	var beat := clampf(float(target - pos), 0.0, 3.0) # each place better than asked adds a quarter
	var pay := base * (1.0 + 0.25 * beat)
	return int(pay if first_clear else pay * REPEAT_SHARE)

## Whether the Hypercar Seicento (and the final race) is open: the top level, or the dev menu's override.
static func hypercar_unlocked(fans: int) -> bool:
	return dev_unlock or is_max(fans)
