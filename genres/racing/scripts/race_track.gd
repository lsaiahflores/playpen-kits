class_name RaceTrack
extends RefCounted
## Builds a closed-loop race TRACK from a few numbers: a smooth Curve3D, a road
## ribbon with striped curbs and a dashed centre line, collision, a grass infield
## and scenery (trees/palms, grandstand, start arch with a fluttering banner,
## glowing signs). Returns everything the race needs: the curve, checkpoints, the
## start grid and a minimap polyline.
##
##   var track := RaceTrack.build(world, {"seed": 4, "radius": 110.0, "road_width": 11.0})
##   track.curve / track.road_width / track.start_transform(i) / track.checkpoints

var curve: Curve3D
var road_width := 11.0
var length := 0.0
var points := PackedVector3Array()      # baked centre line
var checkpoints: Array[Area3D] = []
var map_line := PackedVector2Array()
var root: Node3D
var _surface_mat: ShaderMaterial

static func build(parent: Node3D, opts := {}) -> RaceTrack:
	var t := RaceTrack.new()
	t.road_width = float(opts.get("road_width", 11.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(opts.get("seed", 1))
	var base_r := float(opts.get("radius", 110.0))
	t.root = Node3D.new()
	t.root.name = "Track"
	parent.add_child(t.root)
	# --- centre line: a wobbly loop with a couple of big corners -----------------
	t.curve = Curve3D.new()
	t.curve.bake_interval = 2.0
	var n := 14
	var ctrl: Array[Vector3] = []
	for i in n:
		var a := TAU * i / n
		var r := base_r * (1.0 + 0.28 * sin(a * 2.0 + rng.randf() * 0.8) + 0.12 * sin(a * 3.0 + 1.3) + rng.randf_range(-0.05, 0.05))
		var squash := 0.72
		ctrl.append(Vector3(cos(a) * r, 0.0, sin(a) * r * squash))
	for i in n:
		var p0: Vector3 = ctrl[(i - 1 + n) % n]
		var p1: Vector3 = ctrl[i]
		var p2: Vector3 = ctrl[(i + 1) % n]
		var tan := (p2 - p0) * 0.2
		t.curve.add_point(p1, -tan, tan)
	t.curve.add_point(ctrl[0], -(ctrl[1] - ctrl[n - 1]) * 0.2, (ctrl[1] - ctrl[n - 1]) * 0.2)
	t.points = t.curve.get_baked_points()
	t.length = t.curve.get_baked_length()
	for p in t.points:
		t.map_line.append(Vector2(p.x, p.z))
	t._build_road()
	t._build_ground(opts)
	t._build_scenery(rng, opts)
	t._build_checkpoints(int(opts.get("checkpoints", 8)))
	t._build_boost_pads(rng)
	return t

# ------------------------------------------------------------------ geometry
func _frame(i: int) -> Array:
	var n := points.size()
	var p: Vector3 = points[i % n]
	var nxt: Vector3 = points[(i + 1) % n]
	var prv: Vector3 = points[(i - 1 + n) % n]
	var tan := (nxt - prv).normalized()
	var right := tan.cross(Vector3.UP).normalized()
	return [p, tan, right]

func _build_road() -> void:
	var road := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	var curb := SurfaceTool.new()
	curb.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := points.size()
	var asphalt := PNLook.color("street", Color(0.34, 0.36, 0.4)).srgb_to_linear()
	var lane := Color(0.95, 0.9, 0.6).srgb_to_linear()
	var w := road_width
	for i in n - 1:
		var a := _frame(i)
		var b := _frame(i + 1)
		var pa: Vector3 = a[0]
		var pb: Vector3 = b[0]
		var ra: Vector3 = a[2]
		var rb: Vector3 = b[2]
		var col := asphalt
		_strip(road, pa - ra * w, pa + ra * w, pb - rb * w, pb + rb * w, col, 0.02)
		# dashed centre line
		if (i / 3) % 2 == 0:
			_strip(road, pa - ra * 0.18, pa + ra * 0.18, pb - rb * 0.18, pb + rb * 0.18, lane, 0.035)
		# striped curbs on both edges
		var cc := Color(0.92, 0.2, 0.2).srgb_to_linear() if (i / 2) % 2 == 0 else Color(0.95, 0.95, 0.95).srgb_to_linear()
		_strip(curb, pa + ra * w, pa + ra * (w + 1.2), pb + rb * w, pb + rb * (w + 1.2), cc, 0.045)
		_strip(curb, pa - ra * (w + 1.2), pa - ra * w, pb - rb * (w + 1.2), pb - rb * w, cc, 0.045)
	var mat := PNLook.toon(Color.WHITE)
	mat.set_shader_parameter("use_vertex_color", true)
	var road_mesh := road.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = road_mesh
	mi.material_override = mat
	root.add_child(mi)
	var cm := MeshInstance3D.new()
	cm.mesh = curb.commit()
	cm.material_override = mat
	root.add_child(cm)
	# collision follows the road surface
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	cs.shape = road_mesh.create_trimesh_shape()
	body.add_child(cs)
	root.add_child(body)

func _strip(st: SurfaceTool, a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3, col: Color, lift: float) -> void:
	var up := Vector3(0, lift, 0)
	for tri in [[a0, b0, a1], [a1, b0, b1]]:   # clockwise from above
		for p in tri:
			st.set_color(col)
			st.set_normal(Vector3.UP)
			st.add_vertex(p + up)

func _build_ground(opts: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(900, 900)
	mi.mesh = pm
	mi.material_override = PNLook.terrain_material()
	mi.position.y = -0.05
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(900, 1, 900)
	cs.shape = bs
	cs.position.y = -0.55
	body.add_child(cs)
	root.add_child(body)

func _build_scenery(rng: RandomNumberGenerator, opts: Dictionary) -> void:
	var n := points.size()
	var trees: Array = []
	var palms: Array = []
	var sign_list: Array = []
	var lamps: Array = []
	var density := 0.4 + 0.6 * PNSettings.scale()
	var i := 4
	var look_has_palms := str(PNLook.look.get("id", "")) in ["sunny_tropical", "bright_city"]
	while i < n:
		var f := _frame(i)
		var side := 1.0 if rng.randf() > 0.5 else -1.0
		var off := road_width + rng.randf_range(5.0, 28.0)
		var pos: Vector3 = f[0] + f[2] * side * off
		if look_has_palms and rng.randf() < 0.55:
			palms.append({"pos": pos, "height": rng.randf_range(5.0, 7.5), "seed": i})
		else:
			trees.append({"pos": pos, "height": rng.randf_range(4.0, 8.0), "seed": i})
		if rng.randf() < 0.12:
			var sp: Vector3 = f[0] + f[2] * side * (road_width + 4.0)
			sign_list.append({"pos": sp + Vector3(0, 2.4, 0), "size": Vector2(3.4, 1.4), "color": [PNLook.color("accent"), PNLook.color("primary"), PNLook.color("secondary")][rng.randi() % 3], "yaw": atan2(-f[2].x * side, -f[2].z * side), "text": ""})
		if rng.randf() < 0.1:
			lamps.append(f[0] + f[2] * side * (road_width + 3.0))
		i += int(rng.randf_range(3.0, 6.0) / density) + 1
	PNProps.trees(root, trees)
	PNProps.palms(root, palms)
	PNProps.signs(root, sign_list)
	PNProps.lamps(root, lamps, 5.0, 1.0)
	_build_start_line()

func _build_start_line() -> void:
	var f := _frame(2)
	var p: Vector3 = f[0]
	var tan: Vector3 = f[1]
	var right: Vector3 = f[2]
	var yaw := atan2(tan.x, tan.z)
	# checkered strip
	var b := PNBatch.new()
	var cols := 10
	for r in 2:
		for c in cols:
			var chk := Color(0.1, 0.1, 0.12) if (r + c) % 2 == 0 else Color(0.97, 0.97, 0.97)
			var local := Vector3(-road_width + (c + 0.5) * (road_width * 2.0 / cols), 0.05, (r - 0.5) * 1.0)
			b.add_box(local, Vector3(road_width * 2.0 / cols, 0.02, 1.0), chk, true)
	var m := PNLook.toon(Color.WHITE)
	m.set_shader_parameter("use_vertex_color", true)
	var strip := b.commit(m)
	root.add_child(strip)
	strip.global_position = p
	strip.rotation.y = yaw
	# arch posts + a banner that flutters in the wind
	var arch := PNBatch.new()
	for s in [-1.0, 1.0]:
		arch.add_box(Vector3(s * (road_width + 1.8), 3.2, 0), Vector3(0.8, 6.4, 0.8), Color(0.9, 0.9, 0.92), true)
	arch.add_box(Vector3(0, 6.6, 0), Vector3(road_width * 2.0 + 4.4, 0.9, 0.9), PNLook.color("accent"), true)
	var am := PNLook.toon(Color.WHITE)
	am.set_shader_parameter("use_vertex_color", true)
	var arch_mi := arch.commit(am)
	root.add_child(arch_mi)
	arch_mi.global_position = p
	arch_mi.rotation.y = yaw
	var flag := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(road_width * 2.0, 1.6)
	fq.center_offset = Vector3(road_width, 0, 0)
	flag.mesh = fq
	var fmat := PNLook.sway_material(PNLook.color("primary"), PNLook.color("accent"), road_width * 2.0, 0.35)
	fmat.set_shader_parameter("pin_axis", 0)
	fmat.set_shader_parameter("flutter", 0.25)
	flag.material_override = fmat
	root.add_child(flag)
	flag.global_position = p + Vector3(0, 5.0, 0) - right * road_width
	flag.rotation.y = yaw
	# grandstand
	var gs := PNBatch.new()
	for s in 5:
		gs.add_box(Vector3(0, 0.5 + s * 0.9, -s * 1.1), Vector3(26, 0.9, 2.0), PNLook.color("building").lerp(PNLook.color("accent"), 0.15 * s), true)
	var gm := PNLook.toon(Color.WHITE)
	gm.set_shader_parameter("use_vertex_color", true)
	var gmi := gs.commit(gm)
	root.add_child(gmi)
	gmi.global_position = p + right * (road_width + 9.0)
	gmi.rotation.y = yaw + PI * 0.5

## Glowing boost pads across the road: drive over one for a burst of speed.
func _build_boost_pads(rng: RandomNumberGenerator) -> void:
	var mat := PNLook.glow_material(PNLook.color("primary", Color(1, 0.8, 0.2)), 1.0)
	mat.set_shader_parameter("bob_height", 0.0)
	mat.set_shader_parameter("pulse_amount", 0.5)
	mat.set_shader_parameter("intensity", 1.8)
	for k in [0.17, 0.42, 0.66, 0.86]:
		var off: float = length * k
		var p := curve.sample_baked(off)
		var p2 := curve.sample_baked(fmod(off + 2.0, length))
		var pad := Area3D.new()
		pad.collision_layer = 0
		pad.collision_mask = 2
		root.add_child(pad)
		pad.global_position = p + Vector3(0, 0.12, 0)
		pad.look_at(Vector3(p2.x, pad.global_position.y, p2.z), Vector3.UP)
		pad.rotate_y(rng.randf_range(-0.0, 0.0))
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(5.0, 3.0, 6.0)
		cs.shape = bs
		pad.add_child(cs)
		for c in 3:
			var mesh := PrismMesh.new()
			mesh.size = Vector3(2.4, 0.06, 1.6)
			var chev := MeshInstance3D.new()
			chev.mesh = mesh
			chev.rotation.x = -PI * 0.5
			chev.position = Vector3(0, 0.02, -1.6 + c * 1.6)
			chev.material_override = mat
			pad.add_child(chev)
		pad.body_entered.connect(func(body: Node3D):
			if body.has_meta("kart"):
				(body.get_meta("kart") as Kart).boost(1.1))

# ------------------------------------------------------------------ race helpers
func _build_checkpoints(count: int) -> void:
	for k in count:
		var off := length * float(k) / count
		var p := curve.sample_baked(off)
		var p2 := curve.sample_baked(fmod(off + 1.5, length))
		var a := Area3D.new()
		a.collision_layer = 0
		a.collision_mask = 2
		a.set_meta("index", k)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(road_width * 2.6, 6.0, 5.0)
		cs.shape = bs
		a.add_child(cs)
		root.add_child(a)
		a.global_position = p + Vector3(0, 2.0, 0)
		a.look_at(Vector3(p2.x, a.global_position.y, p2.z), Vector3.UP)
		checkpoints.append(a)

func start_transform(slot: int) -> Transform3D:
	# a 2-wide grid behind the start line (the line is at point index 2)
	var back := 3.0 + (slot / 2) * 5.0
	var off := fmod(length - back + 4.0, length)
	var p := curve.sample_baked(off)
	var ahead := curve.sample_baked(fmod(off + 2.0, length))
	var tan := (ahead - p).normalized()
	var right := tan.cross(Vector3.UP).normalized()
	var lateral := (-1.0 if slot % 2 == 0 else 1.0) * road_width * 0.4
	var pos := p + right * lateral + Vector3(0, 0.3, 0)
	return Transform3D(Basis(Vector3.UP, atan2(tan.x, tan.z)), pos)

func offset_of(world_pos: Vector3) -> float:
	return curve.get_closest_offset(world_pos)

func distance_to_center(world_pos: Vector3) -> float:
	var o := curve.get_closest_offset(world_pos)
	var c := curve.sample_baked(o)
	return Vector2(world_pos.x - c.x, world_pos.z - c.z).length()

func point_ahead(offset: float, dist: float) -> Vector3:
	return curve.sample_baked(fmod(offset + dist + length, length))
