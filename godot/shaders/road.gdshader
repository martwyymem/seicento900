// Circuit asphalt: aggregate grain, repair patches, a rubbered racing line and dusty edges, drying
// from the racing line outwards and gathering puddles with rain ripples when wet.
// UV.x is the lateral offset from the centreline and UV.y the distance along the lap (metres);
// UV2.x is the lateral distance from the racing line.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 base_color : source_color = vec3(0.15, 0.16, 0.17);
uniform float half_width = 6.0;
uniform float roughness_dry = 0.86;
uniform float wet = 0.0;
uniform float rain = 0.0;
uniform float snow : hint_range(0.0, 1.0) = 0.0;
uniform float rubber = 1.0;
uniform float edge_dust = 1.0;
uniform float patches = 1.0;
// close-up detail (race_world sets these per quality; 0 keeps the plain look for other callers): aggregate chips that
// fade out before they can shimmer, tar-sealed cracks, braking streaks and a crumbling edge
uniform float detail : hint_range(0.0, 1.0) = 0.0;
// town tarmac (street stages): many patch repairs with seams, alligator cracks, polished wheel tracks in each lane
// and faded paint, against the smoother circuit asphalt
uniform float street : hint_range(0.0, 1.0) = 0.0;

uniform sampler2D grain : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grain_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

uniform bool use_textures = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_rough_tex = false;
uniform float tex_scale = 0.25; // texture repeats per metre
uniform float tex_color_mix = 0.25; // 0 keeps the circuit palette, 1 uses the photo colours

varying vec3 world_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// distance to the nearest edge between Voronoi cells (approximate F2 - F1): the crack network of old tarmac
float cell_edge(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = vec2(hash12(n + g), hash12(n + g + 17.3)) * 0.85 + 0.075;
			float d = length(g + o - f);
			if (d < f1) {
				f2 = f1;
				f1 = d;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return f2 - f1;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = UV.x;
	float s = UV.y;
	vec2 wxz = world_pos.xz;
	float broad = texture(grain, wxz * 0.021).r;
	float mid = texture(grain, wxz * 0.13 + 0.37).r;
	float fine = texture(grain, vec2(d, s) * 0.55).r;
	float micro = texture(grain, vec2(d, s) * 2.4).r;

	vec3 col;
	float rough;
	vec3 nmap;
	if (use_textures) {
		vec2 tuv = vec2(d, s) * tex_scale;
		vec3 photo = texture(albedo_tex, tuv).rgb;
		col = mix(base_color * photo / max(textureLod(albedo_tex, vec2(0.5), 12.0).rgb, vec3(0.004)), photo, tex_color_mix);
		nmap = texture(normal_tex, tuv).rgb;
		rough = has_rough_tex ? texture(rough_tex, tuv).r : roughness_dry;
	} else {
		col = base_color * (0.78 + 0.44 * fine);
		nmap = texture(grain_normal, vec2(d, s) * 0.9).rgb;
		rough = roughness_dry;
	}
	// large blotches of older and newer surface
	col *= 0.72 + 0.5 * broad + 0.14 * mid;

	// metres per pixel: detail finer than a pixel fades out instead of shimmering in the distance
	float px = length(fwidth(vec2(d, s)));
	float near_chips = (1.0 - smoothstep(0.006, 0.03, px)) * detail;
	float near_grit = (1.0 - smoothstep(0.02, 0.09, px)) * detail;
	float tar = 0.0;
	float crack = 0.0;
	if (detail > 0.0) {
		// aggregate: pale stones and dark voids in the binder, then a coarser grit
		float chips = texture(grain, vec2(d, s) * 7.3 + 0.17).r;
		float voids = texture(grain, vec2(s, d) * 5.1 + 0.61).r;
		col *= 1.0 + (smoothstep(0.66, 0.74, chips) * 0.34 - smoothstep(0.34, 0.27, voids) * 0.3) * near_chips;
		float grit = texture(grain, vec2(d, s) * 1.7 + 0.43).r;
		col *= 1.0 + (grit - 0.5) * 0.24 * near_grit;
		// tar snakes: sealed cracks, thin glossy black squiggles over parts of the road
		float snake_zone = smoothstep(0.56, 0.7, texture(grain, vec2(d, s) * 0.035 + 0.27).r) * (0.6 + 0.4 * street);
		float snake_n = texture(grain, vec2(d * 0.23, s * 0.085) + 0.53).r;
		float snake_aa = fwidth(snake_n);
		tar = (1.0 - smoothstep(0.004, 0.004 + snake_aa * 1.5, abs(snake_n - 0.5))) * snake_zone * (1.0 - smoothstep(0.03, 0.14, px)) * detail;
	}
	if (street > 0.0) {
		// alligator cracking in worn zones, more of it towards the edges where the base gives way
		float worn_zone = texture(grain, vec2(d, s) * 0.05 + 0.11).r + 0.18 * smoothstep(half_width - 1.8, half_width, abs(d));
		float e = cell_edge(vec2(d, s) * vec2(1.9, 1.4));
		float e_aa = fwidth(e);
		float broken = smoothstep(0.38, 0.55, texture(grain, vec2(d, s) * 0.8 + 0.31).r); // not every edge has opened
		crack = (1.0 - smoothstep(0.014, 0.014 + e_aa * 1.5, e)) * broken * smoothstep(0.58, 0.7, worn_zone) * street * (1.0 - smoothstep(0.035, 0.11, px));
	}

	// resurfaced patches: rectangles of slightly darker, smoother tarmac; in town many more, each its own age
	// (fresh black or sun-greyed), with ragged sizes and a sealed seam round the edge
	vec2 cell_size = vec2(half_width * 0.66, 11.0);
	vec2 cell_uv = vec2(d + half_width, s) / cell_size;
	vec2 cell = floor(cell_uv);
	float patch_pick = hash12(cell);
	vec2 in_cell = fract(cell_uv);
	vec2 lo = vec2(0.12, 0.1) + street * vec2(hash12(cell + 2.7), hash12(cell + 4.1)) * vec2(-0.08, 0.35);
	vec2 hi = vec2(0.88, 0.9) - street * vec2(hash12(cell + 6.3), hash12(cell + 8.9)) * vec2(-0.08, 0.35);
	float patch_mask = step(patch_pick, 0.05 * patches * (1.0 + 3.5 * street)) * step(lo.x, in_cell.x) * step(in_cell.x, hi.x) * step(lo.y, in_cell.y) * step(in_cell.y, hi.y);
	float patch_tone = mix(0.78, mix(0.66, 1.16, hash12(cell + 5.1)), street);
	col = mix(col, col * patch_tone, patch_mask);
	rough = mix(rough, rough - 0.08, patch_mask);
	vec2 in_m = in_cell * cell_size;
	vec2 to_rim = min(in_m - lo * cell_size, hi * cell_size - in_m);
	float seam = patch_mask * (1.0 - smoothstep(0.03, 0.03 + px * 1.5, min(to_rim.x, to_rim.y))) * detail;
	crack *= 1.0 - patch_mask; // a patch is newer than the cracks round it

	// rubber laid down on the racing line
	float rl = UV2.x;
	float line = exp(-rl * rl / 1.8) * rubber;
	col = mix(col, col * 0.62, line * 0.55);
	rough = mix(rough, rough * 0.8, line);
	// braking streaks along the line: long dark smears of rubber, a few wheel widths across
	float streak = smoothstep(0.62, 0.8, texture(grain, vec2(d * 0.7, s * 0.008) + 0.9).r) * exp(-rl * rl / 5.0) * detail * rubber;
	col = mix(col, col * 0.55, streak * 0.55);
	// town roads: the cars' wheels polish two darker tracks in each lane
	float lane = abs(abs(d) - half_width * 0.5);
	float wheel = exp(-pow((lane - 0.78) / 0.34, 2.0)) * street * step(half_width, 5.5);
	col = mix(col, col * 0.78, wheel * 0.55);
	rough = mix(rough, rough - 0.12, wheel);

	// dust and marbles collecting at the edges
	float edge = smoothstep(half_width - 1.4, half_width - 0.2, abs(d)) * edge_dust;
	col = mix(col, col * 1.35 + vec3(0.03, 0.028, 0.02), edge * (0.55 + 0.45 * mid));
	// the very edge crumbles into grit and dirt, ragged in town
	float rim = smoothstep(half_width - 0.55, half_width - 0.05, abs(d));
	float crumb = smoothstep(0.5, 0.62, texture(grain, vec2(d, s) * 1.3 + 0.2).r * 0.55 + rim * 0.6) * rim * detail;
	col = mix(col, col * 0.72 + vec3(0.05, 0.045, 0.034), crumb * (0.45 + 0.55 * street));

	// wetness calculation (racing line dries first)
	float w = clamp(wet * (1.0 - line * 0.5 * (1.0 - wet)), 0.0, 1.0);

	// Painted road edge lines (bright white boundary lines giving crisp road definition)
	float edge_dist = abs(abs(d) - (half_width - 0.28));
	// with detail, an antialiased edge as wide as before: crisp up close, no stair-steps far off
	float line_aa = max(fwidth(d), 0.004);
	float edge_line = mix(smoothstep(0.09, 0.03, edge_dist), smoothstep(0.06 + line_aa, 0.06 - line_aa, edge_dist), step(0.001, detail)) * (1.0 - w * 0.35);
	// town paint: faded, scuffed through by the wheels, and gone where the road was patched
	float paint_wear = mix(1.0, (0.4 + 0.6 * smoothstep(0.3, 0.62, texture(grain, vec2(d * 2.0, s * 0.35) + 0.7).r)) * (1.0 - patch_mask * 0.85), street);
	edge_line *= paint_wear;
	col = mix(col, vec3(0.92, 0.94, 0.96) * (0.85 + 0.15 * fine), edge_line * 0.9);
	rough = mix(rough, 0.42, edge_line * 0.9);

	// Subtle dashed road centerline on standard road widths
	if (half_width >= 3.2 && half_width <= 4.2) {
		float dash_pattern = step(0.45, fract(s / 5.5));
		float center_dist = abs(d);
		float center_line = smoothstep(0.065, 0.02, center_dist) * dash_pattern * (1.0 - w * 0.4) * paint_wear;
		col = mix(col, vec3(0.90, 0.91, 0.88) * (0.85 + 0.15 * fine), center_line * 0.75);
		rough = mix(rough, 0.45, center_line * 0.75);
	}

	// Asphalt aggregate micro-specularity glint in sunlight
	float glint = pow(fine * micro, 2.0) * (0.12 + 0.28 * (1.0 - rough)) * (1.0 - detail + near_grit);

	// sealed cracks and patch seams (black, a little glossy) and open cracks (dark), through the paint
	float sealed = max(tar, seam * 0.9);
	// matte, not glossy: a shiny sealant caught the low sun as white squiggles
	col = mix(col, col * 0.4 + vec3(0.004), sealed * 0.8);
	rough = mix(rough, max(rough, 0.82), sealed);
	col *= 1.0 - crack * 0.55;
	col += vec3(0.035, 0.035, 0.038) * glint * (1.0 - w);

	// wet: standing water pools in the dips
	float pool_noise = broad * 0.7 + mid * 0.3;
	float puddle = smoothstep(0.62, 0.76, pool_noise + (w - 0.7) * 0.7 - edge * 0.05) * step(0.3, w);
	col *= mix(1.0, 0.52, w);
	col = mix(col, col * 0.8, puddle);
	rough = mix(rough, 0.3, w); // a wet sheen, not a mirror: the sky would wash the whole road out
	rough = mix(rough, 0.1, puddle);
	vec3 flat_n = vec3(0.5, 0.5, 1.0);
	nmap = mix(nmap, flat_n, w * 0.55 + puddle * 0.45);
	if (rain > 0.02 && puddle > 0.0) {
		// raindrop rings on the standing water
		vec2 rp = wxz * 4.0;
		vec2 id = floor(rp);
		vec2 f = fract(rp) - 0.5;
		float t = fract(TIME * 1.3 + hash12(id) * 7.0);
		float r = length(f + (vec2(hash12(id + 3.1), hash12(id + 7.7)) - 0.5) * 0.4);
		float ring = sin((r - t * 0.4) * 60.0) * smoothstep(0.04, 0.0, abs(r - t * 0.4)) * (1.0 - t) * step(hash12(id + 1.3), 0.5);
		nmap.xy += normalize(f + 1e-4) * ring * 0.12 * rain * puddle;
	}

	if (snow > 0.01) {
		col = mix(col, vec3(0.92, 0.94, 0.98), snow * 0.85);
	}

	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	METALLIC = 0.0;
	SPECULAR = mix(0.35, 0.42, w);
	NORMAL_MAP = nmap;
	NORMAL_MAP_DEPTH = use_textures ? 1.0 : 0.6;
}
