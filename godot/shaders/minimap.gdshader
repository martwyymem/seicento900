// The open world's satnav map (data/world/<key>_map.png) seen round the car: a disc turning with the car's
// heading (heading up), or the whole map when radius_m covers it and rotate is off. map_origin and map_size
// are the picture's rectangle in map metres; centre is the car's map position.
shader_type canvas_item;

uniform sampler2D map_tex : filter_linear_mipmap, repeat_disable;
uniform vec2 map_origin = vec2(0.0);
uniform vec2 map_size = vec2(1000.0);
uniform vec2 centre = vec2(0.0);
uniform float heading = 0.0; // radians from +x towards +y (south)
uniform float radius_m = 250.0;
uniform bool rotate = true;
uniform bool disc = true;
uniform vec4 edge_color : source_color = vec4(1.0, 0.45, 0.1, 1.0);
uniform float aspect = 1.0; // width / height of the control (the full map isn't square)

void fragment() {
	vec2 o = (UV - 0.5) * 2.0;
	o.x *= aspect;
	float r = length(o);
	if (disc && r > 1.0) {
		discard;
	}
	vec2 world;
	if (rotate) {
		vec2 f = vec2(cos(heading), sin(heading));
		vec2 rt = vec2(-f.y, f.x);
		world = centre + (rt * o.x - f * o.y) * radius_m;
	} else {
		world = centre + o * radius_m;
	}
	vec2 uv = (world - map_origin) / map_size;
	vec4 c = texture(map_tex, uv);
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		c = vec4(0.08, 0.1, 0.1, 1.0);
	}
	c.rgb *= 1.08;
	if (disc) {
		float rim = smoothstep(0.92, 0.95, r);
		c = mix(c, edge_color, rim);
		c.a *= 0.93 * (1.0 - smoothstep(0.985, 1.0, r));
	}
	COLOR = c;
}
