## The racing line's braking zones come from the player's own car (user, 2026-11-22: "make the AI brake markers
## visible on track"): in the stock Seicento the stock reference lap paints them (RaceWorld.racing_line_speeds is
## empty), in the hypercar its own speeds do, so the red starts where a hypercar has to brake: from far higher
## speeds and so further before the corner than the stock line's.
extends RefCounted

const WORLD := preload("res://scripts/ui/race_world.gd")

var completed := false
var errors: Array[String] = []

func check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		errors.append("%s %s" % [what, detail])

func _race(cls: String) -> Race:
	var rs := RaceSettings.new()
	rs.track = "gp"
	rs.laps = 1
	rs.opponents = 1
	rs.car_class = cls
	rs.race_control = false
	var cm: CarModel = Hypercar.model() if cls == "hypercar" else CarModel.new()
	return Race.new(rs, {"stints": [{"c": "M", "laps": 1}]}, 7, {"car_model": cm, "tyres": Tyres.new(), "strategy": Strategy.new(cm, Tyres.new())})

## Metres before the slowest point of the lap that the speeds start falling at more than 0.35 g (the line's red).
static func _brake_lead(t: Track, vs: PackedFloat64Array) -> float:
	var lo := 0
	for i in t.n:
		if vs[i] < vs[lo]:
			lo = i
	var lead := 0.0
	var i := (lo - 1 + t.n) % t.n
	while lead < 2000.0:
		var j := (i + 1) % t.n
		var decel := (vs[i] * vs[i] - vs[j] * vs[j]) / (2.0 * maxf(t.RDS[i], 0.01))
		if decel < 0.35 * 9.81 and lead > 5.0:
			break
		lead += t.RDS[i]
		i = (i - 1 + t.n) % t.n
	return lead

func run() -> Array:
	var stock := _race("stock")
	check("the stock car keeps the stock reference colours", WORLD.racing_line_speeds(stock.track, stock).is_empty())
	var stock_vs: PackedFloat64Array = stock.track.cal.get("vs", stock.track.PROF)
	var stock_lead := _brake_lead(stock.track, stock_vs)
	stock.dispose()
	var hyper := _race("hypercar")
	var vs := WORLD.racing_line_speeds(hyper.track, hyper)
	check("the hypercar paints its own speeds", vs.size() == hyper.track.n, str(vs.size()))
	if vs.size() == hyper.track.n:
		var top := 0.0
		for v in vs:
			top = maxf(top, v)
		check("the hypercar's speeds are a hypercar's (above 60 m/s somewhere)", top > 60.0, "(%.1f m/s)" % top)
		var lead := _brake_lead(hyper.track, vs)
		check("its braking zone into the slowest corner starts earlier than the stock car's", lead > stock_lead + 20.0,
			"(hypercar %.0f m, stock %.0f m)" % [lead, stock_lead])
		print("  racing line braking lead into the slowest corner: stock %.0f m, hypercar %.0f m" % [stock_lead, lead])
	hyper.dispose()
	completed = true
	return errors
