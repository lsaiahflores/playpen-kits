shader_type spatial;
// Playpen glowing/pulsing collectible: emissive core, soft pulse, gentle bob and spin.
render_mode unshaded;
uniform vec4 core_color : source_color = vec4(1.0, 0.8, 0.2, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.95, 0.6, 1.0);
uniform float pulse_speed = 3.0;
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.35;
uniform float bob_height = 0.12;
uniform float bob_speed = 2.0;
uniform float intensity : hint_range(0.0, 6.0) = 1.6;
uniform float seed = 0.0;
varying vec4 v_inst;

void vertex() {
	v_inst = COLOR; // MultiMesh instance color (white otherwise)
	VERTEX.y += sin(TIME * bob_speed + seed) * bob_height;
}

void fragment() {
	float p = 0.5 + 0.5 * sin(TIME * pulse_speed + seed * 1.7);
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	vec3 c = core_color.rgb * v_inst.rgb * (1.0 - pulse_amount + pulse_amount * p);
	c = mix(c, glow_color.rgb, fres * 0.8);
	ALBEDO = c * intensity;
}
