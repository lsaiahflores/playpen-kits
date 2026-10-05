shader_type spatial;
// Playpen rim light — an additive fresnel glow. Use as a material next_pass or
// material_overlay on top of any base material.
render_mode unshaded, blend_add, cull_back, depth_draw_never;
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.8, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_intensity : hint_range(0.0, 4.0) = 0.6;

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	ALBEDO = rim_color.rgb * fres * rim_intensity;
}
