shader_type spatial;
// Playpen dissolve / hit flash. Use as a material_overlay: `flash` (0..1) whitens
// the whole mesh for a hit; `amount` (0..1) burns it away with a glowing edge.
render_mode unshaded, blend_mix, depth_draw_opaque;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge_color : source_color = vec4(1.0, 0.55, 0.15, 1.0);
uniform float edge_width : hint_range(0.0, 0.3) = 0.08;
uniform float noise_scale = 3.0;
varying vec3 v_local;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i);
	float n100 = hash31(i + vec3(1, 0, 0));
	float n010 = hash31(i + vec3(0, 1, 0));
	float n110 = hash31(i + vec3(1, 1, 0));
	float n001 = hash31(i + vec3(0, 0, 1));
	float n101 = hash31(i + vec3(1, 0, 1));
	float n011 = hash31(i + vec3(0, 1, 1));
	float n111 = hash31(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y), mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float n = vnoise(v_local * noise_scale);
	if (amount > 0.0 && n < amount) discard;
	float edge = amount > 0.0 ? 1.0 - smoothstep(0.0, edge_width, n - amount) : 0.0;
	if (flash <= 0.001 && edge <= 0.001) discard;
	vec3 c = mix(flash_color.rgb, edge_color.rgb * 2.0, edge);
	ALBEDO = c;
	ALPHA = max(flash * 0.85, edge);
}
