// Crash damage shared by the car's lamp and glass shaders (RaceCarVisual): which lamp of the four is smashed (the
// per-car instance uniform lamp_broken: x front-left, y front-right, z rear-left, w rear-right, 0 whole .. 1 smashed)
// and a shattered-glass pattern (the edges of irregular cells, thin lines that fade with distance).

instance uniform vec4 lamp_broken : instance_index(4) = vec4(0.0);

// How smashed the lamp at this model-space point is (the model's front is -Z, its right +X).
float lamp_smashed(vec3 lp) {
	vec2 side = lp.z < 0.0 ? lamp_broken.xy : lamp_broken.zw;
	return lp.x < 0.0 ? side.x : side.y;
}

vec2 crack_hash(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// 1 on a crack line between shards of about 1/density m, 0 between them; aa is the pattern's screen-space width.
float crack_lines(vec2 p, float density) {
	vec2 q = p * density;
	vec2 cell = floor(q);
	vec2 f = fract(q);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 o = vec2(float(i), float(j));
			vec2 r = o + crack_hash(cell + o) - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	float edge = sqrt(d2) - sqrt(d1);
	float aa = max(fwidth(q.x) + fwidth(q.y), 1e-4);
	return (1.0 - smoothstep(0.03, 0.03 + 1.5 * aa, edge)) * (1.0 - smoothstep(0.35, 0.9, aa));
}
