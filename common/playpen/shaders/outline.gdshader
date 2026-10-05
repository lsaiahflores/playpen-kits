shader_type spatial;
// Playpen outline — inverted-hull. Assign as the next_pass of a mesh material.
render_mode unshaded, cull_front;
uniform vec4 outline_color : source_color = vec4(0.08, 0.06, 0.12, 1.0);
uniform float thickness : hint_range(0.0, 0.12) = 0.025;

void vertex() {
	VERTEX += NORMAL * thickness;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
