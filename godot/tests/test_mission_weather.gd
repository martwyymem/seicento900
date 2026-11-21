## A campaign mission raced on the open-world map brings its weather (Missions' "weather", MapMissions.weather_state)
## as it brings its hour: Rajd Borów's fog thickens the map's fog to a race's, damps the road and cuts the car's grip
## (FreeCar.mu, as Race.grip) and the rival crews' pace with it; RESTART keeps it; abandoning puts the free-roam
## weather back; a dry mission leaves the map dry.
extends RefCounted

var completed := false

func run() -> Array:
	var errors: Array[String] = []
	_states(errors)
	_shaders(errors)
	var map := TownMap.load_map(OpenWorld.MAP_KEY)
	if map == null:
		errors.append("data/world/%s.json did not load" % OpenWorld.MAP_KEY)
	else:
		await _world(map, errors)
	completed = true
	return errors

## Foliage and building shaders (shared by races and the open world) declare wet, rain and snow defaulting to 0.
func _shaders(errors: Array[String]) -> void:
	var surroundings_s: GDScript = preload("res://scripts/ui/surroundings.gd")
	var race_world_s: GDScript = preload("res://scripts/ui/race_world.gd")
	var prop_detail_s: GDScript = preload("res://scripts/ui/prop_detail.gd")
	for pair in [
		[TownBuilder.BUILDING_SHADER, "building.gdshader"],
		[TownBuilder.FOLIAGE_SHADER, "foliage.gdshader"],
		[surroundings_s.CANOPY_SHADER, "canopy.gdshader"],
		[race_world_s.FACADE_SHADER, "facade.gdshader"],
		[prop_detail_s.SHADER, "prop_detail.gdshader"],
	]:
		var sh: Shader = pair[0]
		var label: String = pair[1]
		var names := {}
		for info in sh.get_shader_uniform_list():
			names[String(info.get("name", ""))] = true
		for u in ["wet", "rain", "snow"]:
			if not names.has(u):
				errors.append("%s does not declare uniform '%s'" % [label, u])
			else:
				var def_v = RenderingServer.shader_get_parameter_default(sh.get_rid(), u)
				if def_v != null and absf(float(def_v)) > 1e-6:
					errors.append("%s uniform '%s' defaults to %s, not 0" % [label, u, str(def_v)])
	if surroundings_s.BUILDING_SHADER != TownBuilder.BUILDING_SHADER or surroundings_s.FOLIAGE_SHADER != TownBuilder.FOLIAGE_SHADER or race_world_s.FOLIAGE_SHADER != TownBuilder.FOLIAGE_SHADER:
		errors.append("race and open-world building/foliage shaders diverged")

## The weather modes as the races set them up, and their grip against a dry road.
func _states(errors: Array[String]) -> void:
	var dry := MapMissions.weather_state("dry")
	if dry.mu != 1.0 or dry.fog != 0.0 or dry.wet != 0.0:
		errors.append("dry weather is not a dry road at full grip: %s" % [dry])
	var fog := MapMissions.weather_state("fog")
	if fog.fog < 0.99 or absf(float(fog.wet) - 0.15) > 0.001 or absf(float(fog.mu) - 0.88) > 0.01:
		errors.append("fog is not a race's fog (fog 1, wet 0.15, grip ~0.88): %s" % [fog])
	var wet := MapMissions.weather_state("wet")
	if wet.wet < 0.8 or wet.rain <= 0.0 or not (float(wet.mu) < float(fog.mu)):
		errors.append("wet weather is not wetter and slipperier than fog: %s" % [wet])
	var rain := MapMissions.weather_state("rain")
	if absf(float(rain.rain) - float(wet.rain)) > 1e-6 or absf(float(rain.wet) - float(wet.wet)) > 1e-6 or absf(float(rain.mu) - float(wet.mu)) > 1e-6:
		errors.append("rain alias does not match wet weather state: %s vs %s" % [rain, wet])
	if not (float(MapMissions.weather_state("snow").mu) < float(wet.mu)):
		errors.append("snow grips no worse than rain")
	var rally := MapMissions.event(Missions.index_of("rally_bor"))
	if String(rally.get("weather", "")) != "fog" or absf(float(rally.get("mu", 1.0)) - float(fog.mu)) > 1e-6:
		errors.append("Rajd Borów's map event does not carry its fog: %s / %s" % [rally.get("weather"), rally.get("mu")])
	var drag := MapMissions.event(Missions.index_of("drag_quarter"))
	if String(drag.get("weather", "")) != "dry" or float(drag.get("mu", 0.0)) != 1.0:
		errors.append("the dry drag's map event is not dry")
	# the field's road grip follows the weather; the cached profile does not
	var prof := {"grip": PackedFloat32Array([1.0, 0.8])}
	var p2 := LiveEvents._weather_profile(prof, 0.5)
	if absf((p2.grip as PackedFloat32Array)[1] - 0.4) > 1e-5 or absf((prof.grip as PackedFloat32Array)[1] - 0.8) > 1e-5:
		errors.append("the weather profile does not scale the grip on a copy")

func _world(map: TownMap, errors: Array[String]) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var ow := OpenWorld.new()
	ow.size = Vector2(1600, 900)
	tree.root.add_child(ow)
	await tree.process_frame
	var s: Array = map.spots.get("festival", [0.0, 0.0, 0.0])
	var home := Vector2(s[0], s[1])
	ow.map = map
	ow.progress = WorldProgress.new()
	ow.world = Node3D.new()
	ow.add_child(ow.world)
	ow.route_mesh = MeshInstance3D.new()
	ow.world.add_child(ow.route_mesh)
	ow.builder = TownBuilder.new(map, ow.world)
	var prop_detail_s: GDScript = preload("res://scripts/ui/prop_detail.gd")
	var landmark_mat: ShaderMaterial = null
	for lm_name in ["DworzecBrzeszcze", "KosciolUrbana", "KosciolMarcina"]:
		if ow.builder.models.has(lm_name):
			var lm_mesh := ow.builder.models[lm_name][0] as Mesh
			if lm_mesh:
				for si in lm_mesh.get_surface_count():
					var sm := lm_mesh.surface_get_material(si) as ShaderMaterial
					if sm and sm.shader == prop_detail_s.SHADER:
						landmark_mat = sm
						break
		if landmark_mat != null:
			break
	if landmark_mat == null:
		errors.append("no prop_detail ShaderMaterial found on a Brzeszcze landmark mesh")
	elif not ow.builder.wet_materials.has(landmark_mat):
		errors.append("landmark prop_detail material is not registered in TownBuilder.wet_materials")
	var ground_mat := ow.builder._surface_material(TownBuilder.GROUND_SHADER, "grass")
	var road_mat := ow.builder._surface_material(TownBuilder.ROAD_SHADER, "asphalt")
	var building_mat := ShaderMaterial.new()
	building_mat.shader = TownBuilder.BUILDING_SHADER
	var foliage_mat := ShaderMaterial.new()
	foliage_mat.shader = TownBuilder.FOLIAGE_SHADER
	ow.builder.wet_materials.append(building_mat)
	ow.builder.wet_materials.append(foliage_mat)
	ow.builder.night_materials.append(road_mat)
	ow.builder.night_materials.append(building_mat)
	ow.drive = FreeCar.new(map)
	ow.drive.place(home, 0.0)
	ow.live = LiveEvents.new(map, 4242)
	ow._build_environment()
	ow.hour = 13.0
	ow._apply_time()
	var clear_fog := ow.env.fog_density
	var clear_sun := ow.sun.light_energy
	var clear_shadow := ow.sun.shadow_opacity
	var clear_top := Color(ow.sky_mat.get_shader_parameter("top_color"))
	if ow.weather_fx == null:
		errors.append("open world did not create weather_fx")
	elif ow.weather_fx.any_emitting():
		errors.append("weather particles emit in dry free roam")
	if float(ow.sky_mat.get_shader_parameter("overcast")) > 1e-5:
		errors.append("sky is overcast in dry free roam: %.3f" % float(ow.sky_mat.get_shader_parameter("overcast")))
	var ri := Missions.index_of("rally_bor")
	if not ow._begin_mission(ri):
		errors.append("Rajd Borów did not start on the map")
		ow.queue_free()
		await tree.process_frame
		return
	var fog := MapMissions.weather_state("fog")
	if ow.weather != "fog" or ow.fog < 0.99 or absf(ow.wet - 0.15) > 0.001:
		errors.append("the rally's fog is not on the map: %s fog %.2f wet %.2f" % [ow.weather, ow.fog, ow.wet])
	if absf(ow.drive.mu - float(fog.mu)) > 1e-6:
		errors.append("the car's grip in the rally's fog is %.3f, not %.3f" % [ow.drive.mu, fog.mu])
	if absf(ow.hour - 8.5) > 0.01:
		errors.append("the clock did not move to the rally's hour")
	if not (ow.env.fog_density > 0.015 and ow.env.fog_density > clear_fog * 10.0):
		errors.append("the fog density in the rally is %.5f (free roam %.5f)" % [ow.env.fog_density, clear_fog])
	if ow.weather_fx and (not ow.weather_fx.fog.emitting or ow.weather_fx.rain.emitting or ow.weather_fx.snow.emitting):
		errors.append("rally fog did not emit fog wisps alone (fog=%s rain=%s snow=%s)" % [ow.weather_fx.fog.emitting, ow.weather_fx.rain.emitting, ow.weather_fx.snow.emitting])
	# the crews' stage times are run on the fog's grip: their fastest is past the band's quickest on the foggy reference
	var ev: Dictionary = ow.live.run.ev
	var st0: Dictionary = ev.stages[0]
	var car := String(ow.live.run.car)
	var dry_ref := LiveEvents.pace_time(st0.path, car, 0.0, float(st0.grip))
	var fog_ref := LiveEvents.pace_time(st0.path, car, 0.0, float(st0.grip) * float(fog.mu))
	var band: Vector2 = MapMissions.RALLY_PACE.get(String(ev.get("difficulty", "medium")), MapMissions.RALLY_PACE.medium)
	var fastest := INF
	for times in ow.live.run.rally:
		fastest = minf(fastest, float(times[0]))
	if not (fog_ref > dry_ref) or fastest < fog_ref * band.x * 0.984:
		errors.append("the rally crews are not slowed by the fog: fastest %.1f s, fog reference %.1f s, dry %.1f s" % [fastest, fog_ref, dry_ref])
	ow._pause_action("restart_live")
	if ow.fog < 0.99 or absf(ow.drive.mu - float(fog.mu)) > 1e-6:
		errors.append("RESTART EVENT lost the rally's fog")
	ow._pause_action("abandon_live")
	if ow.weather != "dry" or ow.fog != 0.0 or ow.wet != 0.0 or ow.drive.mu != 1.0:
		errors.append("abandoning the rally left its weather: %s fog %.2f wet %.2f grip %.2f" % [ow.weather, ow.fog, ow.wet, ow.drive.mu])
	if absf(ow.hour - 13.0) > 0.01 or absf(ow.env.fog_density - clear_fog) > 1e-7:
		errors.append("abandoning the rally left its hour or fog: %.2f h, density %.5f" % [ow.hour, ow.env.fog_density])
	# whatever the map had before is what comes back (a wet street here), and a dry mission runs dry;
	# wet_materials (terrain, embankments, buildings, foliage, props/landmarks as well as the streets) get wet, rain and snow
	ow.set_weather(MapMissions.weather_state("snow"))
	if float(ground_mat.get_shader_parameter("snow")) < 0.8 or float(road_mat.get_shader_parameter("snow")) < 0.8 or float(building_mat.get_shader_parameter("snow")) < 0.8 or float(foliage_mat.get_shader_parameter("snow")) < 0.8 or (landmark_mat != null and float(landmark_mat.get_shader_parameter("snow")) < 0.8):
		errors.append("snow weather did not reach ground, road, building, foliage and landmark materials in wet_materials")
	if ow.weather_fx and (not ow.weather_fx.snow.emitting or ow.weather_fx.rain.emitting or ow.weather_fx.fog.emitting):
		errors.append("snow weather did not emit snow particles alone")
	if float(ow.sky_mat.get_shader_parameter("overcast")) < 0.5 or not (ow.sun.light_energy < clear_sun) or not (ow.sun.shadow_opacity < clear_shadow):
		errors.append("snow weather did not turn the sky overcast and dim the sun (overcast=%.2f sun=%.2f/%.2f)" % [float(ow.sky_mat.get_shader_parameter("overcast")), ow.sun.light_energy, clear_sun])
	# falling rain + overcast sky + quality scaling + camera following; then dry turns everything off
	ow.set_weather(MapMissions.weather_state("rain"))
	if ow.weather_fx:
		if not (ow.weather_fx.rain.emitting and ow.weather_fx.rain_splash.emitting and ow.weather_fx.rain_mist.emitting):
			errors.append("rain weather did not emit rain, splash and mist particles")
		if ow.weather_fx.snow.emitting or ow.weather_fx.hail.emitting or ow.weather_fx.fog.emitting:
			errors.append("rain weather emitted non-rain particles")
		var before_rain := ow.weather_fx.rain.global_position
		ow.camera.global_position += Vector3(25.0, 0.0, -15.0)
		ow.weather_fx.place(ow.camera)
		if ow.weather_fx.rain.global_position.distance_to(before_rain) < 20.0:
			errors.append("rain particles did not follow the camera")
		ow.apply_graphics(0)
		if ow.weather_fx.rain.amount != WeatherParticles.RAIN_AMOUNT[0]:
			errors.append("Low preset did not scale rain amount to %d (got %d)" % [WeatherParticles.RAIN_AMOUNT[0], ow.weather_fx.rain.amount])
		ow.apply_graphics(2)
		if ow.weather_fx.rain.amount != WeatherParticles.RAIN_AMOUNT[2]:
			errors.append("High preset did not restore rain amount to %d (got %d)" % [WeatherParticles.RAIN_AMOUNT[2], ow.weather_fx.rain.amount])
	var rain_overcast := float(ow.sky_mat.get_shader_parameter("overcast"))
	var rain_top := Color(ow.sky_mat.get_shader_parameter("top_color"))
	if rain_overcast < 0.5 or not (ow.sun.light_energy < clear_sun) or not (ow.sun.shadow_opacity < clear_shadow) or not (rain_top.s < clear_top.s):
		errors.append("rain weather did not make the sky overcast (overcast=%.2f sun=%.2f/%.2f top_sat=%.2f/%.2f)" % [rain_overcast, ow.sun.light_energy, clear_sun, rain_top.s, clear_top.s])
	ow.set_weather(MapMissions.weather_state("dry"))
	if ow.weather_fx and ow.weather_fx.any_emitting():
		errors.append("dry weather left weather particles emitting")
	if float(ow.sky_mat.get_shader_parameter("overcast")) > 1e-5 or absf(ow.sun.light_energy - clear_sun) > 1e-5:
		errors.append("dry weather did not restore clear sky and sun")
	ow.set_weather(MapMissions.weather_state("wet"))
	if float(ground_mat.get_shader_parameter("wet")) < 0.8 or float(road_mat.get_shader_parameter("rain")) <= 0.0 or float(ground_mat.get_shader_parameter("snow")) != 0.0 or float(building_mat.get_shader_parameter("wet")) < 0.8 or float(foliage_mat.get_shader_parameter("wet")) < 0.8 or float(foliage_mat.get_shader_parameter("rain")) <= 0.0 or float(building_mat.get_shader_parameter("snow")) != 0.0 or float(foliage_mat.get_shader_parameter("snow")) != 0.0 or (landmark_mat != null and (float(landmark_mat.get_shader_parameter("wet")) < 0.8 or float(landmark_mat.get_shader_parameter("rain")) <= 0.0 or float(landmark_mat.get_shader_parameter("snow")) != 0.0)):
		errors.append("wet weather did not update wet_materials (including building, foliage and landmark)")
	var di := Missions.index_of("drag_quarter")
	if ow._begin_mission(di):
		if ow.weather != "dry" or ow.wet != 0.0 or ow.drive.mu != 1.0:
			errors.append("the dry drag did not run dry: %s wet %.2f grip %.2f" % [ow.weather, ow.wet, ow.drive.mu])
		ow._end_run()
		var wet := MapMissions.weather_state("wet")
		if ow.weather != "wet" or absf(ow.wet - float(wet.wet)) > 1e-6 or absf(ow.drive.mu - float(wet.mu)) > 1e-6:
			errors.append("the drag's end did not put the wet streets back: %s wet %.2f" % [ow.weather, ow.wet])
	else:
		errors.append("the drag mission did not start on the map")
	# clear night: night dew damps the road, not landmark props
	ow.set_weather(MapMissions.weather_state("dry"))
	ow.hour = 23.0
	ow._apply_time()
	if landmark_mat != null and float(landmark_mat.get_shader_parameter("wet")) > 0.001:
		errors.append("clear night damped landmark prop material: wet=%.3f" % float(landmark_mat.get_shader_parameter("wet")))
	ow.queue_free()
	await tree.process_frame
