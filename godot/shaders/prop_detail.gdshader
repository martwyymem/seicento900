// Surface detail for the Blender prop kits (furniture, town, roadside, landmarks): concrete pores and rain
// streaks, wood grain and planks, brushed or rusting steel, brick and stone courses, roof tiles, plaster,
// rubber, straw and painted metal. It keeps the model's own colour (base factor x vertex colour) and adds
// albedo, roughness and a screen-space bump on top, projected from the dominant axis of the object-space
// position, so the detail is metric (1 unit = 1 m) and sticks to a prop however it is placed.
// prop_detail.gd swaps it in for the matching StandardMaterial3D by material name.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D grain : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 base_color : source_color = vec4(1.0);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.8;
uniform float base_metallic : hint_range(0.0, 1.0) = 0.0;
uniform bool use_vertex_color = true;
uniform int kind = 0; // 1 concrete, 2 wood, 3 steel, 4 stone, 5 brick, 6 tiles, 7 rubber, 8 paint/plaster, 9 straw, 10 copper
uniform float amount : hint_range(0.0, 2.0) = 1.0;
uniform float bump_strength : hint_range(0.0, 2.0) = 0.6;

varying vec3 obj_pos;
varying vec3 obj_normal;
varying vec3 v_tint;

void vertex() {
	obj_pos = VERTEX;
	obj_normal = NORMAL;
	v_tint = use_vertex_color ? COLOR.rgb : vec3(1.0);
}

float n2(vec2 p) {
	return texture(grain, p).r;
}

// the plane of the dominant axis: x = across, y = along height where the face is vertical
vec2 dominant_plane(vec3 p, vec3 n) {
	vec3 a = abs(n);
	if (a.y > a.x && a.y > a.z) {
		return p.xz;
	}
	if (a.x > a.z) {
		return p.zy;
	}
	return p.xy;
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec3 col = base_color.rgb * v_tint;
	float rough = base_roughness;
	float metal = base_metallic;
	vec2 uv = dominant_plane(obj_pos, obj_normal);
	bool vertical = abs(obj_normal.y) < 0.6;
	float h = 0.0; // height for the bump
	float lum = dot(col, vec3(0.333));
	float px = length(fwidth(uv)); // metres per pixel: detail finer than a few pixels is dropped
	float fine_fade = 1.0 - smoothstep(0.004, 0.02, px);
	float mid_fade = 1.0 - smoothstep(0.02, 0.12, px);

	if (kind == 1) { // concrete: pores, cloudy tone, rain streaks running down walls, a damp base
		float cloud = n2(uv * 0.35) - 0.5;
		float fine = n2(uv * 3.1) - 0.5;
		float pores = smoothstep(0.62, 0.72, n2(uv * 7.3 + 0.4));
		float streak = vertical ? smoothstep(0.45, 0.75, n2(vec2(uv.x * 0.8, uv.y * 0.1))) * mid_fade : 0.0;
		col *= 1.0 + (cloud * 0.35 + fine * 0.18) * amount;
		col *= 1.0 - pores * 0.22 * amount;
		col *= 1.0 - streak * 0.08 * amount;
		float damp = vertical ? smoothstep(0.5, 0.0, obj_pos.y) : 0.0;
		col *= 1.0 - damp * 0.18 * amount;
		rough = clamp(rough + fine * 0.2 - damp * 0.15, 0.0, 1.0);
		h = fine * 0.5 - pores * 0.8;
	} else if (kind == 2) { // wood: long grain, planks, knots
		vec2 g = vertical ? vec2(uv.x, uv.y) : uv;
		float plank = floor(g.x / 0.14);
		float shade = hash21(vec2(plank, 3.1));
		float grain_l = n2(vec2(g.x * 11.0 + shade * 9.0, g.y * 0.55 + shade));
		float grain_f = mix(0.5, n2(vec2(g.x * 40.0, g.y * 1.8)), fine_fade);
		float seam = smoothstep(0.012, 0.0, abs(fract(g.x / 0.14) - 0.0)) + smoothstep(0.012, 0.0, abs(fract(g.x / 0.14) - 1.0));
		col *= (0.78 + 0.34 * shade) * (0.8 + 0.4 * grain_l) * (0.92 + 0.16 * grain_f);
		col *= 1.0 - seam * 0.5;
		col = mix(col, vec3(lum) * vec3(0.9, 0.95, 1.0), smoothstep(0.35, 0.8, n2(uv * 0.5 + 0.3)) * 0.25 * amount); // weathered silver patches
		rough = clamp(rough + (grain_f - 0.5) * 0.2, 0.0, 1.0);
		h = (grain_l - 0.5) * 0.7 - seam * 1.2;
	} else if (kind == 3 || kind == 10) { // steel (and copper): brushing along the part, scratches, rust bleeding from below
		float brush = mix(0.5, n2(vec2(uv.x * 0.7, uv.y * 36.0)), fine_fade);
		float scratch = smoothstep(0.7, 0.8, n2(vec2(uv.x * 1.3 + 0.2, uv.y * 17.0)));
		float rust_mask = smoothstep(0.55, 0.78, n2(uv * 1.8 + 0.7)) * (kind == 10 ? 0.0 : 1.0);
		rust_mask *= vertical ? smoothstep(2.5, 0.0, obj_pos.y) : 0.6;
		col *= 0.88 + 0.24 * brush;
		col += scratch * 0.06 * amount;
		col = mix(col, vec3(0.36, 0.17, 0.07) * (0.7 + 0.6 * n2(uv * 6.0)), rust_mask * 0.7 * amount);
		if (kind == 10) { // verdigris creeping from the lower edge of copper
			float patina = smoothstep(0.45, 0.8, n2(uv * 1.1 + 2.0)) * (vertical ? 1.0 : 0.7);
			col = mix(col, vec3(0.25, 0.5, 0.42), patina * 0.65 * amount);
			rough = mix(rough, 0.75, patina);
		}
		rough = clamp(rough + (brush - 0.5) * 0.25 + rust_mask * 0.4, 0.0, 1.0);
		metal = mix(metal, metal * 0.3, rust_mask);
		h = (brush - 0.5) * 0.25 - scratch * 0.3;
	} else if (kind == 4) { // stone: ashlar courses with joints and a mottled face
		float course = 0.32;
		float row = floor(uv.y / course);
		float off = hash21(vec2(row, 7.0)) * 1.3;
		vec2 cell = vec2((uv.x + off) / 0.62, uv.y / course);
		vec2 f = fract(cell);
		float edge = min(min(f.x, 1.0 - f.x) * 0.62, min(f.y, 1.0 - f.y) * course);
		float joint = (1.0 - smoothstep(0.006, 0.014, edge)) * (1.0 - smoothstep(0.25, 0.6, max(fwidth(cell.x), fwidth(cell.y))));
		float block = hash21(floor(cell));
		float mott = n2(uv * 2.2) - 0.5;
		col *= (0.84 + 0.28 * block) * (1.0 + mott * 0.3 * amount);
		col = mix(col, col * 0.45, joint * 0.8 * amount);
		float moss = vertical ? smoothstep(0.6, 0.0, obj_pos.y) * smoothstep(0.5, 0.75, n2(uv * 3.0 + 1.0)) : 0.0;
		col = mix(col, vec3(0.16, 0.24, 0.1), moss * 0.35 * amount);
		rough = clamp(rough + 0.1 + block * 0.1 - joint * 0.0, 0.0, 1.0);
		h = (block - 0.5) * 0.3 + mott * 0.4 - joint * 1.4;
	} else if (kind == 5) { // brick: running bond, mortar, colour per brick
		vec2 cell = vec2(uv.x / 0.25, uv.y / 0.075);
		float row = floor(cell.y);
		cell.x += mod(row, 2.0) * 0.5;
		vec2 f = fract(cell);
		vec2 e = min(f, 1.0 - f) * vec2(0.25, 0.075);
		float fade = 1.0 - smoothstep(0.35, 0.9, max(fwidth(cell.x), fwidth(cell.y)));
		float mortar = (1.0 - smoothstep(0.004, 0.009, min(e.x, e.y))) * fade;
		float b = hash21(floor(cell) + row * 3.7);
		vec3 far_col = col * vec3(0.99, 0.81, 0.72) * 0.9;
		vec3 tone = mix(vec3(0.86, 0.7, 0.62), vec3(1.12, 0.92, 0.82), b);
		col *= tone * (0.92 + 0.16 * n2(uv * 4.0));
		col = mix(col, vec3(0.62, 0.6, 0.56) * (0.8 + 0.4 * lum), mortar * amount);
		col = mix(far_col, col, fade); // far off, one averaged tone
		rough = clamp(rough + 0.1 - mortar * 0.1, 0.0, 1.0);
		h = (n2(uv * 9.0) - 0.5) * 0.3 - mortar * 1.2;
	} else if (kind == 6) { // roof tiles/shingles: rows with a bright lip and a dark gap, moss and soot
		float rowh = 0.13;
		float row = floor(uv.y / rowh);
		float fy = fract(uv.y / rowh);
		float off = hash21(vec2(row, 1.0)) * 0.3;
		float fx = fract((uv.x + off) / 0.2);
		float gap = smoothstep(0.06, 0.0, fx) + smoothstep(0.94, 1.0, fx) * 0.8;
		float tfade = 1.0 - smoothstep(0.25, 0.6, fwidth(uv.y) / rowh);
		float lip = smoothstep(0.78, 0.98, fy) * tfade;
		float t = hash21(vec2(floor((uv.x + off) / 0.2), row));
		col *= (0.82 + 0.3 * t) * (1.0 - 0.28 * smoothstep(0.0, 0.2, 0.2 - fy)) * (1.0 + 0.12 * lip);
		gap *= tfade;
		col *= 1.0 - gap * 0.3;
		float moss = smoothstep(0.58, 0.8, n2(uv * 0.9 + 0.5));
		col = mix(col, vec3(0.15, 0.22, 0.1), moss * 0.3 * amount);
		rough = clamp(rough + 0.1 + (t - 0.5) * 0.1, 0.0, 1.0);
		h = lip * 0.7 - gap * 0.9 + (t - 0.5) * 0.2;
	} else if (kind == 7) { // rubber: fine speckle, dusty, matte
		float sp = n2(uv * 14.0);
		float dust = n2(uv * 1.4 + 0.2);
		col *= 0.85 + 0.3 * sp;
		col = mix(col, vec3(0.32, 0.31, 0.3), smoothstep(0.55, 0.85, dust) * 0.25 * amount);
		rough = clamp(rough + 0.1, 0.0, 1.0);
		h = (sp - 0.5) * 0.5;
	} else if (kind == 8) { // paint and plaster: stipple, tonal cloud, dirt rising from the ground, chips on exposed edges
		float stip = n2(uv * 5.5) - 0.5;
		float cloud = n2(uv * 0.5 + 0.3) - 0.5;
		float dirt = vertical ? smoothstep(1.2, 0.0, obj_pos.y) : 0.0;
		float streak = vertical ? smoothstep(0.55, 0.8, n2(vec2(uv.x * 0.9, uv.y * 0.12))) * mid_fade : 0.0;
		float chip = smoothstep(0.72, 0.8, n2(uv * 6.0 + 4.0)) * smoothstep(1.5, 0.0, obj_pos.y);
		col *= 1.0 + (stip * 0.12 + cloud * 0.2) * amount;
		col = mix(col, col * vec3(0.55, 0.5, 0.45), dirt * 0.5 * amount);
		col *= 1.0 - streak * 0.05 * amount;
		col = mix(col, vec3(lum) * 0.5 + vec3(0.18), chip * 0.35 * amount);
		rough = clamp(rough + stip * 0.2 + dirt * 0.15, 0.0, 1.0);
		h = stip * 0.15 - chip * 0.3;
	} else if (kind == 9) { // straw: stalks
		float s1 = mix(0.5, n2(vec2(uv.x * 30.0, uv.y * 1.6)), fine_fade);
		float s2 = mix(0.5, n2(vec2(uv.x * 9.0 + 0.4, uv.y * 24.0)), fine_fade);
		col *= 0.7 + 0.5 * s1 * (0.7 + 0.6 * s2);
		rough = 0.95;
		h = (s1 - 0.5) * 0.9;
	} else {
		float g2 = n2(uv * 2.0) - 0.5;
		col *= 1.0 + g2 * 0.2 * amount;
		h = g2;
	}

	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.4;

	// screen-space bump from the height above (Mikkelsen)
	h *= mid_fade;
	if (bump_strength > 0.0) {
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		vec3 r1 = cross(dpdy, NORMAL);
		vec3 r2 = cross(NORMAL, dpdx);
		float det = dot(dpdx, r1);
		// clamped: h jumps where the projection plane switches or a plank/course starts, which would spark one pixel
		vec3 grad = sign(det) * (clamp(dFdx(h), -0.4, 0.4) * r1 + clamp(dFdy(h), -0.4, 0.4) * r2);
		NORMAL = normalize(abs(det) * NORMAL - bump_strength * 0.02 * grad);
	}
}
