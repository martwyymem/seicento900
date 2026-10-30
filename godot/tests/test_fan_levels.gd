## Fan levels climb with the fans, every campaign stage names a level and pays fans for its result.
extends RefCounted

var completed := false
var errors: Array[String] = []

func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		errors.append("%s %s" % [what, detail])

func run() -> Array:
	check("no fans is level 1", FanLevels.level(0) == 1)
	check("level 2 starts at its threshold", FanLevels.level(FanLevels.THRESHOLDS[1] - 1) == 1 and FanLevels.level(FanLevels.THRESHOLDS[1]) == 2)
	check("the top level holds past its threshold", FanLevels.level(10 * FanLevels.THRESHOLDS[-1]) == FanLevels.THRESHOLDS.size())
	check("every level has a title", FanLevels.TITLES.size() == FanLevels.THRESHOLDS.size())
	check("thresholds only rise", FanLevels.THRESHOLDS.slice(1).all(func(t): return t > 0) and _rising())
	check("to_next counts down", FanLevels.to_next(FanLevels.THRESHOLDS[1] - 100) == 100)
	check("to_next is -1 at the top", FanLevels.to_next(FanLevels.THRESHOLDS[-1]) == -1)
	var mid: int = (FanLevels.THRESHOLDS[1] + FanLevels.THRESHOLDS[2]) / 2
	check("progress runs from 0 to 1 through a level", FanLevels.progress(FanLevels.THRESHOLDS[1]) == 0.0 and absf(FanLevels.progress(mid) - 0.5) < 0.01)
	# campaign stages
	var n: int = Campaign.STAGES.size()
	for i in n:
		check("stage %d names a level in range" % i, FanLevels.stage_level(i) >= 1 and FanLevels.stage_level(i) <= FanLevels.THRESHOLDS.size())
		if i > 0:
			check("stage levels never fall", FanLevels.stage_level(i) >= FanLevels.stage_level(i - 1))
			check("later stages pay more", FanLevels.stage_reward(i, 3, 3, true) > FanLevels.stage_reward(i - 1, 3, 3, true))
		var target: int = int(Campaign.STAGES[i].target_pos)
		var first := FanLevels.stage_reward(i, target, target, true)
		check("a first clear pays", first > 0)
		check("a repeat pays less than a first clear", FanLevels.stage_reward(i, target, target, false) < first)
		check("a miss pays least", FanLevels.stage_reward(i, target + 1, target, true) < FanLevels.stage_reward(i, target, target, false) + 1)
		if target > 1:
			check("beating the target pays more", FanLevels.stage_reward(i, target - 1, target, true) > first)
	var campaign_total := 0
	for i in n:
		campaign_total += FanLevels.stage_reward(i, int(Campaign.STAGES[i].target_pos), int(Campaign.STAGES[i].target_pos), true)
	check("clearing the campaign reaches a high level but not the top", FanLevels.level(campaign_total) >= 6 and not FanLevels.is_max(campaign_total),
		"(%d fans, level %d)" % [campaign_total, FanLevels.level(campaign_total)])
	completed = true
	return errors

func _rising() -> bool:
	for i in range(1, FanLevels.THRESHOLDS.size()):
		if FanLevels.THRESHOLDS[i] <= FanLevels.THRESHOLDS[i - 1]:
			return false
	return true
