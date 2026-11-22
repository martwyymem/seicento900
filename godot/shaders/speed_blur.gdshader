shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float strength : hint_range(0.0, 1.0) = 0.0;

// Radial speed blur from just above the screen centre (the vanishing point ahead): the middle stays sharp and the
// edges streak towards the viewer, with a faint darkening at the rim as a fast lens has.
void fragment() {
	vec2 d = SCREEN_UV - vec2(0.5, 0.46);
	float r = length(d);
	float edge = smoothstep(0.08, 0.7, r);
	vec2 step_uv = d * strength * 0.011 * edge;
	vec3 c = vec3(0.0);
	float w = 0.0;
	for (int i = 0; i < 12; i++) {
		float k = float(i);
		float wk = 1.0 - k * 0.06;
		c += texture(screen_tex, SCREEN_UV - step_uv * k).rgb * wk;
		w += wk;
	}
	c /= w;
	c *= 1.0 - 0.22 * strength * smoothstep(0.35, 0.8, r);
	COLOR = vec4(c, 1.0);
}
