class_name PNFollowCamera
extends Node3D
## Playpen kit: collision-aware smooth follow camera (third person).
## SpringArm3D keeps it out of walls; the pivot eases toward the target with a
## little look-ahead; right stick / mouse orbit; it auto-swings behind you when
## you run and the stick is idle; FOV kicks out with speed; idle sway so the world
## never feels frozen. `get_yaw()` gives the camera yaw for camera-relative movement.

@export var target_path: NodePath
@export var distance := 6.5
@export var height := 1.7
@export var min_pitch := -1.15
@export var max_pitch := 0.45
@export var mouse_sens := 0.0032
@export var stick_speed := 2.8
@export var follow_speed := 9.0
@export var look_ahead := 1.4
@export var auto_recenter := true
@export var base_fov := 70.0
@export var fov_kick := 9.0

var target: Node3D
var camera: Camera3D
var arm: SpringArm3D
var yaw := 0.0
var pitch := -0.28
var _idle_t := 0.0
var _look_input_age := 99.0
var _last_target_pos := Vector3.ZERO
var _vel := Vector3.ZERO
var locked_on: Node3D = null    # adventure kit: when set, the camera frames this

func _ready() -> void:
	top_level = true
	arm = SpringArm3D.new()
	arm.spring_length = distance
	arm.margin = 0.35
	arm.collision_mask = 1
	arm.shape = SphereShape3D.new()
	(arm.shape as SphereShape3D).radius = 0.25
	add_child(arm)
	camera = Camera3D.new()
	camera.fov = base_fov
	camera.current = true
	camera.near = 0.08
	camera.far = 600.0
	arm.add_child(camera)
	if target_path != NodePath():
		set_target(get_node(target_path))

func set_target(t: Node3D) -> void:
	target = t
	if target:
		global_position = target.global_position + Vector3(0, height, 0)
		_last_target_pos = target.global_position
		yaw = target.global_rotation.y + PI
		if target is PhysicsBody3D:
			arm.add_excluded_object((target as PhysicsBody3D).get_rid())

func get_yaw() -> float:
	return yaw

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= (event as InputEventMouseMotion).relative.x * mouse_sens
		pitch = clampf(pitch - (event as InputEventMouseMotion).relative.y * mouse_sens, min_pitch, max_pitch)
		_look_input_age = 0.0

func _process(delta: float) -> void:
	if target == null:
		return
	_idle_t += delta
	_look_input_age += delta
	var stick := Vector2(Input.get_axis("look_left", "look_right"), Input.get_axis("look_up", "look_down"))
	if stick.length() > 0.12:
		yaw -= stick.x * stick_speed * delta
		pitch = clampf(pitch - stick.y * stick_speed * 0.7 * delta, min_pitch, max_pitch)
		_look_input_age = 0.0
	var tpos := target.global_position
	_vel = (tpos - _last_target_pos) / maxf(delta, 0.0001)
	_last_target_pos = tpos
	var hv := Vector3(_vel.x, 0, _vel.z)
	if locked_on and is_instance_valid(locked_on):
		var to := locked_on.global_position - tpos
		var want := atan2(-to.x, -to.z) + PI
		yaw = lerp_angle(yaw, want, 1.0 - exp(-6.0 * delta))
		pitch = lerpf(pitch, -0.2, 1.0 - exp(-4.0 * delta))
	elif auto_recenter and hv.length() > 2.0 and _look_input_age > 1.2:
		var behind := atan2(hv.x, hv.z) + PI
		yaw = lerp_angle(yaw, behind, 1.0 - exp(-0.9 * delta))
	var want_pos := tpos + Vector3(0, height, 0) + hv.normalized() * minf(hv.length() * 0.08, look_ahead)
	global_position = global_position.lerp(want_pos, 1.0 - exp(-follow_speed * delta))
	# pivot looks along yaw/pitch; the arm extends backward
	var sway := Vector3(sin(_idle_t * 0.6) * 0.012, cos(_idle_t * 0.45) * 0.01, 0) if hv.length() < 0.5 else Vector3.ZERO
	global_rotation = Vector3(pitch + sway.x, yaw, sway.y)
	arm.spring_length = lerpf(arm.spring_length, distance, 1.0 - exp(-5.0 * delta))
	camera.fov = lerpf(camera.fov, base_fov + clampf(hv.length() / 10.0, 0.0, 1.0) * fov_kick, 1.0 - exp(-4.0 * delta))
	PNWind.track(target)
