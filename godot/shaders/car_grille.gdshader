// Front air-intake grille: a dark satin diamond mesh (the "Grille" surface of the Details mesh), found from the vertex
// position because the model has no UVs. The pattern fades to its average with distance so it never shimmers, and stays
// satin charcoal plastic so direct sunlight never throws a blinding glare blob across the nose.
shader_type spatial;

uniform float cell : hint_range(20.0, 200.0) = 78.0; // diamonds per metre
varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec2 q = lp.xy * cell;
	vec2 d = vec2(q.x + q.y, q.x - q.y) * 0.7071;
	vec2 f = abs(fract(d) - 0.5);          // 0.5 on a wire, 0 in the middle of a diamond
	float wire = smoothstep(0.30, 0.44, max(f.x, f.y));
	float w = fwidth(d.x) + fwidth(d.y);
	wire = mix(wire, 0.22, smoothstep(0.35, 0.9, w)); // far away: the average
	ALBEDO = mix(vec3(0.005, 0.005, 0.006), vec3(0.065, 0.068, 0.072), wire);
	METALLIC = wire * 0.10;
	ROUGHNESS = mix(0.88, 0.56, wire);
	SPECULAR = 0.25;
}
