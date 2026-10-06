shader_type spatial;
// Playpen glossy toy PLASTIC (Compatibility-renderer safe: no depth/screen reads).
// Smooth shaded, a sharp specular highlight (the "wet toy" look), a soft fresnel rim from the sky, and an optional
// per-vertex / per-instance color so a whole brick wall can be ONE MultiMesh draw call.
uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_instance_color = true;
uniform float roughness : hint_range(0.02, 1.0) = 0.2;
uniform float specular : hint_range(0.0, 1.0) = 0.85;
uniform vec4 rim_color : source_color = vec4(0.82, 0.92, 1.0, 1.0);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.22;
uniform float rim_power : hint_range(0.5, 8.0) = 3.2;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 8.0) = 1.0;
varying vec4 v_col;

void vertex() {
	v_col = COLOR;
}

void fragment() {
	vec4 c = albedo;
	if (use_instance_color) {
		c *= v_col;
	}
	ALBEDO = c.rgb;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	METALLIC = 0.0;
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	EMISSION = emission_color.rgb * emission_energy + rim_color.rgb * fres * rim_amount;
}
