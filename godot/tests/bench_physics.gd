## Timing: godot --headless --path godot -s tests/bench_physics.gd
extends SceneTree

func _init() -> void:
	var phys := Physics.new(CarModel.new())
	var cars := []
	for i in 16:
		var c := RaceCar.new()
		c.vx = 20.0 + i
		c.gear = 2
		cars.append(c)
	var env := Physics.Env.new()
	env.mass = 870.0
	env.surface = func(_x, _y): return 0
	var inp := Physics.Controls.new()
	inp.throttle = 0.7
	inp.steer = 0.2
	var t0 := Time.get_ticks_usec()
	var ticks := 120
	for t in ticks:
		for c in cars:
			phys.step(c, inp, env, 1.0 / 120.0)
	var us := Time.get_ticks_usec() - t0
	print("16 cars x %d ticks: %.1f ms  (%.1f us per car-tick, %.0f%% of one core in real time)" % [ticks, us / 1000.0, float(us) / (16 * ticks), us / 1e6 * 100.0 * 120.0 / ticks])
	quit()
