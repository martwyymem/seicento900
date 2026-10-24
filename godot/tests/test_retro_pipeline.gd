## Test suite for RetroPipeline and retro_postprocess.gdshader (Pillar 2).
extends RefCounted

const RETRO_PIPELINE := preload("res://scripts/ui/retro_pipeline.gd")

var completed := false

func run() -> Array:
	var errors: Array[String] = []

	var pipeline = RETRO_PIPELINE.new()
	if not pipeline:
		errors.append("Failed to instantiate RetroPipeline")
		completed = true
		return errors

	# 1. Test MODE_NAMES
	var expected_modes: Array[String] = [
		"Modern Clean",
		"PS1 / Retro 90s",
		"NFS Most Wanted (2005)",
		"GTA San Andreas (2004)",
		"NFS Carbon (2006)",
		"Colin McRae Rally 2.0",
		"Forza Horizon 1"
	]
	if pipeline.MODE_NAMES != expected_modes:
		errors.append("MODE_NAMES mismatch. Expected %s, got %s" % [str(expected_modes), str(pipeline.MODE_NAMES)])

	# 2. Test Shader and Material
	if not pipeline.material:
		errors.append("RetroPipeline material should not be null")
	elif not pipeline.material.shader:
		errors.append("RetroPipeline material shader should not be null")
	else:
		var mode_param = pipeline.material.get_shader_parameter("retro_mode")
		if mode_param != 0:
			errors.append("Initial retro_mode parameter should be 0, got %s" % str(mode_param))

	# 2b. The PS1 grid is set in lines (square, integer-sized blocks), not as a fixed stretched resolution
	if pipeline.material and pipeline.material.shader:
		var uniforms: Array = pipeline.material.shader.get_shader_uniform_list().map(func(u): return u.name)
		for u in ["retro_mode", "ps1_lines", "dither_strength"]:
			if not u in uniforms:
				errors.append("retro shader is missing uniform %s (has %s)" % [u, str(uniforms)])

	# 3. Test set_mode across all modes
	for i in range(expected_modes.size()):
		pipeline.set_mode(i)
		if pipeline.current_mode != i:
			errors.append("set_mode(%d) failed to set current_mode (got %d)" % [i, pipeline.current_mode])
		if pipeline.material.get_shader_parameter("retro_mode") != i:
			errors.append("set_mode(%d) failed to update shader parameter (got %s)" % [i, str(pipeline.material.get_shader_parameter("retro_mode"))])
		if pipeline.get_mode_name() != expected_modes[i]:
			errors.append("get_mode_name() returned unexpected name: %s vs %s" % [pipeline.get_mode_name(), expected_modes[i]])

	# 4. Test cycle_mode
	pipeline.set_mode(0)
	for i in range(1, expected_modes.size()):
		var returned_mode: int = pipeline.cycle_mode()
		if returned_mode != i or pipeline.current_mode != i:
			errors.append("cycle_mode() failed at step %d: returned %d, current %d" % [i, returned_mode, pipeline.current_mode])
	# Wrap around
	var wrap_mode: int = pipeline.cycle_mode()
	if wrap_mode != 0 or pipeline.current_mode != 0:
		errors.append("cycle_mode() failed to wrap to 0: returned %d, current %d" % [wrap_mode, pipeline.current_mode])

	# 5. Test apply_to_texture_rect
	var test_rect := TextureRect.new()
	pipeline.apply_to_texture_rect(test_rect)
	if test_rect.material != pipeline.material:
		errors.append("apply_to_texture_rect did not assign pipeline material to TextureRect")
	test_rect.free()

	# 6. Test update_time
	pipeline.update_time(0.5)
	pipeline.update_time(0.25)
	var time_param = pipeline.material.get_shader_parameter("time")
	if not is_equal_approx(float(time_param), 0.75):
		errors.append("update_time did not correctly accumulate time parameter: expected ~0.75, got %s" % str(time_param))

	completed = true
	return errors
