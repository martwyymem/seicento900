## Headless: the raised junction pads (TownMap.raised_pads) and how many have no raised end at their node (mid-road,
## TownMap.pad_mounds), the drawn mounds against the car's support, and the step where each cone meets its road's side
## slopes (test_open_world_ramps.gd's _cones prints the numbers). godot --headless --path godot -s tests/_junction_pad_probe.gd
extends SceneTree

func _init() -> void:
	var map := TownMap.load_map("brzeszcze")
	var mounds := map.pad_mounds()
	print("raised pads %d, at a raised end %d, mid-road %d" % [map.raised_pads().size(), map.raised_pads().size() - mounds.size(), mounds.size()])
	for m: Dictionary in mounds:
		print("  mid-road pad at (%.1f, %.1f), deck %.2f m, road %d" % [m.c.x, m.c.y, m.deck, m.road])
	var t = load("res://tests/test_open_world_ramps.gd").new()
	var errors: Array[String] = []
	t._cones(map, errors)
	for e in errors:
		print("  ", e)
	quit()
