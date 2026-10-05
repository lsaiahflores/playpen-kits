class_name PNTerrain
extends RefCounted
## Playpen kit: TERRAIN builder — a heightfield mesh + trimesh collision from a
## noise function, with the look pack's triplanar grass/rock material on it.
##
##   var t := PNTerrain.build(world, {"size": 160.0, "res": 64, "amp": 6.0, "flat_radius": 14.0, "seed": 3})
##   player.global_position = Vector3(0, t.height_at(0, 0) + 1.0, 0)
##   t.height_at(x, z)   # for placing trees, rocks, enemies on the ground

var node: StaticBody3D
var mesh_instance: MeshInstance3D
var size := 160.0
var _noise := FastNoiseLite.new()
var _amp := 6.0
var _flat := 14.0
var _water_level := -999.0

static func build(parent: Node3D, opts := {}) -> PNTerrain:
	var t := PNTerrain.new()
	t.size = float(opts.get("size", 160.0))
	t._amp = float(opts.get("amp", 6.0))
	t._flat = float(opts.get("flat_radius", 14.0))
	t._noise.seed = int(opts.get("seed", 1))
	t._noise.frequency = float(opts.get("frequency", 0.02))
	t._noise.fractal_octaves = 3
	var res := int(opts.get("res", 64))
	if PNSettings.quality == PNSettings.Quality.LOW:
		res = mini(res, 48)
	var step := t.size / res
	var half := t.size * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heights := PackedFloat32Array()
	heights.resize((res + 1) * (res + 1))
	for iz in res + 1:
		for ix in res + 1:
			heights[iz * (res + 1) + ix] = t.height_at(-half + ix * step, -half + iz * step)
	for iz in res:
		for ix in res:
			var x0 := -half + ix * step
			var z0 := -half + iz * step
			var h00 := heights[iz * (res + 1) + ix]
			var h10 := heights[iz * (res + 1) + ix + 1]
			var h01 := heights[(iz + 1) * (res + 1) + ix]
			var h11 := heights[(iz + 1) * (res + 1) + ix + 1]
			var p00 := Vector3(x0, h00, z0)
			var p10 := Vector3(x0 + step, h10, z0)
			var p01 := Vector3(x0, h01, z0 + step)
			var p11 := Vector3(x0 + step, h11, z0 + step)
			for tri in [[p00, p10, p01], [p10, p11, p01]]:   # clockwise seen from above = front face in Godot
				var n: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
				for p in tri:
					st.set_normal(n)
					st.add_vertex(p)
	var mesh := st.commit()
	t.mesh_instance = MeshInstance3D.new()
	t.mesh_instance.mesh = mesh
	t.mesh_instance.material_override = opts.get("material", PNLook.terrain_material())
	t.node = StaticBody3D.new()
	t.node.name = "Terrain"
	t.node.collision_layer = 1
	t.node.add_child(t.mesh_instance)
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	t.node.add_child(cs)
	parent.add_child(t.node)
	return t

func height_at(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	var flat := clampf((d - _flat) / maxf(_flat, 1.0), 0.0, 1.0)
	flat = flat * flat * (3.0 - 2.0 * flat)
	var n := _noise.get_noise_2d(x, z) * 0.5 + 0.5
	# gentle rolling hills that rise toward the edges
	var edge := clampf((d - size * 0.25) / (size * 0.25), 0.0, 1.0)
	return (n * _amp + edge * _amp * 0.8) * flat
