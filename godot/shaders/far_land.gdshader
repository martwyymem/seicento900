// The land beyond the circuit's own terrain out to 40 km (far_land.gd): the hills and mountains on the horizon.
// It is drawn behind everything the scene draws, past the camera's far plane: its depth is pushed back
// (reversed Z, so a tiny depth is far away) while it keeps its true place on screen, so it shows only where
// the scene leaves sky. The colour comes from the vertex (sea, field, wood, town, rock) with patches of fields
// from noise; the haze is its own (FOG) and thins out beyond the scene's range, as distant hills do.
shader_type spatial;
render_mode depth_draw_opaque, cull_back, shadows_disabled;

uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform vec3 haze_color : source_color = vec3(0.64, 0.71, 0.8);
uniform float haze_density = 0.00032; // the scene's fog density
uniform float haze_reach = 2500.0; // metres over which the haze builds as the scene's fog does
uniform float haze_beyond = 0.22; // ...and how much slower it thickens past that
uniform float wet = 0.0;
uniform float night = 0.0;
uniform vec3 field_a : source_color = vec3(0.42, 0.5, 0.26);
uniform vec3 field_b : source_color = vec3(0.6, 0.57, 0.34);
uniform vec3 field_c : source_color = vec3(0.34, 0.42, 0.22);

const float DEPTH_SCALE = 5e-8; // depth = DEPTH_SCALE / distance: behind the scene out to its far plane
const float CURVE = 6.8e-8; // the Earth's curvature with refraction: drop = d^2 * 0.87 / (2 * 6371 km)

varying vec3 world_pos;
varying float dist;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 flat = w.xz - CAMERA_POSITION_WORLD.xz;
	w.y -= dot(flat, flat) * CURVE;
	world_pos = w;
	dist = length(w - CAMERA_POSITION_WORLD);
	vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(w, 1.0);
	clip.z = clip.w * DEPTH_SCALE / max(dist, 1.0);
	POSITION = clip;
}

void fragment() {
	vec2 p = world_pos.xz;
	// COLOR.rgb is the land's own colour; COLOR.a 1 on open farmland, where fields of different crops show
	float fields = texture(grain, p * 0.0019 + 0.21).r;
	float shade = texture(grain, p * 0.0007 + 0.6).r;
	vec3 crop = fields < 0.4 ? field_a : (fields < 0.62 ? field_b : field_c);
	vec3 col = mix(COLOR.rgb, crop, COLOR.a * 0.8) * (0.82 + 0.36 * shade);
	ALBEDO = col * mix(1.0, 0.78, wet);
	// UV.x is 1 on the open sea: a smooth surface that catches the sky
	ROUGHNESS = mix(0.95, 0.2, UV.x);
	SPECULAR = mix(0.15, 0.5, UV.x);
	// haze: as the scene's fog near the circuit, much thinner per metre beyond, and thinner over the peaks
	float near = min(dist, haze_reach);
	float far = max(dist - haze_reach, 0.0) * haze_beyond;
	float lift = max(world_pos.y - CAMERA_POSITION_WORLD.y, 0.0);
	float haze = 1.0 - exp(-haze_density * (near + far) * mix(1.0, 0.55, smoothstep(0.0, 1500.0, lift)));
	FOG = vec4(haze_color, clamp(haze, 0.0, 0.97));
}
