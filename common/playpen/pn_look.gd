extends Node
## Playpen kit: the LOOK PACK (autoload "PNLook").
## One JSON file (res://playpen/lookpack.json) decides the whole art direction:
## palette, sky, sun, fog, tonemapping + grade, glow, material style, ambient
## layer preset and music mood. Everything else in the kit reads from here, so a
## game looks like ONE thing instead of a pile of default gray primitives.

signal look_changed

const SHADER_DIR := "res://playpen/shaders/"
var look: Dictionary = {}
var palette: Dictionary = {}
var _shader_cache := {}

func _ready() -> void:
	load_pack("res://playpen/lookpack.json")

func load_pack(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("PNLook: no look pack at %s — using built-in defaults" % path)
		look = {"id": "default", "palette": {}, "ambient": {}}
	else:
		var parsed = JSON.parse_string(f.get_as_text())
		look = parsed if parsed is Dictionary else {"id": "default", "palette": {}, "ambient": {}}
	palette = look.get("palette", {})
	look_changed.emit()

func color(name: String, fallback := Color.WHITE) -> Color:
	var hex = palette.get(name, null)
	return Color(str(hex)) if hex != null else fallback

func ambient_cfg() -> Dictionary:
	return look.get("ambient", {})

func shader(name: String) -> Shader:
	if not _shader_cache.has(name):
		_shader_cache[name] = load(SHADER_DIR + name + ".gdshader")
	return _shader_cache[name]

## A ready-made toon material in the pack's palette. `tint` is the lit color.
func toon(tint: Color, emission := Color.BLACK, emission_energy := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("toon")
	m.set_shader_parameter("albedo", tint)
	m.set_shader_parameter("shade_color", color("shadow", Color(0.38, 0.42, 0.72)).lerp(tint, 0.35))
	m.set_shader_parameter("steps", int(look.get("materials", {}).get("steps", 3)))
	m.set_shader_parameter("rim_amount", float(look.get("materials", {}).get("rim", 0.25)))
	m.set_shader_parameter("rim_color", color("sun", Color(1, 0.96, 0.82)))
	m.set_shader_parameter("emission_color", emission)
	m.set_shader_parameter("emission_energy", emission_energy)
	return m

## Add an outline pass to a toon/any material when the pack asks for it.
func with_outline(mat: Material, thickness := 0.0) -> Material:
	var t := thickness if thickness > 0.0 else float(look.get("materials", {}).get("outline", 0.0))
	if t <= 0.0:
		return mat
	var o := ShaderMaterial.new()
	o.shader = shader("outline")
	o.set_shader_parameter("thickness", t)
	o.set_shader_parameter("outline_color", color("shadow", Color(0.1, 0.08, 0.14)).darkened(0.5))
	mat.next_pass = o
	return mat

func sway_material(tint: Color, tip: Color, height := 1.0, amount := 0.35) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("wind_sway")
	m.set_shader_parameter("albedo", tint)
	m.set_shader_parameter("tip_color", tip)
	m.set_shader_parameter("sway_height", height)
	m.set_shader_parameter("sway_amount", amount)
	return m

func glow_material(core: Color, seed_value := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("glow_pulse")
	m.set_shader_parameter("core_color", core)
	m.set_shader_parameter("glow_color", core.lightened(0.6))
	m.set_shader_parameter("seed", seed_value)
	return m

func water_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("water")
	m.set_shader_parameter("shallow_color", Color(color("water", Color(0.2, 0.75, 0.9)), 0.78))
	m.set_shader_parameter("deep_color", Color(color("water_deep", Color(0.05, 0.5, 0.69)), 0.96))
	m.set_shader_parameter("sky_top", color("sky_top"))
	m.set_shader_parameter("sky_horizon", color("sky_horizon"))
	return m

func terrain_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("triplanar")
	m.set_shader_parameter("top_color", color("foliage", Color(0.32, 0.68, 0.34)).darkened(0.18))
	m.set_shader_parameter("top_color_b", color("foliage", Color(0.45, 0.76, 0.3)).lightened(0.02))
	m.set_shader_parameter("side_color", color("ground", Color(0.46, 0.38, 0.3)).darkened(0.1))
	m.set_shader_parameter("side_color_b", color("ground", Color(0.36, 0.3, 0.26)).darkened(0.3))
	return m

func windows_material(wall: Color, night := -1.0, seed_value := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("windows")
	m.set_shader_parameter("wall_color", wall)
	m.set_shader_parameter("wall_color_b", wall.darkened(0.1))
	m.set_shader_parameter("glass_color", color("secondary", Color(0.25, 0.4, 0.55)).darkened(0.45))
	m.set_shader_parameter("night", night if night >= 0.0 else _night_amount())
	m.set_shader_parameter("seed", seed_value)
	return m

func _night_amount() -> float:
	match str(look.get("ambient", {}).get("time_of_day", "day")):
		"night": return 1.0
		"golden": return 0.25
	return 0.0

## Build the Environment + sun from the pack. Pass your WorldEnvironment and
## DirectionalLight3D (either may be null) and it fills them in.
func apply(world_env: WorldEnvironment, sun: DirectionalLight3D) -> void:
	var sky_cfg: Dictionary = look.get("sky", {})
	var sm := ShaderMaterial.new()
	sm.shader = shader("sky")
	sm.set_shader_parameter("sky_top", color("sky_top", Color(0.18, 0.52, 0.92)))
	sm.set_shader_parameter("sky_horizon", color("sky_horizon", Color(0.77, 0.93, 1.0)))
	sm.set_shader_parameter("ground_color", color("ground_horizon", Color(0.9, 0.95, 1.0)))
	sm.set_shader_parameter("sun_color", color("sun", Color(1, 0.94, 0.77)))
	sm.set_shader_parameter("sun_glow", float(sky_cfg.get("sun_glow", 0.8)))
	sm.set_shader_parameter("haze", float(sky_cfg.get("horizon_haze", 0.55)))
	sm.set_shader_parameter("cloud_cover", float(sky_cfg.get("clouds", 0.5)))
	sm.set_shader_parameter("cloud_speed", float(sky_cfg.get("cloud_speed", 0.012)))
	sm.set_shader_parameter("stars", 1.0 if sky_cfg.get("stars", false) else 0.0)
	sm.set_shader_parameter("cloud_quality", 1 if PNSettings.quality == PNSettings.Quality.LOW else 2)
	var sky := Sky.new()
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_64

	if sun:
		var s: Dictionary = look.get("sun", {})
		sun.rotation_degrees = Vector3(float(s.get("pitch", -45)), float(s.get("yaw", -30)), 0.0)
		sun.light_color = Color(str(s.get("color", "#fff1c9")))
		sun.light_energy = float(s.get("energy", 1.2)) * 0.5
		sun.shadow_enabled = bool(s.get("shadow", true))
		# Shadows are the priciest thing on a weak GPU: on Low, one tight split and a small atlas.
		var low := PNSettings.quality == PNSettings.Quality.LOW
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if low else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = 55.0 if low else 120.0
		sun.shadow_blur = 1.0 if low else 1.6
		RenderingServer.directional_shadow_atlas_set_size(1024 if low else 2048, true)
		sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY

	if world_env:
		var env := Environment.new()
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		# A flat tinted ambient is predictable (the sky shader is only the backdrop).
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = color("sky_horizon", Color(0.77, 0.93, 1.0)).lerp(color("sky_top", Color(0.18, 0.52, 0.92)), 0.4)
		env.ambient_light_energy = 0.3
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		var tm: Dictionary = look.get("tonemap", {})
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC if str(tm.get("mode", "filmic")) == "filmic" else Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = float(tm.get("exposure", 1.0)) * 0.9
		env.tonemap_white = float(tm.get("white", 6.0))
		var g: Dictionary = look.get("grade", {})
		env.adjustment_enabled = PNSettings.quality != PNSettings.Quality.LOW   # a full-screen post pass: skipped on Low
		env.adjustment_brightness = float(g.get("brightness", 1.0))
		env.adjustment_contrast = float(g.get("contrast", 1.05))
		env.adjustment_saturation = float(g.get("saturation", 1.1))
		var fog: Dictionary = look.get("fog", {})
		env.fog_enabled = true
		env.fog_light_color = color("fog", Color(0.8, 0.9, 1.0))
		env.fog_density = float(fog.get("density", 0.004)) * 0.55
		env.fog_aerial_perspective = 0.35
		env.fog_sky_affect = 0.0
		env.fog_sun_scatter = float(fog.get("sun_scatter", 0.2))
		var gl: Dictionary = look.get("glow", {})
		env.glow_enabled = bool(gl.get("enabled", true)) and PNSettings.quality != PNSettings.Quality.LOW
		env.glow_intensity = float(gl.get("intensity", 0.5))
		env.glow_bloom = float(gl.get("bloom", 0.08))
		env.glow_hdr_threshold = float(gl.get("threshold", 1.0))
		world_env.environment = env
	PNWind.configure(look)

## Glossy toy PLASTIC (brick-toy look). With `instance_color` the MultiMesh / vertex color tints it, so a wall of bricks is one draw call.
func plastic_material(tint := Color.WHITE, instance_color := true) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("plastic")
	m.set_shader_parameter("albedo", tint)
	m.set_shader_parameter("use_instance_color", instance_color)
	var mat_cfg: Dictionary = look.get("materials", {})
	m.set_shader_parameter("roughness", float(mat_cfg.get("roughness", 0.2)))
	m.set_shader_parameter("specular", float(mat_cfg.get("specular", 0.85)))
	m.set_shader_parameter("rim_amount", float(mat_cfg.get("rim", 0.22)))
	m.set_shader_parameter("rim_color", color("sky_horizon", Color(0.82, 0.92, 1.0)))
	return m
