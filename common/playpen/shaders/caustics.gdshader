shader_type spatial;
// Playpen simple caustics: animated light web, additive. Put on a ground-hugging
// plane just under the water surface (or as a material overlay on the sea floor).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec4 caustic_color : source_color = vec4(0.7, 1.0, 1.0, 1.0);
uniform float scale = 0.9;
uniform float speed = 0.45;
uniform float intensity : hint_range(0.0, 3.0) = 0.7;
varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float web(vec2 p, float t) {
	vec2 q = p;
	float v = 0.0;
	for (int i = 1; i < 4; i++) {
		float fi = float(i);
		q += vec2(sin(q.y * 1.3 + t * fi) , cos(q.x * 1.1 - t * fi * 0.8)) * 0.55 / fi;
		v += abs(sin(q.x * 2.0) + sin(q.y * 2.0)) * 0.5 / fi;
	}
	return v;
}

void fragment() {
	float t = TIME * speed;
	float c = web(v_world.xz * scale, t);
	float lines = pow(clamp(1.0 - c, 0.0, 1.0), 4.0);
	ALBEDO = caustic_color.rgb * lines * intensity;
}
