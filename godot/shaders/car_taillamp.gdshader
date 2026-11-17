// The Seicento's tail-lamp lens: red moulded glass with a fine prism pattern, a hard clear-coat sheen, and a glow
// that takes over when the lamps are lit (the per-car instance uniform "glow": about 0.25 for the running lights,
// 1 for the brake lights). Found from vertex positions, because the model has no UVs. The environment reflection
// (car_coat.gdshader) is added as the next pass.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform vec3 tint : source_color = vec3(0.62, 0.012, 0.02);
uniform float cell = 190.0; // prisms per metre
// per car (CarCatalog visual "tail_lamp"; these defaults are the Seicento's): the lens's opacity unlit and lit, and a
// gain on its glow
uniform float alpha_off = 0.58;
uniform float alpha_lit = 0.74;
uniform float glow_gain = 1.0;
uniform float sheen = 1.0; // the lens's sun and sky highlights (specular and clear coat)
instance uniform float glow : instance_index(1) = 0.0;

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec2 q = lp.xy * cell;
	vec2 bump = vec2(sin(q.x * 6.2831 + lp.z * 40.0), sin(q.y * 6.2831));
	float prism = 0.5 + 0.25 * (bump.x + bump.y); // 0..1 across a facet
	float w = fwidth(q.x) + fwidth(q.y);
	float fade = 1.0 - smoothstep(0.5, 1.4, w);   // the pattern disappears with distance
	NORMAL = normalize(NORMAL + vec3(bump * 0.1 * fade, 0.0));
	float inner = 0.8 + 0.2 * prism;
	ALBEDO = tint * (0.8 + 0.4 * prism);
	ALPHA = mix(alpha_off, alpha_lit, clamp(glow, 0.0, 1.0));
	ROUGHNESS = 0.05;
	SPECULAR = sheen;
	CLEARCOAT = sheen;
	CLEARCOAT_ROUGHNESS = 0.0;
	EMISSION = vec3(1.0, 0.004, 0.0) * (glow * glow * inner * 1.7 + glow * 0.15) * glow_gain;
}
