class_name PNProps
extends RefCounted
## Playpen kit: ready-made, look-pack-colored PROPS built from primitives with the
## kit's shaders — palms, trees, bushes, flowers, lamps, glowing signs, litter,
## crates. Nothing here needs an asset download, so a first pass is never a blank
## gray box; swap in catalog models later without changing the level code.

static func _mm(mesh: Mesh, mat: Material, parent: Node3D, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

## Palms are drawn as MultiMeshes of two SHARED meshes (a bent trunk and a frond
## crown) — a whole beach of palms costs ~6 draw calls, not hundreds. Each palm
## still sways with the global wind. `placements`: Array of
## {"pos": Vector3, "height": float (optional), "seed": int (optional)}.
static var _palm_cache := {}

static func palms(parent: Node3D, placements: Array) -> void:
	if placements.is_empty():
		return
	var variants := 3
	var trunk_groups: Array = []
	for i in variants:
		trunk_groups.append([])
	for pl in placements:
		var sd := int(pl.get("seed", 0)) + int(pl["pos"].x * 31) + int(pl["pos"].z * 17)
		trunk_groups[absi(sd) % variants].append(pl)
	var trunk_mat := PNLook.toon(Color(0.52, 0.36, 0.22).lerp(PNLook.color("ground", Color(0.6, 0.45, 0.3)), 0.2))
	var frond_mat := PNLook.sway_material(PNLook.color("foliage_dark", Color(0.2, 0.55, 0.3)), PNLook.color("foliage", Color(0.4, 0.8, 0.4)), 2.6, 0.5)
	frond_mat.set_shader_parameter("flutter", 0.12)
	frond_mat.set_shader_parameter("pin_axis", 0)
	for v in variants:
		var group: Array = trunk_groups[v]
		if group.is_empty():
			continue
		var trunk_mesh := _palm_trunk(v)
		var crown_mesh := _palm_crown(v)
		var top: Vector3 = trunk_mesh.get_meta("top")
		var tmm := MultiMesh.new()
		tmm.transform_format = MultiMesh.TRANSFORM_3D
		tmm.mesh = trunk_mesh
		tmm.instance_count = group.size()
		var cmm := MultiMesh.new()
		cmm.transform_format = MultiMesh.TRANSFORM_3D
		cmm.mesh = crown_mesh
		cmm.instance_count = group.size()
		for i in group.size():
			var pl: Dictionary = group[i]
			var h := float(pl.get("height", 6.0)) / 6.0
			var yaw := float(absi(int(pl["pos"].x * 13 + pl["pos"].z * 7))) * 0.7
			var basis := Basis(Vector3.UP, yaw).scaled(Vector3(1, h, 1))
			tmm.set_instance_transform(i, Transform3D(basis, pl["pos"]))
			cmm.set_instance_transform(i, Transform3D(basis, pl["pos"] + basis * top))
		var tmi := MultiMeshInstance3D.new()
		tmi.multimesh = tmm
		tmi.material_override = trunk_mat
		parent.add_child(tmi)
		var cmi := MultiMeshInstance3D.new()
		cmi.multimesh = cmm
		cmi.material_override = frond_mat
		cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(cmi)

## One palm (convenience). Prefer palms() for more than a few.
static func palm(parent: Node3D, pos: Vector3, height := 6.0, seed_value := 0) -> void:
	palms(parent, [{"pos": pos, "height": height, "seed": seed_value}])

static func _palm_trunk(variant: int) -> ArrayMesh:
	var key := "trunk%d" % variant
	if _palm_cache.has(key):
		return _palm_cache[key]
	var lean: Vector2 = [Vector2(0.9, 0.25), Vector2(-0.7, 0.55), Vector2(0.3, -0.85)][variant]
	var segs := 6
	var sides := 7
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for i in segs + 1:
		var t := float(i) / segs
		var c := Vector3(lean.x * t * t * 0.9, 6.0 * t, lean.y * t * t * 0.9)
		rings.append({"c": c, "r": lerpf(0.3, 0.17, t)})
	for i in segs:
		var r0: Dictionary = rings[i]
		var r1: Dictionary = rings[i + 1]
		for k in sides:
			var a0 := TAU * k / sides
			var a1 := TAU * (k + 1) / sides
			var p00: Vector3 = r0["c"] + Vector3(cos(a0), 0, sin(a0)) * r0["r"]
			var p01: Vector3 = r0["c"] + Vector3(cos(a1), 0, sin(a1)) * r0["r"]
			var p10: Vector3 = r1["c"] + Vector3(cos(a0), 0, sin(a0)) * r1["r"]
			var p11: Vector3 = r1["c"] + Vector3(cos(a1), 0, sin(a1)) * r1["r"]
			var n0 := Vector3(cos(a0), 0, sin(a0))
			var n1 := Vector3(cos(a1), 0, sin(a1))
			for tri in [[p00, n0], [p10, n0], [p11, n1], [p00, n0], [p11, n1], [p01, n1]]:
				st.set_normal(tri[1])
				st.add_vertex(tri[0])
	var m := st.commit()
	m.set_meta("top", rings[segs]["c"])
	_palm_cache[key] = m
	return m

static func _palm_crown(variant: int) -> ArrayMesh:
	var key := "crown%d" % variant
	if _palm_cache.has(key):
		return _palm_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + variant
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fronds := 8
	for i in fronds:
		var yaw := TAU * i / fronds + rng.randf_range(-0.15, 0.15)
		var droop := rng.randf_range(0.2, 0.55)
		var length := rng.randf_range(2.3, 2.9)
		# a frond strip along +X, three segments, drooping toward the tip
		var pts := []
		for j in 4:
			var t := float(j) / 3.0
			pts.append(Vector3(t * length, 0.35 * sin(t * PI * 0.8) - droop * t * t * length * 0.5, 0.0))
		for j in 3:
			var w0 := lerpf(0.5, 0.2, float(j) / 3.0)
			var w1 := lerpf(0.5, 0.2, float(j + 1) / 3.0)
			var a: Vector3 = pts[j]
			var b: Vector3 = pts[j + 1]
			var q := [a + Vector3(0, 0, -w0), b + Vector3(0, 0, -w1), b + Vector3(0, 0, w1), a + Vector3(0, 0, w0)]
			for idx in [0, 1, 2, 0, 2, 3]:
				var p: Vector3 = Basis(Vector3.UP, yaw) * q[idx]
				st.set_normal(Vector3.UP)
				st.add_vertex(p)
	var m := st.commit()
	_palm_cache[key] = m
	return m

## A forest in 2 MultiMeshes (trunks + merged foliage). `placements`: Array of
## {"pos": Vector3, "height": float (optional), "seed": int (optional)}. Foliage sways.
static func trees(parent: Node3D, placements: Array) -> void:
	if placements.is_empty():
		return
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.26
	trunk.height = 2.6
	trunk.radial_segments = 6
	trunk.rings = 1
	var fb := PNBatch.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in 3:
		var s := SphereMesh.new()
		s.radius = rng.randf_range(1.0, 1.4)
		s.height = s.radius * 2.0
		s.radial_segments = 8
		s.rings = 4
		fb.add_mesh(s, Transform3D(Basis.IDENTITY, Vector3(rng.randf_range(-0.5, 0.5), 3.1 + i * 0.75, rng.randf_range(-0.5, 0.5))), Color.WHITE)
	var foliage_inst := fb.commit(null)
	var foliage := foliage_inst.mesh
	foliage_inst.free()   # only the mesh is needed
	var tmm := MultiMesh.new()
	tmm.transform_format = MultiMesh.TRANSFORM_3D
	tmm.mesh = trunk
	tmm.instance_count = placements.size()
	var fmm := MultiMesh.new()
	fmm.transform_format = MultiMesh.TRANSFORM_3D
	fmm.use_colors = true
	fmm.mesh = foliage
	fmm.instance_count = placements.size()
	var tints := [PNLook.color("foliage"), PNLook.color("foliage").lerp(PNLook.color("primary"), 0.25), PNLook.color("foliage_dark").lightened(0.15)]
	for i in placements.size():
		var pl: Dictionary = placements[i]
		var sd := int(pl.get("seed", 0)) + i
		var h := float(pl.get("height", 5.0)) / 5.0
		var basis := Basis(Vector3.UP, float(sd) * 1.7).scaled(Vector3(h, h, h))
		tmm.set_instance_transform(i, Transform3D(basis, pl["pos"] + Vector3(0, 1.3 * h, 0)))
		fmm.set_instance_transform(i, Transform3D(basis, pl["pos"]))
		fmm.set_instance_color(i, (tints[absi(sd) % tints.size()] as Color).srgb_to_linear())
	var tmi := MultiMeshInstance3D.new()
	tmi.multimesh = tmm
	tmi.material_override = PNLook.toon(PNLook.color("ground", Color(0.5, 0.38, 0.25)).darkened(0.35))
	parent.add_child(tmi)
	var fmat := PNLook.sway_material(Color.WHITE, Color.WHITE, 6.0, 0.12)
	fmat.set_shader_parameter("tip_color", Color(1.12, 1.12, 1.05))
	var fmi := MultiMeshInstance3D.new()
	fmi.multimesh = fmm
	fmi.material_override = fmat
	parent.add_child(fmi)

static func bush(parent: Node3D, pos: Vector3, size := 1.0) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = 0.6 * size
	s.height = 0.9 * size
	s.radial_segments = 8
	s.rings = 4
	var m := PNLook.sway_material(PNLook.color("foliage_dark"), PNLook.color("foliage"), 0.9 * size, 0.1)
	return _mm(s, m, parent, pos + Vector3(0, 0.35 * size, 0))

## A tuft of grass blades / flowers that bends in the wind and away from the player.
static func flower_patch(parent: Node3D, pos: Vector3, count := 10, color := Color(1, 0.5, 0.6), seed_value := 0) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + int(pos.x * 7) + int(pos.z * 11)
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	var stem := QuadMesh.new()
	stem.size = Vector2(0.06, 0.5)
	stem.center_offset = Vector3(0, 0.25, 0)
	var stem_mat := PNLook.sway_material(PNLook.color("foliage_dark"), PNLook.color("foliage"), 0.5, 0.45)
	var head := SphereMesh.new()
	head.radius = 0.1
	head.height = 0.14
	head.radial_segments = 6
	head.rings = 3
	var head_mat := PNLook.sway_material(color, color.lightened(0.25), 0.55, 0.45)
	for i in count:
		var o := Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))
		_mm(stem, stem_mat, root, o).rotation.y = rng.randf() * PI
		_mm(head, head_mat, root, o + Vector3(0, 0.52, 0))
	return root

## Many street lamps at once: two MultiMeshes (poles + glowing heads).
static func lamps(parent: Node3D, spots: Array, height := 5.0, glow := 1.0) -> void:
	if spots.is_empty():
		return
	var pole := CylinderMesh.new()
	pole.top_radius = 0.07
	pole.bottom_radius = 0.1
	pole.height = height
	pole.radial_segments = 6
	pole.rings = 1
	var head := SphereMesh.new()
	head.radius = 0.28
	head.height = 0.56
	head.radial_segments = 8
	head.rings = 4
	var lit := PNLook.color("primary", Color(1, 0.85, 0.5)).lightened(0.3)
	var pm := MultiMesh.new()
	pm.transform_format = MultiMesh.TRANSFORM_3D
	pm.mesh = pole
	pm.instance_count = spots.size()
	var hm := MultiMesh.new()
	hm.transform_format = MultiMesh.TRANSFORM_3D
	hm.mesh = head
	hm.instance_count = spots.size()
	for i in spots.size():
		pm.set_instance_transform(i, Transform3D(Basis.IDENTITY, spots[i] + Vector3(0, height * 0.5, 0)))
		hm.set_instance_transform(i, Transform3D(Basis.IDENTITY, spots[i] + Vector3(0, height + 0.15, 0)))
	var pmi := MultiMeshInstance3D.new()
	pmi.multimesh = pm
	pmi.material_override = PNLook.toon(PNLook.color("shadow", Color(0.3, 0.3, 0.4)).darkened(0.2))
	pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(pmi)
	var hmi := MultiMeshInstance3D.new()
	hmi.multimesh = hm
	hmi.material_override = PNLook.toon(lit, lit, 1.5 + glow * 1.5)
	hmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(hmi)

## Many glowing shop signs at once (one MultiMesh, pulsing, per-sign color).
## `signs`: Array of {"pos": Vector3, "size": Vector2, "color": Color, "yaw": float, "text": String}.
## Text labels are real Label3D nodes, so only the first few are drawn, and only
## on High quality.
static func signs(parent: Node3D, signs: Array) -> void:
	if signs.is_empty():
		return
	var box := BoxMesh.new()
	box.size = Vector3(1, 1, 0.18)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box
	mm.instance_count = signs.size()
	for i in signs.size():
		var sg: Dictionary = signs[i]
		var sz: Vector2 = sg["size"]
		var basis := Basis(Vector3.UP, float(sg.get("yaw", 0.0))).scaled(Vector3(sz.x, sz.y, 1.0))
		mm.set_instance_transform(i, Transform3D(basis, sg["pos"]))
		mm.set_instance_color(i, (sg["color"] as Color).srgb_to_linear())
	var mat := PNLook.glow_material(Color.WHITE, 1.3)
	mat.set_shader_parameter("pulse_amount", 0.18)
	mat.set_shader_parameter("bob_height", 0.0)
	mat.set_shader_parameter("intensity", 1.9)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if PNSettings.quality == PNSettings.Quality.HIGH:
		var n := 0
		for sg in signs:
			if str(sg.get("text", "")) == "" or n >= 10:
				continue
			n += 1
			var l := Label3D.new()
			l.text = sg["text"]
			l.font_size = 72
			l.pixel_size = 0.0075 * sg["size"].y / 0.9
			l.modulate = Color(1, 1, 1)
			l.outline_size = 0
			l.position = sg["pos"] + Basis(Vector3.UP, float(sg.get("yaw", 0.0))) * Vector3(0, 0, 0.11)
			l.rotation.y = float(sg.get("yaw", 0.0))
			parent.add_child(l)

## A street lamp: pole + glowing head (emission + bloom, no real light = cheap).
static func lamp(parent: Node3D, pos: Vector3, height := 5.0, glow := 1.0) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.07
	pole.bottom_radius = 0.1
	pole.height = height
	pole.radial_segments = 6
	_mm(pole, PNLook.toon(PNLook.color("shadow", Color(0.3, 0.3, 0.4)).darkened(0.2)), root, Vector3(0, height * 0.5, 0))
	var head := SphereMesh.new()
	head.radius = 0.28
	head.height = 0.56
	head.radial_segments = 8
	head.rings = 4
	var lit := PNLook.color("primary", Color(1, 0.85, 0.5)).lightened(0.3)
	_mm(head, PNLook.toon(lit, lit, 1.5 + glow * 1.5), root, Vector3(0, height + 0.15, 0))
	return root

## A glowing shop sign / neon box. `text` is drawn with a Label3D when non-empty.
static func sign(parent: Node3D, pos: Vector3, size := Vector2(2.4, 0.9), color := Color(1, 0.35, 0.4), text := "", yaw := 0.0) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)
	var box := BoxMesh.new()
	box.size = Vector3(size.x, size.y, 0.18)
	var mat := PNLook.glow_material(color, pos.x * 0.37 + pos.z * 0.11)
	mat.set_shader_parameter("pulse_amount", 0.18)
	mat.set_shader_parameter("bob_height", 0.0)
	mat.set_shader_parameter("intensity", 1.9)
	_mm(box, mat, root)
	if text != "":
		var l := Label3D.new()
		l.text = text
		l.font_size = 72
		l.pixel_size = 0.0075 * size.y / 0.9
		l.modulate = Color(1, 1, 1)
		l.outline_size = 0
		l.position = Vector3(0, 0, 0.11)
		l.no_depth_test = false
		root.add_child(l)
	return root

static func crate(parent: Node3D, pos: Vector3, size := 1.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos + Vector3(0, size * 0.5, 0)
	parent.add_child(body)
	var box := BoxMesh.new()
	box.size = Vector3.ONE * size
	_mm(box, PNLook.toon(PNLook.color("accent", Color(0.8, 0.5, 0.3)).darkened(0.1)), body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3.ONE * size
	cs.shape = bs
	body.add_child(cs)
	return body

## A piece of litter (soda can / paper bag / bottle) — also the collectible for
## "pick up trash" games. Returns an Area3D (group "collectible") that only
## carries the physics; ALL litter visuals are drawn by 3 MultiMeshes created by
## finish_litter(parent) — 50 pieces of trash cost 3 draw calls, not 50.
static var _litter_pending := {}

static func litter(parent: Node3D, pos: Vector3, kind := -1, seed_value := 0) -> Area3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + int(pos.x * 3) + int(pos.z * 5)
	if kind < 0:
		kind = rng.randi() % 3
	var area := Area3D.new()
	area.position = pos + Vector3(0, 0.45, 0)
	area.add_to_group("collectible")
	area.set_meta("kind", ["can", "bag", "bottle"][kind])
	parent.add_child(area)
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.7
	cs.shape = sp
	area.add_child(cs)
	area.collision_layer = 0
	area.collision_mask = 2  # the player body lives on layer 2
	var key := parent.get_instance_id()
	if not _litter_pending.has(key):
		_litter_pending[key] = [[], [], []]
	var basis := Basis.from_euler(Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4)))
	_litter_pending[key][kind].append({"area": area, "xform": Transform3D(basis, area.position)})
	return area

## Call once after placing litter: builds the shared MultiMeshes. Collected
## pieces vanish from them automatically.
static func finish_litter(parent: Node3D) -> void:
	var key := parent.get_instance_id()
	if not _litter_pending.has(key):
		return
	var groups: Array = _litter_pending[key]
	_litter_pending.erase(key)
	var meshes: Array[Mesh] = []
	var can := CylinderMesh.new()
	can.top_radius = 0.1
	can.bottom_radius = 0.1
	can.height = 0.28
	can.radial_segments = 8
	can.rings = 1
	meshes.append(can)
	var bag := BoxMesh.new()
	bag.size = Vector3(0.3, 0.34, 0.18)
	meshes.append(bag)
	var bottle := CylinderMesh.new()
	bottle.top_radius = 0.05
	bottle.bottom_radius = 0.1
	bottle.height = 0.38
	bottle.radial_segments = 8
	bottle.rings = 1
	meshes.append(bottle)
	var cols := [Color(0.9, 0.25, 0.25), Color(0.85, 0.7, 0.45), Color(0.4, 0.8, 0.9)]
	for k in 3:
		var items: Array = groups[k]
		if items.is_empty():
			continue
		var gm := PNLook.glow_material(cols[k], float(k) * 2.0)
		gm.set_shader_parameter("intensity", 1.3)
		gm.set_shader_parameter("bob_height", 0.08)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[k]
		mm.instance_count = items.size()
		for i in items.size():
			mm.set_instance_transform(i, items[i]["xform"])
			var area: Area3D = items[i]["area"]
			var idx := i
			var xf: Transform3D = items[i]["xform"]
			area.tree_exiting.connect(func(): mm.set_instance_transform(idx, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), xf.origin)))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = gm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
