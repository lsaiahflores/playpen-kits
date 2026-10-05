shader_type spatial;
// Playpen toon / cel shader — banded light, tinted shadows, rim light, optional texture.
// Compatibility-renderer safe (no depth/screen reads).
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;
uniform vec4 shade_color : source_color = vec4(0.38, 0.42, 0.72, 1.0);
uniform int steps : hint_range(2, 6) = 3;
uniform float softness : hint_range(0.01, 0.5) = 0.12;
uniform vec4 rim_color : source_color = vec4(1.0, 0.96, 0.82, 1.0);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.25;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 8.0) = 1.0;
uniform float uv_scale = 1.0;
uniform bool use_vertex_color = false;  // merged meshes (PNBatch) carry their color per vertex
varying vec4 v_col;

void vertex() {
	v_col = COLOR;
}

void fragment() {
	vec4 c = albedo;
	if (use_vertex_color) {
		c *= v_col;
	}
	if (use_texture) {
		c *= texture(albedo_tex, UV * uv_scale);
	}
	ALBEDO = c.rgb;
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	EMISSION = emission_color.rgb * emission_energy + rim_color.rgb * fres * rim_amount;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float nl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float q = nl * float(steps);
	float band = floor(q);
	float edge = smoothstep(0.0, softness * float(steps), fract(q));
	float v = clamp((band + edge) / float(steps), 0.0, 1.0);
	vec3 lit = mix(shade_color.rgb, vec3(1.0), v);
	DIFFUSE_LIGHT += LIGHT_COLOR * lit / PI;
}
