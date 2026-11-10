## Headless probe: 0-100, top speed, braking from 100 and lateral g of each catalogue car on dry tarmac, in the race physics
## (tests/test_surfaces.gd's PhysRig with the car's model swapped in). godot --headless --path godot -s tests/_car_probe.gd
extends SceneTree

const S := preload("res://tests/test_surfaces.gd")

static func rig_for(cm: CarModel):
	var ids := S.surf_ids()
	var r = S.PhysRig.new(ids.asphalt, 1.0)
	r.model = cm
	r.phys = Physics.new(cm)
	r.env.mass = cm.mass_with_fuel(S.FUEL)
	return r

## {t100, top (km/h after 90 s flat out), brake (m from 100 km/h), lat_g, t_400 (s for 400 m), mass}
static func measure(cm: CarModel) -> Dictionary:
	var m := S.measure(rig_for(cm))
	var r = rig_for(cm)
	r.reset(0.0)
	var t := 0.0
	var dist := 0.0
	var t400 := INF
	while t < 90.0:
		r.step(1.0, 0.0, 0.0)
		t += S.DT
		dist += r.speed() * S.DT
		if t400 == INF and dist >= 400.0:
			t400 = t
	return {"t100": m.t100, "top": r.speed() * 3.6, "brake": m.brake, "lat_g": m.lat_g, "t400": t400, "mass": cm.mass_with_fuel(S.FUEL)}

func _initialize() -> void:
	await process_frame
	var cars := {"stock": CarModel.new(), "golf4": Golf4.model()}
	for k in cars:
		var m := measure(cars[k])
		print("%-8s mass %5.0f kg  0-100 %5.2f s  400 m %5.2f s  top %5.1f km/h  brake100 %5.1f m  lat %4.2f g" % [k, m.mass, m.t100, m.t400, m.top, m.brake, m.lat_g])
	quit()
