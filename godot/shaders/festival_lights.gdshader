// Festival overhead string-light bulbs along street bunting and over the hub plaza.
// Vertex colour RGB holds the bulb's festive tint; A holds its random sparkle phase.
// Uniform `night` is driven by OpenWorld._apply_time() via TownBuilder.night_materials.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform float night = 0.0;

void fragment() {
	vec3 col = COLOR.rgb;
	float twinkle = 0.84 + 0.16 * sin(TIME * 2.6 + COLOR.a * 41.0);
	ALBEDO = mix(col * 0.45 + vec3(0.35), col, night);
	ROUGHNESS = 0.25;
	EMISSION = col * night * 7.5 * twinkle;
}
