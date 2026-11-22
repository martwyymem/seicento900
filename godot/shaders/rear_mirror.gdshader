shader_type canvas_item;
// Rounded-rectangle rear-view mirror: horizontal flip, dark bezel, a faint gloss.
uniform float radius : hint_range(0.0, 0.5) = 0.16;
uniform float bezel = 0.045;
uniform vec2 aspect = vec2(4.0, 1.0);

float sd_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - 0.5) * aspect;
	float r = radius * aspect.y;
	vec2 half_size = aspect * 0.5;
	float d = sd_box(p, half_size, r);
	float inner = sd_box(p, half_size - vec2(bezel * aspect.y), max(r - bezel * aspect.y, 0.01));
	vec3 col = texture(TEXTURE, vec2(1.0 - UV.x, UV.y)).rgb;
	col *= 1.0 - 0.18 * smoothstep(0.0, 0.5, UV.y) * 0.0;
	col += vec3(0.05) * smoothstep(0.5, 0.0, UV.y);
	float in_glass = 1.0 - smoothstep(-0.004, 0.004, inner);
	vec3 bez = mix(vec3(0.03), vec3(0.16), smoothstep(0.0, -0.02, d) * 0.5);
	float a = 1.0 - smoothstep(-0.004, 0.004, d);
	COLOR = vec4(mix(bez, col, in_glass), a);
}
