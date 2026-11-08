// The Seicento's front air intake: a black diamond mesh (the "Grille" surface of the Details mesh, which is only
// that intake) with bright wires, found from the vertex position because the model has no UVs. The pattern fades
// to its average with distance so it never shimmers.
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
	ALBEDO = mix(vec3(0.004), vec3(0.34, 0.35, 0.37), wire);
	METALLIC = wire * 0.9;
	ROUGHNESS = mix(0.8, 0.32, wire);
	SPECULAR = 0.6;
}
