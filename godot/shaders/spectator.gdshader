// Animated festival spectators (SpectatorStand / SpectatorCheer / SpectatorWave from tools/blender/build_town.py).
// Mesh vertex colour COLOR codes each vertex:
//   R = body part (0.0 shirt, 0.25 skin, 0.50 trousers/shoes, 0.75 hair/cap, 1.0 phone/lightstick)
//   G = animation weight (0.0 feet/hips, 0.35 torso/head, 0.65..1.0 arms & hands)
//   B = lateral arm side (0.0 left arm, 0.5 centre body, 1.0 right arm)
// MultiMesh INSTANCE_CUSTOM passes per-spectator data:
//   RGB = festival shirt/jacket albedo tint (linear)
//   A   = per-spectator random seed [0..1)
// Driven cheaply in vertex() by player car proximity and speed: idle sway, cheering/waving/jumping as the
// car passes, and a quick jump-back dodge if the car drives close.
// suit = 1 (the organisers' FestExec* pieces, a second ShaderMaterial): INSTANCE_CUSTOM.rgb is the jacket, trousers are
// dark business colours, nobody wears a cap, part 1.0 is paper (clipboard, lanyard badge: no night glow) and the
// excitement is muted so they stay composed (they still dodge a close car).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 car_pos = vec3(0.0, -9999.0, 0.0);
uniform vec3 car_vel = vec3(0.0);
uniform float night = 0.0;
uniform float suit = 0.0;

varying vec3 tint;
varying float glow_flag;

vec3 pick6(float h, vec3 a, vec3 b, vec3 c, vec3 d, vec3 e, vec3 f) {
	float k = floor(fract(h) * 6.0);
	return k < 1.0 ? a : k < 2.0 ? b : k < 3.0 ? c : k < 4.0 ? d : k < 5.0 ? e : f;
}

void vertex() {
	float seed = INSTANCE_CUSTOM.a;
	float h1 = fract(seed * 17.31 + 0.13);
	float h2 = fract(seed * 37.73 + 0.41);
	float h3 = fract(seed * 73.19 + 0.77);

	float part = floor(COLOR.r * 4.0 + 0.5);
	float anim_w = COLOR.g;
	float side = (COLOR.b - 0.5) * 2.0; // -1 left arm, 0 body, +1 right arm

	// Per-person colour palette (shirt from INSTANCE_CUSTOM.rgb, natural skin/trousers/hair/caps from seed)
	vec3 shirt = INSTANCE_CUSTOM.rgb;
	vec3 skin = mix(vec3(0.76, 0.54, 0.42), vec3(0.32, 0.19, 0.13), h1 * h1);
	vec3 legs = pick6(h2,
		vec3(0.10, 0.16, 0.30), // denim
		vec3(0.06, 0.06, 0.08), // black
		vec3(0.42, 0.36, 0.27), // khaki
		vec3(0.18, 0.24, 0.36), // slate blue
		vec3(0.24, 0.24, 0.26), // charcoal
		vec3(0.35, 0.22, 0.16)  // brown
	);
	vec3 hair = pick6(h3,
		vec3(0.05, 0.035, 0.025),
		vec3(0.20, 0.12, 0.06),
		vec3(0.48, 0.36, 0.18),
		vec3(0.55, 0.52, 0.48),
		vec3(0.12, 0.08, 0.05),
		vec3(0.34, 0.18, 0.09)
	);
	// ~30% wear bright festival caps matching or contrasting the shirt
	if (h1 > 0.70 && suit < 0.5) {
		hair = mix(shirt, vec3(0.95, 0.78, 0.15), step(0.85, h1));
	}
	if (suit > 0.5) {
		legs = pick6(h2,
			vec3(0.05, 0.05, 0.07),
			vec3(0.09, 0.10, 0.14),
			vec3(0.14, 0.14, 0.16),
			vec3(0.07, 0.08, 0.12),
			vec3(0.11, 0.09, 0.09),
			vec3(0.16, 0.17, 0.19)
		);
	}
	glow_flag = (part > 3.5 && suit < 0.5) ? 1.0 : 0.0;
	tint = part < 0.5 ? shirt : part < 1.5 ? skin : part < 2.5 ? legs : part < 3.5 ? hair : (suit > 0.5 ? vec3(0.93, 0.92, 0.86) : vec3(0.85, 0.92, 1.0));

	// Subtle per-person height variation (~1.75 m average)
	VERTEX.y *= 0.94 + h2 * 0.12;

	// World-space proximity to player car
	vec3 inst_world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec2 to_inst = inst_world.xz - car_pos.xz;
	float dist = length(to_inst);
	float dy = abs(inst_world.y - car_pos.y);
	float car_spd = length(car_vel.xz);
	float near_h = 1.0 - smoothstep(3.0, 48.0, dist);
	float excite = near_h * clamp(0.35 + car_spd / 16.0, 0.35, 1.45) * (1.0 - smoothstep(4.0, 10.0, dy));
	excite *= mix(1.0, 0.3, suit);

	// Idle sway & rhythmic cheering/jumping
	float phase = seed * 43.0;
	float t_idle = TIME * (1.3 + h3 * 0.8) + phase;
	float t_fast = TIME * (6.5 + h1 * 2.5) + phase;

	// Vertical bob/jump (whole body hops slightly when excited, upper body bounces more)
	float jump = abs(sin(t_fast)) * 0.19 * excite + sin(t_idle * 2.0) * 0.025 * anim_w;
	VERTEX.y += jump * (0.35 + 0.65 * anim_w);

	// Torso sway & arm waving
	float arm_only = smoothstep(0.45, 0.95, anim_w);
	VERTEX.x += sin(t_idle) * 0.035 * anim_w + sin(t_fast * 1.15 + side * 1.4) * 0.14 * arm_only * (0.28 + 0.95 * excite);
	VERTEX.y += sin(t_fast * 1.15 + side * 0.7) * 0.08 * arm_only * (0.20 + 0.85 * excite);
	VERTEX.z += (cos(t_idle * 0.7) * 0.03 + sin(t_fast) * 0.07 * excite) * anim_w;

	// Jump-back dodge if the car comes very close (< 6.5 m)
	float dodge = (1.0 - smoothstep(2.0, 6.5, dist)) * (1.0 - smoothstep(2.2, 5.0, dy));
	if (dodge > 0.001) {
		vec2 away = dist > 0.05 ? to_inst / dist : vec2(1.0, 0.0);
		vec3 world_shift = vec3(away.x, 0.0, away.y) * (dodge * 1.55) + vec3(0.0, sin(dodge * 3.14159) * 0.38, 0.0);
		VERTEX += inverse(mat3(MODEL_MATRIX)) * world_shift;
	}
}

void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 0.84;
	if (glow_flag > 0.5) {
		EMISSION = vec3(0.75, 0.88, 1.0) * (0.6 + 3.6 * night);
	} else if (night > 0.01) {
		// Soft festival ambient bounce so roadside/gate crowds stay readable at night
		EMISSION = tint * (0.10 * night);
	}
}
