// Grandstand tiers filled with spectators: every seat-sized cell is a random shirt colour or an empty
// seat, and the crowd gently shifts about.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

instance uniform vec4 seat_color : source_color = vec4(0.8, 0.2, 0.15, 1.0);
uniform float fill = 0.72;

varying vec3 local_pos;
varying vec3 local_normal;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 col = seat_color.rgb;
	float along = local_pos.x;
	vec2 id = vec2(floor(along / 0.55), floor(local_pos.z / 0.45) + floor(NODE_POSITION_WORLD.y * 3.0));
	float h = hash12(id);
	float bob = sin(TIME * (1.5 + h * 2.0) + h * 30.0) * 0.5 + 0.5;
	if (local_normal.y > 0.5 || local_normal.z > 0.5) {
		if (h < fill) {
			vec3 shirt = vec3(hash12(id + 1.7), hash12(id + 5.1), hash12(id + 9.3));
			shirt = mix(shirt, vec3(dot(shirt, vec3(0.33))), 0.35);
			float head = step(0.65, fract(along / 0.55)) * step(fract(along / 0.55), 0.95);
			col = mix(shirt * 0.9, vec3(0.62, 0.47, 0.37) * (0.7 + 0.3 * h), head * 0.5) * (0.85 + 0.15 * bob);
		}
	}
	ALBEDO = col;
	ROUGHNESS = 0.85;
}
