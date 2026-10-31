// Buildings from OpenStreetMap footprints (surroundings.gd, town_builder.gd): windows, doors, cladding and
// weathering drawn from each face's own measurements, so one material serves every building.
// Vertex data: COLOR = wall (or roof) colour; UV = metres along the wall and up from its foot;
// UV2.x = the building's seed (fraction) + the wall's top height in decimetres (integer part, 0 = none),
// UV2.y = kind + 10 * face (face 0 wall, 1 roof) + 20 * the wall's length in decimetres (0 = unknown). On walls UV.x
// restarts at 0 at each wall's start, so the shader knows how far a point is from the wall's ends (corner quoins) and
// from its top (cornice) without extra geometry. Kinds (build_surroundings.py):
// 0 house, 1 flats/town, 2 industrial or large, 3 shed/garage, 4 farm, 5 church, 6 grandstand,
// 7 shops and public buildings (town_builder.gd only).
// The seed also picks the facade: some houses, farms, churches and halls are bare red brick, blocks of flats
// are prefab panels with stacked balconies, shops have a glazed ground floor under a sign band.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform float night = 0.0;
uniform float wet = 0.0;
uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform vec3 glass_color : source_color = vec3(0.24, 0.32, 0.42);
uniform vec3 frame_color : source_color = vec3(0.92, 0.91, 0.88);
// Detail textures from tools/build_building_textures.py: all cover 1.5 m, so the texel density is the same everywhere.
// building_wall: R roughcast, G smooth plaster, B concrete panel; building_brick: RGB brick tint, A mortar;
// building_roof: R tile shade, G moss, B per-tile tint. Left unset they would read as all-mortar, so set them.
uniform sampler2D tex_wall : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_brick : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_roof : filter_linear_mipmap, repeat_enable;
const float TEX_M = 1.5;

const vec3 BRICKS[4] = vec3[](vec3(0.21, 0.075, 0.05), vec3(0.16, 0.065, 0.045), vec3(0.25, 0.11, 0.07), vec3(0.15, 0.075, 0.055));
// shop sign bands and the painted accent strips on renovated blocks (linear)
const vec3 ACCENTS[6] = vec3[](vec3(0.55, 0.08, 0.05), vec3(0.05, 0.18, 0.45), vec3(0.08, 0.35, 0.12),
	vec3(0.75, 0.42, 0.03), vec3(0.42, 0.12, 0.30), vec3(0.06, 0.32, 0.36));
const vec3 CURTAINS[4] = vec3[](vec3(0.85, 0.82, 0.74), vec3(0.75, 0.55, 0.40), vec3(0.55, 0.62, 0.70), vec3(0.80, 0.78, 0.60));

varying vec3 world_pos;
varying flat float v_seed;
varying flat float v_kind;
varying flat float v_face;
varying flat float v_wall_len; // m, 0 when the generator did not say
varying flat float v_top; // m: the wall's top over the highest ground (the eave), 0 when it is not level

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float top_dm = floor(UV2.x + 0.0001);
	v_seed = UV2.x - top_dm;
	v_top = top_dm * 0.1;
	float len_dm = floor(UV2.y / 20.0 + 0.001);
	v_wall_len = len_dm * 0.1;
	float kf = UV2.y - len_dm * 20.0;
	v_face = floor(kf / 10.0 + 0.01);
	v_kind = kf - v_face * 10.0;
}

// A window grid on a wall: returns (inside window 0/1, the window's id hash, frame 0/1).
vec3 windows(vec2 uv, float bay, float storey, float w, float h, float sill, float first_row) {
	float bx = uv.x / bay;
	float row = floor((uv.y - first_row) / storey);
	vec2 f = vec2(fract(bx), fract((uv.y - first_row) / storey));
	float hw = w / bay * 0.5;
	float lo = sill / storey;
	float hi = (sill + h) / storey;
	float inside = step(0.5 - hw, f.x) * step(f.x, 0.5 + hw) * step(lo, f.y) * step(f.y, hi) * step(0.0, row)
		* step(first_row, uv.y);
	float fw = 0.08 / bay;
	float fh = 0.08 / storey;
	float frame = inside * (1.0 - step(0.5 - hw + fw, f.x) * step(f.x, 0.5 + hw - fw) * step(lo + fh, f.y) * step(f.y, hi - fh));
	return vec3(inside, hash12(vec2(floor(bx), row) + v_seed * 7.13), frame);
}

// Thin lines every `period` metres, faded out where they would shimmer (smaller than a pixel or so).
float lines(float x, float period, float width, float fw) {
	float d = abs(fract(x / period + 0.5) - 0.5) * period;
	float l = 1.0 - smoothstep(width * 0.5, width * 0.5 + fw, d);
	return l * (1.0 - smoothstep(period * 0.25, period * 0.5, fw));
}

// Running-bond brick: 1 where the mortar is.
float brick_mortar(vec2 uv, vec2 fw) {
	float course = floor(uv.y / 0.075);
	float bx = uv.x + mod(course, 2.0) * 0.125;
	return max(lines(uv.y, 0.075, 0.012, fw.y), lines(bx, 0.25, 0.012, fw.x));
}

// Glass with a sky reflection fading up the pane, a curtain behind some, a mullion, lit at random after dark.
vec3 glass(vec3 w, vec2 uv, float storey, float bay, out vec3 glow, float lit_share) {
	vec3 g = glass_color * (0.85 + 0.35 * w.y);
	float sky_fade = smoothstep(0.0, 1.0, fract((uv.y - 0.9) / storey));
	g = mix(g, g * 1.35 + vec3(0.05, 0.09, 0.15), sky_fade * 0.45);
	float curtain = step(0.45, fract(w.y * 13.7));
	g = mix(g, CURTAINS[int(fract(w.y * 31.1) * 4.0)] * 0.32, curtain * 0.55 * smoothstep(0.35, 0.75, fract((uv.y - 0.9) / storey)));
	// the mullion splitting the pane in two
	float mull = 1.0 - smoothstep(0.03, 0.05, abs(fract(uv.x / bay) - 0.5) * bay);
	g = mix(g, frame_color, mull);
	glow = vec3(1.0, 0.85, 0.6) * step(w.y, lit_share) * night * 1.6 * (1.0 - mull);
	return g;
}

void fragment() {
	vec3 base = COLOR.rgb;
	vec2 uv = UV;
	vec2 fw = fwidth(uv);
	float g = texture(grain, world_pos.xz * 0.11 + world_pos.y * 0.07).r;
	float g2 = texture(grain, world_pos.xz * 0.023 + world_pos.y * 0.019).r;
	vec3 col = base * (0.9 + 0.2 * g);
	float rough = 0.88;
	float metal = 0.0;
	vec3 glow = vec3(0.0);
	bool is_window = false;
	int kind = int(v_kind + 0.5);
	float pick = fract(v_seed * 17.31);
	// bare red brick: a fifth of houses, a third of farms, most churches, half the halls (the mine buildings)
	bool brick = v_face < 0.5 && ((kind == 0 && pick < 0.2) || (kind == 4 && pick < 0.35) || kind == 5 || (kind == 2 && pick < 0.5));
	if (brick) {
		vec3 b = BRICKS[int(fract(v_seed * 5.7) * 4.0)];
		// the baked brick texture (1.5 m = 6 bricks x 20 courses); the seed shifts it so two walls never repeat in step
		vec4 bt = texture(tex_brick, uv / TEX_M + vec2(fract(v_seed * 3.1), fract(v_seed * 7.3)));
		b *= 0.55 + 0.9 * bt.rgb;
		col = mix(b, vec3(0.42, 0.40, 0.36), bt.a * 0.75) * (0.88 + 0.24 * g);
		rough = 0.92;
	}
	if (v_face > 0.5) {
		// roofs: clay or concrete tiles in courses, flat roofs of tar paper with seams, patches and puddle stains
		if (kind == 0 || kind == 4 || kind == 5) {
			// UV is metres across and up the slope, so the 1.5 m texture's 5 courses of 0.3 m run eave to ridge
			vec4 rt = texture(tex_roof, uv / TEX_M + vec2(fract(v_seed * 5.3), 0.0));
			col *= 0.45 + 1.1 * rt.r * (0.85 + 0.3 * rt.b);
			// moss and soot gathered in patches
			col = mix(col, vec3(0.06, 0.07, 0.04), smoothstep(0.35, 0.9, rt.g * 0.6 + g2 * 0.5) * 0.35);
		} else {
			float seam = lines(uv.x + uv.y * 0.02, 1.0, 0.05, fw.x);
			col *= (0.78 + 0.3 * texture(grain, world_pos.xz * 0.05).r) * (1.0 - 0.12 * seam);
			col = mix(col, col * 0.6, smoothstep(0.6, 0.75, g2) * 0.6);
			metal = kind == 2 ? 0.1 : 0.0;
		}
		rough = 0.9;
	} else if ((kind == 2 || kind == 6) && !brick) {
		// halls: ribbed metal cladding, a band of high windows, roller doors on the ground
		float rib = lines(uv.x, 0.8, 0.12, fw.x);
		col *= 0.95 - 0.1 * rib;
		col *= 0.97 + 0.06 * step(fract(uv.y / 12.0 + v_seed), 0.5) * step(4.5, uv.y);
		metal = 0.2;
		rough = 0.55;
		vec3 w = windows(uv, 6.0, 100.0, 4.6, 1.1, 0.0, 5.2);
		if (w.x > 0.5 && uv.y < 6.3) {
			is_window = w.z < 0.5;
			col = mix(glass_color, frame_color * 0.6, w.z);
			rough = 0.15;
			glow = vec3(1.0, 0.92, 0.75) * step(w.y, 0.45) * night * 1.2 * (1.0 - w.z);
		}
		float door_x = fract(uv.x / 18.0 + v_seed);
		if (uv.y < 4.2 && door_x > 0.35 && door_x < 0.6) {
			col = base * 0.6 * (0.85 + 0.15 * lines(uv.y, 0.12, 0.03, fw.y));
		}
	} else if (kind == 2) {
		// brick halls: tall windows with arched-looking lintels, a stone sill band
		vec3 w = windows(uv, 5.0, 7.0, 2.0, 4.2, 1.6, 0.0);
		float lintel = step(abs(fract(uv.x / 5.0) - 0.5) * 5.0, 1.25) * step(abs(fract(uv.y / 7.0) - (5.95 / 7.0)) * 7.0, 0.22);
		col = mix(col, col * 0.75, lintel);
		if (w.x > 0.5) {
			is_window = w.z < 0.5;
			float pane = max(lines(uv.x, 0.5, 0.05, fw.x), lines(uv.y, 0.6, 0.05, fw.y));
			col = mix(glass_color * (0.7 + 0.4 * w.y), frame_color * 0.35, max(w.z, pane));
			rough = 0.2;
			glow = vec3(1.0, 0.9, 0.7) * step(w.y, 0.3) * night * 1.2 * (1.0 - w.z);
		}
	} else if (kind == 3) {
		if (pick < 0.45) {
			// garden sheds: vertical boards
			col *= 0.88 + 0.12 * hash12(vec2(floor(uv.x / 0.18), v_seed)) - 0.15 * lines(uv.x, 0.18, 0.02, fw.x);
			rough = 0.95;
		} else {
			// garages: a ribbed up-and-over door
			float door_x = fract(uv.x / 3.2 + v_seed);
			if (uv.y < 2.1 && door_x > 0.12 && door_x < 0.88) {
				vec3 door = ACCENTS[int(fract(v_seed * 9.3) * 6.0)] * 0.5 + base * 0.25;
				col = door * (0.9 + 0.1 * g) * (1.0 - 0.18 * lines(uv.y, 0.15, 0.02, fw.y));
				metal = 0.3;
				rough = 0.5;
			}
		}
	} else {
		bool shop = kind == 7;
		bool block = kind == 1;
		float storey = (block || shop) ? 3.0 : (kind == 5 ? 12.0 : 2.8);
		float bay = block ? 2.8 : (shop ? 3.2 : (kind == 5 ? 4.5 : 3.4));
		float ww = kind == 5 ? 1.4 : (shop ? 1.6 : 1.2);
		float wh = kind == 5 ? 6.0 : (shop ? 1.6 : 1.35);
		float first = kind == 4 ? 1.0 : (shop ? 3.0 : 0.0);
		vec3 w = windows(uv, bay, storey, ww, wh, kind == 5 ? 3.0 : 0.9, first);
		float column = floor(uv.x / bay);
		float in_row = fract((uv.y - first) / storey) * storey;
		float in_bay = abs(fract(uv.x / bay) - 0.5) * bay;
		if (block) {
			// wielka płyta: a panel joint at every floor and every two bays, a painted accent strip on some
			float joint = max(lines(uv.y, storey, 0.04, fw.y), lines(uv.x, bay * 2.0, 0.04, fw.x));
			col *= 1.0 - 0.18 * joint;
			float strip = step(0.55, pick) * step(abs(fract(column / 9.0 + v_seed) - 0.5) * 9.0, 0.6);
			col = mix(col, ACCENTS[int(fract(v_seed * 3.3) * 6.0)] * (0.8 + 0.2 * g) + col * 0.15, strip * 0.85);
			// loggias stacked in some columns: a dark recess with a solid balcony front below the window
			float loggia = step(hash12(vec2(column, v_seed * 3.1)), 0.32) * step(storey, uv.y);
			if (loggia > 0.5 && in_bay < bay * 0.47) {
				if (in_row < 1.0) {
					col = mix(col * 1.05, ACCENTS[int(fract(column * 0.37 + v_seed) * 6.0)] * 0.6, step(0.7, pick) * 0.6);
					col *= 1.0 - 0.3 * smoothstep(0.9, 1.0, in_row);
				} else {
					col = base * 0.28 + glass_color * 0.25;
					w.x = step(0.9, in_row) * step(in_row, 2.5) * step(in_bay, 0.6);
					w.z = 0.0;
				}
			}
			// the stairwell: a glass-block strip up the middle of the wall
			float stair = step(abs(fract(uv.x / (bay * 7.0) + v_seed) - 0.5) * bay * 7.0, 0.5) * step(1.5, uv.y);
			if (stair > 0.5) {
				col = vec3(0.45, 0.5, 0.5) * (0.8 + 0.2 * max(lines(uv.x, 0.2, 0.03, fw.x), lines(uv.y, 0.2, 0.03, fw.y)));
				glow = vec3(1.0, 0.9, 0.7) * night * 0.18 * step(0.4, fract(v_seed * 6.1));
				w.x = 0.0;
			}
		}
		if (shop && uv.y < 3.0) {
			// a glazed shop front under a coloured sign band, a darker pillar between the windows
			vec3 sign = ACCENTS[int(fract(v_seed * 7.7) * 6.0)];
			float pillar = step(abs(fract(uv.x / 6.0 + v_seed) - 0.5) * 6.0, 0.35);
			if (uv.y > 2.45) {
				col = mix(sign, vec3(0.95), lines(uv.y - 2.725, 10.0, 0.18, fw.y) * step(0.5, fract(uv.x / 0.9)) * 0.5);
				glow = sign * night * 0.5;
			} else if (uv.y > 0.35 && pillar < 0.5) {
				is_window = true;
				col = glass_color * 0.8 + vec3(0.04, 0.05, 0.06);
				col = mix(col, frame_color * 0.4, max(lines(uv.x, 1.5, 0.06, fw.x), step(2.35, uv.y)));
				col = mix(col, vec3(0.9, 0.85, 0.7) * 0.3, step(0.4, uv.y) * step(uv.y, 1.6) * 0.25 * g);
				glow = vec3(1.0, 0.9, 0.75) * night * (0.25 + 0.35 * step(0.5, fract(floor(uv.x / 6.0) * 0.618 + v_seed)));
				rough = 0.08;
			} else {
				col = base * 0.6;
			}
		} else if (w.x > 0.5 && (kind != 4 || w.y < 0.5)) {
			is_window = w.z < 0.5;
			bool shutter = kind == 0 && w.y > 0.82;
			vec3 lit;
			vec3 pane = glass(w, uv, storey, bay, lit, block ? 0.4 : 0.35);
			col = shutter ? base * vec3(0.55, 0.62, 0.55) * (1.0 - 0.2 * lines(uv.y, 0.1, 0.02, fw.y)) : mix(pane, frame_color, w.z);
			rough = shutter ? 0.8 : 0.12;
			glow = shutter ? vec3(0.0) : lit * (1.0 - w.z);
		} else if (!brick) {
			// plaster: a little roughcast, a light sill under every window and a lintel over it
			float sill_band = step(in_bay, ww * 0.5 + 0.08) * step(abs(in_row - 0.84), 0.06) * step(first, uv.y);
			float lintel = step(in_bay, ww * 0.5 + 0.05) * step(abs(in_row - (0.9 + wh + 0.12)), 0.1) * step(first, uv.y) * step(0.5, float(kind == 0 || kind == 4));
			// plaster from the baked texture: roughcast, smooth with trowel marks, or (on blocks) prefab concrete
			vec3 pl = texture(tex_wall, uv / TEX_M + vec2(fract(v_seed * 11.7), fract(v_seed * 5.9))).rgb;
			float variant = kind == 1 ? pl.b : (pick < 0.5 ? pl.r : pl.g);
			col *= 0.84 + 0.32 * variant;
			col = mix(col, vec3(0.82, 0.8, 0.76), sill_band * 0.8);
			col = mix(col, col * 1.1 + 0.03, lintel);
			if (kind == 1 && fract(uv.y / storey) < 0.06) {
				col *= 1.08;
			}
		} else if (w.x < 0.5) {
			// brick houses: a concrete sill under each window
			col = mix(col, vec3(0.6, 0.58, 0.55), step(in_bay, ww * 0.5 + 0.06) * step(abs(in_row - 0.85), 0.05) * step(first, uv.y));
		}
		// the front door on houses and farms
		float door_x = fract(uv.x / 11.0 + v_seed);
		if ((kind == 0 || kind == 4 || kind == 5) && uv.y < 2.2 && uv.y > 0.15 && door_x > 0.46 && door_x < 0.55) {
			vec3 door = mix(vec3(0.12, 0.06, 0.03), ACCENTS[int(fract(v_seed * 4.1) * 6.0)] * 0.3, step(0.6, fract(v_seed * 2.9)));
			col = door * (0.9 + 0.2 * lines(uv.x, 0.33, 0.03, fw.x));
			rough = 0.6;
		}
	}
	if (v_face < 0.5) {
		// weathering: rain streaks running down from the top, and a stone or concrete plinth
		float streak = texture(grain, vec2(uv.x * 0.9, uv.y * 0.04 + v_seed)).r;
		col *= 1.0 - 0.12 * smoothstep(0.5, 0.8, streak) * (is_window ? 0.0 : 1.0);
		float plinth = 1.0 - step(0.55, uv.y);
		if (!is_window && kind != 3 && kind != 2) {
			col = mix(col, vec3(0.32, 0.31, 0.29) * (0.85 + 0.3 * g), plinth * 0.85);
		}
		col *= mix(0.8, 1.0, smoothstep(-0.2, 0.9, uv.y));
		// corner quoins and a cornice, read from the wall's own length and top (see the header)
		if (!is_window && v_wall_len > 2.0 && (kind == 0 || kind == 4 || kind == 5 || kind == 7) && !brick) {
			float de = min(uv.x, v_wall_len - uv.x);
			float course = floor(uv.y / 0.3);
			float qw = 0.5 + 0.22 * mod(course, 2.0);
			float quoin = (1.0 - smoothstep(qw - 0.01, qw + 0.01, de)) * step(0.55, uv.y) * step(uv.y, max(v_top, 4.0) - 0.4) * step(0.0, de) * (kind == 7 ? step(3.0, uv.y) : 1.0);
			col = mix(col, mix(vec3(0.62, 0.6, 0.56), col * 1.12, 0.35) * (0.9 + 0.2 * g) * (1.0 - 0.2 * lines(uv.y, 0.3, 0.025, fw.y)), quoin * 0.9);
		}
		if (v_top > 2.0 && !is_window && kind != 2 && kind != 3 && kind != 6) {
			float d = v_top - uv.y;
			// a lit band at the eave, the shadow it throws just below
			float band = 1.0 - smoothstep(0.2, 0.24, d);
			float shade = smoothstep(0.2, 0.26, d) * (1.0 - smoothstep(0.26, 0.55, d));
			col = col * (1.0 + 0.1 * band) * (1.0 - 0.16 * shade);
		}
	}
	col *= mix(1.0, 0.7, wet);
	ALBEDO = col;
	ROUGHNESS = mix(rough, rough * 0.5, wet);
	METALLIC = metal;
	SPECULAR = is_window ? 0.8 : 0.35;
	EMISSION = glow;
}
