class_name PNRich
extends Node3D
## Playpen kit: RICH BY DEFAULT + LIVING WORLD BY DEFAULT.
##
## One call after PNLook.apply():   PNRich.build(world, env_node, sun, player, Rect2(-80, -80, 160, 160))
## It reads the look pack (res://playpen/lookpack.json: `rich`, `living`, `richness`) and, when present, the design
## bible (res://design-bible.json: richness level, living-world lists, time of day), and builds — within a hard,
## tier-based BUDGET so an 8 GB / integrated-GPU machine and the web preview stay smooth:
##   sky      time-of-day (day / dusk / dawn / night / overcast), moon, stars, shooting stars (sky shader)
##   lighting sun key + sky fill + ambient + rim light on characters, soft shadows (distance-limited by tier)
##   distance sky-tinted fog (PNLook), layered horizon silhouettes, soft vignette, light shafts and real depth of
##            field ONLY in Play in full quality (Forward+); the Compatibility/web renderer gets fake depth instead
##   ground   instanced grass blades with wind sway + colour variation + distance fade, dirt/moss patches,
##            rocks and flowers placed by rules (varied size/rotation, never tiled)
##   life     birds, butterflies, bees, dragonflies, fireflies, bats, owls, leaves, motes, mist, rain/snow/petals/embers
##   sound    ambience beds matching that life (through the Ambience bus), tied to the time of day
## `richness` = "rich" (default) | "stylized" | "flat". Stylized/flat keep the same care in their own language
## (fewer, simpler pieces), never a bare flat sky or silent world.

const SHADER_VIGNETTE := "shader_type canvas_item;\nuniform float strength = 0.38;\nuniform float softness = 0.6;\nvoid fragment() {\n\tvec2 uv = UV - vec2(0.5);\n\tfloat d = length(uv * vec2(1.0, 0.82));\n\tfloat v = smoothstep(0.32, 0.32 + softness, d);\n\tCOLOR = vec4(0.0, 0.0, 0.0, v * strength);\n}\n"

## Mirrors src/main/richWorld.js BUDGETS (keyed by PNSettings.Quality: 0 low, 1 medium, 2 high).
const BUDGETS := {
	0: {"tier": "low", "particles": 150, "creatures": 24, "grass": 1500, "props": 120, "horizon": 2, "weather": false, "shafts": false},
	1: {"tier": "medium", "particles": 400, "creatures": 60, "grass": 4500, "props": 300, "horizon": 3, "weather": true, "shafts": false},
	2: {"tier": "high", "particles": 900, "creatures": 140, "grass": 11000, "props": 700, "horizon": 4, "weather": true, "shafts": true},
}

static var last_report := {}

var env_node: WorldEnvironment
var sun: DirectionalLight3D
var target: Node3D
var area := Rect2(-80, -80, 160, 160)
var level := "rich"
var tod := "day"
var budget := {}
var forward_plus := false
var look := {}
var bible := {}
var features: Array = []
var counts := {"grass": 0, "creatures": 0, "props": 0, "particles": 0}
var _rng := RandomNumberGenerator.new()
var _horizon: Node3D
var _owls: Array = []
var _swarms: Array = []
var _t := 0.0
var _amb: PNAmbient
var _ground_y := 0.0
var _opts := {}

static func build(world: Node3D, p_env: WorldEnvironment, p_sun: DirectionalLight3D, p_target: Node3D, p_area := Rect2(-80, -80, 160, 160), opts := {}) -> PNRich:
	var r := PNRich.new()
	r.name = "PNRich"
	world.add_child(r)
	r.setup(p_env, p_sun, p_target, p_area, opts)
	return r

func setup(p_env: WorldEnvironment, p_sun: DirectionalLight3D, p_target: Node3D, p_area: Rect2, opts := {}) -> void:
	env_node = p_env
	sun = p_sun
	target = p_target
	area = p_area
	_opts = opts
	_ground_y = float(opts.get("ground_y", 0.0))
	_rng.seed = int(opts.get("seed", 7331))
	look = PNLook.look
	bible = _read_bible()
	level = str(opts.get("richness", (bible.get("richness", {}) as Dictionary).get("level", look.get("richness", "rich")) if bible.get("richness") is Dictionary else look.get("richness", "rich")))
	if not ["rich", "stylized", "flat"].has(level):
		level = "rich"
	budget = BUDGETS[clampi(PNSettings.quality, 0, 2)]
	forward_plus = RenderingServer.get_current_rendering_method() == "forward_plus"
	_decide_time_of_day(opts)
	rebuild()

func _read_bible() -> Dictionary:
	for p in ["res://design-bible.json", "res://brain/design-bible.json"]:
		if FileAccess.file_exists(p):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
			if parsed is Dictionary:
				return parsed
	return {}

func _decide_time_of_day(opts: Dictionary) -> void:
	var from_pack := str((look.get("ambient", {}) as Dictionary).get("time_of_day", "day"))
	var pack_tod := "dusk" if from_pack == "golden" else from_pack
	var lw: Dictionary = bible.get("livingWorld", {}) if bible.get("livingWorld") is Dictionary else {}
	tod = str(opts.get("time_of_day", lw.get("timeOfDay", pack_tod)))
	if not ["day", "dusk", "dawn", "night", "overcast"].has(tod):
		tod = "day"
	opts["_pack_tod"] = pack_tod

## Rebuild every piece for the current `tod` (call set_time_of_day() to move through a day/night cycle).
## The ambient-life node PNRich built (birds, butterflies, fireflies...), for games that want to poke it.
func ambient() -> PNAmbient:
	return _amb

func set_time_of_day(new_tod: String) -> void:
	tod = new_tod
	rebuild()

func rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_owls.clear()
	_swarms.clear()
	features.clear()
	counts = {"grass": 0, "creatures": 0, "props": 0, "particles": 0}
	_apply_time_of_day()
	_build_rim_light()
	if budget["tier"] == "low":
		_limit_shadows()
	_build_vignette()
	if level != "flat":
		_build_horizon()
		if not bool(_opts.get("no_grass", false)):
			_build_grass()
		if not bool(_opts.get("no_ground_detail", false)):
			_build_ground_detail()
	_build_life()
	_build_weather()
	_build_mist()
	_build_light_shafts()
	_apply_depth_of_field()
	_apply_audio()
	_report()

# ------------------------------------------------------------------ sky + lighting by time of day
func _sky_mat() -> ShaderMaterial:
	if env_node and env_node.environment and env_node.environment.sky:
		return env_node.environment.sky.sky_material as ShaderMaterial
	return null

func _apply_time_of_day() -> void:
	var sm := _sky_mat()
	var env: Environment = env_node.environment if env_node else null
	if sm == null or env == null:
		return
	features.append("sky_" + tod)
	var pack_tod := str(_opts.get("_pack_tod", "day"))
	var sky_cfg: Dictionary = look.get("sky", {})
	sm.set_shader_parameter("moon", 1.0 if (tod == "night" or sky_cfg.get("moon", false)) else 0.0)
	sm.set_shader_parameter("shooting_star", 1.0 if (tod == "night" or sky_cfg.get("stars", false)) else 0.0)
	if tod == pack_tod and tod != "night":
		return   # the look pack already IS this time of day
	match tod:
		"night":
			sm.set_shader_parameter("sky_top", Color("#060a22"))
			sm.set_shader_parameter("sky_horizon", Color("#27346a"))
			sm.set_shader_parameter("ground_color", Color("#10162f"))
			sm.set_shader_parameter("sun_color", Color("#9fb3ff"))
			sm.set_shader_parameter("sun_glow", 0.15)
			sm.set_shader_parameter("stars", 1.0)
			sm.set_shader_parameter("cloud_cover", 0.25)
			sm.set_shader_parameter("cloud_color", Color("#3a4673"))
			sm.set_shader_parameter("cloud_shade", Color("#141a3a"))
			sm.set_shader_parameter("haze", 0.7)
			if sun:
				sun.rotation_degrees = Vector3(-38.0, -125.0, 0.0)
				sun.light_color = Color("#9fb3ff")
				sun.light_energy = 0.32
			env.ambient_light_color = Color("#34498f")
			env.ambient_light_energy = 0.65
			env.fog_light_color = Color("#1b2552")
			env.fog_density = maxf(env.fog_density, 0.006)
		"dusk", "dawn":
			sm.set_shader_parameter("sky_top", Color("#2c3a86") if tod == "dusk" else Color("#4a5da8"))
			sm.set_shader_parameter("sky_horizon", Color("#ff9560") if tod == "dusk" else Color("#ffb7a0"))
			sm.set_shader_parameter("ground_color", Color("#4a3b5e"))
			sm.set_shader_parameter("sun_color", Color("#ffb070"))
			sm.set_shader_parameter("sun_glow", 1.3)
			sm.set_shader_parameter("stars", 0.35 if tod == "dusk" else 0.0)
			sm.set_shader_parameter("cloud_color", Color("#ffd2b0"))
			sm.set_shader_parameter("cloud_shade", Color("#8a6a9a"))
			if sun:
				sun.rotation_degrees = Vector3(-9.0, -40.0, 0.0)
				sun.light_color = Color("#ffb070")
				sun.light_energy = 0.8
			env.ambient_light_color = Color("#6b6a9e")
			env.fog_light_color = Color("#d58a7a")
		"overcast":
			sm.set_shader_parameter("sky_top", Color("#7f8b9c"))
			sm.set_shader_parameter("sky_horizon", Color("#c3cad2"))
			sm.set_shader_parameter("cloud_cover", 0.95)
			sm.set_shader_parameter("cloud_color", Color("#d6dbe0"))
			sm.set_shader_parameter("cloud_shade", Color("#8f99a6"))
			sm.set_shader_parameter("sun_glow", 0.1)
			if sun:
				sun.light_energy = 0.45
				sun.light_color = Color("#e4eaf0")
			env.ambient_light_color = Color("#aab4c0")
			env.fog_light_color = Color("#bcc5ce")
			env.fog_density = maxf(env.fog_density, 0.007)
		_:
			# "day" on a pack whose own default is golden/dusk/night: a clear, saturated daytime sky
			sm.set_shader_parameter("sky_top", Color("#2f86ea"))
			sm.set_shader_parameter("sky_horizon", Color("#bfe6ff"))
			sm.set_shader_parameter("ground_color", Color("#e4f1ff"))
			sm.set_shader_parameter("sun_color", Color("#fff0c4"))
			sm.set_shader_parameter("sun_glow", 0.85)
			sm.set_shader_parameter("stars", 0.0)
			sm.set_shader_parameter("moon", 0.0)
			sm.set_shader_parameter("cloud_color", Color("#ffffff"))
			sm.set_shader_parameter("cloud_shade", Color("#b4c6e0"))
			if sun:
				sun.rotation_degrees = Vector3(-46.0, -35.0, 0.0)
				sun.light_color = Color("#fff0c4")
				sun.light_energy = 0.7
			env.ambient_light_color = Color("#9fc4ee")
			env.fog_light_color = Color("#cdeaff")

func _build_rim_light() -> void:
	if level == "flat" or sun == null:
		return
	var rim := DirectionalLight3D.new()
	rim.name = "RimLight"
	rim.shadow_enabled = false
	rim.light_color = Color("#b8d4ff") if tod != "dusk" else Color("#ffc08a")
	rim.light_energy = 0.22 if tod == "night" else 0.3
	rim.rotation_degrees = Vector3(-18.0, sun.rotation_degrees.y + 180.0, 0.0)
	add_child(rim)
	features.append("rim_light")

func _limit_shadows() -> void:
	if sun:
		sun.directional_shadow_max_distance = 40.0
		features.append("shadow_distance_40m")

# ------------------------------------------------------------------ vignette + depth
func _build_vignette() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	layer.name = "Vignette"
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER_VIGNETTE
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("strength", 0.42 if tod == "night" else 0.3)
	rect.material = m
	layer.add_child(rect)
	add_child(layer)
	features.append("vignette")

func _apply_depth_of_field() -> void:
	if env_node == null or level != "rich":
		return
	if forward_plus:
		var ca := CameraAttributesPractical.new()
		ca.dof_blur_far_enabled = true
		ca.dof_blur_far_distance = 70.0
		ca.dof_blur_far_transition = 50.0
		ca.dof_blur_amount = 0.06
		env_node.camera_attributes = ca
		features.append("depth_of_field")
	else:
		features.append("fake_depth(fog+haze+horizon_layers)")   # DoF is Forward+ only; this renderer gets fake depth instead

# ------------------------------------------------------------------ horizon silhouettes
func _build_horizon() -> void:
	_horizon = Node3D.new()
	_horizon.name = "Horizon"
	add_child(_horizon)
	var n := int(budget["horizon"])
	var sky_h := PNLook.color("sky_horizon", Color(0.77, 0.93, 1.0))
	if tod == "day" and str((look.get("ambient", {}) as Dictionary).get("time_of_day", "day")) != "day":
		sky_h = Color("#bfe6ff")
	var far_col := sky_h.lerp(Color("#7d8fb8"), 0.55)       # distant ridges are hazy blue-grey
	var near_col := PNLook.color("foliage_dark", Color(0.14, 0.35, 0.27)).lerp(Color("#3c5a52"), 0.3)
	if tod == "night":
		far_col = far_col.darkened(0.55)
		near_col = near_col.darkened(0.6)
	var noise := FastNoiseLite.new()
	noise.seed = int(_rng.seed)
	noise.frequency = 0.9
	for i in n:
		var t := float(i) / maxf(1.0, float(n - 1))
		var radius := 360.0 - 60.0 * i
		var height := 62.0 - 14.0 * i
		var col := far_col.lerp(near_col, 0.25 + 0.6 * t)
		_horizon.add_child(_ridge_ring(radius, height, col, noise, float(i) * 17.0))
	features.append("horizon_layers_%d" % n)

func _ridge_ring(radius: float, height: float, col: Color, noise: FastNoiseLite, offset: float) -> MeshInstance3D:
	var segs := 96
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for s in segs + 1:
		var a := TAU * float(s) / float(segs)
		var h := height * (0.45 + 0.55 * (noise.get_noise_2d(cos(a) * 2.0 + offset, sin(a) * 2.0) * 0.5 + 0.5))
		verts.append(Vector3(cos(a) * radius, -6.0, sin(a) * radius))
		verts.append(Vector3(cos(a) * radius, h, sin(a) * radius))
	for s in segs:
		var b := s * 2
		idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = col
	mat.disable_fog = true
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4000.0
	return mi

# ------------------------------------------------------------------ grass, ground detail
func _clump_mesh(height := 0.5, width := 0.055, blades := 7) -> ArrayMesh:
	# a CLUMP: a fan of tapered, leaning blades (one instance = ~7 blades), double-sided via the material
	var v := PackedVector3Array()
	var cols := PackedColorArray()
	var r := RandomNumberGenerator.new()
	r.seed = 99
	for k in blades:
		var ang := TAU * float(k) / float(blades) + r.randf() * 0.6
		var off := Vector3(cos(ang), 0, sin(ang)) * r.randf_range(0.02, 0.13)
		var side := Vector3(-sin(ang), 0, cos(ang)) * width * r.randf_range(0.8, 1.2)
		var h := height * r.randf_range(0.65, 1.2)
		var lean := Vector3(cos(ang), 0, sin(ang)) * r.randf_range(0.03, 0.16)
		v.append_array([off - side, off + side, off + lean + Vector3(0, h, 0)])
		cols.append_array([Color(1, 1, 1), Color(1, 1, 1), Color(1, 1, 1)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

func _ground_at(p: Vector2) -> float:
	if _opts.has("height_fn"):
		return float((_opts["height_fn"] as Callable).call(p.x, p.y))
	return _ground_y

static func _hash2(x: float, z: float) -> float:
	return fposmod(sin(x * 127.1 + z * 311.7) * 43758.5453, 1.0)

var _grass: MultiMeshInstance3D
var _grass_pts := PackedVector2Array()
var _grass_cell := Vector2i(1 << 30, 0)
var _grass_step := 4.0
var _grass_radius := 20.0
var _grass_noise := FastNoiseLite.new()

## Grass follows the player on a lattice (so the pattern stays put as the field slides): 1500 / 4500 / 11000 clumps by tier,
## each ~7 blades, with wind sway, colour variation, bare patches, and a distance fade (LOD).
func _build_grass() -> void:
	var cap := int(budget["grass"])
	if level == "stylized":
		cap = int(cap * 0.5)
	if cap <= 0:
		return
	var density := 2.2 if budget["tier"] == "low" else (2.6 if budget["tier"] == "medium" else 3.0)
	_grass_radius = sqrt(float(cap) / (density * PI))
	var spacing := 1.0 / sqrt(density)
	_grass_step = spacing * 6.0
	_grass_noise.seed = int(_rng.seed) + 5
	_grass_noise.frequency = 0.05
	var base := PNLook.color("foliage", Color(0.32, 0.68, 0.34)).darkened(0.18)
	var tip := PNLook.color("foliage", Color(0.45, 0.76, 0.3)).lightened(0.3)
	if tod == "night":
		base = base.darkened(0.45)
		tip = tip.darkened(0.4)
	var mat := PNLook.sway_material(base, tip, 0.5, 0.4)
	# jittered lattice points inside the disc (local offsets); the lattice moves in whole steps, so it never swims
	var reach := int(ceil((_grass_radius + _grass_step) / spacing))
	var pts := PackedVector2Array()
	for ix in range(-reach, reach + 1):
		for iz in range(-reach, reach + 1):
			var q := Vector2(ix, iz) * spacing
			q += Vector2(_rng.randf() - 0.5, _rng.randf() - 0.5) * spacing * 0.9
			if q.length() <= _grass_radius + _grass_step * 0.5:
				pts.append(q)
	if pts.size() > cap:
		pts.resize(cap)
	_grass_pts = pts
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _clump_mesh()
	mm.instance_count = pts.size()
	_grass = MultiMeshInstance3D.new()
	_grass.name = "Grass"
	_grass.multimesh = mm
	_grass.material_override = mat
	_grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grass.extra_cull_margin = 4.0
	_grass.visibility_range_end = _grass_radius + 4.0                         # LOD: clumps fade out toward the rim instead of popping
	_grass.visibility_range_end_margin = _grass_radius * 0.35
	_grass.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(_grass)
	_regrid_grass(Vector2.ZERO, true)
	counts["grass"] = pts.size()
	features.append("grass_clumps_%d(~%d blades)" % [pts.size(), pts.size() * 7])

func _update_grass(tp: Vector3) -> void:
	if _grass == null:
		return
	var cell := Vector2i(int(floor(tp.x / _grass_step)), int(floor(tp.z / _grass_step)))
	if cell != _grass_cell:
		_regrid_grass(Vector2(cell.x * _grass_step, cell.y * _grass_step), false)
		_grass_cell = cell

func _regrid_grass(center: Vector2, first: bool) -> void:
	var mm := _grass.multimesh
	var spacing_hash := 0.37
	for i in _grass_pts.size():
		var wp := center + _grass_pts[i]
		var h := _hash2(wp.x * spacing_hash, wp.y * spacing_hash)
		var patch := _grass_noise.get_noise_2dv(wp) * 0.5 + 0.5
		var bare := patch < 0.26 or h > smoothstep(0.26, 0.55, patch) + 0.15          # thin out toward bare/dirt patches
		var sz := (0.7 + 0.8 * _hash2(wp.y * 0.91, wp.x * 1.13)) * (0.8 + 0.5 * patch)
		var yaw := _hash2(wp.x * 2.3, wp.y * 1.7) * TAU
		var b := Basis(Vector3.UP, yaw).scaled(Vector3(sz, sz * (0.8 + 0.7 * h), sz)) if not bare else Basis.IDENTITY.scaled(Vector3(0.0001, 0.0001, 0.0001))
		mm.set_instance_transform(i, Transform3D(b, Vector3(wp.x, _ground_at(wp), wp.y)))
		var t := 0.82 + 0.3 * _hash2(wp.x * 0.5, wp.y * 0.77)
		var warm := _hash2(wp.y * 0.31, wp.x * 0.43) * 0.35
		mm.set_instance_color(i, Color(t * (1.0 + warm), t * (1.0 + warm * 0.4), t * (1.0 - warm * 0.5), 1.0))

func _scatter(mesh: Mesh, mat: Material, count: int, scale_range: Vector2, name_: String, y_off := 0.0, colors: Array = []) -> void:
	if count <= 0:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors.size() > 0
	mm.mesh = mesh
	mm.instance_count = count
	for i in count:
		var p := Vector2(_rng.randf_range(area.position.x, area.end.x), _rng.randf_range(area.position.y, area.end.y))
		var s := _rng.randf_range(scale_range.x, scale_range.y)
		var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s * _rng.randf_range(0.8, 1.3), s * _rng.randf_range(0.6, 1.2), s * _rng.randf_range(0.8, 1.3)))
		mm.set_instance_transform(i, Transform3D(b, Vector3(p.x, _ground_at(p) + y_off, p.y)))
		if colors.size() > 0:
			mm.set_instance_color(i, colors[_rng.randi() % colors.size()])
	var mi := MultiMeshInstance3D.new()
	mi.name = name_
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if name_ != "Rocks" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.visibility_range_end = 90.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mi)
	counts["props"] += count

func _flat_mat(col: Color, vertex_colors := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.95
	m.vertex_color_use_as_albedo = vertex_colors
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _build_ground_detail() -> void:
	var total := int(budget["props"])
	if level == "stylized":
		total = int(total * 0.5)
	var ground := PNLook.color("ground", Color(0.46, 0.38, 0.3))
	var foliage := PNLook.color("foliage", Color(0.32, 0.68, 0.34))
	# dirt + moss patches: flat discs just above the ground, varied in size/colour so the floor is never one flat colour
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.03
	disc.radial_segments = 12
	disc.rings = 1
	var patch_cols := [ground.darkened(0.15), ground.lightened(0.05), foliage.darkened(0.45), ground.darkened(0.3)]
	_scatter(disc, _flat_mat(Color.WHITE, true), int(total * 0.22), Vector2(0.8, 3.2), "GroundPatches", 0.02, patch_cols)
	# rocks: low-poly, squashed, random size and rotation
	var rock := SphereMesh.new()
	rock.radial_segments = 7
	rock.rings = 4
	rock.radius = 0.5
	rock.height = 0.7
	_scatter(rock, _flat_mat(Color.WHITE, true), int(total * 0.18), Vector2(0.4, 1.5), "Rocks", 0.12, [Color("#8b8579"), Color("#6f6a60"), Color("#a09a8c"), Color("#7a7468")])
	# flowers: tiny bright cards sprinkled in the grass
	var fl := QuadMesh.new()
	fl.size = Vector2(0.16, 0.16)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.vertex_color_use_as_albedo = true
	fm.albedo_texture = _dot_tex()
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_scatter(fl, fm, int(total * 0.45), Vector2(0.8, 1.6), "Flowers", 0.25, [Color("#ffd24a"), Color("#ff7a9c"), Color("#f4f4ff"), Color("#9b7bff"), Color("#ff9a3c")])
	features.append("ground_detail_%d" % counts["props"])

func _dot_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.95, 0.5)
	t.width = 32
	t.height = 32
	return t

# ------------------------------------------------------------------ the living world
func _life_list() -> Array:
	var lw: Dictionary = bible.get("livingWorld", {}) if bible.get("livingWorld") is Dictionary else {}
	if not lw.is_empty() and lw.get("active") is Array and (lw["active"] as Array).size() > 0:
		return lw["active"]
	var lk: Dictionary = look.get("living", {})
	var per := "night" if tod == "night" else ("dusk" if (tod == "dusk" or tod == "dawn") else "day")
	if lk.get(per) is Array:
		return lk[per]
	return ["songbirds", "insects", "swaying_grass"]

func _life_sounds() -> Array:
	var lw: Dictionary = bible.get("livingWorld", {}) if bible.get("livingWorld") is Dictionary else {}
	if lw.get("sounds") is Array and (lw["sounds"] as Array).size() > 0:
		return lw["sounds"]
	return ["wind"]

func _build_life() -> void:
	var active := _life_list()
	var cap := int(budget["creatures"])
	var s := PNSettings.scale()
	_amb = PNAmbient.new()
	_amb.name = "Ambient"
	var cfg := {"wind": 0.5, "birds": "none", "bird_count": 0, "butterflies": 0, "fireflies": 0, "pigeons": 0, "motes": 0.0, "leaves": 0.0, "firefly_size": 0.46 if tod == "night" else 0.3}
	var used := 0
	var want_birds := ""
	for a in active:
		match str(a):
			"songbirds": want_birds = "songbirds"
			"gulls": want_birds = "gulls"
			"hawks", "crows", "distant_bird_flocks": if want_birds == "": want_birds = "songbirds"
			"pigeons": cfg["pigeons"] = 8
			"butterflies": cfg["butterflies"] = 10
			"fireflies": cfg["fireflies"] = 26
			"insects", "dust_motes", "pollen", "moths": cfg["motes"] = 0.6
			"falling_leaves", "drifting_petals": cfg["leaves"] = 0.7
	if want_birds != "":
		cfg["birds"] = want_birds
		cfg["bird_count"] = 8
	# hard cap: scale every count so the total never exceeds this tier's creature budget
	var total := int(cfg["bird_count"]) + int(cfg["pigeons"]) + int(cfg["butterflies"]) + int(cfg["fireflies"])
	var k := minf(1.0, float(cap) / maxf(1.0, float(total) * s))
	for key in ["bird_count", "pigeons", "butterflies", "fireflies"]:
		cfg[key] = int(round(float(cfg[key]) * k))
	_amb.override_cfg = cfg
	add_child(_amb)
	_amb.build(target, area, int(_rng.seed))
	used = int(cfg["bird_count"]) + int(cfg["pigeons"]) + int(cfg["butterflies"]) + int(cfg["fireflies"])
	# creatures the base layer doesn't have: bees, dragonflies, bats, owls
	var left := maxi(0, cap - int(float(used) * s))
	if "bees" in active and left > 0:
		_make_swarm("bees", mini(8, left), Color("#ffcf3a"), 4.0, 0.9)
		left -= 8
	if "dragonflies" in active and left > 0:
		_make_swarm("dragonflies", mini(5, left), Color("#4bd3d9"), 2.6, 1.6)
		left -= 5
	if "bats" in active and left > 0:
		_make_bats(mini(10, maxi(4, left)))
	if "owls" in active and tod == "night":
		_build_owls(3 if level == "rich" else 1)
	counts["creatures"] = used + _swarms.size()
	features.append("life_" + ",".join(PackedStringArray(active.slice(0, 6))))

func _make_swarm(kind: String, count: int, col: Color, speed: float, height: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _amb._wing_mesh(0.07, 0.05)
	mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.name = kind
	mi.multimesh = mm
	var wm := _amb._wing_material(col)
	wm.set_shader_parameter("flap_speed", 40.0)
	mi.material_override = wm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 200.0
	add_child(mi)
	var data := []
	for i in count:
		data.append({"anchor": Vector3(_rng.randf_range(area.position.x, area.end.x), 0, _rng.randf_range(area.position.y, area.end.y)), "ph": _rng.randf() * TAU, "rad": _rng.randf_range(1.5, 5.0), "h": height + _rng.randf() * 0.8})
		mm.set_instance_color(i, col.srgb_to_linear())
		mm.set_instance_custom_data(i, Color(_rng.randf() * TAU, 1.0, 0.0, 0.0))
	_swarms.append({"mm": mm, "data": data, "speed": speed})

func _make_bats(count: int) -> void:
	_amb._make_flock("bats", count)
	var fl: Dictionary = _amb._flocks[_amb._flocks.size() - 1]
	for b in fl["birds"]:
		b["center"].y = _rng.randf_range(5.0, 11.0)      # bats hunt low and fast, in tight erratic circles
		b["radius"] = _rng.randf_range(5.0, 12.0)
		b["speed"] = b["speed"] * 2.2
	features.append("bats_%d" % count)

func _build_owls(count: int) -> void:
	for i in count:
		var root := Node3D.new()
		root.name = "Owl%d" % i
		var p := Vector3(_rng.randf_range(area.position.x, area.end.x) * 0.5, 0, _rng.randf_range(area.position.y, area.end.y) * 0.5)
		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.1
		pm.bottom_radius = 0.16
		pm.height = 2.4
		post.mesh = pm
		post.material_override = _flat_mat(Color("#4a3b2c"))
		post.position = Vector3(0, 1.2, 0)
		root.add_child(post)
		var body := MeshInstance3D.new()
		var bm := CapsuleMesh.new()
		bm.radius = 0.15
		bm.height = 0.46
		body.mesh = bm
		body.material_override = _flat_mat(Color("#7a6248"))
		body.position = Vector3(0, 2.62, 0)
		root.add_child(body)
		var head := Node3D.new()
		head.position = Vector3(0, 2.9, 0)
		var hm := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.15
		sm.height = 0.3
		hm.mesh = sm
		hm.material_override = _flat_mat(Color("#8a7254"))
		head.add_child(hm)
		for sx in [-1, 1]:
			var eye := MeshInstance3D.new()
			var em := SphereMesh.new()
			em.radius = 0.04
			em.height = 0.08
			eye.mesh = em
			var emat := StandardMaterial3D.new()
			emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			emat.albedo_color = Color("#ffd75a")
			eye.material_override = emat
			eye.position = Vector3(0.065 * sx, 0.02, 0.12)
			head.add_child(eye)
		root.add_child(head)
		root.position = p
		add_child(root)
		_owls.append({"head": head, "ph": _rng.randf() * TAU})
	features.append("owls_%d" % count)

# ------------------------------------------------------------------ weather + mist + light shafts
func _particles(count: int, size: Vector2, col: Color, additive := false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_color = col                       # the colour lives on the material (particle vertex colour stays white)
	m.albedo_texture = _dot_tex()
	m.no_depth_test = false
	m.fixed_size = false
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.disable_receive_shadows = true
	q.material = m
	p.mesh = q
	p.amount = maxi(1, mini(count, int(budget["particles"])))
	p.color = Color.WHITE
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(22, 0.5, 22)
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	counts["particles"] += p.amount
	return p

func _build_weather() -> void:
	if not bool(budget["weather"]) or level == "flat":
		return
	var lw: Dictionary = bible.get("livingWorld", {}) if bible.get("livingWorld") is Dictionary else {}
	var kinds: Array = []
	if tod == "overcast":
		kinds = (lw.get("weather", []) as Array) if lw.get("weather") is Array else []
		kinds = kinds.filter(func(k): return ["rain", "snow", "drifting_petals", "falling_leaves", "embers"].has(k))
	elif _opts.get("weather") is Array:
		kinds = _opts["weather"]
	if kinds.is_empty():
		return
	var kind := str(kinds[0])
	var p: CPUParticles3D
	match kind:
		"rain":
			p = _particles(500, Vector2(0.02, 0.55), Color(0.78, 0.86, 1.0, 0.5))
			p.direction = Vector3(0.12, -1, 0)
			p.initial_velocity_min = 22.0
			p.initial_velocity_max = 26.0
			p.lifetime = 0.9
			p.emission_box_extents = Vector3(22, 0.2, 22)
			p.position = Vector3(0, 16, 0)
		"snow":
			p = _particles(400, Vector2(0.09, 0.09), Color(1, 1, 1, 0.9))
			p.direction = Vector3(0.1, -1, 0)
			p.initial_velocity_min = 1.2
			p.initial_velocity_max = 2.2
			p.lifetime = 9.0
			p.position = Vector3(0, 12, 0)
		"drifting_petals":
			p = _particles(120, Vector2(0.12, 0.12), Color(1.0, 0.72, 0.82, 0.95))
			p.direction = Vector3(1, -0.3, 0.3)
			p.initial_velocity_min = 0.8
			p.initial_velocity_max = 1.8
			p.lifetime = 9.0
			p.position = Vector3(0, 7, 0)
		"embers":
			p = _particles(120, Vector2(0.08, 0.08), Color(1.0, 0.55, 0.15, 1.0), true)
			p.direction = Vector3(0.2, 1, 0)
			p.initial_velocity_min = 0.8
			p.initial_velocity_max = 2.0
			p.lifetime = 5.0
			p.position = Vector3(0, 0.5, 0)
		_:
			return
	p.name = "Weather_" + kind
	add_child(p)
	_swarms.append({"follow": p})
	features.append("weather_" + kind)

func _build_mist() -> void:
	if level == "flat" or bool(_opts.get("no_mist", false)):
		return
	var active := _life_list()
	if not ("mist" in active) and tod != "overcast":
		return
	var p := _particles(30, Vector2(9, 5), Color(0.62, 0.7, 0.9, 0.12) if tod == "night" else Color(0.85, 0.88, 0.92, 0.14))
	p.name = "Mist"
	p.direction = Vector3(1, 0, 0.3)
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.35
	p.lifetime = 14.0
	p.emission_box_extents = Vector3(34, 0.3, 34)
	p.position = Vector3(0, 0.8, 0)
	add_child(p)
	_swarms.append({"follow": p})
	features.append("mist")

func _build_light_shafts() -> void:
	if not bool(budget["shafts"]) or not forward_plus or level != "rich" or sun == null:
		return
	if not bool((look.get("ambient", {}) as Dictionary).get("light_shafts", false)) and not bool((look.get("rich", {}) as Dictionary).get("light_shafts", false)):
		return
	for i in 5:
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.3
		cm.bottom_radius = 2.6
		cm.height = 26.0
		cm.radial_segments = 10
		cone.mesh = cm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(sun.light_color.r, sun.light_color.g, sun.light_color.b, 0.05)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		cone.material_override = m
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cone.position = Vector3(_rng.randf_range(-20, 20), 12.0, _rng.randf_range(-20, 20))
		cone.rotation_degrees = Vector3(-sun.rotation_degrees.x - 90.0 + 180.0, 0, 0)
		add_child(cone)
	features.append("light_shafts")

# ------------------------------------------------------------------ sound
func _apply_audio() -> void:
	var beds: Array = []
	for s in _life_sounds():
		if not beds.has(s) and beds.size() < 4:
			beds.append(s)
	if not beds.has("wind"):
		beds.append("wind")
	PNAudio.play_beds(beds)
	features.append("beds_" + ",".join(PackedStringArray(beds)))

# ------------------------------------------------------------------ per-frame + report
func _process(delta: float) -> void:
	_t += delta
	var tp := target.global_position if target and is_instance_valid(target) else Vector3.ZERO
	if _horizon:
		_horizon.global_position = Vector3(tp.x, 0, tp.z)
	_update_grass(tp)
	for o in _owls:
		var h: Node3D = o["head"]
		h.rotation.y = sin(_t * 0.35 + o["ph"]) * 1.1
	for sw in _swarms:
		if sw.has("follow"):
			var p: Node3D = sw["follow"]
			p.global_position = Vector3(tp.x, p.global_position.y, tp.z)
			continue
		var mm: MultiMesh = sw["mm"]
		var i := 0
		for d in sw["data"]:
			if tp.distance_to(d["anchor"]) > 40.0:
				d["anchor"] = tp + Vector3(_rng.randf_range(-24, 24), 0, _rng.randf_range(-24, 24))
			var ph: float = d["ph"]
			var spd: float = sw["speed"]
			var pos: Vector3 = d["anchor"] + Vector3(sin(_t * 0.7 * spd + ph) * d["rad"], d["h"] + sin(_t * 2.1 + ph) * 0.3, cos(_t * 0.55 * spd + ph * 1.3) * d["rad"])
			var v := Vector3(cos(_t * 0.7 * spd + ph), 0, -sin(_t * 0.55 * spd + ph * 1.3))
			mm.set_instance_transform(i, Transform3D(Basis.looking_at(v.normalized() if v.length() > 0.01 else Vector3.FORWARD, Vector3.UP), pos))
			i += 1

func _report() -> void:
	last_report = {"tier": budget["tier"], "level": level, "time_of_day": tod, "renderer": RenderingServer.get_current_rendering_method(), "forward_plus": forward_plus,
		"counts": counts.duplicate(), "features": features.duplicate()}
	print("[pn-rich] tier=%s level=%s tod=%s renderer=%s grass=%d props=%d creatures=%d particles=%d features=%s" % [budget["tier"], level, tod, RenderingServer.get_current_rendering_method(), counts["grass"], counts["props"], counts["creatures"], counts["particles"], ",".join(PackedStringArray(features))])
