class_name PNBatch
extends RefCounted
## Playpen kit: merges many simple boxes into ONE mesh (one draw call) with a
## per-vertex color. A whole city of buildings, roofs and awnings becomes a single
## draw instead of hundreds — the difference between smooth and slideshow on an
## 8GB / integrated-graphics machine.
##
##   var b := PNBatch.new()
##   b.add_box(Vector3(10, 8, 4), Vector3(8, 16, 8), Color(.9, .8, .7))          # walls (windows drawn by shader)
##   b.add_box(Vector3(10, 17, 4), Vector3(3, 2, 3), Color(.6, .4, .4), true)    # solid = no windows
##   var mi := b.commit(PNLook.windows_material(Color.WHITE))
##
## `solid` boxes write alpha 0 so the windows shader leaves them a flat color.

var _st := SurfaceTool.new()
var _count := 0

func _init() -> void:
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)

func add_box(center: Vector3, size: Vector3, color: Color, solid := false) -> void:
	var lin := color.srgb_to_linear()   # vertex colors are linear
	var c := Color(lin.r, lin.g, lin.b, 0.0 if solid else 1.0)
	var h := size * 0.5
	var x0 := center.x - h.x
	var x1 := center.x + h.x
	var y0 := center.y - h.y
	var y1 := center.y + h.y
	var z0 := center.z - h.z
	var z1 := center.z + h.z
	# +Y, -Y, +X, -X, +Z, -Z  (counter-clockwise from outside)
	_quad(Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3.UP, c)
	_quad(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector3.DOWN, c)
	_quad(Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3.RIGHT, c)
	_quad(Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3.LEFT, c)
	_quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.BACK, c)
	_quad(Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3.FORWARD, c)
	_count += 1

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	for p in [a, b, c, a, c, d]:
		_st.set_color(col)
		_st.set_normal(n)
		_st.add_vertex(p)

## Bake an existing primitive mesh (sphere, capsule, cylinder...) with a transform and color.
func add_mesh(mesh: Mesh, xform: Transform3D, color: Color) -> void:
	var lin := color.srgb_to_linear()
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx = arrays[Mesh.ARRAY_INDEX]
	var nb := xform.basis.inverse().transposed()
	if idx != null and (idx as PackedInt32Array).size() > 0:
		for i in idx:
			_st.set_color(Color(lin.r, lin.g, lin.b, 1.0))
			_st.set_normal((nb * norms[i]).normalized())
			_st.add_vertex(xform * verts[i])
	else:
		for i in verts.size():
			_st.set_color(Color(lin.r, lin.g, lin.b, 1.0))
			_st.set_normal((nb * norms[i]).normalized())
			_st.add_vertex(xform * verts[i])
	_count += 1

func count() -> int:
	return _count

func commit(material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _st.commit()
	mi.material_override = material
	return mi
