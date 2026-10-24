// Painted edge lines (race_world.gd _add_edge_lines): slightly grainy road paint that dulls with dirt in places,
// worn and scuffed on town roads, darker and satin when wet (never a white glare), and snowed over like the road.
// UV.x runs across the line (0..1) and UV.y along the lap in metres.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform vec3 paint_color : source_color = vec3(0.91, 0.9, 0.85);
uniform vec3 asphalt_color : source_color = vec3(0.13, 0.14, 0.145);
uniform sampler2D grain : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float street : hint_range(0.0, 1.0) = 0.0;
uniform float wet = 0.0;
uniform float snow : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float s = UV.y;
	float across = UV.x * 0.3;
	float fine = texture(grain, vec2(across, s) * 3.1 + 0.2).r;
	float dirt = texture(grain, vec2(across * 0.5, s * 0.06) + 0.45).r;
	vec3 col = paint_color * (0.9 + 0.12 * fine) * mix(1.0, 0.86, smoothstep(0.5, 0.75, dirt));
	// town paint: worn down to the tarmac in patches and along the wheel scuffs
	float wear = smoothstep(0.62, 0.3, texture(grain, vec2(across * 2.0, s * 0.35) + 0.7).r) * street;
	col = mix(col, asphalt_color * (0.9 + 0.2 * fine), wear * 0.75);
	col *= mix(1.0, 0.82, wet);
	if (snow > 0.01) {
		col = mix(col, vec3(0.92, 0.94, 0.98), snow * 0.85);
	}
	ALBEDO = col;
	ROUGHNESS = mix(0.62, 0.4, wet);
	SPECULAR = 0.35;
}
