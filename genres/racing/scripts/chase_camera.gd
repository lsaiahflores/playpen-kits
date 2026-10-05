class_name ChaseCamera
extends Node3D
## Racing chase camera: sits behind and above the kart, swings with its heading,
## pulls back and widens the FOV with speed (and more on a boost), looks slightly
## ahead of the kart, and sways a little when drifting.

@export var distance := 7.2
@export var height := 3.1
@export var follow := 7.0
@export var base_fov := 68.0
var kart: Kart
var camera: Camera3D
var _yaw := 0.0

func _ready() -> void:
	top_level = true
	camera = Camera3D.new()
	camera.fov = base_fov
	camera.far = 700.0
	camera.near = 0.1
	camera.current = true
	add_child(camera)

func set_kart(k: Kart) -> void:
	kart = k
	_yaw = k.yaw

func _process(delta: float) -> void:
	if kart == null or not is_instance_valid(kart):
		return
	_yaw = lerp_angle(_yaw, kart.yaw - (kart.drift_dir * 0.35 if kart.drifting else 0.0), 1.0 - exp(-follow * 0.8 * delta))
	var back := Vector3(-sin(_yaw), 0, -cos(_yaw))
	var spd := clampf(absf(kart.speed) / kart.max_speed, 0.0, 1.4)
	var dist := distance + spd * 1.6 + (1.2 if kart.boost_time > 0.0 else 0.0)
	var want := kart.global_position + back * dist + Vector3(0, height + spd * 0.4, 0)
	global_position = global_position.lerp(want, 1.0 - exp(-follow * delta))
	var look_at_pos := kart.global_position + Vector3(sin(_yaw), 0, cos(_yaw)) * 5.0 + Vector3(0, 1.0, 0)
	look_at(look_at_pos, Vector3.UP)
	var fov_t := base_fov + spd * 14.0 + (10.0 if kart.boost_time > 0.0 else 0.0)
	camera.fov = lerpf(camera.fov, fov_t, 1.0 - exp(-4.0 * delta))
	if kart.boost_time > 0.0:
		camera.h_offset = randf_range(-0.03, 0.03)
		camera.v_offset = randf_range(-0.03, 0.03)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
