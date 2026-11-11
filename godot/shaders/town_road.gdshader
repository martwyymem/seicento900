// Town streets of the open world (town_builder.gd): asphalt with Polish markings, granite setts or concrete
// slabs, or a gravel track, worn wheel tracks and tar repairs, darker and glossy in the rain.
// Vertex data: UV.x = metres right of the centreline, UV.y = metres along the road;
// UV2.x = half the road's width, UV2.y = marking style (0 none, 1 dashed centre, 2 centre + edge lines,
// 3 carriageway: lane lines + edge lines); COLOR.r = how much of the marking shows (0 at junctions),
// COLOR.g = surface (0 asphalt, 0.5 setts or slabs, 1 gravel), COLOR.b = lanes / 8, COLOR.a = 1 one way.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 asphalt_color : source_color = vec3(0.19, 0.195, 0.205);
uniform vec3 asphalt_old_color : source_color = vec3(0.3, 0.3, 0.3);
uniform vec3 sett_color : source_color = vec3(0.42, 0.4, 0.38);
uniform vec3 gravel_color : source_color = vec3(0.5, 0.45, 0.36);
uniform vec3 paint_color : source_color = vec3(0.93, 0.93, 0.9);
uniform float wet = 0.0;
uniform float rain = 0.0;
uniform float night : hint_range(0.0, 1.0) = 0.0; // after dark the wet road mirrors the lamps
uniform float snow : hint_range(0.0, 1.0) = 0.0;
// tools/build_surface_textures.py: micro (1 m: R aggregate tone, GB normal, A sparkle), macro (4 m: R cloud, G cracks, B stains, A pores)
uniform sampler2D surf_micro : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D surf_macro : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grain : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grain_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_textures = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tex_scale = 0.25;
// TownMap.pothole_texture(): per 3 m cell a rank, the hole's centre and its radius (the car drops into the same ones)
uniform sampler2D potholes : filter_nearest, repeat_enable;

varying vec3 world_pos;
varying flat float v_style;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_style = UV2.y;
}

// a painted band of width w centred on x = c, anti-aliased
float band(float x, float c, float w) {
	float d = abs(x - c);
	float aa = fwidth(x) * 1.5 + 0.004; // an edge a pixel and a half wide: stable under a jittered (temporal) projection
	return 1.0 - smoothstep(w * 0.5 - aa, w * 0.5 + aa, d);
}

void fragment() {
	float x = UV.x;
	float s = UV.y;
	float half_w = UV2.x;
	float show = COLOR.r;
	float surf = COLOR.g;
	float lanes = max(1.0, floor(COLOR.b * 8.0 + 0.5));
	bool oneway = COLOR.a > 0.5;
	vec2 p = world_pos.xz;
	float g1 = texture(grain, p * 0.37).r;
	float g2 = texture(grain, p * 0.043).r;
	float g3 = texture(grain, p * 2.9).r;
	float px = length(fwidth(p)); // metres per pixel: detail finer than a pixel fades out instead of shimmering
	vec3 col;
	float rough = 0.88;
	vec3 nmap = texture(grain_normal, p * 0.9).xyz;
	float nmap_depth = 0.35;
	float spark = 0.0;
	float pores = 0.5;
	float crack = 0.0;
	float seam = 0.0;
	float wheel_zone = 0.0;
	float gutter = 0.0;
	vec3 micro_n = vec3(0.0);
	if (surf < 0.25) {
		col = asphalt_color;
		if (use_textures) {
			col = mix(col, texture(albedo_tex, p * tex_scale).rgb * 0.75, 0.45);
			nmap = texture(normal_tex, p * tex_scale).xyz;
			nmap_depth = 0.45;
		}
		// aggregate: pale stones against dark binder, a tangent normal and rare glints (mipmaps average them away)
		vec4 mi = texture(surf_micro, p);
		vec4 mi2 = texture(surf_micro, mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 0.41 + 0.27);
		micro_n = vec3(mi.gb - 0.5, 0.0) + vec3(mi2.gb - 0.5, 0.0) * 0.6;
		spark = mi.a;
		// cloudy older and newer surface, cracks, stains
		vec4 ma = texture(surf_macro, p * 0.25);
		vec4 mb = texture(surf_macro, mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p * 0.093 + 0.41);
		pores = ma.a;
		float cloud = ma.r * 0.6 + mb.r * 0.4;
		col *= 0.8 + 0.4 * cloud;
		col *= 0.62 + 0.8 * mi.r;
		col *= 1.22;
		col *= 0.9 + 0.2 * (g1 - 0.5) + 0.06 * (g3 - 0.5);
		// sun-bleached older surface in patches (soft, not blotches), darker tar repairs
		float old = smoothstep(0.58, 0.85, g2);
		col = mix(col, asphalt_old_color * (0.8 + 0.3 * mi.r), old * 0.22);
		// cracks open in the worn zones: along the edges and the wheel tracks first
		float worn = smoothstep(0.35, 0.7, mb.r + 0.25 * smoothstep(half_w - 1.8, half_w, abs(x)));
		crack = max(ma.g, mb.g * 0.8) * worn * (1.0 - smoothstep(0.012, 0.06, px));
		// patches: each its own age, with a sealed seam all round
		vec2 pc = vec2(s / 9.0, (x + half_w) / (half_w * 0.7));
		vec2 pid = floor(pc);
		vec2 pf = fract(pc);
		float pick = hash12(pid + 13.0);
		vec2 plo = vec2(0.08, 0.08) + 0.25 * vec2(hash12(pid + 2.0), hash12(pid + 3.0));
		vec2 phi = vec2(0.92, 0.92) - 0.25 * vec2(hash12(pid + 5.0), hash12(pid + 7.0));
		float inside = step(0.9, pick) * step(plo.x, pf.x) * step(pf.x, phi.x) * step(plo.y, pf.y) * step(pf.y, phi.y);
		inside *= step(abs(x), half_w - 0.3);
		vec2 pm = pf * vec2(9.0, half_w * 0.7);
		vec2 rim = min(pm - plo * vec2(9.0, half_w * 0.7), phi * vec2(9.0, half_w * 0.7) - pm);
		float patch_aa = length(fwidth(pm));
		seam = inside * (1.0 - smoothstep(0.03, 0.03 + patch_aa * 1.5 + 0.02, min(rim.x, rim.y))) * (1.0 - smoothstep(0.1, 0.4, patch_aa));
		float fresh = hash12(pid + 21.0);
		col = mix(col, col * mix(0.62, 1.15, fresh), inside * 0.9);
		rough = mix(rough, 0.78, inside * 0.5);
		crack *= 1.0 - inside;
		// the cars' wheels polish two darker, oilier tracks in each lane
		wheel_zone = exp(-pow((abs(abs(x) - half_w * 0.5) - 0.78) / 0.4, 2.0)) * step(half_w, 5.6);
		float oil = smoothstep(0.35, 0.8, ma.b) * (0.5 + wheel_zone);
		col *= 1.0 - 0.16 * wheel_zone - 0.35 * oil * 0.5;
		rough -= 0.1 * wheel_zone + 0.12 * oil;
		// the gutter along each kerb: a grimy dark strip with dust and grit heaped at its edge
		float ea = abs(x) - (half_w - 0.75);
		gutter = smoothstep(0.0, 0.25, ea) * (1.0 - smoothstep(0.55, 0.75, ea));
		col *= 1.0 - 0.28 * gutter * (0.6 + 0.4 * pores);
		float grit_edge = smoothstep(half_w - 0.4, half_w - 0.05, abs(x));
		col = mix(col, gravel_color * 0.5 * (0.7 + 0.5 * mi.r), grit_edge * smoothstep(0.38, 0.7, pores + 0.3 * g3) * 0.7);
		rough += 0.06 * gutter;
		col *= 1.0 - 0.1 * smoothstep(1.5, 0.0, half_w - abs(x)) * (1.0 - old);
	} else if (surf < 0.75) {
		// setts in courses (ul. Dworcowa's old cobbles, the yards): stones about 0.12 x 0.18 m
		vec2 q = vec2(s / 0.18, x / 0.12);
		q.x += step(1.0, mod(floor(q.y), 2.0)) * 0.5;
		vec2 f = fract(q);
		float joint = smoothstep(0.0, 0.12, f.x) * smoothstep(1.0, 0.88, f.x) * smoothstep(0.0, 0.14, f.y) * smoothstep(1.0, 0.86, f.y);
		float stone = hash12(floor(q));
		col = sett_color * (0.75 + 0.4 * stone) * mix(0.45, 1.0, joint);
		rough = 0.8;
		nmap_depth = 0.8;
	} else {
		col = gravel_color * (0.7 + 0.45 * g1 + 0.2 * g3);
		// the two wheel ruts and the grass between them
		float rut = band(x, half_w * 0.45, 0.7) + band(x, -half_w * 0.45, 0.7);
		col *= 1.0 - 0.15 * rut;
		float middle = band(x, 0.0, 0.6) * smoothstep(0.4, 0.7, g3);
		col = mix(col, vec3(0.2, 0.3, 0.12), middle * 0.7);
		float verge = smoothstep(half_w - 0.5, half_w + 0.1, abs(x));
		col = mix(col, vec3(0.22, 0.32, 0.13), verge * 0.8);
		rough = 0.95;
		nmap_depth = 1.0;
	}

	// markings (asphalt only), worn where wheels cross them
	if (surf < 0.25 && v_style > 0.5) {
		float wear = 0.78 + 0.22 * smoothstep(0.25, 0.6, g1);
		float m = 0.0;
		if (v_style < 1.5) {
			// a dashed centre line: 3 m dashes, 6 m gaps
			m = band(x, 0.0, 0.12) * step(fract(s / 9.0), 0.333);
		} else if (v_style < 2.5) {
			m = band(x, 0.0, 0.12) * step(fract(s / 12.0), 0.333);
			m = max(m, band(abs(x), half_w - 0.35, 0.18));
		} else {
			// carriageway: dashed lane lines, a solid line on either edge
			float lane_w = (2.0 * half_w - 1.2) / lanes;
			for (float k = 1.0; k < 4.0; k += 1.0) {
				if (k < lanes) {
					m = max(m, band(x, -half_w + 0.6 + k * lane_w, 0.15) * step(fract(s / 18.0), 0.333));
				}
			}
			m = max(m, band(abs(x), half_w - 0.45, 0.25));
		}
		// the paint wears through to the aggregate where the wheels cross it, and its edges are ragged
		float chip = smoothstep(0.3, 0.62, pores + 0.35 * (spark * 0.0 + g3 - 0.5));
		float paint_a = m * show * wear * mix(0.55, 1.0, chip) * (1.0 - 0.5 * wheel_zone);
		col = mix(col, paint_color * (0.88 + 0.12 * g3), paint_a);
		rough = mix(rough, 0.55, paint_a);
		spark *= 1.0 - paint_a;
	}

	// potholes on the lesser streets: broken through to the base, a crumbled lighter rim
	float pot = 0.0;
	if (surf < 0.25 && v_style < 1.5) {
		vec2 pc = floor(p / 3.0);
		vec4 pt = texelFetch(potholes, ivec2(mod(pc, 128.0)), 0);
		if (pt.r < 0.12 * (v_style < 0.5 ? 1.0 : 0.4)) {
			vec2 c = (pc + 0.25 + pt.gb * 0.5) * 3.0;
			float r = 0.3 + 0.3 * pt.a;
			float d = length(p - c) + (g3 - 0.5) * 0.1;
			float far = 1.0 - smoothstep(0.12, 0.35, px);
			pot = (1.0 - smoothstep(r * 0.55, r * 0.8, d)) * far;
			float rim = (1.0 - smoothstep(r * 0.8, r * 1.3, d)) * (1.0 - pot) * far;
			col = mix(col, col * 0.55, rim * 0.7); // broken, tar-dark edge
			// the far wall of the hole is in shade, the floor is dirt and loose stone
			float wall = smoothstep(r * 0.2, r * 0.8, d) * clamp(0.5 + 0.5 * normalize(p - c + 1e-4).y, 0.0, 1.0);
			col = mix(col, vec3(0.055, 0.045, 0.032) * (0.7 + 0.6 * g1) * (1.0 - 0.75 * wall), pot);
			rough = mix(rough, 1.0, pot);
			spark *= 1.0 - pot;
		}
	}

	// cracks and seams: dark, matte
	float sealed = max(seam, 0.0);
	col = mix(col, col * 0.35, clamp(crack * 0.62 + sealed * 0.8, 0.0, 1.0) * (1.0 - float(surf > 0.25)));
	rough = mix(rough, 0.9, clamp(crack + sealed, 0.0, 1.0));

	// rain: darker, glossier, with standing water in the dips of the wheel tracks and along the gutters
	float dip = clamp(smoothstep(0.62, 0.8, g2) + 0.55 * gutter + 0.35 * wheel_zone * smoothstep(0.4, 0.6, pores), 0.0, 1.0);
	float puddle = wet * smoothstep(0.35, 0.8, dip) * (1.0 - smoothstep(half_w - 0.3, half_w, abs(x)));
	puddle = max(puddle, wet * pot); // the holes fill first
	float w = wet * (surf < 0.75 ? 1.0 : 0.85);
	col *= mix(1.0, 0.55, w);
	// a wet film is a sheen, not a mirror, and the pores keep it uneven; after dark the lamps streak across it
	rough = mix(rough, mix(0.3, 0.16, night) + 0.18 * (pores - 0.5) * 0.0, w * 0.8);
	rough = mix(rough, mix(0.04, 0.025, night), puddle);
	spark *= 1.0 - w;
	// rain rings in the puddles
	vec2 ringv = vec2(0.0);
	if (rain > 0.02 && puddle > 0.05) {
		vec2 rp = p * 4.0;
		vec2 rid = floor(rp);
		vec2 rf = fract(rp) - 0.5;
		float t = fract(TIME * 1.3 + hash12(rid) * 7.0);
		float r = length(rf + (vec2(hash12(rid + 3.1), hash12(rid + 7.7)) - 0.5) * 0.4);
		float ring = sin((r - t * 0.4) * 60.0) * smoothstep(0.04, 0.0, abs(r - t * 0.4)) * (1.0 - t) * step(hash12(rid + 1.3), 0.5);
		ringv = normalize(rf + 1e-4) * ring * 0.12 * rain * puddle;
	}
	if (snow > 0.01) {
		float wheel = band(x, half_w * 0.5, 1.2) + band(x, -half_w * 0.5, 1.2);
		col = mix(col, vec3(0.9, 0.92, 0.96), snow * (0.95 - 0.55 * clamp(wheel, 0.0, 1.0)));
	}
	// the aggregate's own relief, flattened under water; sparkle: a few stones catch the light
	float flat_k = clamp(w * 0.55 + puddle * 0.45, 0.0, 1.0);
	vec2 bump = (nmap.xy - 0.5) * nmap_depth + micro_n.xy * 1.1 * (1.0 - 0.8 * flat_k);
	// under the lamps after dark every glinting stone and facet of the aggregate twinkles as the car moves (worse
	// through a temporal upscaler): the sparkle goes and the relief flattens with the night and with distance
	spark *= 1.0 - night;
	float px_fade = (1.0 - smoothstep(0.004, 0.02, px) * 0.85) * (1.0 - 0.6 * night);
	bump = bump * px_fade + ringv;
	float spec_k = 0.4 + 0.3 * w;
	rough = mix(rough, 0.3, spark * 0.7 * (1.0 - flat_k));
	spec_k += spark * 0.4;
	ALBEDO = col;
	// only real rain makes a mirror: the night's dew under the lamps and headlights keeps a matte floor, or every
	// facet of the surface throws a sub-pixel glint that a temporal upscaler turns into flicker
	ROUGHNESS = clamp(rough, mix(0.42, 0.02, smoothstep(0.3, 0.6, wet)), 1.0);
	SPECULAR = spec_k;
	NORMAL_MAP = vec3(0.5 + bump.x, 0.5 + bump.y, 1.0);
	NORMAL_MAP_DEPTH = 1.0;
}
