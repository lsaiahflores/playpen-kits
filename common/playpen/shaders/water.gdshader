shader_type spatial;
// Playpen stylized water: wind-driven waves, depth-tinted color, shoreline foam,
// faked sky reflection, sun glints. Compatibility-renderer safe.
render_mode cull_disabled;
uniform vec4 shallow_color : source_color = vec4(0.16, 0.75, 0.88, 0.75);
uniform vec4 deep_color : source_color = vec4(0.05, 0.5, 0.69, 0.95);
uniform vec4 sky_top : source_color = vec4(0.18, 0.5, 0.92, 1.0);
uniform vec4 sky_horizon : source_color = vec4(0.77, 0.93, 1.0, 1.0);
uniform vec4 foam_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float wave_height : hint_range(0.0, 1.0) = 0.12;
uniform float wave_speed = 0.8;
uniform float wave_scale = 0.35;
uniform float depth_fade = 2.0;
uniform float foam_width = 0.55;
uniform float reflect_amount : hint_range(0.0, 1.0) = 0.55;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
global uniform float pn_wind_strength;

varying vec3 v_world;

float wave(vec2 p, float t) {
	return sin(p.x * 1.0 + t) * 0.5 + sin(p.y * 1.3 + t * 1.2) * 0.35 + sin((p.x + p.y) * 0.7 - t * 0.8) * 0.4;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x), mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wave_speed;
	float amp = wave_height * (0.6 + pn_wind_strength * 0.8);
	VERTEX.y += wave(v_world.xz * wave_scale * 3.0, t) * amp;
}

void fragment() {
	float t = TIME * wave_speed;
	vec2 p = v_world.xz * wave_scale;
	// perturbed normal from the wave field
	float e = 0.15;
	float h0 = wave(p * 3.0, t);
	float hx = wave((p + vec2(e, 0.0)) * 3.0, t);
	float hz = wave((p + vec2(0.0, e)) * 3.0, t);
	vec3 n = normalize(vec3((h0 - hx) * 1.2, 1.0, (h0 - hz) * 1.2));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// scene depth behind the surface (GL Compatibility: ndc z in [-1,1])
	float d = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV, d) * 2.0 - 1.0;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vp.xyz /= vp.w;
	float water_depth = max(0.0, -vp.z - (-VERTEX.z));

	float depth01 = 1.0 - exp(-water_depth / max(depth_fade, 0.01));
	vec4 col = mix(shallow_color, deep_color, depth01);

	// shoreline foam + drifting foam flecks
	float shore = 1.0 - smoothstep(0.0, foam_width, water_depth);
	float n1 = vnoise(v_world.xz * 2.2 + vec2(t * 0.6, -t * 0.4));
	float foam = clamp(shore * (0.55 + 0.6 * n1), 0.0, 1.0);
	foam = smoothstep(0.35, 0.7, foam);
	float flecks = smoothstep(0.78, 0.9, vnoise(v_world.xz * 3.5 - vec2(t * 0.3, t * 0.2)));
	foam = max(foam, flecks * 0.55);

	// fake reflection: sky gradient by view angle
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	vec3 sky = mix(sky_horizon.rgb, sky_top.rgb, clamp(1.0 - fres, 0.0, 1.0));
	vec3 rgb = mix(col.rgb, sky, fres * reflect_amount);
	rgb = mix(rgb, foam_color.rgb, foam);

	ALBEDO = rgb;
	ALPHA = clamp(mix(col.a, 1.0, max(foam, fres * 0.5)), 0.0, 1.0);
	ROUGHNESS = 0.12;
	SPECULAR = 0.8;
	METALLIC = 0.0;
}
