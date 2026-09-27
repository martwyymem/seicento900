## One-off conversion of the JS TRACK_CONFIG into data/tracks/<key>.tres. After this the .tres files are the
## source of truth; re-running overwrites them.
##   node -e "..." > /tmp/track_config.json   (see README)
##   godot --headless --path godot -s tools/import_track_config.gd -- /tmp/track_config.json
extends SceneTree

func _init() -> void:
	var path: String = OS.get_cmdline_user_args()[0]
	var cfgs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	for key in cfgs:
		var c: Dictionary = cfgs[key]
		var t := TrackDef.new()
		t.key = key
		t.display_name = c.name
		t.short_name = c.short
		t.width = c.width
		t.start_offset = c.startOffset
		t.pit_entry = c.pitEntry
		t.pit_exit = c.pitExit
		t.pit_ramp = c.pitRamp
		t.pit_offset = c.pitOffset
		t.box_start = c.boxStart
		t.box_spacing = c.boxSpacing
		t.runoff = c.runoff
		t.runoff_color = Color(c.runoffColor)
		t.runoff_surface = c.runoffSurface
		t.barrier = c.barrier
		t.theme = c.theme
		t.tree_density = c.trees.density
		t.tree_patch = c.trees.patch
		t.tree_conifer = c.trees.conifer
		t.terrain_fine = c.terrainFine
		t.grandstands = c.grandstands
		t.stands = Vector2(c.stands[0], c.stands[1])
		t.stand_tiers = int(c.standTiers)
		t.sea = c.get("sea", false)
		t.osm_names = c.osmNames
		for cn in c.corners:
			var n := CornerName.new()
			n.distance = cn[0]
			n.name = cn[1]
			t.corners.append(n)
		var err := ResourceSaver.save(t, "res://data/tracks/%s.tres" % key)
		print("%s: %s" % [key, "saved" if err == OK else "error %d" % err])
	quit()
