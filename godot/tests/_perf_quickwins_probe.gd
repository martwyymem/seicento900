## Headless µs probe for the per-frame quick wins:  godot --headless --path godot -s tests/_perf_quickwins_probe.gd
extends SceneTree
func _initialize() -> void:
	await process_frame
	var host := Control.new(); host.size = Vector2(1600, 900); root.add_child(host)
	var hud := OpenWorldHud.new(); host.add_child(hud)
	hud.set_stats(5000, 10, 100, 9.5, "RAIN")
	var n := 2000
	var t := Time.get_ticks_usec()
	for i in n: hud._stats_key = ""; hud.set_stats(5000, 10, 100, 9.5, "RAIN")  # old behaviour: full work each call
	print("set_stats full work: %.1f us/call" % ((Time.get_ticks_usec() - t) / float(n)))
	t = Time.get_ticks_usec()
	for i in n: hud.set_stats(5000, 10, 100, 9.5, "RAIN")
	print("set_stats cached:    %.2f us/call" % ((Time.get_ticks_usec() - t) / float(n)))
	# beacon label lookup
	var node := Node3D.new(); var l := Label3D.new(); l.name = "Label"; node.add_child(l); node.set_meta("label_ref", l)
	t = Time.get_ticks_usec()
	for i in n: var x: Node = node.get_node_or_null("Label")
	print("get_node_or_null:    %.2f us" % ((Time.get_ticks_usec() - t) / float(n)))
	t = Time.get_ticks_usec()
	for i in n: var x: Variant = node.get_meta("label_ref", null)
	print("get_meta:            %.2f us" % ((Time.get_ticks_usec() - t) / float(n)))
	# string size
	var f := hud.area_label.get_theme_font("font")
	t = Time.get_ticks_usec()
	for i in n: var w := f.get_string_size("OSIEDLE PADEREWSKIEGO", HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	print("get_string_size:     %.2f us (cached path: ~0.1)" % ((Time.get_ticks_usec() - t) / float(n)))
	# fireworks write
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true; mm.mesh = BoxMesh.new(); mm.instance_count = 168
	var c := Color(1, 0.5, 0.2, 0.8); var b := Basis.IDENTITY; var p := Vector3(1, 2, 3)
	t = Time.get_ticks_usec()
	for k in 200:
		for idx in 168:
			mm.set_instance_transform(idx, Transform3D(b, p)); mm.set_instance_color(idx, c)
	print("fireworks old write: %.1f us/frame" % ((Time.get_ticks_usec() - t) / 200.0))
	var buf := PackedFloat32Array(); buf.resize(168 * 16)
	t = Time.get_ticks_usec()
	for k in 200:
		for idx in 168:
			var o := idx * 16
			buf[o] = b.x.x; buf[o + 1] = b.y.x; buf[o + 2] = b.z.x; buf[o + 3] = p.x
			buf[o + 4] = b.x.y; buf[o + 5] = b.y.y; buf[o + 6] = b.z.y; buf[o + 7] = p.y
			buf[o + 8] = b.x.z; buf[o + 9] = b.y.z; buf[o + 10] = b.z.z; buf[o + 11] = p.z
			buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = c.a
		mm.buffer = buf
	print("fireworks new write: %.1f us/frame" % ((Time.get_ticks_usec() - t) / 200.0))
	quit()
