## Dev probe: how many jump, narrows and crest calls each rally stage (its span) and street track gets.
## godot --headless --path godot -s tests/_jump_narrow_probe.gd
extends SceneTree
func _initialize() -> void:
	var seen := {}
	print("== rally stages (jump / narrows / crest calls in the stage's span; L m)")
	for ev in Rally.EVENTS:
		for sd in ev.stages:
			var key: String = sd.track
			var tr: Track = Race.get_track(key)
			var pn := PaceNotes.new(tr)
			var sp := Rally.span(sd)
			var length := (sp.y if sp.y > sp.x else sp.y + tr.L) - sp.x
			var counts := _count(pn, tr, sp.x, length)
			print("  %-18s %-16s %5.0f m  jump %2d  narrows %2d  crest %2d" % [sd.name, key, length, counts.jump, counts.narrows, counts.crest])
			seen[key] = true
	print("== street tracks (whole lap)")
	for f in DirAccess.get_files_at("res://data/tracks"):
		if not f.ends_with(".tres"):
			continue
		var key := f.get_basename()
		var def: TrackDef = load("res://data/tracks/" + f)
		if not def.street_stage:
			continue
		var tr: Track = Race.get_track(key)
		var counts := _count(PaceNotes.new(tr), tr, 0.0, tr.L)
		print("  %-18s %-16s %5.0f m  jump %2d  narrows %2d  crest %2d" % [def.display_name, key, tr.L, counts.jump, counts.narrows, counts.crest])
	quit()

func _count(pn: PaceNotes, tr: Track, from: float, length: float) -> Dictionary:
	var c := {"jump": 0, "narrows": 0, "crest": 0}
	for nt in pn.notes:
		if nt.dir != 0:
			continue
		var d := tr.rel(float(nt.s) - from)
		if d < 0.0 or d > length:
			continue
		c[nt.grade] = int(c.get(nt.grade, 0)) + 1
	return c
