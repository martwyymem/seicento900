## Dev probe: prints each circuit's pace notes. TRACKS=monza,spa godot --headless --path godot -s tests/_notes_probe.gd
extends SceneTree
func _initialize() -> void:
	var keys := OS.get_environment("TRACKS").split(",") if OS.get_environment("TRACKS") != "" else PackedStringArray(["monza", "monaco", "spa", "fiat"])
	for key in keys:
		var tr: Track = Race.get_track(key)
		var pn := PaceNotes.new(tr)
		print("== %s  L=%.0f  notes=%d" % [key, tr.L, pn.notes.size()])
		for nt in pn.notes:
			print("  %6.0f-%6.0f R=%5.0f turn=%4.0f°  %-40s  [%s]" % [nt.s, nt.e, nt.radius, rad_to_deg(nt.turn), PaceNotes.spoken(nt), tr.sector_name(nt.apex)])
	quit()
