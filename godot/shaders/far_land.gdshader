// The land beyond the circuit's own terrain out to 40 km (far_land.gd): the hills and mountains on the horizon.
// It is drawn behind everything the scene draws, past the camera's far plane: its depth is pushed back
// (reversed Z, so a tiny depth is far away) while it keeps its true place on screen, so it shows only where
// the scene leaves sky. The colour comes from the vertex (sea, field, wood, town, rock) with patches of fields
// and town blocks from noise, lit at night; the haze is its own (FOG) and thins out beyond the scene's range, as distant hills do.
shader_type spatial;
render_mode depth_draw_opaque, cull_back, shadows_disabled;

uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform vec3 haze_color : source_color = vec3(0.64, 0.71, 0.8);
uniform float haze_density = 0.00032; // the scene's fog density
uniform float haze_reach = 2500.0; // metres over which the haze builds as the scene's fog does
uniform float haze_beyond = 0.22; // ...and how much slower it thickens past that
uniform float mist = 0.0; // the scene's volumetric fog density (rain and night), here a haze into the sky
uniform float wet = 0.0;
uniform float night = 0.0;
uniform vec3 field_a : source_color = vec3(0.42, 0.5, 0.26);
uniform vec3 field_b : source_color = vec3(0.6, 0.57, 0.34);
uniform vec3 field_c : source_color = vec3(0.34, 0.42, 0.22);
// the sky's own horizon (copied from sky.gdshader's uniforms by far_land.gd), which the far haze turns into, as the
// scene's fog does through its aerial perspective; otherwise a night sky's bright horizon would show the hills black
uniform float aerial = 0.55; // the scene fog's share of colour from the sky
uniform vec3 horizon_color : source_color = vec3(0.64, 0.71, 0.8);
uniform vec3 glow_color : source_color = vec3(0.91, 0.52, 0.35);
uniform float glow_amount = 0.0;
uniform vec3 sun_dir = vec3(0.0, 0.7, -0.7);
uniform float sky_energy = 1.0;
uniform sampler2D hdri_a : filter_linear, repeat_enable, hint_default_black;
uniform sampler2D hdri_b : filter_linear, repeat_enable, hint_default_black;
uniform sampler2D hdri_o : filter_linear, repeat_enable, hint_default_black;
uniform float hdri_rot_a = 0.0;
uniform float hdri_rot_b = 0.0;
uniform float hdri_rot_o = 0.0;
uniform float hdri_gain_a = 1.0;
uniform float hdri_gain_b = 1.0;
uniform float hdri_gain_o = 1.0;
uniform float hdri_ab = 0.0;
uniform float hdri_mix = 0.0;
uniform float hdri_o_mix = 0.0;
uniform float hdri_clamp = 48.0;

const float DEPTH_SCALE = 5e-8; // depth = DEPTH_SCALE / distance: behind the scene out to its far plane
const float CURVE = 6.8e-8; // the Earth's curvature with refraction: drop = d^2 * 0.87 / (2 * 6371 km)

const float FOG_SEEN_AT = 90.0; // the furthest the volumetric fog sees the far land: its own reach, in metres

varying vec3 world_pos;
varying float dist;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 across = w.xz - CAMERA_POSITION_WORLD.xz;
	w.y -= dot(across, across) * CURVE;
	world_pos = w;
	dist = length(w - CAMERA_POSITION_WORLD);
	vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(w, 1.0);
	clip.z = clip.w * DEPTH_SCALE / max(dist, 1.0);
	POSITION = clip;
	// the volumetric fog (rain, night) goes by the view-space distance and would bury land tens of kilometres
	// off in its own dim colour while the sky behind stays clear: it sees the far land only as far off as it reaches
	vec3 seen = CAMERA_POSITION_WORLD + (w - CAMERA_POSITION_WORLD) * min(1.0, FOG_SEEN_AT / max(dist, 1.0));
	VERTEX = (inverse(MODEL_MATRIX) * vec4(seen, 1.0)).xyz;
}

vec3 panorama(sampler2D tex, vec3 d, float rot) {
	float c = cos(rot);
	float s = sin(rot);
	vec3 r = vec3(c * d.x - s * d.z, d.y, s * d.x + c * d.z);
	vec2 uv = vec2(atan(r.x, -r.z) / (2.0 * PI) + 0.5, acos(clamp(r.y, -1.0, 1.0)) / PI);
	return min(texture(tex, uv).rgb, vec3(hdri_clamp));
}

// The sky just above the horizon in direction d, as sky.gdshader draws it (less its stars and clouds).
vec3 sky_horizon(vec3 d) {
	d = normalize(vec3(d.x, 0.03, d.z));
	float toward_sun = max(dot(normalize(vec3(d.x, 0.0, d.z) + 1e-5), normalize(vec3(sun_dir.x, 0.0, sun_dir.z) + 1e-5)), 0.0);
	float band = exp(-d.y * 9.0) * (0.35 + 0.65 * pow(toward_sun, 3.0));
	vec3 col = mix(horizon_color, glow_color, clamp(band * glow_amount, 0.0, 1.0)) * sky_energy;
	if (hdri_mix > 0.001) {
		vec3 hd = mix(panorama(hdri_a, d, hdri_rot_a) * hdri_gain_a, panorama(hdri_b, d, hdri_rot_b) * hdri_gain_b, hdri_ab);
		col = mix(col, hd, hdri_mix);
	}
	if (hdri_o_mix > 0.001) {
		col = mix(col, panorama(hdri_o, d, hdri_rot_o) * hdri_gain_o, hdri_o_mix);
	}
	return col;
}

void fragment() {
	vec2 p = world_pos.xz;
	// COLOR.rgb is the land's own colour; COLOR.a 1 on open farmland, where fields of different crops show
	float fields = texture(grain, p * 0.0019 + 0.21).r;
	float shade = texture(grain, p * 0.0007 + 0.6).r;
	vec3 crop = fields < 0.4 ? field_a : (fields < 0.62 ? field_b : field_c);
	vec3 col = mix(COLOR.rgb, crop, COLOR.a * 0.8) * (0.82 + 0.36 * shade);
	// UV.y is 1 in towns: blocks of roofs, streets and gardens rather than one flat sheet
	float blocks = texture(grain, p * 0.011 + 0.37).r;
	float roofs = texture(grain, p * 0.043 + 0.81).r;
	vec3 town = col * (0.62 + 0.75 * roofs);
	town = mix(town, vec3(0.2, 0.27, 0.16), smoothstep(0.62, 0.72, blocks) * 0.7);
	col = mix(col, town, UV.y);
	// towns light up at night: points of street and window light, merging into a glow too far to pick out
	float park = smoothstep(0.62, 0.72, blocks);
	float lamps = smoothstep(0.66, 0.74, texture(grain, p * 0.21 + 0.13).r);
	float lit = UV.y * (1.0 - park) * mix(lamps, 0.12, smoothstep(2500.0, 9000.0, dist)) * night;
	EMISSION = vec3(1.0, 0.72, 0.42) * lit * 2.4;
	ALBEDO = col * mix(1.0, 0.78, wet);
	// UV.x is 1 on the open sea: a smooth surface that catches the sky
	ROUGHNESS = mix(0.95, 0.2, UV.x);
	SPECULAR = mix(0.15, 0.5, UV.x);
	// haze: as the scene's fog near the circuit, much thinner per metre beyond, and thinner over the peaks
	float near = min(dist, haze_reach);
	float far = max(dist - haze_reach, 0.0) * haze_beyond;
	float lift = max(world_pos.y - CAMERA_POSITION_WORLD.y, 0.0);
	float haze = 1.0 - exp(-(haze_density * (near + far) + mist * near) * mix(1.0, 0.55, smoothstep(0.0, 1500.0, lift)));
	// near the circuit the haze is the scene's fog; far off it becomes the sky behind the hills
	vec3 sky = sky_horizon(world_pos - CAMERA_POSITION_WORLD);
	vec3 tint = mix(haze_color, sky, mix(aerial, 1.0, smoothstep(haze_reach, 25000.0, dist)));
	FOG = vec4(tint, clamp(haze, 0.0, 0.97) * (1.0 - 0.5 * min(lit * 4.0, 1.0))); // lights show through the haze
}
