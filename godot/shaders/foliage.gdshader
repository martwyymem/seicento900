// Procedural trees: vertex-coloured foliage that sways in the wind (more with height, and harder in
// rain), with light shining through the leaves from behind.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform float wind = 1.0;
uniform float sway_height = 9.0;
uniform float translucency = 0.35;
uniform float roughness_value = 0.88;
uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform bool linear_colors = false; // the Blender trees (models/trees.glb) store linear vertex colours
// each tree's leaves a little yellower or bluer than its neighbours', and darker deep inside the crown (race_world sets
// it; 0 keeps the plain look for other callers)
uniform float variety : hint_range(0.0, 1.0) = 0.0;
uniform float wet : hint_range(0.0, 1.0) = 0.0;
uniform float rain : hint_range(0.0, 1.0) = 0.0;
uniform float snow : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 tree_tint;
varying float crown_height;

// vertex colours are stored as sRGB
vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float h = max(VERTEX.y, 0.0) / sway_height;
	float phase = dot(origin.xz, vec2(0.13, 0.07));
	float pick = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453);
	tree_tint = mix(vec3(1.0), mix(vec3(0.82, 0.98, 0.92), vec3(1.14, 1.06, 0.74), pick), variety);
	crown_height = clamp(VERTEX.y / sway_height, 0.0, 1.0);
	float sway_wind = wind * (1.0 + 0.55 * rain);
	float gust = sin(TIME * 0.7 + phase * 0.3) * 0.5 + 0.5;
	float sway = (sin(TIME * 1.6 + phase) * 0.6 + sin(TIME * 2.9 + phase * 1.7) * 0.25) * (0.4 + 0.6 * gust);
	vec3 bend = vec3(sway, 0.0, sway * 0.4) * h * h * 0.35 * sway_wind;
	// the flutter only moves the leaves (bright vertex alpha marks foliage)
	bend += vec3(sin(TIME * 6.0 + VERTEX.x * 3.0 + phase), 0.0, cos(TIME * 5.3 + VERTEX.z * 3.0)) * 0.03 * sway_wind * COLOR.a;
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * bend);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	float n = texture(grain, world_pos.xz * 0.9 + world_pos.y * 0.37).r;
	vec3 base_col = linear_colors ? COLOR.rgb : to_linear(COLOR.rgb);
	base_col *= mix(vec3(1.0), tree_tint * mix(0.78, 1.1, crown_height), COLOR.a * variety);
	vec3 col = base_col * (0.82 + 0.36 * n);
	float rough = roughness_value;
	float spec = 0.3;
	float back_k = 1.0;
	float up = clamp(normalize(world_normal).y, 0.0, 1.0);
	float w = clamp(max(wet, rain * 0.65), 0.0, 1.0);
	if (w > 0.001) {
		float wet_k = w * (0.55 + 0.45 * up);
		col *= mix(1.0, 0.74, w * (0.7 + 0.3 * up));
		rough = mix(rough, mix(0.50, 0.38, COLOR.a), wet_k);
		spec = mix(spec, mix(0.38, 0.44, COLOR.a), wet_k);
	}
	if (snow > 0.001) {
		vec3 snow_col = vec3(0.90, 0.93, 0.98) * (0.91 + 0.16 * n);
		float leaf_bias = mix(-0.18, 0.16, COLOR.a) + 0.12 * crown_height * COLOR.a;
		float snow_cover = clamp(snow * smoothstep(0.18, 0.72, up + leaf_bias + (n - 0.5) * 0.48) * 1.15, 0.0, 1.0);
		col = mix(col, snow_col, snow_cover * 0.92);
		rough = mix(rough, 0.82, snow_cover);
		spec = mix(spec, 0.25, snow_cover);
		back_k *= 1.0 - snow_cover * 0.85;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	BACKLIGHT = base_col * translucency * COLOR.a * back_k;
}
