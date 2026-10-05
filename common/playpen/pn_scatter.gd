class_name PNScatter
extends RefCounted
## Playpen kit: MULTIMESH SCATTER — fill a level with foliage, rocks, litter, props.
## One draw call per scatter, density maps and "keep clear" masks as Callables,
## raycast to the ground, counts scaled by PNSettings quality. This is how a first
## pass feels FULL instead of like four boxes.
##
##   PNScatter.scatter(self, rock_mesh, rock_mat, Rect2(-50,-50,100,100), 80,
##       {"seed": 3, "min_scale": 0.6, "max_scale": 1.6,
##        "density": func(p: Vector2) -> float: return noise.get_noise_2dv(p) * .5 + .5,
##        "avoid": func(p: Vector2) -> bool: return p.length() < 6.0})

static func scatter(parent: Node3D, mesh: Mesh, material: Material, area: Rect2, count: int, opts := {}) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(opts.get("seed", 1))
	if bool(opts.get("scale_with_quality", true)):
		count = maxi(1, int(round(count * PNSettings.scale())))
	var density: Callable = opts.get("density", Callable())
	var avoid: Callable = opts.get("avoid", Callable())
	var smin := float(opts.get("min_scale", 0.8))
	var smax := float(opts.get("max_scale", 1.2))
	var ground_y := float(opts.get("ground_y", 0.0))
	var raycast := bool(opts.get("raycast", false))
	var yoff := float(opts.get("y_offset", 0.0))
	var colors: Array = opts.get("colors", [])
	var space: PhysicsDirectSpaceState3D = parent.get_world_3d().direct_space_state if raycast and parent.is_inside_tree() else null
	var xforms: Array = []
	var cols: Array = []
	var tries := 0
	while xforms.size() < count and tries < count * 12:
		tries += 1
		var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		if avoid.is_valid() and avoid.call(p):
			continue
		if density.is_valid() and rng.randf() > float(density.call(p)):
			continue
		var y := ground_y
		var up := Vector3.UP
		if space:
			var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 200, p.y), Vector3(p.x, -50, p.y), 1)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			y = hit.position.y
			if bool(opts.get("align", false)):
				up = hit.normal
		var s := rng.randf_range(smin, smax)
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		if up != Vector3.UP:
			basis = Basis(Quaternion(Vector3.UP, up)) * basis
		basis = basis.scaled(Vector3.ONE * s)
		xforms.append(Transform3D(basis, Vector3(p.x, y + yoff, p.y)))
		if not colors.is_empty():
			cols.append(colors[rng.randi() % colors.size()])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if not cols.is_empty():
			mm.set_instance_color(i, (cols[i] as Color).srgb_to_linear())
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(opts.get("shadows", false)) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

## Pebbles, flowers, tufts and puddles — the "ground detail" that stops big flat
## areas looking empty. `avoid` keeps them off roads/water.
static func ground_detail(parent: Node3D, area: Rect2, avoid := Callable(), seed_value := 11, flowers := true, puddles := true) -> void:
	var peb := SphereMesh.new()
	peb.radius = 0.12
	peb.height = 0.12
	peb.radial_segments = 5
	peb.rings = 2
	var peb_mat := PNLook.toon(PNLook.color("ground", Color(0.6, 0.55, 0.5)).darkened(0.1))
	scatter(parent, peb, peb_mat, area, 140, {"seed": seed_value, "min_scale": 0.5, "max_scale": 1.8, "avoid": avoid})
	# grass tufts — wind-driven, bend away from the player
	var tuft := QuadMesh.new()
	tuft.size = Vector2(0.35, 0.5)
	tuft.center_offset = Vector3(0, 0.25, 0)
	var tuft_mat := PNLook.sway_material(PNLook.color("foliage_dark"), PNLook.color("foliage"), 0.5, 0.4)
	scatter(parent, tuft, tuft_mat, area, 260, {"seed": seed_value + 1, "min_scale": 0.7, "max_scale": 1.5, "avoid": avoid})
	if flowers:
		var fm := SphereMesh.new()
		fm.radius = 0.08
		fm.height = 0.12
		fm.radial_segments = 5
		fm.rings = 2
		var fmat := PNLook.sway_material(Color.WHITE, Color.WHITE, 0.2, 0.3)
		scatter(parent, fm, fmat, area, 90, {"seed": seed_value + 2, "min_scale": 0.8, "max_scale": 1.4, "y_offset": 0.15, "avoid": avoid,
			"colors": [PNLook.color("accent"), PNLook.color("primary"), Color(1, 1, 1), PNLook.color("secondary")]})
	if puddles:
		var pd := CylinderMesh.new()
		pd.top_radius = 0.9
		pd.bottom_radius = 0.9
		pd.height = 0.01
		pd.radial_segments = 12
		pd.rings = 1
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(PNLook.color("sky_horizon"), 0.55)
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.roughness = 0.05
		pm.metallic = 0.2
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		scatter(parent, pd, pm, area, 10, {"seed": seed_value + 3, "min_scale": 0.6, "max_scale": 1.8, "y_offset": 0.015, "avoid": avoid})
