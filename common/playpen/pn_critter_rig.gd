class_name PNCritterRig
extends Node3D
## Playpen kit: a cute, fully procedural hero — body, head, ears, eyes, tail and
## feet from primitives, animated in code (run bob, lean, tail wag, foot swing,
## breathing, jump stretch, landing squash). It exists so the very first pass has
## a CHARACTER with life in it, never a gray capsule. Recolor it (a tiger is
## orange + `stripes = true`) or drop a real glTF model in as a child named
## "Model" and call PNAnimTree.attach(); the rig then steps aside.
##
## Drive it from the controller:
##     rig.update_motion(delta, horizontal_speed, on_floor, vertical_velocity)

@export var body_color := Color(1.0, 0.62, 0.2)
@export var belly_color := Color(1.0, 0.9, 0.75)
@export var accent_color := Color(0.18, 0.12, 0.1)   # eyes / nose / stripes
@export var stripes := false
@export var ear_style := "round"      # "round" | "pointy"
@export var scale_factor := 1.0
@export var tail_length := 5

var _body: Node3D
var _head: Node3D
var _tail: Array[Node3D] = []
var _feet: Array[Node3D] = []
var _t := 0.0
var _was_on_floor := true
var _has_model := false

func _ready() -> void:
	if get_node_or_null("Model"):
		_has_model = true
		return
	_build()

func _toon(c: Color) -> Material:
	return PNLook.with_outline(PNLook.toon(c))

func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

func _sphere(r: float, seg := 12) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = maxi(seg / 2, 4)
	return s

func _toon_vc() -> Material:
	# one shared toon material that reads the per-vertex colors baked by PNBatch
	var m := PNLook.toon(Color.WHITE)
	m.set_shader_parameter("use_vertex_color", true)
	return PNLook.with_outline(m)

func _merged(parent: Node3D, batch: PNBatch, mat: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := batch.commit(mat)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

func _build() -> void:
	scale = Vector3.ONE * scale_factor
	var vc := _toon_vc()
	var T := func(p: Vector3, s: Vector3 = Vector3.ONE) -> Transform3D:
		return Transform3D(Basis.IDENTITY.scaled(s), p)
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	# --- body: torso + belly + (stripes) — ONE mesh
	var bb := PNBatch.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.4
	bm.height = 1.0
	bm.radial_segments = 14
	bm.rings = 5
	bb.add_mesh(bm, T.call(Vector3(0, 0.62, 0)), body_color)
	bb.add_mesh(_sphere(0.34), T.call(Vector3(0, 0.55, 0.22), Vector3(1.0, 1.05, 0.7)), belly_color)
	if stripes:
		for i in 4:
			var sm := BoxMesh.new()
			sm.size = Vector3(0.86, 0.07, 0.2)
			bb.add_mesh(sm, T.call(Vector3(0, 0.42 + i * 0.17, -0.12)), accent_color)
	_merged(_body, bb, vc)
	# --- head: skull + muzzle + nose + eyes + ears — ONE mesh
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0, 1.28, 0.05)
	_body.add_child(_head)
	var hb := PNBatch.new()
	hb.add_mesh(_sphere(0.42), T.call(Vector3.ZERO, Vector3(1.08, 0.96, 1.0)), body_color)
	hb.add_mesh(_sphere(0.2), T.call(Vector3(0, -0.12, 0.34), Vector3(1.2, 0.8, 0.8)), belly_color)
	hb.add_mesh(_sphere(0.065, 8), T.call(Vector3(0, -0.04, 0.5), Vector3(1.2, 0.8, 0.8)), accent_color)
	for sx in [-1.0, 1.0]:
		hb.add_mesh(_sphere(0.075, 8), T.call(Vector3(sx * 0.17, 0.08, 0.36)), accent_color)
		hb.add_mesh(_sphere(0.025, 6), T.call(Vector3(sx * 0.17 + 0.02 * sx, 0.11, 0.415)), Color.WHITE)
		var ear_mesh: Mesh
		if ear_style == "pointy":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = 0.14
			cm.height = 0.3
			cm.radial_segments = 6
			ear_mesh = cm
		else:
			ear_mesh = _sphere(0.14, 8)
		var ear_t := Transform3D(Basis(Vector3(0, 0, 1), -sx * 0.25).scaled(Vector3(1.0, 1.0, 0.6)), Vector3(sx * 0.3, 0.38, -0.02))
		hb.add_mesh(ear_mesh, ear_t, body_color)
		hb.add_mesh(_sphere(0.07, 6), Transform3D(Basis(Vector3(0, 0, 1), -sx * 0.25).scaled(Vector3(1, 1, 0.5)), Vector3(sx * 0.3, 0.37, 0.02)), belly_color)
	_merged(_head, hb, vc)
	# --- tail: ONE mesh that wags as a whole
	var tb := PNBatch.new()
	for i in tail_length:
		tb.add_mesh(_sphere(0.11 - i * 0.008, 8), T.call(Vector3(0, 0.0 + float(i) * 0.05, -float(i) * 0.14)), body_color if i < tail_length - 1 else accent_color)
	var tail := _merged(_body, tb, vc, Vector3(0, 0.55, -0.42))
	_tail.append(tail)
	# --- feet: two small meshes (they swing independently)
	for sx2 in [-1.0, 1.0]:
		var fb := PNBatch.new()
		fb.add_mesh(_sphere(0.15, 8), T.call(Vector3.ZERO, Vector3(1.0, 0.7, 1.35)), belly_color)
		var foot := _merged(self, fb, vc, Vector3(sx2 * 0.22, 0.13, 0.05))
		_feet.append(foot)

## Call every physics frame from the controller.
func update_motion(delta: float, speed: float, on_floor: bool, vy: float) -> void:
	if _has_model or _body == null:
		return
	_t += delta
	var run := clampf(speed / 8.0, 0.0, 1.4)
	var cyc := _t * (7.0 + run * 8.0)
	if on_floor:
		_body.position.y = absf(sin(cyc)) * 0.07 * run + (sin(_t * 2.0) * 0.012 if run < 0.05 else 0.0)
		_body.rotation.x = lerpf(_body.rotation.x, 0.18 * run, delta * 10.0)
		_body.rotation.z = sin(cyc) * 0.05 * run
		for i in _feet.size():
			var side := 1.0 if i == 0 else -1.0
			_feet[i].position.z = 0.05 + sin(cyc + (0.0 if i == 0 else PI)) * 0.32 * run
			_feet[i].position.y = 0.13 + maxf(0.0, sin(cyc + (0.0 if i == 0 else PI))) * 0.16 * run
			_feet[i].position.x = side * 0.22
	else:
		_body.position.y = lerpf(_body.position.y, 0.0, delta * 8.0)
		_body.rotation.x = lerpf(_body.rotation.x, clampf(-vy * 0.02, -0.4, 0.4), delta * 8.0)
		for f in _feet:
			f.position.y = lerpf(f.position.y, 0.3 if vy > 0 else 0.18, delta * 10.0)
			f.position.z = lerpf(f.position.z, -0.1 if vy > 0 else 0.25, delta * 10.0)
	# head counter-bob + tail wag (fast when running, lazy at idle)
	_head.rotation.x = -_body.rotation.x * 0.6 + sin(_t * 1.6) * 0.02
	_head.rotation.y = sin(_t * 0.9) * 0.05 * (1.0 - clampf(run, 0.0, 1.0))
	for tl in _tail:
		var amp := 0.18 + 0.38 * run
		tl.rotation.y = sin(_t * (3.0 + run * 7.0)) * amp
		tl.rotation.x = -0.25 - (0.0 if on_floor else 0.25)
	if on_floor and not _was_on_floor:
		Juice.squash(self, 1.22, 0.78, 0.2)
	_was_on_floor = on_floor

func jump_stretch() -> void:
	Juice.stretch(self, 1.28, 0.22)
