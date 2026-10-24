// Sun lens flare elements (lens_flare.gd), drawn additively over the 3D picture inside the race viewport, so
// the retro styles filter it with everything else and the HUD stays on top. Each element is a small textured
// quad; whether the sun is hidden is decided per quad in the vertex stage from a few taps of the rendered
// picture round the sun (a tree, a stand, a bridge or a tunnel roof in front of it is dark, the sun white),
// so occlusion costs four texture reads per quad rather than anything per pixel.
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 sun_uv = vec2(0.5); // the sun in the viewport, 0..1
uniform vec2 tap = vec2(0.006, 0.01); // tap spread round the sun (about half the disc), in UV
uniform float lit_from = 0.72; // picture luma under the sun where the flare starts to show...
uniform float lit_full = 0.93; // ...and where it is at full strength

varying float seen;

float lit(vec2 uv) {
	vec3 c = textureLod(screen_tex, clamp(uv, vec2(0.0), vec2(1.0)), 0.0).rgb;
	return smoothstep(lit_from, lit_full, dot(c, vec3(0.2126, 0.7152, 0.0722)));
}

void vertex() {
	seen = (lit(sun_uv) * 2.0 + lit(sun_uv + vec2(tap.x, 0.0)) + lit(sun_uv - vec2(tap.x, 0.0))
		+ lit(sun_uv + vec2(0.0, tap.y)) + lit(sun_uv - vec2(0.0, tap.y))) / 6.0;
}

void fragment() {
	COLOR = texture(TEXTURE, UV) * COLOR * seen;
}
