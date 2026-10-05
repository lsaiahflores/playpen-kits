class_name PlatformerPlayer
extends CharacterBody3D
## 3D platformer hero (Sunshine / Mario-style feel).
##   • camera-relative movement with acceleration and a snappy turn
##   • COYOTE TIME  — you can still jump for a moment after running off a ledge
##   • JUMP BUFFER  — a jump pressed just BEFORE landing still fires on landing
##   • VARIABLE JUMP — release early for a short hop; hold for full height
##   • LEDGE FORGIVENESS — head-bonk corner nudge (you slip past a ledge corner
##     instead of bonking) and a small step-up so tiny lips never stop you
##   • heavier fall than rise (feels weighty, not floaty); terminal velocity
##   • dust, footsteps by surface, landing squash, blob shadow, respawn
## All tuning lives in the @export block — change numbers, don't rewrite the logic.

signal jumped
signal landed(impact: float)
signal respawned

@export_group("Run")
@export var run_speed := 9.5
@export var accel := 58.0
@export var decel := 75.0
@export var air_control := 0.55
@export var turn_speed := 15.0
@export_group("Jump")
@export var jump_velocity := 11.8
@export var gravity_up := 27.0
@export var gravity_down := 44.0
@export var jump_cut := 0.42
@export var coyote_time := 0.12
@export var buffer_time := 0.14
@export var max_fall := 40.0
@export_group("Forgiveness")
@export var corner_nudge := 0.42
@export var step_up := 0.38
@export var fall_limit := -40.0
@export_group("Look")
@export var body_color := Color(1.0, 0.62, 0.2)
@export var stripes := false
@export var ear_style := "round"

var respawn_point := Vector3(0, 2, 0)
var camera: PNFollowCamera
var rig: PNCritterRig
var surface := "pavement"          # set by the level for footstep sounds
var _coyote := 0.0
var _buffer := 0.0
var _was_on_floor := false
var _step_timer := 0.0
var _peak_fall := 0.0
var _jumping := false
var _visual: Node3D

func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(52.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 1.5
	cs.shape = cap
	cs.position.y = 0.75
	add_child(cs)
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	rig = PNCritterRig.new()
	rig.body_color = body_color
	rig.belly_color = body_color.lightened(0.55)
	rig.stripes = stripes
	rig.ear_style = ear_style
	_visual.add_child(rig)
	Juice.blob_shadow(self, 0.75)
	respawn_point = global_position + Vector3(0, 0.2, 0)

func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	# --- timers --------------------------------------------------------------
	if on_floor:
		_coyote = coyote_time
		_jumping = false
	else:
		_coyote = maxf(0.0, _coyote - delta)
	if Input.is_action_just_pressed("jump"):
		_buffer = buffer_time
	else:
		_buffer = maxf(0.0, _buffer - delta)

	# --- gravity: lighter going up, heavier coming down ----------------------
	if not on_floor:
		var g := gravity_up if velocity.y > 0.0 else gravity_down
		velocity.y = maxf(velocity.y - g * delta, -max_fall)
		_peak_fall = minf(_peak_fall, velocity.y)

	# --- jump (coyote + buffer) ---------------------------------------------
	if _buffer > 0.0 and _coyote > 0.0:
		velocity.y = jump_velocity
		_buffer = 0.0
		_coyote = 0.0
		_jumping = true
		jumped.emit()
		PNAudio.sfx("jump", randf_range(0.97, 1.05), -6.0)
		Juice.dust(global_position + Vector3(0, 0.1, 0), 5)
		rig.jump_stretch()
	if _jumping and velocity.y > 0.0 and Input.is_action_just_released("jump"):
		velocity.y *= jump_cut      # variable height: let go early = short hop

	# --- movement relative to the camera ------------------------------------
	var input := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_back"))
	if input.length() > 1.0:
		input = input.normalized()
	var yaw := camera.get_yaw() if camera else 0.0
	var basis_yaw := Basis(Vector3.UP, yaw)
	var wish := basis_yaw * Vector3(input.x, 0.0, input.y)
	var control := 1.0 if on_floor else air_control
	var target_h := wish * run_speed
	var h := Vector3(velocity.x, 0.0, velocity.z)
	var rate := (accel if wish.length() > 0.05 else decel) * control
	h = h.move_toward(target_h, rate * delta)
	velocity.x = h.x
	velocity.z = h.z
	if h.length() > 0.5:
		var want := atan2(h.x, h.z)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, want, 1.0 - exp(-turn_speed * delta))

	# --- ledge forgiveness: corner nudge on head-bonk, tiny step-up ---------
	if velocity.y > 0.5:
		_corner_nudge()
	_step_up(h, delta)

	move_and_slide()

	# --- landing / footsteps / respawn --------------------------------------
	on_floor = is_on_floor()
	if on_floor and not _was_on_floor:
		var impact := -_peak_fall
		_peak_fall = 0.0
		if impact > 6.0:
			Juice.dust(global_position + Vector3(0, 0.1, 0), clampi(int(impact * 0.6), 4, 14))
			PNAudio.footstep(surface, global_position)
			landed.emit(impact)
			if impact > 22.0:
				Juice.shake(0.1, 0.16)
	_was_on_floor = on_floor
	if on_floor and h.length() > 1.5:
		_step_timer -= delta * (h.length() / run_speed)
		if _step_timer <= 0.0:
			_step_timer = 0.34
			PNAudio.footstep(surface, global_position)
			if h.length() > run_speed * 0.8:
				Juice.dust(global_position + Vector3(0, 0.05, 0), 2, Color(0.85, 0.8, 0.7, 0.55), 0.12)
	rig.update_motion(delta, h.length(), on_floor, velocity.y)
	if global_position.y < fall_limit:
		respawn()

func _corner_nudge() -> void:
	# going up and about to bonk a ceiling corner? slide sideways to clear it.
	var up := Vector3(0, 0.12, 0)
	if not test_move(global_transform, up):
		return
	for off in [Vector3(corner_nudge, 0, 0), Vector3(-corner_nudge, 0, 0), Vector3(0, 0, corner_nudge), Vector3(0, 0, -corner_nudge)]:
		var t := global_transform
		t.origin += off
		if not test_move(t, up) and not test_move(global_transform, off):
			global_position += off
			return

func _step_up(h: Vector3, delta: float) -> void:
	# a low lip in front of us while we're running on the ground: hop onto it
	if not is_on_floor() or h.length() < 1.0:
		return
	var dir := h.normalized() * 0.5
	if test_move(global_transform, dir) and not test_move(_raised(step_up), dir):
		global_position.y += step_up * minf(1.0, delta * 30.0)

func _raised(by: float) -> Transform3D:
	var t := global_transform
	t.origin.y += by
	return t

func respawn() -> void:
	velocity = Vector3.ZERO
	global_position = respawn_point
	Juice.sparkle(respawn_point, Color(0.7, 0.9, 1.0), 12)
	PNAudio.sfx("respawn", 1.0, -6.0)
	respawned.emit()
