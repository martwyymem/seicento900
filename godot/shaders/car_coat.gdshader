// A clear coat's mirror: an alpha-blended pass over the paint (and, with other uniforms, the glass and the lamp lenses)
// that adds what a glossy surface would reflect, with a Fresnel weight: the sky's gradient, a crisp horizon, a broken
// skyline of trees and houses just above it, dark ground below it and a hard glint of the sun. The sky radiance map
// alone is too soft for that, and this is what makes a car read as a hard glossy object. It is kept out of the panel
// gaps (vertex colour), fades with distance, with night (set_night) and on damaged paint (the per-car "coat" uniform).
// Drawn by race_car_visual.gd, which keeps sky_*, ground, sun_* in step with the world.
shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_back, fog_disabled, shadows_disabled;

uniform vec3 sky_top : source_color = vec3(0.38, 0.56, 0.82);
uniform vec3 sky_horizon : source_color = vec3(0.78, 0.84, 0.9);
uniform vec3 ground : source_color = vec3(0.06, 0.06, 0.065); ///< the road and verge the paint mirrors below the horizon
uniform vec3 sun_dir = vec3(0.42, 0.78, 0.46);                  ///< towards the sun, world space
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_power = 1.0;
uniform float strength = 0.65;  ///< overall weight (set_night lowers it after dark)
uniform float f0 = 0.07;        ///< reflectance face-on: 0.04 is bare clear coat, more for glass and lenses
uniform float skyline = 1.0;    ///< 0 hides the trees and houses
uniform float exposure = 1.7;   ///< the real sky is far brighter than the screen's white, so the mirror is too
uniform float use_vertex_color = 1.0;
instance uniform float coat = 1.0;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	vec3 r = (INV_VIEW_MATRIX * vec4(reflect(-v, n), 0.0)).xyz;
	float nv = clamp(dot(n, v), 0.0, 1.0);
	float F = f0 + (1.0 - f0) * pow(1.0 - nv, 5.0);
	float h = r.y;

	// the sky: horizon haze up into the zenith blue
	vec3 sky = mix(sky_horizon, sky_top, smoothstep(0.0, 0.75, h));
	sky = mix(sky, vec3(dot(sky, vec3(0.3, 0.59, 0.11))), 0.45); // a lacquer mirrors hazy white more than the saturated blue
	// a broken skyline (world-fixed, so it slides along the panels as the car turns)
	float az = atan(r.x, r.z);
	float sk = 0.03 + 0.016 * sin(az * 3.0 + 1.0) + 0.012 * sin(az * 7.0 + 2.3) + 0.010 * sin(az * 17.0 + 0.4) + 0.008 * sin(az * 31.0);
	sk = max(sk, 0.0) * skyline;
	vec3 dark = mix(ground * 1.8, sky_horizon * 0.25, 0.55);
	vec3 up = mix(dark, sky, smoothstep(sk, sk + 0.012, h));
	// below the horizon the ground, darker the further it tips down, lifted a little by the haze at the line itself
	vec3 down = ground * mix(1.6, 0.6, smoothstep(0.0, -0.7, h)) + sky_horizon * 0.10 * exp(h * 18.0);
	vec3 env = mix(down, up, smoothstep(-0.006, 0.006, h));

	// the sun: a tight disc and a wider glare, hard to see through the paint's roughness only at grazing angles
	float sd = max(dot(r, normalize(sun_dir)), 0.0);
	env += sun_color * (pow(sd, 1200.0) * 60.0 + pow(sd, 90.0) * 1.2) * sun_power;

	float fade = 1.0 - smoothstep(60.0, 160.0, length(VERTEX));
	float vc = mix(1.0, COLOR.r, use_vertex_color);
	float a = clamp(F * strength * coat * fade * vc, 0.0, 1.0);
	ALBEDO = env * exposure;
	ALPHA = a;
}
