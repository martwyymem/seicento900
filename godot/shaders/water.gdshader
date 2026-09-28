// Harbour water: two scrolling ripple normal maps, dark and clear in deep water, a lighter teal
// towards the quays. Reflections come from the sky and (when enabled) screen-space reflections.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 deep_color : source_color = vec3(0.02, 0.17, 0.23);
uniform vec3 shallow_color : source_color = vec3(0.06, 0.36, 0.4);
uniform sampler2D ripples : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 size = vec2(300.0, 200.0);
uniform float choppy = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec3 n1 = texture(ripples, p * 0.021 + TIME * vec2(0.011, 0.006)).rgb;
	vec3 n2 = texture(ripples, p * 0.057 - TIME * vec2(0.007, 0.014)).rgb;
	vec3 n = normalize(mix(n1, n2, 0.5) * 2.0 - 1.0);
	n.xy *= choppy;
	vec2 edge = abs(UV - 0.5) * 2.0;
	float shallow = smoothstep(0.7, 1.0, max(edge.x, edge.y));
	ALBEDO = mix(deep_color, shallow_color, shallow);
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	NORMAL_MAP = normalize(n) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.7;
}
