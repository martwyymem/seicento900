## Headless: a map read from its snapshot equals the one parsed from the bake, member by member; times both.
extends SceneTree
func _initialize() -> void:
	var dir := "user://snapshot_probe"
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	var t := Time.get_ticks_usec()
	var a := TownMap.new()
	a._load("brzeszcze")
	print("parse+index   %.0f ms" % [(Time.get_ticks_usec() - t) / 1000.0])
	t = Time.get_ticks_usec()
	a._save_snapshot(dir)
	print("save snapshot %.0f ms" % [(Time.get_ticks_usec() - t) / 1000.0])
	for f in DirAccess.get_files_at(dir):
		print("  ", f, " ", FileAccess.get_file_as_bytes(dir.path_join(f)).size() / 1000000, " MB")
	t = Time.get_ticks_usec()
	var b := TownMap.new()
	var ok := b._load_snapshot("brzeszcze", dir)
	print("load snapshot %.0f ms ok=%s" % [(Time.get_ticks_usec() - t) / 1000.0, ok])
	var bad := 0
	for n in a._snapshot_vars():
		var va = a.get(n)
		var vb = b.get(n)
		if typeof(va) != typeof(vb) or var_to_bytes(va) != var_to_bytes(vb):
			print("DIFFERENT: ", n, " ", typeof(va), " ", typeof(vb))
			bad += 1
		if va is Array and (va as Array).is_typed() != (vb as Array).is_typed():
			print("TYPED DIFFERS: ", n)
			bad += 1
	print("differences: ", bad)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	quit()
