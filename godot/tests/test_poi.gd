## The open world's points of interest (scripts/world/poi.gd): the list built from the real Brzeszcze map (9 speed
## traps, the merged landmarks), unknown / known / discovered states, the save round trip and an old save without the
## new keys, the marker dictionaries and info lines, the satnav's culling and limit, the progress summary, the GPS
## route to a point, the banners (one per event, a repeat doesn't stack) and the street name's readability.
extends RefCounted

var completed := false
const SMALL_CANVAS := Vector2(1231, 692)

func run() -> Array:
	var errors: Array[String] = []
	var map := TownMap.load_map(OpenWorld.MAP_KEY)
	if map == null:
		errors.append("data/world/%s.json did not load" % OpenWorld.MAP_KEY)
		completed = true
		return errors
	var tree := Engine.get_main_loop() as SceneTree
	var traps := Poi.find_traps(map)
	var list := Poi.build(map, traps)
	_list(map, traps, list, errors)
	_states(list, errors)
	_save(list, errors)
	_markers(list, errors)
	_minimap(list, errors)
	_text_fits(list, errors)
	await _world(map, list, errors, tree)
	await _hud(list, errors, tree)
	completed = true
	return errors

# ------------------------------------------------------------------------------------------ the list

func _list(map: TownMap, traps: Array, list: Array[Poi], errors: Array[String]) -> void:
	if traps.size() != Poi.TRAP_COUNT:
		errors.append("%d speed traps, expected %d" % [traps.size(), Poi.TRAP_COUNT])
	var ids := {}
	var n_traps := 0
	var n_land := 0
	for p in list:
		if ids.has(p.id):
			errors.append("two points share the id '%s'" % p.id)
		ids[p.id] = true
		if p.name == "":
			errors.append("a %s has no name (%s)" % [p.kind, p.id])
		if map.play.size() > 2 and not Geometry2D.is_point_in_polygon(p.pos, map.play):
			errors.append("%s '%s' stands outside the playable area" % [p.kind, p.name])
		if p.kind == Poi.TRAP:
			n_traps += 1
			if p.dir.length() < 0.99:
				errors.append("trap '%s' has no road direction" % p.name)
		else:
			n_land += 1
			if p.sub == "":
				errors.append("landmark '%s' has no kind of place" % p.name)
	if n_traps != Poi.TRAP_COUNT:
		errors.append("%d trap points in the list" % n_traps)
	if n_land < 12 or n_land > 30:
		errors.append("%d landmarks: the merge or the filter is off" % n_land)
	for i in traps.size():
		for j in range(i + 1, traps.size()):
			if (traps[i].pos as Vector2).distance_to(traps[j].pos) < Poi.TRAP_SPACING:
				errors.append("traps %d and %d are closer than %d m" % [i, j, Poi.TRAP_SPACING])
	# no two landmarks within the merge radius (a churchyard is one landmark)
	for i in list.size():
		for j in range(i + 1, list.size()):
			if list[i].kind == Poi.LANDMARK and list[j].kind == Poi.LANDMARK and list[i].pos.distance_to(list[j].pos) <= Poi.MERGE_RADIUS:
				errors.append("landmarks '%s' and '%s' are %.0f m apart and were not merged" % [list[i].name, list[j].name, list[i].pos.distance_to(list[j].pos)])
	# the same map gives the same list
	var again := Poi.build(map, Poi.find_traps(map))
	if again.size() != list.size():
		errors.append("building twice gives %d then %d points" % [list.size(), again.size()])
	else:
		for i in list.size():
			if again[i].id != list[i].id or again[i].pos != list[i].pos:
				errors.append("point %d differs between two builds: %s / %s" % [i, list[i].id, again[i].id])
	# the landmark kinds are the ones the world has always discovered
	var a := Poi.LANDMARK_LABELS.keys()
	var b := OpenWorld.DISCOVER_KINDS.duplicate()
	a.sort()
	b.sort()
	if a != b:
		errors.append("Poi.LANDMARK_LABELS %s differs from OpenWorld.DISCOVER_KINDS %s" % [a, b])
	# the old name-keyed save: a bare name is still the key of a landmark whose name is unique
	var named := list.filter(func(p: Poi) -> bool: return p.kind == Poi.LANDMARK and p.id == p.name)
	if named.size() < 8:
		errors.append("only %d landmarks are keyed by their bare name" % named.size())

# ------------------------------------------------------------------------------------------ states

func _first(list: Array[Poi], kind: String) -> Poi:
	for p in list:
		if p.kind == kind:
			return p
	return null

func _states(list: Array[Poi], errors: Array[String]) -> void:
	var prog := WorldProgress.new()
	var trap := _first(list, Poi.TRAP)
	var land := _first(list, Poi.LANDMARK)
	if trap.state(prog) != Poi.State.KNOWN:
		errors.append("a trap not driven is KNOWN from the start (it is signed in the world)")
	if land.state(prog) != Poi.State.UNKNOWN:
		errors.append("a landmark not found is UNKNOWN")
	var c := Poi.counts(list, prog)
	if c[Poi.TRAP][0] != 0 or c[Poi.TRAP][1] != Poi.TRAP_COUNT or c[Poi.LANDMARK][0] != 0:
		errors.append("fresh counts: %s" % [c])
	# driving a trap: discovered, the best kept, a slower run does not lower it
	if not trap.record_run(prog, 87.4):
		errors.append("the first run is a new best")
	if trap.state(prog) != Poi.State.DISCOVERED or absf(trap.best_kmh(prog) - 87.4) > 0.01:
		errors.append("trap after a run: state %d best %s" % [trap.state(prog), trap.best_kmh(prog)])
	if trap.record_run(prog, 60.0) or absf(trap.best_kmh(prog) - 87.4) > 0.01:
		errors.append("a slower run replaced the best: %s" % trap.best_kmh(prog))
	if not trap.record_run(prog, 104.0) or int(trap.best_kmh(prog)) != 104:
		errors.append("a faster run is a new best")
	for kmh in [79.9, 80.0, 99.9, 100.0, 119.9, 120.0, 200.0]:
		var want: int = [0, 1, 1, 2, 2, 3, 3][[79.9, 80.0, 99.9, 100.0, 119.9, 120.0, 200.0].find(kmh)]
		if Poi.stars(kmh) != want:
			errors.append("%s km/h is %d stars, expected %d" % [kmh, Poi.stars(kmh), want])
	if Poi.star_text(2) != "★★☆" or Poi.star_text(0) != "☆☆☆" or Poi.star_text(9) != "★★★":
		errors.append("star text: %s %s %s" % [Poi.star_text(2), Poi.star_text(0), Poi.star_text(9)])
	# finding a landmark: nothing at 200 m, found at 50 m, once only
	var before := prog.landmarks.size()
	var found := Poi.discover_near(list, prog, land.pos + Vector2(Poi.DISCOVER_RADIUS + 5.0, 0))
	for p in found:
		if p != land and p.pos.distance_to(land.pos + Vector2(Poi.DISCOVER_RADIUS + 5.0, 0)) >= Poi.DISCOVER_RADIUS:
			errors.append("'%s' was found from beyond the discovery radius" % p.name)
	if land in found:
		errors.append("'%s' found from %d m, past the radius" % [land.name, Poi.DISCOVER_RADIUS + 5.0])
	found = Poi.discover_near(list, prog, land.pos + Vector2(50, 0))
	if not land in found or land.state(prog) != Poi.State.DISCOVERED:
		errors.append("'%s' is not found from 50 m: %s" % [land.name, found.map(func(p): return p.name)])
	if not Poi.discover_near(list, prog, land.pos + Vector2(50, 0)).is_empty():
		errors.append("a landmark is found twice")
	if prog.landmarks.size() <= before:
		errors.append("the find is not in the save's landmarks")
	var c2 := Poi.counts(list, prog)
	if c2[Poi.TRAP][0] != 1 or c2[Poi.LANDMARK][0] < 1:
		errors.append("counts after a trap and a landmark: %s" % [c2])
	if Poi.summary(list, prog, 212, 1830) != "Speed traps 1/%d · Landmarks %d/%d · Roads 212/1830" % [Poi.TRAP_COUNT, c2[Poi.LANDMARK][0], c2[Poi.LANDMARK][1]]:
		errors.append("summary: %s" % Poi.summary(list, prog, 212, 1830))
	# the explanation of a kind comes once
	var tip := Poi.take_intro(prog, Poi.TRAP)
	if tip == "" or Poi.take_intro(prog, Poi.TRAP) != "":
		errors.append("the first-time speed trap tip comes once")
	if Poi.take_intro(prog, Poi.LANDMARK) == "":
		errors.append("the landmark tip is separate from the trap tip")

# ------------------------------------------------------------------------------------------ the save

func _save(list: Array[Poi], errors: Array[String]) -> void:
	var prog := WorldProgress.new()
	prog.pos = Vector2(123.4, -567.8)
	prog.heading = 1.5
	prog.has_pos = true
	prog.fans = 4321
	prog.roads = {3: true, 9: true}
	var trap := _first(list, Poi.TRAP)
	var land := _first(list, Poi.LANDMARK)
	trap.record_run(prog, 111.1)
	prog.landmarks[land.id] = true
	Poi.take_intro(prog, Poi.TRAP)
	var back := WorldProgress.from_dict(JSON.parse_string(JSON.stringify(prog.to_dict())))
	if JSON.stringify(back.to_dict()) != JSON.stringify(prog.to_dict()):
		errors.append("a save does not survive JSON: %s vs %s" % [back.to_dict(), prog.to_dict()])
	if not back.tips.has(Poi.TRAP) or back.tips.has(Poi.LANDMARK):
		errors.append("tips after a round trip: %s" % [back.tips])
	if trap.state(back) != Poi.State.DISCOVERED or land.state(back) != Poi.State.DISCOVERED:
		errors.append("what was found is not found after loading")
	# an old save without the new keys (and with the old name-keyed landmarks) loads
	var named: Poi = null
	for p in list:
		if p.kind == Poi.LANDMARK and p.id == p.name:
			named = p
			break
	var old := WorldProgress.from_dict({"pos": [1.0, 2.0, 0.5], "hour": 9.0, "roads": [1, 2], "landmarks": [named.name], "traps": {"trap_1_2": 99.0}, "fans": 5})
	if not old.tips.is_empty() or old.fans != 5 or old.traps.size() != 1 or old.roads.size() != 2:
		errors.append("an old save loads wrong: tips %s fans %d" % [old.tips, old.fans])
	if named.state(old) != Poi.State.DISCOVERED:
		errors.append("a landmark found in an old save (keyed by name) is lost: '%s'" % named.name)
	if not WorldProgress.from_dict(null).landmarks.is_empty() or not WorldProgress.from_dict("junk").traps.is_empty():
		errors.append("an unreadable save gives a fresh progress")
	# the file itself: written and read back at once, then the previous file restored (the sandbox is shared)
	var path := SaveData.path(WorldProgress.SAVE_FILE)
	var previous := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	prog.save()
	var from_disk := WorldProgress.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
	if JSON.stringify(from_disk.to_dict()) != JSON.stringify(prog.to_dict()):
		errors.append("the saved file reads back differently")
	if previous != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(previous)
	else:
		DirAccess.remove_absolute(path)

# ------------------------------------------------------------------------------------------ markers

func _markers(list: Array[Poi], errors: Array[String]) -> void:
	var prog := WorldProgress.new()
	var trap := _first(list, Poi.TRAP)
	var land := _first(list, Poi.LANDMARK)
	var m := land.marker(prog)
	if not m.unknown or m.kind != "poi" or m.poi != Poi.LANDMARK or m.id != land.id or m.pos != land.pos:
		errors.append("unknown landmark marker: %s" % [m])
	if m.color != Poi.UNKNOWN_COLOR or m.label != "" or not String(m.info).begins_with("UNDISCOVERED · drive there to find out what it is"):
		errors.append("an unknown landmark shows nothing of what it is: %s / '%s' / '%s'" % [m.color, m.label, m.info])
	if land.name in String(m.info) or land.sub in String(m.info):
		errors.append("an unknown landmark's info gives its name away: %s" % m.info)
	prog.landmarks[land.id] = true
	m = land.marker(prog)
	if m.unknown or m.color != Poi.KINDS[Poi.LANDMARK].color or m.label != land.name or m.shape != "square":
		errors.append("discovered landmark marker: %s" % [m])
	if not String(m.info).begins_with("LANDMARK · %s" % land.name):
		errors.append("discovered landmark info: %s" % m.info)
	var t := trap.marker(prog)
	if t.unknown or t.color != Poi.KINDS[Poi.TRAP].color or t.shape != "diamond" or t.state != Poi.State.KNOWN or t.label != "Speed trap":
		errors.append("an undriven trap shows as a trap: %s" % [t])
	if not "not driven yet" in String(t.info) or not String(t.info).begins_with("SPEED TRAP · %s · drive through as fast as you can" % trap.name):
		errors.append("undriven trap info: %s" % t.info)
	trap.record_run(prog, 104.2)
	t = trap.marker(prog)
	var want := "SPEED TRAP · %s · drive through as fast as you can · best 104 km/h ★★☆ (120 km/h for ★★★)" % trap.name
	if t.info != want:
		errors.append("trap info '%s', expected '%s'" % [t.info, want])
	if t.label != "104 km/h ★★☆" or t.state != Poi.State.DISCOVERED:
		errors.append("driven trap marker: %s" % [t])
	trap.record_run(prog, 133.0)
	if "(" in trap.info(prog) or not trap.info(prog).ends_with("best 133 km/h ★★★"):
		errors.append("a three-star trap offers no next star: %s" % trap.info(prog))
	trap.record_run(prog, 139.0)
	var routed := Poi.markers(list, prog, trap.id)
	var n_routed := routed.filter(func(x): return x.routed).size()
	if routed.size() != list.size() or n_routed != 1 or not routed[list.find(trap)].routed:
		errors.append("exactly the routed point is marked routed (%d)" % n_routed)
	if Poi.markers(list, prog).any(func(x): return x.routed):
		errors.append("nothing is routed without an id")

# ------------------------------------------------------------------------------------------ the satnav

func _minimap(list: Array[Poi], errors: Array[String]) -> void:
	var prog := WorldProgress.new()
	var car := Vector2(100, 100)
	var ms := [{"pos": car + Vector2(10, 0), "color": Color.ORANGE, "label": "1. stage"}, {"pos": car, "kind": "waypoint", "label": "WAYPOINT"}]
	# 12 points around the car at 20..240 m, one far away
	for i in 12:
		var p := Poi.new()
		p.kind = Poi.LANDMARK
		p.id = "p%d" % i
		p.name = "p%d" % i
		p.pos = car + Vector2(20.0 + 20.0 * i, 0).rotated(i)
		ms.append(p.marker(prog))
	var far := Poi.new()
	far.kind = Poi.TRAP
	far.id = "far"
	far.pos = car + Vector2(5000, 0)
	ms.append(far.marker(prog))
	var shown := Poi.minimap_pois(ms, car, 250.0)
	if shown.size() != 8:
		errors.append("the satnav shows %d points, expected the limit of 8" % shown.size())
	for m in shown:
		if m.kind != "poi":
			errors.append("a stage or waypoint marker came through the point filter")
		if (m.pos as Vector2).distance_to(car) > 250.0 * 0.9 + 0.01:
			errors.append("a point %.0f m away is on a 250 m disc" % (m.pos as Vector2).distance_to(car))
	for i in range(1, shown.size()):
		if (shown[i].pos as Vector2).distance_to(car) < (shown[i - 1].pos as Vector2).distance_to(car):
			errors.append("the satnav's points are not nearest first")
	if Poi.minimap_pois(ms, car, 250.0, 100).size() != 11: # 20..220 within 225 m
		errors.append("with no limit %d points are inside the disc (expected 11)" % Poi.minimap_pois(ms, car, 250.0, 100).size())
	if not Poi.minimap_pois(ms, car + Vector2(9000, 9000), 250.0).is_empty():
		errors.append("far from every point, the satnav shows none")
	if not Poi.minimap_pois([], car, 250.0).is_empty():
		errors.append("no markers, no points")

# ------------------------------------------------------------------------------------------ text fits

func _text_fits(list: Array[Poi], errors: Array[String]) -> void:
	var font := CmrStyle.font(800)
	var width := SMALL_CANVAS.x - 80.0
	var longest := 0.0
	for best in [0.0, 70.0, 85.0, 105.0, 130.0]:
		for found in [false, true]:
			var prog := WorldProgress.new()
			for p in list:
				if p.kind == Poi.TRAP and best > 0.0:
					p.record_run(prog, best)
				if p.kind == Poi.LANDMARK and found:
					prog.landmarks[p.id] = true
				var lines := font.get_multiline_string_size(p.info(prog), HORIZONTAL_ALIGNMENT_LEFT, width, 18).y / font.get_height(18)
				longest = maxf(longest, lines)
				if lines > 2.01:
					errors.append("the info of '%s' needs %.0f lines at %d px: %s" % [p.name, lines, width, p.info(prog)])
	# the progress line and the key side by side
	var prog := WorldProgress.new()
	var s := Poi.summary(list, prog, 1830, 1830)
	var w := 40.0 + font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 36.0 + OpenWorldHud.legend_width()
	if w > SMALL_CANVAS.x - 40.0:
		errors.append("the map's progress line and key need %.0f px of %d" % [w, SMALL_CANVAS.x])

# ------------------------------------------------------------------------------------------ the world

func _banners(hud: OpenWorldHud, prefix: String) -> int:
	var n := 0
	for b in hud.banners.get_children():
		var head := (b.get_child(0).get_child(0) as Label).text
		if head.begins_with(prefix) and not b.is_queued_for_deletion():
			n += 1
	return n

func _world(map: TownMap, list: Array[Poi], errors: Array[String], tree: SceneTree) -> void:
	var ow := OpenWorld.new()
	ow.size = Vector2(1600, 900)
	tree.root.add_child(ow)
	await tree.process_frame
	ow.map = map
	ow.progress = WorldProgress.new()
	ow.world = Node3D.new()
	ow.route_mesh = MeshInstance3D.new()
	ow.drive = FreeCar.new(map)
	ow._build_traps()
	if ow.traps.size() != Poi.TRAP_COUNT or ow.pois.size() != list.size():
		errors.append("OpenWorld._build_traps: %d traps, %d points (expected %d, %d)" % [ow.traps.size(), ow.pois.size(), Poi.TRAP_COUNT, list.size()])
		ow.free()
		return
	ow._update_markers()
	var hud := ow.hud
	if hud.markers.size() != list.size():
		errors.append("the HUD has %d markers for %d points (no events, no waypoint)" % [hud.markers.size(), list.size()])
	if "Speed traps 0/9" not in hud.summary:
		errors.append("the map's summary line: '%s'" % hud.summary)
	# a landmark found: one DISCOVERED banner, with the first-time tip; a second look adds none
	var land := _first(list, Poi.LANDMARK)
	ow.drive.place(land.pos + Vector2(30, 0), 0.0)
	ow._check_discovery()
	if _banners(hud, "DISCOVERED") != 1:
		errors.append("finding a landmark gives %d DISCOVERED banners" % _banners(hud, "DISCOVERED"))
	var sub := ((hud.banners.get_child(0).get_child(0) as Control).get_child(1) as Label).text
	if land.name not in sub or Poi.KINDS[Poi.LANDMARK].intro not in sub or "/" not in sub:
		errors.append("the discovery banner does not say what, how many and what landmarks are: '%s'" % sub)
	ow._check_discovery()
	if _banners(hud, "DISCOVERED") != 1:
		errors.append("a second look at the same landmark added a banner")
	var mk: Dictionary = hud.markers.filter(func(m): return m.get("id", "") == land.id)[0]
	if mk.unknown or mk.label != land.name:
		errors.append("the map still shows the found landmark as unknown: %s" % [mk])
	if "Landmarks 1/" not in hud.summary:
		errors.append("the summary didn't move after a find: '%s'" % hud.summary)
	# a trap driven: one banner, explaining traps the first time only
	for b in hud.banners.get_children():
		b.free()
	var t: Dictionary = ow.traps[0]
	ow._trap_driven(t, 104.0)
	ow._trap_driven(t, 90.0)
	if _banners(hud, "SPEED TRAP") != 2:
		errors.append("two runs give %d speed trap banners" % _banners(hud, "SPEED TRAP"))
	var subs := []
	for b in hud.banners.get_children():
		if (b.get_child(0).get_child(0) as Label).text.begins_with("SPEED TRAP") and not b.is_queued_for_deletion():
			subs.append(((b.get_child(0) as Control).get_child(1) as Label).text)
	if subs.size() == 2 and (Poi.KINDS[Poi.TRAP].intro not in subs[0] or Poi.KINDS[Poi.TRAP].intro in subs[1]):
		errors.append("the trap explanation is in the first banner only: %s" % [subs])
	if absf(float(ow.progress.traps[t.id]) - 104.0) > 0.1:
		errors.append("the best through the trap is %s, expected 104" % ow.progress.traps[t.id])
	# the GPS route to a point: the waypoint machinery carries it
	var p := _first(list, Poi.TRAP)
	ow.drive.place(Vector2(map.spots.festival[0], map.spots.festival[1]), 0.0)
	ow._route_to_poi(p)
	if ow.wp_poi != p.id or not ow.wp_on or not ow.gps_waypoint or not ow._has_target() or ow._target_pos() != p.pos:
		errors.append("the route to a point: wp_poi '%s' on %s gps %s target %s" % [ow.wp_poi, ow.wp_on, ow.gps_waypoint, ow._target_pos()])
	if ow.route.size() < 2:
		errors.append("no route to the point (%d nodes)" % ow.route.size())
	var routed := hud.markers.filter(func(m): return m.get("routed", false))
	if routed.size() != 1 or routed[0].id != p.id:
		errors.append("the routed point is highlighted on the map: %s" % [routed])
	if hud.markers.any(func(m): return m.get("kind", "") == "waypoint"):
		errors.append("a route to a point also drops a WAYPOINT pin")
	# arrival clears it
	ow.drive.place(p.pos, 0.0)
	ow._check_waypoint_reached()
	if ow.wp_poi != "" or ow.wp_on or ow.gps_waypoint:
		errors.append("arriving at the point leaves the route: wp_poi '%s'" % ow.wp_poi)
	# the player's own waypoint replaces a route to a point
	ow._route_to_poi(p)
	ow._set_waypoint(p.pos + Vector2(40, 40))
	if ow.wp_poi != "" or not hud.markers.any(func(m): return m.get("kind", "") == "waypoint"):
		errors.append("a placed waypoint should replace the route to a point")
	if hud.markers.any(func(m): return m.get("routed", false)):
		errors.append("no point stays highlighted after a placed waypoint")
	ow.free()

# ------------------------------------------------------------------------------------------ the HUD

func _hud(list: Array[Poi], errors: Array[String], tree: SceneTree) -> void:
	var host := Control.new()
	host.size = SMALL_CANVAS
	tree.root.add_child(host)
	var hud := OpenWorldHud.new()
	hud.size = SMALL_CANVAS
	host.add_child(hud)
	await tree.process_frame
	# the same banner twice is one banner; another text is another
	hud.notify("BACK ON THE ROAD", "")
	hud.notify("BACK ON THE ROAD", "")
	if hud.banners.get_child_count() != 1:
		errors.append("the same banner twice stacks %d" % hud.banners.get_child_count())
	hud.notify("BACK ON THE ROAD", "The Seicento doesn't swim")
	hud.notify("ROUTE SET", "x")
	if hud.banners.get_child_count() != 3:
		errors.append("different banners should stack: %d" % hud.banners.get_child_count())
	# the street name stays readable: no fade to 10%, a plate under it
	hud.set_street("ul. Dworcowa")
	for k in 600:
		hud.update_drive(40.0, 2, 3000.0, 6500.0, Vector2.ZERO, 0.0, 1.0 / 60.0)
	if hud.street_label.modulate.a < 0.6:
		errors.append("the street name fades to %.2f after ten seconds" % hud.street_label.modulate.a)
	hud._layout()
	if not hud.street_plate.visible or hud.street_plate.modulate.a < 0.6:
		errors.append("the street name has no plate")
	var text_w := hud.street_label.get_theme_font("font").get_string_size(hud.street_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, hud.street_label.get_theme_font_size("font_size")).x
	if hud.street_plate.offset_right - hud.street_plate.offset_left < text_w + 20.0:
		errors.append("the street plate (%.0f px) is narrower than the text (%.0f px)" % [hud.street_plate.offset_right - hud.street_plate.offset_left, text_w])
	if hud.street_plate.offset_top > hud.street_label.offset_top or hud.street_plate.offset_bottom < hud.street_label.offset_bottom:
		errors.append("the street plate doesn't cover the text's line")
	# every kind of marker draws on the satnav and the big map without errors
	var prog := WorldProgress.new()
	prog.landmarks[_first(list, Poi.LANDMARK).id] = true
	_first(list, Poi.TRAP).record_run(prog, 95.0)
	var ms := [{"pos": Vector2(50, 0), "color": Color.ORANGE, "label": "1. Fiat", "info": "stage"}]
	ms.append_array(Poi.markers(list, prog, list[0].id))
	hud.set_markers(ms)
	hud.set_summary(Poi.summary(list, prog, 12, 1830))
	hud.car_pos = list[0].pos + Vector2(30, 0)
	hud.overlay.size = Vector2(250, 250)
	hud.overlay.set_meta("radius", 250.0)
	hud.big_overlay.size = SMALL_CANVAS
	hud.map = TownMap.new()
	hud.big_map_mat.set_shader_parameter("centre", Vector2.ZERO)
	hud.big_map_mat.set_shader_parameter("radius_m", 4500.0)
	hud.big_map_mat.set_shader_parameter("aspect", SMALL_CANVAS.x / SMALL_CANVAS.y)
	var draws := [0]
	hud.overlay.draw.connect(func(): draws[0] += 1)
	hud.big_overlay.draw.connect(func(): draws[0] += 1)
	hud.big_map.show()
	hud.map_open = true
	for sel in [0, 1, 2, ms.size() - 1]:
		hud.map_sel = sel
		hud.overlay.queue_redraw()
		hud.big_overlay.queue_redraw()
		await tree.process_frame
	if draws[0] == 0:
		errors.append("the overlays never drew (the draw code was not exercised)")
	hud.map_sel = 9999
	hud.set_markers(ms.slice(0, 3))
	if hud.map_sel != 2:
		errors.append("a shorter marker list keeps the selection on a marker (%d)" % hud.map_sel)
	host.free()
