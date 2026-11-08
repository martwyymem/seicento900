// Meadow grass and wheat patches (GrassPatch, WheatPatch in models/roadside.glb, planted by vegetation.gd).
// The mesh's vertex colour is data: R the blade's dryness, G the height along the blade (0 root, 1 tip), B 1 on a
// wheat ear, A a per-blade random. INSTANCE_CUSTOM: rgb a tint, a how dry the patch is.
// The blades sway in rolling gusts, get a dark root and a sunlit tip, let the sun through from behind, and shrink
// into the ground one by one towards the far edge of the planted ring (and across the dense/sparse hand-over) so
// the cells never pop in.
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

uniform vec3 root_color : source_color = vec3(0.09, 0.16, 0.05);
uniform vec3 mid_color : source_color = vec3(0.30, 0.50, 0.11);
uniform vec3 tip_color : source_color = vec3(0.56, 0.68, 0.20);
uniform vec3 dry_color : source_color = vec3(0.80, 0.68, 0.36);
uniform vec3 ear_color : source_color = vec3(0.86, 0.70, 0.36);
uniform float wind_strength = 0.16; // m of tip sway in a gust
uniform float wind_speed = 1.0;
uniform vec2 wind_dir = vec2(0.8, 0.6);
uniform float fade_start = 60.0; // m: blades start to sink
uniform float fade_end = 88.0; // m: gone
// the hand-over between the dense patches near the camera and the sparse ones further out (vegetation.gd draws both
// over a band, the cells overlapping): in that band (x..y m; y = 0: none) the dense blades leave one by one and the
// sparse ones come in, so no cell's grass changes all at once
uniform vec2 lod_out = vec2(0.0);
uniform vec2 lod_in = vec2(0.0);
uniform float translucency = 0.55;

varying float v_h;
varying float v_dry;
varying float v_ear;
varying vec3 v_tint;
varying float v_rnd;
varying float v_far;

// 1 before this blade's turn in band [a, b], 0 after it: each blade goes over a fifth of the band, at a point set by
// its own random
float blade_leaves(vec2 band, float d, float rnd) {
	float w = band.y - band.x;
	float at = band.x + w * rnd * 0.8;
	return 1.0 - smoothstep(at, at + w * 0.2, d);
}

void vertex() {
	float h = COLOR.g;
	v_h = h;
	v_ear = COLOR.b;
	v_rnd = COLOR.a;
	v_tint = INSTANCE_CUSTOM.rgb;
	v_dry = clamp(COLOR.r * (0.4 + INSTANCE_CUSTOM.a) + INSTANCE_CUSTOM.a * 0.35, 0.0, 1.0);

	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float d = distance(origin.xz, cam.xz);
	// towards the far edge each blade sinks in its own turn (the patch thins out, no line where it all goes), and
	// takes the plain mid colour, nearer the ground's, so the edge of the planted ring doesn't read as a wall
	float keep = blade_leaves(vec2(fade_start, fade_end), d, v_rnd);
	keep *= 1.0 - smoothstep(fade_start, fade_end, d) * 0.5;
	v_far = smoothstep(fade_start - 20.0, fade_end, d);
	if (lod_out.y > 0.0) {
		keep *= blade_leaves(lod_out, d, v_rnd);
	}
	if (lod_in.y > 0.0) {
		keep *= 1.0 - blade_leaves(lod_in, d, fract(v_rnd * 7.31 + 0.37));
	}
	VERTEX.y *= keep;

	// wind: a slow rolling gust front plus a quick flutter per blade, both bending the tip the most
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 wd = normalize(wind_dir);
	float t = TIME * wind_speed;
	float front = dot(wp.xz, wd) * 0.09 - t * 1.3;
	float gust = 0.55 + 0.45 * sin(front) * sin(front * 0.37 + 1.7);
	float flutter = sin(t * 3.1 + v_rnd * 6.283 + wp.x * 0.7) * 0.35;
	float bend = h * h * wind_strength * (gust + flutter * 0.5);
	vec3 push = vec3(wd.x, -0.25 * abs(gust), wd.y) * bend;
	// into model space: MODEL_MATRIX is a rotation and a scale, so its transpose over the squared scale inverts it
	mat3 m = mat3(MODEL_MATRIX);
	vec3 inv = vec3(dot(m[0], m[0]), dot(m[1], m[1]), dot(m[2], m[2]));
	VERTEX += (transpose(m) * push) / max(inv, vec3(1e-4));
}

void fragment() {
	float h = v_h;
	vec3 col = mix(root_color, mid_color, smoothstep(0.0, 0.45, h));
	col = mix(col, tip_color, smoothstep(0.6, 1.0, h));
	col = mix(col, dry_color * mix(0.65, 1.0, h), v_dry);
	col *= 0.85 + 0.3 * v_rnd;
	col = mix(col, ear_color * (0.85 + 0.25 * v_rnd), v_ear);
	col *= v_tint;
	col = mix(col, mid_color * v_tint * 0.95, v_far * 0.7);
	ALBEDO = col;
	ROUGHNESS = 0.78;
	SPECULAR = 0.3;
	// mostly up-facing normals: the meadow takes the light as one soft surface, not as thousands of cards
	vec3 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	NORMAL = normalize(mix(NORMAL, up, 0.65));
	BACKLIGHT = col * translucency * (0.3 + 0.7 * h);
	AO = mix(0.35, 1.0, smoothstep(0.0, 0.7, h));
	AO_LIGHT_AFFECT = 0.5;
}
