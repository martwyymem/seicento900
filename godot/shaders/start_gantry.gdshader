// Start-light gantry of an open-world event (scripts/world/event_dressing.gd), one draw call per gantry.
// Vertex colour codes the part: G = 0 frame (R = grey shade), 0.5 accent stripe (the event's colour, glows),
// 1.0 lamp (R = the lamp's column 0..4 divided by 4). The `lit` instance uniform is the number of columns
// lit (EventDressing.lit_columns): column k glows red while k < lit, otherwise it is a dark red lens.
// Fog is off for the lamps and the accent stripe so the lights read through fog and rain at any hour.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, fog_disabled;

uniform vec3 accent : source_color = vec3(1.0, 0.2, 0.5);
uniform float night = 0.0; // driven by OpenWorld._apply_time via TownBuilder.night_materials
instance uniform float lit : hint_range(0.0, 5.0) = 0.0;

void fragment() {
	float kind = COLOR.g;
	if (kind > 0.75) {
		float col = floor(COLOR.r * 4.0 + 0.5);
		float on = step(col + 0.5, lit);
		ALBEDO = vec3(0.04, 0.0, 0.0);
		ROUGHNESS = 0.2;
		// a lit column is far into HDR so it blooms; an unlit lens still shows as a faint red disc
		EMISSION = mix(vec3(0.16, 0.0, 0.0) * (0.35 + 0.65 * night), vec3(1.0, 0.07, 0.04) * 9.0, on);
	} else if (kind > 0.25) {
		ALBEDO = accent * 0.35;
		ROUGHNESS = 0.5;
		EMISSION = accent * (0.9 + 1.6 * night);
	} else {
		ALBEDO = vec3(COLOR.r);
		ROUGHNESS = 0.55;
		METALLIC = 0.35;
	}
}
