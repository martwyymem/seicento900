// Pavements and kerbs of the open world (town_builder.gd _build_pavements): concrete slabs or interlocking paving
// in courses along the pavement, dark joints with weeds, stains and cracks, a granite kerb in stone lengths,
// darker and glossy in the rain.
// Vertex data: COLOR = the tone (the kerb face is lighter than a plain face); UV = the pavement's course direction (cos, sin)
// on the top, (0, 0) on the vertical faces. The top is told from the sides by its normal.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform float wet = 0.0;
uniform float rain = 0.0;
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform float snow : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D grain : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D surf_micro : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D surf_macro : filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec2 course_dir;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	course_dir = UV;
}

// 1 on a joint of width w between cells of a unit grid, antialiased
float joint(vec2 f, vec2 cell_m, float w, vec2 fw_m) {
	vec2 e = min(f, 1.0 - f) * cell_m;
	vec2 aa = fw_m + 0.0015;
	vec2 j = 1.0 - smoothstep(vec2(w * 0.5) - aa, vec2(w * 0.5) + aa, e);
	return max(j.x, j.y);
}

void fragment() {
	vec3 base = COLOR.rgb;
	vec3 n = normalize(world_normal);
	bool top = n.y > 0.5;
	vec2 p = world_pos.xz;
	vec4 mi = texture(surf_micro, p);
	vec4 ma = texture(surf_macro, p * 0.25);
	float g2 = texture(grain, p * 0.05).r;
	float px = length(fwidth(p));
	vec3 col = base;
	float rough = 0.85;
	float spark = 0.0;
	vec2 bump = vec2(0.0);
	float dirt = 0.0;
	float weeds = 0.0;
	if (top) {
		// the pavement's own axes: along its longest edge and across it
		vec2 d = length(course_dir) > 0.1 ? normalize(course_dir) : vec2(1.0, 0.0);
		vec2 q = vec2(dot(p, d), dot(p, vec2(-d.y, d.x)));
		// the surface type changes from one stretch to the next (12 m cells): slabs, or small paving blocks
		vec2 region = floor(p / 14.0);
		float kind = hash12(region + 7.0);
		vec2 fwq = vec2(length(vec2(dFdx(q.x), dFdy(q.x))), length(vec2(dFdx(q.y), dFdy(q.y))));
		float jt;
		float tone;
		float id_h;
		if (kind < 0.6) {
			// concrete slabs, 0.35 m, a little off true
			vec2 cell = q / 0.35;
			vec2 id = floor(cell);
			vec2 f = fract(cell);
			jt = joint(f, vec2(0.35), 0.014, fwq * 0.8);
			id_h = hash12(id + 11.0);
			tone = 0.86 + 0.28 * id_h;
			// slabs are tinted slightly apart, a few stained or cracked
			col *= tone * vec3(1.0, 1.0, 0.99 + 0.02 * id_h);
			col *= 1.0 - 0.2 * step(0.93, hash12(id + 3.7)) * smoothstep(0.2, 0.8, ma.b);
			// each slab slightly dished: lighter in the middle
			vec2 c = f - 0.5;
			col *= 1.0 + 0.05 * (1.0 - dot(c, c) * 4.0) * (1.0 - smoothstep(0.1, 0.5, px));
		} else {
			// interlocking paving blocks 0.2 x 0.1 in running bond, grey, graphite and brick red mixed
			vec2 cell = vec2(q.x / 0.2, q.y / 0.1);
			float row = floor(cell.y);
			cell.x += 0.5 * mod(row, 2.0);
			vec2 id = floor(cell);
			vec2 f = fract(cell);
			jt = joint(f, vec2(0.2, 0.1), 0.01, fwq * 0.8);
			id_h = hash12(id + 5.0);
			float sel = hash12(floor(p / 3.0) + 31.0); // a few metres of one colour at a time
			vec3 grey = base * (0.9 + 0.3 * id_h);
			vec3 graphite = base * vec3(0.62, 0.62, 0.65) * (0.9 + 0.25 * id_h);
			vec3 red = vec3(0.34, 0.15, 0.11) * (0.8 + 0.4 * id_h);
			col = sel < 0.55 ? grey : (sel < 0.8 ? graphite : red);
			col = mix(col, grey, step(0.7, id_h) * 0.5);
			// blocks fade to one tone when a block is smaller than a pixel or two
			col = mix(col, base * 0.85, smoothstep(0.015, 0.05, px));
			bump.x += (f.x - 0.5) * 0.05;
		}
		float jfade = 1.0 - smoothstep(0.02, 0.07, px);
		float j = jt * jfade;
		// joints: dark, with weeds and moss in some, dirt washed into the rest
		weeds = smoothstep(0.55, 0.8, ma.a * 0.6 + g2 * 0.7) * j;
		col = mix(col, vec3(0.075, 0.07, 0.065), j * 0.85);
		col = mix(col, vec3(0.07, 0.12, 0.04), weeds * 0.55);
		dirt = smoothstep(0.45, 0.8, ma.b * 0.7 + (1.0 - g2) * 0.35);
		col *= 1.0 - 0.18 * dirt;
		// hairline cracks, tyre marks where cars have parked, aggregate in the concrete
		col *= 1.0 - 0.45 * ma.g * (1.0 - smoothstep(0.012, 0.05, px));
		col *= 0.9 + 0.2 * mi.r;
		spark = mi.a * 0.5;
		bump += (mi.gb - 0.5) * 0.7;
		rough = 0.82 - 0.1 * (1.0 - dirt) * (1.0 - j);
	} else {
		// vertical faces: the kerb is granite or concrete stone in 1 m lengths with a lip and grime at the foot
		vec2 t = vec2(-n.z, n.x);
		float u = dot(p, t);
		bool kerb_face = base.r > 0.43;
		float len = kerb_face ? 1.0 : 2.0;
		float cell = u / len;
		float f = fract(cell);
		float id_h = hash12(vec2(floor(cell), floor(dot(p, vec2(0.7, 0.3)) * 0.01)) + 17.0);
		float jx = (1.0 - smoothstep(0.004, 0.012 + px, min(f, 1.0 - f) * len)) * (1.0 - smoothstep(0.03, 0.08, px));
		vec3 stone = kerb_face ? vec3(0.52, 0.5, 0.47) * (0.85 + 0.3 * id_h) : base * (0.9 + 0.2 * id_h);
		col = mix(base, stone, 0.65);
		// speckled granite
		col *= 0.88 + 0.28 * mi.r;
		col = mix(col, vec3(0.06), jx * 0.6);
		dirt = smoothstep(0.35, 0.8, ma.b * 0.6 + 0.4 * (1.0 - g2));
		col *= 1.0 - 0.25 * dirt;
		spark = mi.a * 0.3;
		bump += (mi.gb - 0.5) * 0.5;
		rough = 0.8;
	}
	float w = wet * 0.85;
	col *= mix(1.0, 0.58, w);
	rough = mix(rough, mix(0.32, 0.2, night), w * 0.8);
	spark *= 1.0 - w;
	if (snow > 0.01) {
		col = mix(col, vec3(0.92, 0.94, 0.98), snow * 0.85 * (top ? 1.0 : 0.4));
	}
	rough = mix(rough, 0.35, spark * 0.6);
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	SPECULAR = 0.4 + 0.25 * w + spark * 0.3;
	bump *= 1.0 - smoothstep(0.004, 0.03, px) * 0.6;
	NORMAL_MAP = vec3(0.5 + bump.x, 0.5 + bump.y, 1.0);
	NORMAL_MAP_DEPTH = 1.0 - 0.6 * w;
}
