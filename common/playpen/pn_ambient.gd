class_name PNAmbient
extends Node3D
## Playpen kit: the LIVING WORLD ambient layer.
## Visual richness with ZERO gameplay complexity — drifting dust motes, birds /
## gulls / pigeons that circle or perch and scatter when you run past,
## butterflies, fireflies, falling leaves / blowing paper, water ripples. Which
## pieces appear (and how many) comes from the LOOK PACK's `ambient` block,
## scaled by PNSettings.scale() so it stays smooth on an 8GB / integrated-GPU box.
##
## Usage (the kit's main scene already does this):
##     var amb := PNAmbient.new(); add_child(amb)
##     amb.build(player, Rect2(-60, -60, 120, 120))
## Everything is MultiMesh / CPUParticles with cheap per-frame math — no AI.

const WINGS_SHADER := "res://playpen/shaders/wings.gdshader"

var target: Node3D
var area := Rect2(-60, -60, 120, 120)
var cfg: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _t := 0.0

# flocks: each is {mm:MultiMesh, birds:Array}
var _flocks: Array = []
var _butterflies: MultiMeshInstance3D
var _bfly_data: Array = []
var _fireflies: MultiMeshInstance3D
var _ff_data: Array = []
var _motes: CPUParticles3D
var _leaves: CPUParticles3D
var _paper: CPUParticles3D

func build(player: Node3D, play_area := Rect2(-60, -60, 120, 120), seed_value := 4242) -> void:
	target = player
	area = play_area
	_rng.seed = seed_value
	cfg = PNLook.ambient_cfg()
	var s := PNSettings.scale()
	PNWind.gust.connect(_on_gust)
	if float(cfg.get("motes", 0.0)) > 0.0:
		_make_motes(int(120.0 * float(cfg["motes"]) * s))
	var kind := str(cfg.get("birds", "none"))
	var bc := int(round(float(cfg.get("bird_count", 0)) * s))
	if kind != "none" and bc > 0:
		_make_flock(kind, bc)
	var pig := int(round(float(cfg.get("pigeons", 0)) * s))
	if pig > 0:
		_make_flock("pigeons", pig, true)
	var bf := int(round(float(cfg.get("butterflies", 0)) * s))
	if bf > 0:
		_make_butterflies(bf)
	var ff := int(round(float(cfg.get("fireflies", 0)) * s))
	if ff > 0:
		_make_fireflies(ff)
	if float(cfg.get("leaves", 0.0)) > 0.0:
		_make_leaves(int(30.0 * float(cfg["leaves"]) * s))
	var paper := int(round(float(cfg.get("blowing_paper", 0)) * s))
	if paper > 0:
		_make_paper(paper)

func _process(delta: float) -> void:
	_t += delta
	var tp := target.global_position if target and is_instance_valid(target) else Vector3.ZERO
	for fl in _flocks:
		_update_flock(fl, delta, tp)
	_update_butterflies(delta, tp)
	_update_fireflies(delta, tp)
	if _motes:
		_motes.global_position = tp + Vector3(0, 3.0, 0)
	if _leaves:
		_leaves.global_position = tp + Vector3(0, 9.0, 0)
	if _paper:
		_paper.global_position = tp + Vector3(0, 0.3, 0)

# ----------------------------------------------------------------- meshes
func _wing_mesh(span := 0.5, length := 0.32) -> ArrayMesh:
	# a tiny bird: body triangle + two wing triangles. Local +Z is forward.
	var verts := PackedVector3Array([
		Vector3(0, 0, length), Vector3(-0.05, 0, -length * 0.5), Vector3(0.05, 0, -length * 0.5),   # body
		Vector3(-0.04, 0, length * 0.2), Vector3(-span, 0, -length * 0.1), Vector3(-0.04, 0, -length * 0.4),  # left wing
		Vector3(0.04, 0, length * 0.2), Vector3(0.04, 0, -length * 0.4), Vector3(span, 0, -length * 0.1),     # right wing
	])
	var normals := PackedVector3Array()
	for i in verts.size():
		normals.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

func _wing_material(tip: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(WINGS_SHADER)
	mat.set_shader_parameter("tip_color", tip)
	return mat

func _multimesh(mesh: Mesh, count: int, custom := true) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = count
	return mm

# ----------------------------------------------------------------- flocks
func _bird_colors(kind: String) -> Array:
	match kind:
		"gulls": return [Color(0.97, 0.97, 0.98), Color(0.2, 0.22, 0.28)]
		"pigeons": return [Color(0.58, 0.6, 0.66), Color(0.35, 0.37, 0.45)]
		"songbirds": return [Color(0.95, 0.6, 0.25), Color(0.25, 0.2, 0.3)]
	return [Color(0.2, 0.2, 0.25), Color(0.1, 0.1, 0.12)]

func _make_flock(kind: String, count: int, perching := false) -> void:
	var cols := _bird_colors(kind)
	var mm := _multimesh(_wing_mesh(0.34 if kind != "gulls" else 0.5, 0.26), count)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _wing_material(cols[1])
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 200.0
	add_child(mi)
	var birds := []
	for i in count:
		var home := Vector3(_rng.randf_range(area.position.x, area.end.x), 0.0, _rng.randf_range(area.position.y, area.end.y))
		var b := {
			"center": Vector3(_rng.randf_range(area.position.x, area.end.x), _rng.randf_range(14.0, 26.0), _rng.randf_range(area.position.y, area.end.y)),
			"radius": _rng.randf_range(10.0, 26.0), "angle": _rng.randf() * TAU, "speed": _rng.randf_range(0.6, 1.1) * (1 if _rng.randf() > 0.5 else -1),
			"phase": _rng.randf() * TAU, "home": home, "state": "fly",
			"pos": Vector3.ZERO, "fly_until": 0.0
		}
		if perching:
			b["state"] = "perch"
			b["pos"] = home
		birds.append(b)
		mm.set_instance_color(i, cols[0].lerp(cols[1], _rng.randf() * 0.25).srgb_to_linear())
		mm.set_instance_custom_data(i, Color(b["phase"], 1.0, 1.0, 0.0))
	_flocks.append({"mm": mm, "birds": birds, "perching": perching, "kind": kind})

func _update_flock(fl: Dictionary, delta: float, tp: Vector3) -> void:
	var mm: MultiMesh = fl["mm"]
	var i := 0
	for b in fl["birds"]:
		var state: String = b["state"]
		var pos: Vector3
		var fwd := Vector3.FORWARD
		if state == "fly":
			b["angle"] += delta * b["speed"] * (14.0 / b["radius"])
			var a: float = b["angle"]
			var c: Vector3 = b["center"]
			var r: float = b["radius"]
			pos = c + Vector3(cos(a) * r, sin(_t * 0.5 + b["phase"]) * 1.2, sin(a) * r)
			var tang := Vector3(-sin(a), 0.0, cos(a)) * signf(b["speed"])
			fwd = tang
			if fl["perching"] and _t > b["fly_until"]:
				# come back down to land at home
				b["state"] = "land"
				b["pos"] = pos
		elif state == "land":
			var home: Vector3 = b["home"]
			var p: Vector3 = b["pos"]
			p = p.move_toward(home, delta * 7.0)
			fwd = (home - p).normalized() if p.distance_to(home) > 0.05 else Vector3.FORWARD
			b["pos"] = p
			pos = p
			if p.distance_to(home) < 0.06:
				b["state"] = "perch"
		else: # perch
			pos = b["home"]
			pos.y += 0.12
			fwd = Vector3(sin(b["phase"]), 0, cos(b["phase"]))
			if tp.distance_to(b["home"]) < 5.5:
				# scatter: take off, climb, then circle for a while
				b["state"] = "fly"
				b["center"] = b["home"] + Vector3(_rng.randf_range(-8, 8), _rng.randf_range(9.0, 15.0), _rng.randf_range(-8, 8))
				b["angle"] = atan2(b["home"].z - b["center"].z, b["home"].x - b["center"].x)
				b["fly_until"] = _t + _rng.randf_range(5.0, 9.0)
		var basis := Basis.looking_at(fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD, Vector3.UP)
		if state == "perch":
			mm.set_instance_custom_data(i, Color(b["phase"], 0.0, 1.0, 0.0))
		else:
			mm.set_instance_custom_data(i, Color(b["phase"], 1.0 if state == "land" else (0.0 if sin(_t * 0.7 + b["phase"]) > 0.55 else 1.0), 1.0, 0.0))
		mm.set_instance_transform(i, Transform3D(basis, pos))
		i += 1

# ----------------------------------------------------------------- butterflies
func _make_butterflies(count: int) -> void:
	var mm := _multimesh(_wing_mesh(0.11, 0.07), count)
	_butterflies = MultiMeshInstance3D.new()
	_butterflies.multimesh = mm
	_butterflies.material_override = _wing_material(Color(1, 1, 1))
	_butterflies.material_override.set_shader_parameter("flap_speed", 22.0)
	_butterflies.material_override.set_shader_parameter("flap_amount", 1.6)
	_butterflies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_butterflies.extra_cull_margin = 200.0
	add_child(_butterflies)
	var palette := [Color(1.0, 0.8, 0.2), Color(1.0, 0.45, 0.6), Color(0.45, 0.7, 1.0), Color(0.95, 0.95, 1.0)]
	for i in count:
		var anchor := Vector3(_rng.randf_range(area.position.x, area.end.x), 0.0, _rng.randf_range(area.position.y, area.end.y))
		_bfly_data.append({"anchor": anchor, "phase": _rng.randf() * TAU, "rad": _rng.randf_range(1.5, 4.0), "h": _rng.randf_range(0.8, 2.0)})
		mm.set_instance_color(i, palette[i % palette.size()].srgb_to_linear())
		mm.set_instance_custom_data(i, Color(_rng.randf() * TAU, 1.0, 0.0, 0.0))

func _update_butterflies(_delta: float, tp: Vector3) -> void:
	if _butterflies == null:
		return
	var mm := _butterflies.multimesh
	for i in _bfly_data.size():
		var d: Dictionary = _bfly_data[i]
		# re-home near the player so they're always where you can see them
		if tp.distance_to(d["anchor"]) > 45.0:
			d["anchor"] = tp + Vector3(_rng.randf_range(-30, 30), 0, _rng.randf_range(-30, 30))
		var ph: float = d["phase"]
		var a: Vector3 = d["anchor"]
		var p := a + Vector3(sin(_t * 0.6 + ph) * d["rad"], d["h"] + sin(_t * 1.7 + ph) * 0.35, cos(_t * 0.45 + ph * 1.3) * d["rad"])
		var v := Vector3(cos(_t * 0.6 + ph) * 0.6, 0, -sin(_t * 0.45 + ph * 1.3) * 0.45)
		mm.set_instance_transform(i, Transform3D(Basis.looking_at(v.normalized() if v.length() > 0.01 else Vector3.FORWARD, Vector3.UP), p))

# ----------------------------------------------------------------- fireflies
func _make_fireflies(count: int) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot()
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.95, 0.5)
	mat.emission_energy_multiplier = 2.0
	mat.disable_receive_shadows = true
	quad.material = mat
	var mm := _multimesh(quad, count, false)
	_fireflies = MultiMeshInstance3D.new()
	_fireflies.multimesh = mm
	_fireflies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fireflies.extra_cull_margin = 200.0
	add_child(_fireflies)
	for i in count:
		_ff_data.append({"off": Vector3(_rng.randf_range(-18, 18), _rng.randf_range(0.5, 3.5), _rng.randf_range(-18, 18)), "ph": _rng.randf() * TAU, "sp": _rng.randf_range(0.2, 0.5)})
		mm.set_instance_color(i, Color(1.0, 0.95, 0.5, 1.0))

func _update_fireflies(_delta: float, tp: Vector3) -> void:
	if _fireflies == null:
		return
	var mm := _fireflies.multimesh
	for i in _ff_data.size():
		var d: Dictionary = _ff_data[i]
		var o: Vector3 = d["off"]
		var ph: float = d["ph"]
		var sp: float = d["sp"]
		var p := tp + o + Vector3(sin(_t * sp + ph) * 1.5, sin(_t * sp * 1.3 + ph) * 0.6, cos(_t * sp * 0.8 + ph) * 1.5)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, p))
		var glow := 0.5 + 0.5 * sin(_t * 2.2 + ph * 3.0)
		mm.set_instance_color(i, Color(1.0, 0.95, 0.5, clampf(glow * glow, 0.0, 1.0)))

func _soft_dot() -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex

# ----------------------------------------------------------------- particles: motes, leaves, paper
func _particle_quad(size: float, color: Color, billboard := true) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.albedo_texture = _soft_dot() if billboard else null
	if billboard:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	else:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = mat
	return q

func _make_motes(count: int) -> void:
	if count < 4:
		return
	_motes = CPUParticles3D.new()
	_motes.amount = count
	_motes.lifetime = 9.0
	_motes.preprocess = 9.0
	_motes.mesh = _particle_quad(0.06, Color(1, 0.97, 0.85, 0.65))
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_motes.emission_box_extents = Vector3(14, 4, 14)
	_motes.gravity = Vector3(0.12, 0.03, 0.05)
	_motes.initial_velocity_min = 0.05
	_motes.initial_velocity_max = 0.25
	_motes.direction = Vector3(1, 0.2, 0.3)
	_motes.spread = 180.0
	_motes.local_coords = false
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_motes)

func _make_leaves(count: int) -> void:
	if count < 3:
		return
	_leaves = CPUParticles3D.new()
	_leaves.amount = count
	_leaves.lifetime = 8.0
	_leaves.preprocess = 8.0
	var tint := PNLook.color("foliage_dark", Color(0.3, 0.6, 0.3)).lerp(PNLook.color("primary", Color(1, 0.8, 0.3)), 0.35)
	_leaves.mesh = _particle_quad(0.14, tint, false)
	_leaves.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_leaves.emission_box_extents = Vector3(18, 0.5, 18)
	_leaves.gravity = Vector3(0.6, -0.9, 0.25)
	_leaves.initial_velocity_min = 0.1
	_leaves.initial_velocity_max = 0.5
	_leaves.angular_velocity_min = -180.0
	_leaves.angular_velocity_max = 180.0
	_leaves.direction = Vector3(1, -0.2, 0.4)
	_leaves.spread = 40.0
	_leaves.damping_min = 0.4
	_leaves.damping_max = 1.0
	_leaves.local_coords = false
	_leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_leaves)

func _make_paper(count: int) -> void:
	_paper = CPUParticles3D.new()
	_paper.amount = maxi(count, 2)
	_paper.lifetime = 7.0
	_paper.preprocess = 7.0
	_paper.mesh = _particle_quad(0.22, Color(0.97, 0.96, 0.9, 1.0), false)
	_paper.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_paper.emission_box_extents = Vector3(16, 0.1, 16)
	_paper.gravity = Vector3(0, -0.6, 0)
	_paper.initial_velocity_min = 1.2
	_paper.initial_velocity_max = 3.0
	_paper.angular_velocity_min = -360.0
	_paper.angular_velocity_max = 360.0
	_paper.direction = Vector3(1, 0.35, 0.3)
	_paper.spread = 25.0
	_paper.local_coords = false
	_paper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_paper)

func _on_gust(strength: float) -> void:
	# a gust briefly kicks the leaves / paper along the wind
	var dir := PNWind.direction
	for p in [_leaves, _paper]:
		if p:
			p.gravity.x = dir.x * (1.0 + strength * 3.0)
			p.gravity.z = dir.y * (1.0 + strength * 3.0)
			get_tree().create_timer(2.5).timeout.connect(func(): if is_instance_valid(p): p.gravity.x = dir.x * 0.6; p.gravity.z = dir.y * 0.4)

# ----------------------------------------------------------------- water helpers
## A subdivided plane with the pack's animated water on it.
static func make_water(parent: Node, size: Vector2, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	pm.subdivide_width = int(clampf(size.x * 0.6, 8, 90))
	pm.subdivide_depth = int(clampf(size.y * 0.6, 8, 90))
	mi.mesh = pm
	mi.material_override = PNLook.water_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = at
	return mi

## Ring + droplets where something enters or lands in water.
static func ripple(parent: Node, at: Vector3, scale_factor := 1.0) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.45
	tm.outer_radius = 0.5
	ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.8)
	ring.material_override = mat
	ring.scale = Vector3(0.3, 0.05, 0.3) * scale_factor
	parent.add_child(ring)
	ring.global_position = at + Vector3(0, 0.03, 0)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(3.0, 0.05, 3.0) * scale_factor, 0.9)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.9)
	tw.chain().tween_callback(ring.queue_free)
	Juice.dust(at + Vector3(0, 0.1, 0), 10, Color(0.85, 0.95, 1.0, 0.85), 0.12)
