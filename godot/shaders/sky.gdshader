// Seicento sky: procedural gradient, sun and moon discs, drifting clouds and stars, with optional
// HDRI panoramas blended on top. race_world.gd drives every uniform from the time of day and weather.
// Each HDRI is turned about the vertical axis so its own sun lines up with the game's sun.
shader_type sky;
render_mode use_debanding;

uniform vec3 top_color : source_color = vec3(0.29, 0.44, 0.61);
uniform vec3 horizon_color : source_color = vec3(0.64, 0.71, 0.8);
uniform vec3 ground_color : source_color = vec3(0.13, 0.16, 0.13);
uniform vec3 glow_color : source_color = vec3(0.91, 0.52, 0.35);
uniform float glow_amount = 0.0;
uniform float sky_energy = 1.0;
uniform float night = 0.0;
uniform float overcast = 0.0;

uniform vec3 sun_dir = vec3(0.0, 0.7, -0.7); // toward the real sun (may be below the horizon)
uniform vec3 moon_dir = vec3(0.0, 0.6, 0.8);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.86);
uniform float sun_disc = 1.0;

uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float cloud_cover = 0.35;
uniform float cloud_speed = 0.004;
uniform vec3 cloud_lit : source_color = vec3(1.0);
uniform vec3 cloud_shade : source_color = vec3(0.55, 0.6, 0.68);
uniform float star_amount = 0.0;
uniform float cloud_opacity = 1.0;
// race_world.gd's look (the defaults keep the plain look for other callers, e.g. the open world):
uniform float cloud_paint = 0.0; // 1 = painted clouds: crisper edges, lit sun-side rims, darker bellies
uniform float halo_amount = 0.0; // a wide warm aureole round the sun
uniform float hdri_saturation = 1.0; // > 1 deepens the clear panoramas' pale blue

// HDRI layers: A and B are two clear-sky times of day, O is an overcast sky.
uniform sampler2D hdri_a : filter_linear, repeat_enable, hint_default_black;
uniform sampler2D hdri_b : filter_linear, repeat_enable, hint_default_black;
uniform sampler2D hdri_o : filter_linear, repeat_enable, hint_default_black;
uniform float hdri_rot_a = 0.0;
uniform float hdri_rot_b = 0.0;
uniform float hdri_rot_o = 0.0;
uniform float hdri_gain_a = 1.0;
uniform float hdri_gain_b = 1.0;
uniform float hdri_gain_o = 1.0;
uniform float hdri_ab = 0.0; // 0 = all A, 1 = all B
uniform float hdri_mix = 0.0; // clear HDRI over the procedural sky
uniform float hdri_o_mix = 0.0; // overcast HDRI over everything
uniform float hdri_clamp = 48.0; // keeps a raw HDRI sun from flooding reflections and bloom


float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 panorama(sampler2D tex, vec3 d, float rot) {
	float c = cos(rot);
	float s = sin(rot);
	vec3 r = vec3(c * d.x - s * d.z, d.y, s * d.x + c * d.z);
	vec2 uv = vec2(atan(r.x, -r.z) / (2.0 * PI) + 0.5, acos(clamp(r.y, -1.0, 1.0)) / PI);
	return min(texture(tex, uv).rgb, vec3(hdri_clamp));
}

vec3 procedural(vec3 d) {
	float up = d.y;
	float h = clamp(up, 0.0, 1.0);
	vec3 col = mix(horizon_color, top_color, pow(h, 0.55));
	// warm band hugging the horizon on the sun's side at dawn and dusk
	float toward_sun = max(dot(normalize(vec3(d.x, 0.0, d.z) + 1e-5), normalize(vec3(sun_dir.x, 0.0, sun_dir.z) + 1e-5)), 0.0);
	float band = exp(-abs(up) * 9.0) * (0.35 + 0.65 * pow(toward_sun, 3.0));
	col = mix(col, glow_color, clamp(band * glow_amount, 0.0, 1.0));
	// the ground side fades to a dim, horizon-tinted floor
	vec3 floor_col = mix(horizon_color * 0.62, ground_color, clamp(-up * 6.0, 0.0, 1.0));
	col = up < 0.0 ? floor_col : col;

	if (up > 0.0) {
		// stars, twinkling a little and hidden by cloud and daylight
		if (star_amount > 0.001) {
			vec3 cell = floor(d * 260.0);
			float r = hash13(cell);
			float star = step(0.9965, r) * smoothstep(0.0, 0.25, up);
			float tw = 0.7 + 0.3 * sin(TIME * (1.0 + r * 3.0) + r * 60.0);
			col += vec3(0.9, 0.93, 1.0) * star * tw * star_amount * (1.0 - overcast) * 2.5;
		}
	}
	return col;
}

// Cloud layer as (colour, coverage); drawn over both the procedural sky and the HDRIs.
vec4 clouds(vec3 d) {
	float up = d.y;
	if (up <= 0.0) {
		return vec4(0.0);
	}
	vec2 p = d.xz / (up + 0.12) * 0.22;
	vec2 wind = vec2(TIME * cloud_speed, TIME * cloud_speed * 0.35);
	float n = texture(cloud_noise, p + wind).r * 0.65 + texture(cloud_noise, p * 2.7 - wind * 1.6).r * 0.35;
	float cover = mix(cloud_cover, 0.92, overcast);
	float paint = cloud_paint * (1.0 - overcast);
	float dens = smoothstep(1.0 - cover, 1.0 - cover + mix(0.32, 0.16, paint), n) * smoothstep(0.0, 0.12, up);
	float lit = clamp(0.55 + 0.45 * dot(normalize(vec3(d.x, 0.0, d.z) + 1e-5), normalize(vec3(sun_dir.x, 0.0, sun_dir.z) + 1e-5)), 0.0, 1.0);
	// painted: thin edges catch the light, thick cores and the side away from the sun go to the shade colour
	float core = smoothstep(1.0 - cover + 0.08, 1.0 - cover + 0.5, n);
	lit = mix(lit, clamp(lit * (1.15 - core * 0.55) + 0.1, 0.0, 1.0), paint);
	vec3 cloud = mix(cloud_shade, cloud_lit, lit * (1.0 - overcast * 0.6));
	float rim = pow(max(dot(d, normalize(sun_dir)), 0.0), 12.0) * (1.0 - core);
	cloud += cloud_lit * rim * 0.5 * paint;
	cloud = mix(cloud, glow_color * 1.2, glow_amount * 0.45 * (1.0 - overcast));
	return vec4(cloud, dens * 0.92);
}

void sky() {
	vec3 d = EYEDIR;
	vec3 col = procedural(d) * sky_energy;

	// sun and moon discs (the radiance pass skips them so reflections do not get a hot spot)
	if (!AT_CUBEMAP_PASS && d.y > -0.02) {
		float sd = dot(d, normalize(sun_dir));
		float disc = smoothstep(0.99985, 0.99993, sd);
		float halo = pow(max(sd, 0.0), 900.0) * 0.6 + pow(max(sd, 0.0), 40.0) * 0.12;
		col += sun_color * (disc * 22.0 + halo * 2.0) * sun_disc * (1.0 - overcast * 0.92) * (1.0 - night);
		// a wide aureole, warm at the golden hour
		col += sun_color * pow(max(sd, 0.0), 8.0) * 0.18 * halo_amount * (1.0 - overcast) * (1.0 - night);
		float md = dot(d, normalize(moon_dir));
		float moon = smoothstep(0.99955, 0.99968, md);
		col += vec3(0.85, 0.88, 0.95) * (moon * 3.0 + pow(max(md, 0.0), 400.0) * 0.25) * night * (1.0 - overcast * 0.85);
	}

	if (hdri_mix > 0.001) {
		vec3 hd = mix(panorama(hdri_a, d, hdri_rot_a) * hdri_gain_a, panorama(hdri_b, d, hdri_rot_b) * hdri_gain_b, hdri_ab);
		float hl = dot(hd, vec3(0.2126, 0.7152, 0.0722));
		hd = max(mix(vec3(hl), hd, hdri_saturation), vec3(0.0));
		col = mix(col, hd, hdri_mix);
	}
	vec4 cl = clouds(d);
	col = mix(col, cl.rgb * sky_energy, cl.a * cloud_opacity);
	if (hdri_o_mix > 0.001) {
		col = mix(col, panorama(hdri_o, d, hdri_rot_o) * hdri_gain_o, hdri_o_mix);
	}
	COLOR = col;
}
