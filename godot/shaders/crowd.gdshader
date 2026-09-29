// Seated spectators (the StandCrowd mesh from tools/blender/build_trackside.py): one row of 18 figures per
// instance. The vertex colour codes each vertex: red is the body part (0 shirt, 0.25 skin, 0.5 legs,
// 0.75 hair) and green the seat, (seat + 0.5) / 18. Every seat gets its own clothes, skin and hair (some
// wear a cap), a share of the seats stay empty, and the crowd shifts about a little.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform float fill = 0.8; // share of seats taken

varying vec3 tint;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 pick(float h, vec3 a, vec3 b, vec3 c, vec3 d, vec3 e, vec3 f) {
	float k = floor(h * 6.0);
	return k < 1.0 ? a : k < 2.0 ? b : k < 3.0 ? c : k < 4.0 ? d : k < 5.0 ? e : f;
}

void vertex() {
	float part = floor(COLOR.r * 4.0 + 0.5);
	float seat = floor(COLOR.g * 18.0);
	// seat, row and stand: the row's instance number and where the stand is
	vec2 id = vec2(seat + float(INSTANCE_ID) * 19.0, dot(NODE_POSITION_WORLD.xz, vec2(0.13, 0.071)));
	float h0 = hash12(id);
	if (h0 > fill) {
		VERTEX = vec3(0.0); // an empty seat
	} else {
		float h1 = hash12(id + 3.7);
		float h2 = hash12(id + 8.1);
		float h3 = hash12(id + 13.9);
		vec3 shirt = pick(h1, vec3(0.62, 0.05, 0.05), vec3(0.9, 0.88, 0.84), vec3(0.05, 0.12, 0.35),
			vec3(0.06, 0.06, 0.07), vec3(0.9, 0.62, 0.05), vec3(0.1, 0.36, 0.2));
		// a second, paler palette for half the crowd so it isn't all team colours
		vec3 casual = pick(fract(h1 * 7.3), vec3(0.45, 0.55, 0.7), vec3(0.72, 0.3, 0.28), vec3(0.55, 0.52, 0.45),
			vec3(0.8, 0.8, 0.78), vec3(0.3, 0.3, 0.33), vec3(0.85, 0.45, 0.55));
		shirt = mix(shirt, casual, step(0.5, h2));
		vec3 skin = mix(vec3(0.72, 0.5, 0.38), vec3(0.3, 0.18, 0.12), h3 * h3);
		vec3 legs = pick(h2, vec3(0.12, 0.17, 0.3), vec3(0.08, 0.08, 0.1), vec3(0.45, 0.4, 0.3),
			vec3(0.2, 0.26, 0.4), skin, vec3(0.3, 0.3, 0.32)); // one in six in shorts
		vec3 hair = pick(fract(h3 * 5.1), vec3(0.06, 0.04, 0.03), vec3(0.2, 0.12, 0.06), vec3(0.5, 0.38, 0.2),
			vec3(0.55, 0.53, 0.5), vec3(0.08, 0.06, 0.05), vec3(0.3, 0.2, 0.1));
		hair = fract(h1 * 13.7) < 0.22 ? pick(fract(h2 * 3.3), vec3(0.62, 0.05, 0.05), vec3(0.9, 0.9, 0.88),
			vec3(0.06, 0.06, 0.07), vec3(0.05, 0.12, 0.35), vec3(0.9, 0.7, 0.05), vec3(0.62, 0.05, 0.05)) : hair; // caps
		tint = part < 0.5 ? shirt : part < 1.5 ? skin : part < 2.5 ? legs : hair;
		// the upper body sways and leans, each spectator in their own time
		float up = max(VERTEX.y - 0.55, 0.0);
		float t = TIME * (0.6 + h2 * 0.9) + h0 * 40.0;
		VERTEX.x += sin(t) * 0.05 * up;
		VERTEX.z += (sin(t * 0.37 + h3 * 6.0) * 0.5 + 0.3) * 0.12 * up;
	}
}

void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 0.85;
}
