// Procedural trees: vertex-coloured foliage that sways in the wind (more with height, and harder in
// rain), with light shining through the leaves from behind.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform float wind = 1.0;
uniform float sway_height = 9.0;
uniform float translucency = 0.35;
uniform float roughness_value = 0.88;
uniform sampler2D grain : filter_linear_mipmap, repeat_enable;

varying vec3 world_pos;

// vertex colours are stored as sRGB
vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float h = max(VERTEX.y, 0.0) / sway_height;
	float phase = dot(origin.xz, vec2(0.13, 0.07));
	float gust = sin(TIME * 0.7 + phase * 0.3) * 0.5 + 0.5;
	float sway = (sin(TIME * 1.6 + phase) * 0.6 + sin(TIME * 2.9 + phase * 1.7) * 0.25) * (0.4 + 0.6 * gust);
	vec3 bend = vec3(sway, 0.0, sway * 0.4) * h * h * 0.35 * wind;
	// the flutter only moves the leaves (bright vertex alpha marks foliage)
	bend += vec3(sin(TIME * 6.0 + VERTEX.x * 3.0 + phase), 0.0, cos(TIME * 5.3 + VERTEX.z * 3.0)) * 0.03 * wind * COLOR.a;
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * bend);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = texture(grain, world_pos.xz * 0.9 + world_pos.y * 0.37).r;
	ALBEDO = to_linear(COLOR.rgb) * (0.82 + 0.36 * n);
	ROUGHNESS = roughness_value;
	SPECULAR = 0.3;
	BACKLIGHT = to_linear(COLOR.rgb) * translucency * COLOR.a;
}
