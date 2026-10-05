class_name PNCity
extends RefCounted
## Playpen kit: CITY BLOCK BUILDER.
## Streets, sidewalks, lane lines, buildings with lit windows, rooftop clutter,
## street lamps, glowing shop signs, palms/planters, and a generic landmark
## silhouette — from simple parameters. Nothing trademarked: for a real-city theme
## ("Dallas", "Tokyo"...) pick a `landmark` style and rename signs; the SHAPES are
## generic (a sphere-on-a-spire tower, a glass slab, a stepped deco tower, an arch).
##
##   var city := PNCity.build(self, {"blocks": Vector2i(4, 4), "seed": 9, "landmark": "needle_tower"})
##   player.global_position = city.spawn
##
## Returns {bounds: Rect2, spawn: Vector3, street_points: Array[Vector3],
##          sidewalk_points: Array[Vector3], landmarks: Array[Node3D], extent: float,
##          map: {blocks: Array[Rect2], streets: Array[Rect2]}}   <- feed straight to PNMinimap

const SIGN_WORDS := ["CAFE", "DINER", "PIZZA", "TACOS", "BOOKS", "ARCADE", "BAKERY", "NOODLES", "BBQ", "RECORDS", "FLORIST", "DONUTS"]

static func build(parent: Node3D, opts := {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(opts.get("seed", 1))
	var blocks: Vector2i = opts.get("blocks", Vector2i(4, 4))
	var block := float(opts.get("block_size", 38.0))
	var street := float(opts.get("street_width", 11.0))
	var pitch := block + street
	var total := Vector2(blocks.x * pitch + street, blocks.y * pitch + street)
	var origin := Vector3(-total.x * 0.5, 0, -total.y * 0.5)
	var root := Node3D.new()
	root.name = "City"
	parent.add_child(root)
	var asphalt_col: Color = PNLook.color("street", Color(0.36, 0.38, 0.41))
	var walk_col: Color = PNLook.color("sidewalk", Color(0.8, 0.79, 0.76))

	# ground slab (one collider for the whole city, asphalt under everything)
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	root.add_child(ground)
	var gm := MeshInstance3D.new()
	var gp := PlaneMesh.new()
	gp.size = total + Vector2(120, 120)
	gm.mesh = gp
	gm.material_override = PNLook.toon(asphalt_col)
	gm.position = Vector3(0, 0.0, 0)
	ground.add_child(gm)
	var gc := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = Vector3(total.x + 120, 1.0, total.y + 120)
	gc.shape = gs
	gc.position = Vector3(0, -0.5, 0)
	ground.add_child(gc)

	var street_points: Array = []
	var sidewalk_points: Array = []
	var landmarks: Array = []
	var lamp_spots: Array = []
	var block_rects: Array = []
	var batch := PNBatch.new()
	var colliders := StaticBody3D.new()
	colliders.name = "Buildings"
	colliders.collision_layer = 1
	root.add_child(colliders)
	var sign_list: Array = []
	var palm_list: Array = []
	var street_rects: Array = []
	for ix in range(blocks.x + 1):
		street_rects.append(Rect2(origin.x + ix * pitch, origin.z, street, total.y))
	for iz in range(blocks.y + 1):
		street_rects.append(Rect2(origin.x, origin.z + iz * pitch, total.x, street))

	# lane lines: one MultiMesh of dashes down the middle of every street
	var dash := BoxMesh.new()
	dash.size = Vector3(0.28, 0.02, 2.2)
	var dash_mat := PNLook.toon(Color(0.95, 0.9, 0.55))
	var dash_t: Array = []
	for ix in range(blocks.x + 1):
		var x := origin.x + ix * pitch + street * 0.5
		var z := origin.z
		while z < origin.z + total.y:
			dash_t.append(Transform3D(Basis.IDENTITY, Vector3(x, 0.03, z + 1.1)))
			z += 6.0
		street_points.append(Vector3(x, 0, origin.z + total.y * 0.5))
	for iz in range(blocks.y + 1):
		var z2 := origin.z + iz * pitch + street * 0.5
		var x2 := origin.x
		while x2 < origin.x + total.x:
			dash_t.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x2 + 1.1, 0.03, z2)))
			x2 += 6.0
		street_points.append(Vector3(origin.x + total.x * 0.5, 0, z2))
	var dmm := MultiMesh.new()
	dmm.transform_format = MultiMesh.TRANSFORM_3D
	dmm.mesh = dash
	dmm.instance_count = dash_t.size()
	for i in dash_t.size():
		dmm.set_instance_transform(i, dash_t[i])
	var dmi := MultiMeshInstance3D.new()
	dmi.multimesh = dmm
	dmi.material_override = dash_mat
	dmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(dmi)

	var landmark_block := Vector2i(rng.randi() % blocks.x, rng.randi() % blocks.y)
	var palette_walls := [PNLook.color("building", Color(0.8, 0.72, 0.62)), PNLook.color("building", Color(0.8, 0.72, 0.62)).lerp(PNLook.color("secondary"), 0.25),
		PNLook.color("building").lerp(PNLook.color("accent"), 0.2), PNLook.color("building").lightened(0.15)]
	var sign_cols := [PNLook.color("accent"), PNLook.color("primary"), PNLook.color("secondary"), Color(0.95, 0.4, 0.85)]
	var glow_signs := float(PNLook.ambient_cfg().get("glow_signs", 0.5))

	for bx in blocks.x:
		for bz in blocks.y:
			var bo := origin + Vector3(street + bx * pitch, 0, street + bz * pitch)
			block_rects.append(Rect2(bo.x, bo.z, block, block))
			# sidewalk slab
			var sw := MeshInstance3D.new()
			var swm := BoxMesh.new()
			swm.size = Vector3(block, 0.22, block)
			sw.mesh = swm
			sw.material_override = PNLook.toon(walk_col)
			sw.position = bo + Vector3(block * 0.5, 0.11, block * 0.5)
			root.add_child(sw)
			sidewalk_points.append(bo + Vector3(block * 0.5, 0.2, 1.4))
			sidewalk_points.append(bo + Vector3(1.4, 0.2, block * 0.5))
			var is_landmark := (Vector2i(bx, bz) == landmark_block) and str(opts.get("landmark", "needle_tower")) != "none"
			if is_landmark:
				var lm := _landmark(root, str(opts.get("landmark", "needle_tower")), bo + Vector3(block * 0.5, 0.22, block * 0.5), rng)
				landmarks.append(lm)
				# a small plaza ring of palms/planters around it
				continue
			# 2x2 lots
			var lot := (block - 6.0) * 0.5
			for lx in 2:
				for lz in 2:
					var h := rng.randf_range(9.0, 34.0)
					if rng.randf() < 0.18:
						h = rng.randf_range(34.0, 58.0)
					var w := lot - rng.randf_range(0.5, 2.0)
					var d := lot - rng.randf_range(0.5, 2.0)
					var c := bo + Vector3(3.0 + lot * (lx + 0.5), 0.22, 3.0 + lot * (lz + 0.5))
					_building(batch, colliders, sign_list, c, Vector3(w, h, d), palette_walls[rng.randi() % palette_walls.size()], rng, sign_cols, glow_signs)
			# plaza dressing on the corner
			lamp_spots.append(bo + Vector3(1.0, 0.22, 1.0))
			lamp_spots.append(bo + Vector3(block - 1.0, 0.22, block - 1.0))
			if PNLook.palette.has("foliage"):
				palm_list.append({"pos": bo + Vector3(block - 1.4, 0.22, 1.4), "height": rng.randf_range(5.0, 7.0), "seed": rng.randi()})
				PNProps.bush(root, bo + Vector3(1.6, 0.22, block - 1.6), 1.0)

	PNProps.lamps(root, lamp_spots, 5.0, glow_signs + 0.3)
	PNProps.palms(root, palm_list)
	PNProps.signs(root, sign_list)
	# ONE mesh for every building, roof and awning (the windows are drawn by the shader)
	var city_mesh := batch.commit(PNLook.windows_material(Color.WHITE, -1.0, 7.0))
	city_mesh.name = "BuildingsMesh"
	root.add_child(city_mesh)

	return {
		"root": root,
		"bounds": Rect2(origin.x, origin.z, total.x, total.y),
		"spawn": Vector3(origin.x + street * 0.5 + pitch, 1.2, origin.z + street * 0.5 + pitch),
		"street_points": street_points,
		"sidewalk_points": sidewalk_points,
		"landmarks": landmarks,
		"extent": maxf(total.x, total.y),
		"pitch": pitch,
		"map": {"blocks": block_rects, "streets": street_rects},
	}

static func _building(batch: PNBatch, colliders: StaticBody3D, sign_list: Array, base: Vector3, size: Vector3, wall: Color, rng: RandomNumberGenerator, sign_cols: Array, glow_signs: float) -> void:
	var center := base + Vector3(0, size.y * 0.5, 0)
	batch.add_box(center, size, wall)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = center
	colliders.add_child(cs)
	# rooftop clutter + a ground-floor awning and glowing sign on the street-facing side
	var roof_col: Color = PNLook.color("roof", Color(0.5, 0.4, 0.4))
	batch.add_box(center + Vector3(rng.randf_range(-0.2, 0.2) * size.x, size.y * 0.5 + 0.55, rng.randf_range(-0.2, 0.2) * size.z),
		Vector3(size.x * 0.28, 1.1, size.z * 0.22), roof_col, true)
	var awn_col: Color = sign_cols[rng.randi() % sign_cols.size()]
	batch.add_box(center + Vector3(0, -size.y * 0.5 + 3.0, size.z * 0.5 + 0.7), Vector3(size.x * 0.8, 0.14, 1.5), awn_col.darkened(0.1), true)
	if glow_signs > 0.05:
		sign_list.append({
			"pos": center + Vector3(0, -size.y * 0.5 + 4.1, size.z * 0.5 + 0.2),
			"size": Vector2(size.x * 0.5, 0.95), "color": awn_col.lightened(0.15), "yaw": 0.0,
			"text": SIGN_WORDS[rng.randi() % SIGN_WORDS.size()]
		})

## Generic landmark silhouettes (no real-world shapes): needle_tower, glass_slab, deco_tower, arch.
static func _landmark(parent: Node3D, style: String, at: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "Landmark_" + style
	root.position = at
	parent.add_child(root)
	var steel := PNLook.toon(PNLook.color("building").lightened(0.2))
	var glow := PNLook.color("accent", Color(1, 0.4, 0.4)).lightened(0.2)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	root.add_child(body)
	match style:
		"glass_slab":
			var bm := BoxMesh.new()
			bm.size = Vector3(10, 64, 6)
			var mi := MeshInstance3D.new()
			mi.mesh = bm
			mi.material_override = PNLook.windows_material(PNLook.color("secondary").lightened(0.2), -1.0, 3.0)
			mi.position.y = 32
			body.add_child(mi)
			_box_shape(body, bm.size, Vector3(0, 32, 0))
		"deco_tower":
			var y := 0.0
			for i in 4:
				var s := Vector3(16 - i * 3.2, 14, 12 - i * 2.4)
				var bm2 := BoxMesh.new()
				bm2.size = s
				var mi2 := MeshInstance3D.new()
				mi2.mesh = bm2
				mi2.material_override = PNLook.windows_material(PNLook.color("building").lightened(0.1), -1.0, 5.0 + i)
				mi2.position.y = y + s.y * 0.5
				body.add_child(mi2)
				_box_shape(body, s, Vector3(0, y + s.y * 0.5, 0))
				y += s.y
			var spire := CylinderMesh.new()
			spire.top_radius = 0.1
			spire.bottom_radius = 0.6
			spire.height = 14
			var sm := MeshInstance3D.new()
			sm.mesh = spire
			sm.material_override = PNLook.toon(glow, glow, 1.6)
			sm.position.y = y + 7
			body.add_child(sm)
		"arch":
			for sx in [-9, 9]:
				var pm := BoxMesh.new()
				pm.size = Vector3(3.2, 34, 3.2)
				var p := MeshInstance3D.new()
				p.mesh = pm
				p.material_override = steel
				p.position = Vector3(sx, 17, 0)
				body.add_child(p)
				_box_shape(body, pm.size, p.position)
			var top := TorusMesh.new()
			top.inner_radius = 8.4
			top.outer_radius = 10.2
			var tm := MeshInstance3D.new()
			tm.mesh = top
			tm.material_override = steel
			tm.rotation = Vector3(PI * 0.5, 0, 0)
			tm.position = Vector3(0, 34, 0)
			tm.scale = Vector3(1, 1, 0.6)
			body.add_child(tm)
		_:  # needle_tower: a slim shaft with a glowing sphere on top and a thin spire
			var shaft := CylinderMesh.new()
			shaft.top_radius = 1.3
			shaft.bottom_radius = 2.6
			shaft.height = 62
			shaft.radial_segments = 8
			var sh := MeshInstance3D.new()
			sh.mesh = shaft
			sh.material_override = steel
			sh.position.y = 31
			body.add_child(sh)
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 2.4
			cyl.height = 62
			cs.shape = cyl
			cs.position.y = 31
			body.add_child(cs)
			var ball := SphereMesh.new()
			ball.radius = 6.0
			ball.height = 12.0
			ball.radial_segments = 14
			ball.rings = 8
			var bl := MeshInstance3D.new()
			bl.mesh = ball
			bl.material_override = PNLook.toon(glow, glow, 1.2)
			bl.position.y = 64
			body.add_child(bl)
			var spire2 := CylinderMesh.new()
			spire2.top_radius = 0.05
			spire2.bottom_radius = 0.5
			spire2.height = 16
			var sp := MeshInstance3D.new()
			sp.mesh = spire2
			sp.material_override = steel
			sp.position.y = 78
			body.add_child(sp)
	return root

static func _box_shape(body: StaticBody3D, size: Vector3, at: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = at
	body.add_child(cs)
