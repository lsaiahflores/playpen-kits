class_name PNCheckpoint
extends Area3D
## Playpen kit: a checkpoint flag. Touch it and it becomes the respawn point, the
## flag runs up the pole and flutters in the wind, with a stinger and a toast.
## The player needs a `respawn_point: Vector3` property and group "player".

signal activated(cp: PNCheckpoint)
var active := false
var _flag: MeshInstance3D

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(3.2, 4.0, 3.2)
	cs.shape = bs
	cs.position.y = 2.0
	add_child(cs)
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.06
	pm.bottom_radius = 0.08
	pm.height = 3.6
	pm.radial_segments = 6
	pole.mesh = pm
	pole.material_override = PNLook.toon(Color(0.9, 0.9, 0.92))
	pole.position.y = 1.8
	add_child(pole)
	_flag = MeshInstance3D.new()
	var fm := QuadMesh.new()
	fm.size = Vector2(1.5, 0.9)
	fm.center_offset = Vector3(0.75, 0, 0)
	_flag.mesh = fm
	var mat := PNLook.sway_material(PNLook.color("secondary", Color(0.3, 0.7, 0.9)).darkened(0.1), PNLook.color("accent", Color(1, 0.5, 0.4)), 1.5, 0.55)
	mat.set_shader_parameter("flutter", 0.35)
	mat.set_shader_parameter("pin_axis", 0)
	mat.set_shader_parameter("sway_height", 1.5)
	_flag.material_override = mat
	_flag.position = Vector3(0.05, 2.2, 0)
	add_child(_flag)
	body_entered.connect(_on_body)

func _on_body(body: Node3D) -> void:
	if active or not body.is_in_group("player"):
		return
	active = true
	body.set("respawn_point", global_position + Vector3(0, 1.5, 0))
	Juice.sparkle(global_position + Vector3(0, 3.0, 0), Color(0.6, 1, 0.8), 18)
	var tw := create_tween()
	_flag.position.y = 0.9
	tw.tween_property(_flag, "position:y", 2.7, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	PNAudio.stinger("checkpoint", -6.0)
	activated.emit(self)
