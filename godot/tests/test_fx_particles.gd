## Smoke tests for the shared, bounded race FX helper.
extends RefCounted

const FX := preload("res://scripts/ui/fx_particles.gd")

var completed := false

func run() -> Array:
	var errors: Array[String] = []
	for preset in ["kickup_grass", "kickup_gravel", "kickup_dirt", "kickup_snow", "sparks", "debris", "smoke", "splash", "spray", "exhaust", "backfire", "leaves", "dust_motes", "fog_wisp"]:
		if not FX.PRESETS.has(preset):
			errors.append("missing FX preset %s" % preset)
	var parent := Node3D.new()
	Engine.get_main_loop().root.add_child(parent)
	var continuous: GPUParticles3D = FX.attach(parent, "kickup_gravel", 0, 1.0)
	if continuous == null or continuous.amount != 11 or continuous.process_material == null or continuous.draw_pass_1 == null:
		errors.append("attach did not create a low-quality gravel emitter with shared resources")
	var burst: GPUParticles3D = FX.burst(parent, "sparks", Vector3(1.0, 2.0, 3.0), 7, 3)
	if burst == null or not burst.one_shot or burst.amount != 7 or burst.global_position != Vector3(1.0, 2.0, 3.0):
		errors.append("burst did not create the requested one-shot spark effect")
	var capped: GPUParticles3D = FX.burst(parent, "sparks", Vector3.ZERO, 10000, 0)
	if capped == null or capped.amount > int(FX.PRESETS.sparks.amount * FX.QUALITY_SCALE[0]):
		errors.append("burst particle count exceeded the preset and quality cap")
	if FX.attach(parent, "not_a_preset") != null or FX.burst(parent, "not_a_preset", Vector3.ZERO) != null:
		errors.append("unknown preset should be ignored")
	parent.free()
	completed = true
	return errors
