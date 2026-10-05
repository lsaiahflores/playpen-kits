shader_type spatial;
// Playpen wind sway for grass, flowers, bushes, palm fronds, flags and banners.
// Reads the ONE global wind value (PNWind autoload) and bends away from the
// player. `sway_height` = model height in metres; the base (y = 0) stays planted.
// For flags/cloth set `pin_axis` so the pole edge doesn't move.
render_mode cull_disabled;
uniform vec4 albedo : source_color = vec4(0.3, 0.7, 0.3, 1.0);
uniform vec4 tip_color : source_color = vec4(0.55, 0.85, 0.4, 1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;
uniform float sway_height = 1.0;
uniform float sway_amount = 0.35;
uniform float sway_speed = 1.6;
uniform float flutter = 0.0;        // extra fast flutter for cloth/leaves
uniform int pin_axis = 1;           // 0 = x, 1 = y (height), 2 = z
uniform float trample_radius = 1.6;
uniform float trample_amount = 0.6;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.0;
global uniform float pn_wind_strength;
global uniform vec2 pn_wind_dir;
global uniform vec3 pn_player_pos;

varying float v_tip;
varying vec4 v_col;

void vertex() {
	vec3 wpos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float pin = pin_axis == 0 ? VERTEX.x : (pin_axis == 2 ? VERTEX.z : VERTEX.y);
	float h = clamp(pin / max(sway_height, 0.001), 0.0, 1.0);
	v_tip = h;
	v_col = COLOR; // per-instance color from a MultiMesh (white otherwise)
	float w = pn_wind_strength;
	float phase = TIME * sway_speed + wpos.x * 0.55 + wpos.z * 0.45;
	float wave = sin(phase) + 0.5 * sin(phase * 2.3 + 1.7);
	vec2 dir = normalize(pn_wind_dir + vec2(0.0001));
	vec2 off = dir * wave * sway_amount * w * h * h;
	off += vec2(sin(TIME * 9.0 + VERTEX.x * 6.0), cos(TIME * 8.0 + VERTEX.z * 6.0)) * flutter * w * h;
	// bend away from the player
	vec3 d = wpos - pn_player_pos;
	float dist = length(d.xz);
	float push = (1.0 - smoothstep(0.0, trample_radius, dist)) * trample_amount;
	vec2 away = dist > 0.001 ? d.xz / dist : vec2(0.0);
	off += away * push * h;
	// transform world-space offset into local space (ignore non-uniform scale)
	vec3 loc = (inverse(mat3(MODEL_MATRIX)) * vec3(off.x, -push * h * 0.35, off.y));
	VERTEX += loc;
}

void fragment() {
	vec4 c = mix(albedo, tip_color, v_tip) * v_col;
	if (use_texture) c *= texture(albedo_tex, UV);
	if (alpha_scissor > 0.0 && c.a < alpha_scissor) discard;
	ALBEDO = c.rgb;
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
	// a little translucency so foliage glows against the sun
	BACKLIGHT = c.rgb * 0.35;
}
