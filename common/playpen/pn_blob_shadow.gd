extends MeshInstance3D
## Keeps a blob shadow glued to the ground under its parent (raycast down).
## Shrinks and fades as the parent leaves the ground — the classic platformer cue
## for "how high am I".

@export var max_height := 8.0
@export var ground_mask := 1
var _base_alpha := 0.55

func _ready() -> void:
	top_level = true
	var mat := material_override as StandardMaterial3D
	if mat:
		_base_alpha = mat.albedo_color.a

func _process(_delta: float) -> void:
	var parent := get_parent() as Node3D
	if parent == null:
		return
	var from := parent.global_position + Vector3(0, 0.5, 0)
	var to := from + Vector3(0, -max_height, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, ground_mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		visible = false
		return
	visible = true
	var p: Vector3 = hit.position
	global_position = p + Vector3(0, 0.03, 0)
	var h := clampf((from.y - p.y) / max_height, 0.0, 1.0)
	scale = Vector3.ONE * lerpf(1.0, 0.45, h)
	var mat := material_override as StandardMaterial3D
	if mat:
		mat.albedo_color.a = _base_alpha * lerpf(1.0, 0.35, h)
