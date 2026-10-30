## The Goliath (the final race, campaign stage 10): a 27 km lap of the whole Brzeszcze open world, raced in the
## Hypercar Seicento, locked until the top fan level.
extends RefCounted

var completed := false
var errors: Array[String] = []

func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		errors.append("%s %s" % [what, detail])

func run() -> Array:
	var def := Track.load_def("goliath")
	check("the Goliath has a TrackDef", def != null and def.street_stage)
	if def == null:
		return errors
	var tr := Track.new(def)
	check("one lap is 26-28 km", tr.L > 26000.0 and tr.L < 28000.0, "(%.0f m)" % tr.L)
	var env = JSON.parse_string(FileAccess.get_file_as_string("res://data/tracks/goliath_env.json"))
	check("every side road is closed off", env is Dictionary and (env.road_blockages as Array).size() > 100)

	var idx := -1
	for i in Campaign.STAGES.size():
		if Campaign.STAGES[i].track == "goliath":
			idx = i
	check("the Goliath is the last campaign stage", idx == Campaign.STAGES.size() - 1)
	var st: Dictionary = Campaign.STAGES[idx]
	check("it is one lap in the hypercar", int(st.laps) == 1 and st.car_class == "hypercar" and st.fan_lock)
	check("it is meant for the top fan level", FanLevels.stage_level(idx) == FanLevels.THRESHOLDS.size())
	FanLevels.dev_unlock = false
	check("it is locked below the top fan level", not Campaign.is_unlocked(idx, FanLevels.THRESHOLDS[-1] - 1))
	check("it opens at the top fan level, whatever the stages before", Campaign.is_unlocked(idx, FanLevels.THRESHOLDS[-1]))
	FanLevels.dev_unlock = true
	check("the dev unlock opens it", Campaign.is_unlocked(idx, 0))
	FanLevels.dev_unlock = false
	check("its beacon stands at a map spot", OpenWorld.STAGE_SPOTS.has("goliath"))
	completed = true
	return errors
