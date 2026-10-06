class_name PNBricks
extends RefCounted
## Playpen kit: MODULAR TOY BRICKS (Part 7.3) — beveled bricks, plates and slopes with STUDS, for building arenas and levels
## procedurally. One MultiMesh per brick size (a whole wall is a handful of draw calls), glossy plastic material from the
## look pack, a collider per solid piece.
##
##   var b := PNBricks.new()
##   b.plate(world, Vector3(0, 0, 0), Vector2i(48, 48), PNLook.color("ground"))              # a studded base plate
##   b.wall(Vector3(-20, 0, -20), Vector3(20, 0, -20), 6, [Color.RED, Color.WHITE])            # courses of bricks, alternating colors
##   b.brick(Vector3(5, 0.5, 5), Vector2i(2, 4), 3, Color.YELLOW)                              # 2x4 studs, 3 plates tall
##   b.slope(Vector3(8, 0, 0), Vector2i(4, 6), 4, 0.0, Color.BLUE)                             # a ramp, yaw in degrees
##   b.commit(world)                                                                           # builds meshes + colliders
##
## Sizes are in STUDS (pitch `STUD` metres) and PLATES (height `PLATE` metres; a full brick is 3 plates).

const STUD := 0.5
const PLATE := 0.2
const BRICK_H := PLATE * 3.0
const BEVEL := 0.045

var _groups := {}          # size key -> { mesh, xforms, colors }
var _stud_xf: Array = []
var _stud_col: Array = []
var _colliders: Array = []  # [Vector3 center, Vector3 size, float yaw]
var _slopes: Array = []     # [Transform3D, Vector3 size, Color]
var solid := true

static var _mesh_cache := {}

## A box with chamfered (beveled) edges: 6 faces + 12 edge strips + 8 corner triangles. Smooth highlights on the bevel.
static func chamfer_box(size: Vector3, bevel: float = BEVEL) -> ArrayMesh:
	var key := "%s|%s" % [size, bevel]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var h := size * 0.5
	var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.9)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# the 24 corner points of the chamfered box: for each of 8 corners, 3 points (one per adjoining face)
	var corners: Array = []
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				corners.append(Vector3(sx, sy, sz))
	# helper: point on corner c lying on the face whose normal axis is `axis` (0=x,1=y,2=z)
	var pt := func(c: Vector3, axis: int) -> Vector3:
		var p := Vector3(c.x * (h.x - b), c.y * (h.y - b), c.z * (h.z - b))
		match axis:
			0: p.x = c.x * h.x
			1: p.y = c.y * h.y
			_: p.z = c.z * h.z
		return p
	var quad := func(a: Vector3, bb: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
		for p in [a, bb, c, a, c, d]:
			st.set_normal(n)
			st.add_vertex(p)
	# 6 main faces (inset quad on each face)
	for axis in 3:
		for s in [-1, 1]:
			var n := Vector3.ZERO
			n[axis] = s
			var u := (axis + 1) % 3
			var v := (axis + 2) % 3
			var pts: Array = []
			for su in [-1, 1]:
				for sv in [-1, 1]:
					var c := Vector3.ZERO
					c[axis] = s
					c[u] = su
					c[v] = sv
					pts.append(pt.call(c, axis))
			# pts order: (u-,v-), (u-,v+), (u+,v-), (u+,v+)
			var a: Vector3 = pts[0]
			var bq: Vector3 = pts[2]
			var cq: Vector3 = pts[3]
			var dq: Vector3 = pts[1]
			var tri_n := (bq - a).cross(dq - a)
			if tri_n.dot(n) < 0.0:
				quad.call(a, dq, cq, bq, n)
			else:
				quad.call(a, bq, cq, dq, n)
	# 12 edge strips (between two faces): normal is the average of the two face normals
	for axis in 3:      # the edge runs ALONG this axis
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for su in [-1, 1]:
			for sv in [-1, 1]:
				var c0 := Vector3.ZERO
				c0[axis] = -1
				c0[u] = su
				c0[v] = sv
				var c1 := c0
				c1[axis] = 1
				# point on face u and on face v for each end
				var a0: Vector3 = pt.call(c0, u)
				var b0: Vector3 = pt.call(c0, v)
				var a1: Vector3 = pt.call(c1, u)
				var b1: Vector3 = pt.call(c1, v)
				var n := Vector3.ZERO
				n[u] = su
				n[v] = sv
				n = n.normalized()
				var t := (a1 - a0).cross(b0 - a0)
				if t.dot(n) < 0.0:
					quad.call(a0, a1, b1, b0, n)
				else:
					quad.call(a0, b0, b1, a1, n)
	# 8 corner triangles
	for c in corners:
		var p0: Vector3 = pt.call(c, 0)
		var p1: Vector3 = pt.call(c, 1)
		var p2: Vector3 = pt.call(c, 2)
		var n: Vector3 = (c as Vector3).normalized()
		var t := (p1 - p0).cross(p2 - p0)
		var tri: Array = [p0, p1, p2] if t.dot(n) > 0.0 else [p0, p2, p1]
		for p in tri:
			st.set_normal(n)
			st.add_vertex(p)
	var mesh := st.commit()
	_mesh_cache[key] = mesh
	return mesh

static func stud_mesh() -> CylinderMesh:
	if _mesh_cache.has("stud"):
		return _mesh_cache["stud"]
	var m := CylinderMesh.new()
	m.top_radius = STUD * 0.3
	m.bottom_radius = STUD * 0.3
	m.height = PLATE * 0.5
	m.radial_segments = 10
	m.rings = 1
	_mesh_cache["stud"] = m
	return m

static func plastic(tint := Color.WHITE) -> ShaderMaterial:
	return PNLook.plastic_material(tint)

## A brick: `studs` = footprint (x, z), `plates` = height in plates (3 = one brick). `pos` is the CENTER of the bottom face.
func brick(pos: Vector3, studs: Vector2i, plates: int, color: Color, yaw_deg := 0.0, with_studs := true) -> void:
	var size := Vector3(studs.x * STUD, plates * PLATE, studs.y * STUD)
	var center := pos + Vector3(0, size.y * 0.5, 0)
	var key := str(size)
	if not _groups.has(key):
		_groups[key] = {"mesh": chamfer_box(size), "xforms": [], "colors": [], "size": size}
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	_groups[key]["xforms"].append(Transform3D(basis, center))
	_groups[key]["colors"].append(color)
	if solid:
		_colliders.append([center, size, yaw_deg])
	if with_studs:
		for ix in studs.x:
			for iz in studs.y:
				var local := Vector3((ix - (studs.x - 1) * 0.5) * STUD, size.y + PLATE * 0.275, (iz - (studs.y - 1) * 0.5) * STUD)
				_stud_xf.append(Transform3D(Basis.IDENTITY, pos + basis * local))
				_stud_col.append(color)

## A thin studded plate (1 plate tall by default) — floors, base plates, platforms.
func plate(parent: Node3D, pos: Vector3, studs: Vector2i, color: Color, plates := 1) -> void:
	# split a big plate into <=16x16 stud tiles so the stud/MultiMesh instance counts stay sane and each collider is small
	var tx := 0
	while tx < studs.x:
		var sx := mini(16, studs.x - tx)
		var tz := 0
		while tz < studs.y:
			var sz := mini(16, studs.y - tz)
			var c := pos + Vector3((tx + sx * 0.5 - studs.x * 0.5) * STUD, 0, (tz + sz * 0.5 - studs.y * 0.5) * STUD)
			brick(c, Vector2i(sx, sz), plates, color, 0.0, PNSettings.quality != PNSettings.Quality.LOW or (tx + tz) % 2 == 0)
			tz += sz
		tx += sx

## A straight wall of brick courses from `a` to `b` (XZ), `courses` bricks high, alternating `colors`.
func wall(a: Vector3, b: Vector3, courses: int, colors: Array, thickness := 2) -> void:
	var d := b - a
	var length := Vector2(d.x, d.z).length()
	var yaw := rad_to_deg(atan2(d.x, d.z))
	var n := int(ceil(length / (4.0 * STUD)))
	var dir := d / maxf(length, 0.001)
	for course in courses:
		var col: Color = colors[course % colors.size()]
		var offset := 0.5 * STUD * 2.0 if course % 2 == 1 else 0.0   # running bond: stagger every other course
		for i in n:
			var c := a + dir * ((i + 0.5) * 4.0 * STUD + offset) + Vector3(0, course * BRICK_H, 0)
			if (c - a).length() > length:
				continue
			brick(c, Vector2i(thickness, 4), 3, col, yaw)   # local +Z is the long side: yaw points it ALONG the wall

## A ramp / slope brick: rises `plates` high over `studs.y` studs, facing along +Z rotated by yaw. Builds a wedge + collider.
func slope(pos: Vector3, studs: Vector2i, plates: int, yaw_deg: float, color: Color) -> void:
	var size := Vector3(studs.x * STUD, plates * PLATE, studs.y * STUD)
	_slopes.append([Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos), size, color])

## Build everything: MultiMeshes (bodies + studs), slopes and colliders under `parent`.
func commit(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Bricks"
	parent.add_child(root)
	var mat := plastic(Color.WHITE)
	for key in _groups:
		var g: Dictionary = _groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = g["mesh"]
		mm.instance_count = g["xforms"].size()
		for i in g["xforms"].size():
			mm.set_instance_transform(i, g["xforms"][i])
			mm.set_instance_color(i, (g["colors"][i] as Color))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if PNSettings.quality != PNSettings.Quality.LOW else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	if _stud_xf.size() > 0:
		var sm := MultiMesh.new()
		sm.transform_format = MultiMesh.TRANSFORM_3D
		sm.use_colors = true
		sm.mesh = stud_mesh()
		sm.instance_count = _stud_xf.size()
		for i in _stud_xf.size():
			sm.set_instance_transform(i, _stud_xf[i])
			sm.set_instance_color(i, _stud_col[i])
		var smi := MultiMeshInstance3D.new()
		smi.multimesh = sm
		smi.material_override = mat
		smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(smi)
	for s in _slopes:
		_build_slope(root, s[0], s[1], s[2], mat)
	var body := StaticBody3D.new()
	body.name = "BrickColliders"
	body.collision_layer = 1
	root.add_child(body)
	for c in _colliders:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = c[1]
		cs.shape = bs
		cs.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(c[2])), c[0])
		body.add_child(cs)
	return root

func _build_slope(root: Node3D, xf: Transform3D, size: Vector3, color: Color, mat: ShaderMaterial) -> void:
	# wedge: low edge at -Z/2, high edge at +Z/2
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p000 := Vector3(-hx, 0, -hz)
	var p100 := Vector3(hx, 0, -hz)
	var p001 := Vector3(-hx, 0, hz)
	var p101 := Vector3(hx, 0, hz)
	var p011 := Vector3(-hx, size.y, hz)
	var p111 := Vector3(hx, size.y, hz)
	var lin := color.srgb_to_linear()
	var col := Color(lin.r, lin.g, lin.b, 1.0)
	var tris := [
		[p000, p100, p111, p011],   # sloped top
		[p001, p011, p111, p101],   # back (+Z)
		[p000, p001, p101, p100],   # bottom
	]
	var wedge_c := Vector3(0, size.y * 0.33, 0)
	for q in tris:
		var n: Vector3 = ((q[1] - q[0]).cross(q[3] - q[0])).normalized()
		var order: Array = [q[0], q[1], q[2], q[0], q[2], q[3]]
		var fc: Vector3 = (q[0] + q[1] + q[2] + q[3]) * 0.25
		if n.dot(fc - wedge_c) < 0.0:      # wound inward: flip so the face is visible and lit from outside
			n = -n
			order = [q[0], q[2], q[1], q[0], q[3], q[2]]
		for p in order:
			st.set_color(col)
			st.set_normal(n)
			st.add_vertex(p)
	# the two triangular sides
	for tri in [[p000, p001, p011], [p100, p111, p101]]:
		var n2: Vector3 = ((tri[1] - tri[0]).cross(tri[2] - tri[0])).normalized()
		var tc: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
		if n2.dot(tc - wedge_c) < 0.0:
			n2 = -n2
			tri = [tri[0], tri[2], tri[1]]
		for p in tri:
			st.set_color(col)
			st.set_normal(n2)
			st.add_vertex(p)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m2 := mat.duplicate() as ShaderMaterial
	mi.material_override = m2
	mi.transform = xf
	root.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.transform = xf
	var cs := CollisionShape3D.new()
	cs.shape = mi.mesh.create_trimesh_shape()
	body.add_child(cs)
	root.add_child(body)
