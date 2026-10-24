// Post-processing canvas_item shader for full-screen / viewport TextureRects.
// Recreates iconic retro aesthetics: PS1/90s, NFS Most Wanted (2005), GTA San Andreas (2004),
// NFS Carbon (2006), Colin McRae Rally 2.0 (2000), and Forza Horizon 1 (2012).
shader_type canvas_item;
render_mode blend_mix;

// Active post-processing style:
// 0: Modern Clean
// 1: PS1 / Retro 90s
// 2: Need for Speed: Most Wanted (2005)
// 3: Grand Theft Auto: San Andreas (2004)
// 4: Need for Speed: Carbon (2006)
// 5: Colin McRae Rally 2.0 (2000)
// 6: Forza Horizon 1 (2012)
uniform int retro_mode : hint_range(0, 6) = 0;

// Animated time (kept for scripts that drive it; the styles below are deliberately static so nothing
// crawls or swims across the picture at racing speed)
uniform float time = 0.0;

// PS1 / Retro 90s: the picture is rebuilt on a grid of about this many lines, with square pixels an
// integer number of screen pixels wide, so the blocks stay even and locked in place.
uniform float ps1_lines = 240.0;
// 1.0 is the PS1 GPU's own dither (its 4x4 table spans about half a 5-bit step either way); half of that
// keeps the sky gradients broken up without laying a screen-door mesh over flat tarmac
uniform float dither_strength = 0.5;

// Bayer 4x4 dither matrix pattern
const float BAYER_4X4[16] = float[](
	 0.0,  8.0,  2.0, 10.0,
	12.0,  4.0, 14.0,  6.0,
	 3.0, 11.0,  1.0,  9.0,
	15.0,  7.0, 13.0,  5.0
);

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
const int BLOOM_TAPS = 20;

float get_bayer_val(ivec2 p) {
	int idx = (p.x & 3) + (p.y & 3) * 4;
	return (BAYER_4X4[idx] + 0.5) / 16.0 - 0.5;
}

vec3 saturate_by(vec3 c, float s) {
	return mix(vec3(dot(c, LUMA)), c, s);
}

// gentle S-curve around mid grey; k = 0 leaves the image alone
vec3 contrast_by(vec3 c, float k) {
	return mix(c, c * c * (3.0 - 2.0 * c), k);
}

// soft highlight roll-off above k: wet glare, sky and bloom keep their shape instead of clipping flat white
vec3 shoulder(vec3 c) {
	const float k = 0.8;
	vec3 e = max(c - vec3(k), vec3(0.0));
	return min(c, vec3(k)) + e / (vec3(1.0) + e / (1.0 - k));
}

void fragment() {
	vec4 raw = texture(TEXTURE, UV);
	if (retro_mode == 0) {
		COLOR = raw;
	} else {
		vec2 texel = TEXTURE_PIXEL_SIZE;
		if (texel.x <= 0.0 || texel.y <= 0.0) {
			texel = vec2(1.0 / 1600.0, 1.0 / 900.0);
		}
		// effect radii are authored for a 900-line picture and scale with the real one
		float px = (1.0 / texel.y) / 900.0;
		vec2 to_center = UV - vec2(0.5);
		float vig = dot(to_center * vec2(1.0, 0.75), to_center * vec2(1.0, 0.75));
		vec3 col = raw.rgb;

		// Soft bloom for the styles that glow: a dense spiral of taps (no sparse cross taps, so no ghost
		// copies of cars or lines), keeping only what is brighter than the style's threshold.
		vec3 bloom = vec3(0.0);
		if (retro_mode != 1 && retro_mode != 5) {
			float threshold = retro_mode == 2 ? 0.66 : (retro_mode == 4 ? 0.60 : 0.70);
			float radius = (retro_mode == 2 ? 16.0 : 12.0) * px;
			float wsum = 0.0;
			for (int i = 0; i < BLOOM_TAPS; i++) {
				float f = (float(i) + 0.5) / float(BLOOM_TAPS);
				float a = float(i) * 2.39996;
				vec2 off = vec2(cos(a), sin(a)) * sqrt(f) * radius;
				vec3 tap = texture(TEXTURE, UV + off * texel).rgb;
				float w = 1.0 - f * 0.6;
				bloom += tap * smoothstep(threshold, threshold + 0.3, dot(tap, LUMA)) * w;
				wsum += w;
			}
			bloom /= wsum;
		}

		// Mode 1: PS1 / Retro 90s
		// Square low-res pixels on an integer grid, 15-bit RGB555 colour with a Bayer 4x4 ordered dither
		// locked to those pixels. Each block averages the pixels under it so it holds still instead of
		// flickering between the detail it covers.
		if (retro_mode == 1) {
			vec2 screen_px = UV / texel;
			float block = max(1.0, round((1.0 / texel.y) / ps1_lines));
			vec2 cell = floor(screen_px / block);
			vec2 base = cell * block;
			vec3 acc = vec3(0.0);
			for (int y = 0; y < 2; y++) {
				for (int x = 0; x < 2; x++) {
					vec2 sp = base + (vec2(float(x), float(y)) + 0.5) * block * 0.5;
					acc += texture(TEXTURE, sp * texel).rgb;
				}
			}
			col = acc * 0.25;
			col = saturate_by(col, 1.08);
			col = contrast_by(col, 0.12);
			float dither = get_bayer_val(ivec2(cell)) * dither_strength;
			col = floor(clamp(col + vec3(dither / 31.0), 0.0, 1.0) * 31.0 + 0.5) / 31.0;
		}

		// Mode 2: Need for Speed: Most Wanted (2005)
		// The golden "Rockport" grade: colour pulled part-way to a yellow-green duotone (car paint survives),
		// punchy contrast and a big soft glow off the sky.
		else if (retro_mode == 2) {
			float l = dot(col, LUMA);
			col = mix(col, l * vec3(1.12, 1.06, 0.66), 0.4);
			col *= vec3(1.03, 1.03, 0.90);
			col = contrast_by(clamp(col, 0.0, 1.0), 0.30);
			col = shoulder(col + bloom * vec3(1.0, 0.94, 0.62) * 0.45);
			col *= 1.0 - vig * 0.45;
		}

		// Mode 3: Grand Theft Auto: San Andreas (2004)
		// A Los Santos afternoon: the PS2 colour filter (warm, lifted shadows), a touch of soft focus, and an
		// orange haze that sits on the horizon band (strongest there, thinner up the sky, gone by the near
		// road) so the tarmac, lines and cars keep their contrast instead of drowning in sepia.
		else if (retro_mode == 3) {
			vec3 soft = vec3(0.0);
			for (int i = 0; i < 6; i++) {
				float a = float(i) * 1.0472;
				soft += texture(TEXTURE, UV + vec2(cos(a), sin(a)) * 1.2 * px * texel).rgb;
			}
			col = mix(col, soft / 6.0, 0.2);
			col = col * vec3(1.08, 1.0, 0.84) + vec3(0.04, 0.026, 0.008) * (1.0 - col);
			const float HORIZON = 0.45; // where the chase camera puts the horizon, as a fraction of the height
			float haze = smoothstep(HORIZON + 0.17, HORIZON, UV.y) * (1.0 - 0.55 * smoothstep(HORIZON, 0.0, UV.y));
			vec3 haze_col = vec3(1.0, 0.78, 0.48) * 0.6;
			col = mix(col, 1.0 - (1.0 - col) * (1.0 - haze_col), haze * 0.55);
			col += bloom * vec3(1.0, 0.82, 0.55) * 0.3;
			col = saturate_by(col, 1.1);
			col = shoulder(contrast_by(clamp(col, 0.0, 1.2), 0.08));
		}

		// Mode 4: Need for Speed: Carbon (2006)
		// Cool blue-teal grade: blue in the shadows, cyan-white highlights, deep but open blacks and a
		// cold glow around lamps and sky.
		else if (retro_mode == 4) {
			float l = dot(col, LUMA);
			col = mix(col, l * vec3(0.80, 0.98, 1.18), 0.4);
			col *= vec3(0.92, 0.98, 1.06);
			col += vec3(0.0, 0.02, 0.05) * (1.0 - smoothstep(0.0, 0.5, l));
			col = contrast_by(clamp(col, 0.0, 1.0), 0.35) * 0.96;
			col = shoulder(col + bloom * vec3(0.7, 0.9, 1.1) * 0.4);
			col *= 1.0 - vig * 0.55;
		}

		// Mode 5: Colin McRae Rally 2.0 (2000)
		// The clean one: a light sharpen, rich colour and a crisp contrast curve, nothing else.
		else if (retro_mode == 5) {
			vec3 n_up = texture(TEXTURE, UV + vec2(0.0, -px) * texel).rgb;
			vec3 n_down = texture(TEXTURE, UV + vec2(0.0, px) * texel).rgb;
			vec3 n_left = texture(TEXTURE, UV + vec2(-px, 0.0) * texel).rgb;
			vec3 n_right = texture(TEXTURE, UV + vec2(px, 0.0) * texel).rgb;
			vec3 blur = (n_up + n_down + n_left + n_right) * 0.25;
			col = col + (col - blur) * 0.35;
			col = saturate_by(col, 1.18);
			col = contrast_by(clamp(col, 0.0, 1.0), 0.2);
		}

		// Mode 6: Forza Horizon 1 (2012)
		// Festival warmth: saturated, golden highlights, a gentle glow and a soft vignette.
		else if (retro_mode == 6) {
			float l = dot(col, LUMA);
			col = saturate_by(col, 1.18);
			col *= vec3(1.05, 1.0, 0.9);
			col += vec3(0.05, 0.03, 0.0) * smoothstep(0.5, 1.0, l);
			col = contrast_by(clamp(col, 0.0, 1.0), 0.18);
			col = shoulder(col + bloom * vec3(1.0, 0.86, 0.6) * 0.3);
			col *= 1.0 - vig * 0.55;
		}

		COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), raw.a);
	}
}
