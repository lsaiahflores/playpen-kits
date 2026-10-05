shader_type spatial;
// Playpen building facade: procedural windows (no textures), a floor/column grid,
// per-window lit/unlit variation, and a `night` slider that turns lit windows into
// warm glowing emission. World-space grid so any box scale works.
uniform vec4 wall_color : source_color = vec4(0.78, 0.7, 0.6, 1.0);
uniform vec4 wall_color_b : source_color = vec4(0.7, 0.62, 0.55, 1.0);
uniform vec4 glass_color : source_color = vec4(0.25, 0.4, 0.55, 1.0);
uniform vec4 lit_color : source_color = vec4(1.0, 0.82, 0.45, 1.0);
uniform vec2 cell = vec2(2.6, 3.2);   // metres per window column / floor
uniform vec2 window_size = vec2(0.58, 0.56); // fraction of the cell
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform float lit_chance : hint_range(0.0, 1.0) = 0.45;
uniform float seed = 1.0;
uniform float roof_shade = 0.82;
varying vec3 v_world;
varying vec3 v_wnormal;
varying vec4 v_vc;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	v_vc = COLOR; // batched buildings: rgb = wall color, a = 0 for solid (no windows) parts
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	bool side = abs(v_wnormal.y) < 0.5 && v_vc.a > 0.5;
	float horiz = abs(v_wnormal.x) > abs(v_wnormal.z) ? v_world.z : v_world.x;
	vec3 base = mix(wall_color.rgb, wall_color_b.rgb, hash21(floor(vec2(horiz, v_world.y) / cell) + seed)) * v_vc.rgb;
	vec3 col = base;
	vec3 emis = vec3(0.0);
	if (!side) {
		col = v_vc.a > 0.5 ? base * roof_shade : base;
	} else {
		vec2 uv = vec2(horiz, v_world.y) / cell;
		vec2 id = floor(uv);
		vec2 f = fract(uv);
		vec2 lo = (1.0 - window_size) * 0.5;
		bool in_win = f.x > lo.x && f.x < 1.0 - lo.x && f.y > lo.y && f.y < 1.0 - lo.y && v_world.y > 1.2;
		if (in_win) {
			float r = hash21(id + vec2(seed * 7.0, seed * 3.0));
			bool lit = r < lit_chance;
			col = glass_color.rgb * (lit ? 1.0 : 0.8);
			emis = lit ? lit_color.rgb * night * 1.8 : vec3(0.0);
			if (lit) col = mix(col, lit_color.rgb, night * 0.7);
		}
	}
	ALBEDO = col;
	EMISSION = emis;
	ROUGHNESS = 0.85;
	SPECULAR = 0.15;
}
