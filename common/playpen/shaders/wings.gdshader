shader_type spatial;
// Playpen wings: flapping birds / gulls / pigeons / butterflies in ONE MultiMesh draw.
// Per-instance: COLOR = body color, INSTANCE_CUSTOM.x = flap phase,
// INSTANCE_CUSTOM.y = flap rate (0 = gliding), INSTANCE_CUSTOM.z = tip color mix.
render_mode cull_disabled;
uniform float flap_speed = 9.0;
uniform float flap_amount = 0.55;
uniform vec4 tip_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
varying vec4 v_col;
varying float v_tip;

void vertex() {
	float wing = abs(VERTEX.x);
	float ph = INSTANCE_CUSTOM.x;
	float rate = INSTANCE_CUSTOM.y;
	float lift = rate > 0.01 ? sin(TIME * flap_speed * rate + ph) : 0.25;
	VERTEX.y += lift * flap_amount * wing;
	v_col = COLOR;
	v_tip = clamp(wing * 2.0, 0.0, 1.0) * INSTANCE_CUSTOM.z;
}

void fragment() {
	ALBEDO = mix(v_col.rgb, tip_color.rgb, v_tip);
	ROUGHNESS = 0.9;
	SPECULAR = 0.0;
	BACKLIGHT = v_col.rgb * 0.4;
}
