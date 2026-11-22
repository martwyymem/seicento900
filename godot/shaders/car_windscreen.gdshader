// The windscreen (the model's Windscreen mesh): the car's tinted glass (as race_car_visual.gd's Glass material) that a
// frontal crash cracks. Per car (instance uniforms, RaceCarVisual): crack 0 whole .. 1 a spider web across the screen ..
// 1.3 frosted white (the laminate crazed all over), grown from crack_at, the model-space point of the first blow.
// The environment reflection (car_coat.gdshader) is added as the next pass.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
#include "res://shaders/car_damage.gdshaderinc"

uniform vec4 tint : source_color = vec4(0.01, 0.014, 0.018, 0.56);
instance uniform float crack : instance_index(5) = 0.0;
instance uniform vec3 crack_at : instance_index(6) = vec3(0.0, 1.0, -0.8);

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

float h1(float n) {
	return fract(sin(n * 91.345) * 47453.5453);
}

void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = tint.a;
	ROUGHNESS = 0.02;
	SPECULAR = 0.6;
	if (crack > 0.001) {
		// on the glass, round the blow: u across the car, v up the screen
		vec3 d = lp - crack_at;
		vec2 q = vec2(d.x, length(d.yz) * sign(d.y));
		float r = length(q);
		float reach = crack * 0.85;
		float aa = fwidth(r) + 1e-4;
		// radial cracks: a dozen jagged spokes of different lengths
		float a = atan(q.y, q.x) / 6.2831853 + 0.5;
		float n = 13.0;
		float k = floor(a * n);
		float wob = 0.35 * (h1(k) - 0.5) + 0.06 * sin(r * 60.0 + k * 3.0);
		float off = abs(fract(a * n) - 0.5 - wob * 0.6) * 6.2831853 / n * r; // metres from the spoke
		float spoke_len = reach * (0.45 + 0.55 * h1(k + 7.0));
		float spokes = (1.0 - smoothstep(0.0008, 0.0008 + aa * 1.5, off)) * (1.0 - smoothstep(spoke_len * 0.8, spoke_len, r));
		// rings joining the spokes, a geometric series out from the blow, broken between spokes
		float g = log(max(r, 0.004) / 0.02) / log(1.55);
		float ring_off = abs(fract(g + 0.3 * h1(k + 3.0)) - 0.5) * r * 0.44;
		float ring = (1.0 - smoothstep(0.0007, 0.0007 + aa * 1.5, ring_off)) * step(0.45, h1(k * 1.7 + floor(g)))
			* (1.0 - smoothstep(reach * 0.55, reach * 0.7, r));
		// the crushed star at the blow and a frost of fine crazing over the whole screen past crack 1
		float star = 1.0 - smoothstep(0.012, 0.03 + 0.02 * crack, r);
		float frost = smoothstep(1.0, 1.3, crack);
		float craze = crack_lines(lp.xz + lp.yy * 0.7, 55.0) * frost;
		float c = clamp(max(max(spokes, ring * 0.8), max(star * 0.9, craze * 0.7)), 0.0, 1.0);
		vec3 white = vec3(0.86, 0.88, 0.9);
		ALBEDO = mix(ALBEDO, white, max(c, frost * 0.55));
		ALPHA = mix(ALPHA, 0.92, max(c * 0.9, frost * 0.75));
		ROUGHNESS = mix(ROUGHNESS, 0.55, max(c, frost * 0.7));
	}
}
