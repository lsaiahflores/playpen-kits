class_name TpsPlayer
extends PNFighter
## THIRD-PERSON shooter player: an over-the-shoulder camera on a collision-aware spring arm, your own rigged brick-toy figure
## (idle / walk / run / jump / attack / hit / die animations), aim-down-sights that tightens the camera and the spread, the
## same four weapons as the first-person kit (recoil, flash, tracers, hit markers), sprint, jump, crouch.
## Shots go where the CROSSHAIR points (a ray from the camera), not where the muzzle faces.

signal hit_marker(killed: bool, headshot: bool)
signal weapon_changed(weapon: PNWeapon)

@export var model_path := "res://models/brick_soldier_blue.glb"
@export var walk_speed := 5.6
@export var sprint_speed := 8.6
@export var crouch_speed := 3.0
@export var accel := 46.0
@export var gravity := 28.0
@export var jump_velocity := 8.0
@export var mouse_sens := 0.0024
@export var stick_sens := 2.6
@export var weapon_ids: Array[String] = ["rifle", "pistol", "shotgun", "launcher"]

var pivot: Node3D
var arm: SpringArm3D
var cam: Camera3D
var weapons: Array[PNWeapon] = []
var weapon_idx := 0
var weapon: PNWeapon
var input_enabled := false
var _model: Node3D
var _anim: AnimationPlayer
var _cur := ""
var _yaw := 0.0
var _pitch := -0.15
var _kick := 0.0
var _kick_vel := 0.0
var _step_t := 0.0
var _anims := {}

func _ready() -> void:
	super._ready()
	add_to_group("local_player")
	display_name = "You"
	collision_layer = 2
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)
	var res: Resource = load(model_path) if ResourceLoader.exists(model_path) else null
	if res is PackedScene:
		_model = (res as PackedScene).instantiate() as Node3D
		add_child(_model)
		_anim = _find_anim(_model)
		if _anim:
			for n in _anim.get_animation_list():
				_anims[String(n)] = true
				if String(n).ends_with("-loop"):
					_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	pivot = Node3D.new()
	pivot.top_level = true
	add_child(pivot)
	arm = SpringArm3D.new()
	arm.spring_length = 3.4
	arm.margin = 0.3
	arm.collision_mask = 1
	arm.add_excluded_object(get_rid())
	pivot.add_child(arm)
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.1
	cam.far = 400.0
	cam.position = Vector3(0.7, 0.0, 0.0)   # over the right shoulder
	arm.add_child(cam)
	cam.make_current()
	for id in weapon_ids:
		var w := PNWeapon.new()
		w.setup(id, self)
		w.fired.connect(_on_fired)
		w.hit_confirmed.connect(func(k, h): hit_marker.emit(k, h))
		add_child(w)
		w.position = Vector3(-0.35, 1.3, -0.7)
		weapons.append(w)
	_select(0)
	damaged.connect(func(_a, _b, _c): Juice.shake(0.05, 0.14); PNAudio.sfx("hurt", 1.0, -3.0); _play("hit"))
	_play("idle-loop")

func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r:
			return r
	return null

func _play(name: String) -> void:
	if _anim == null or not _anims.has(name) or _cur == name:
		return
	_cur = name
	_anim.play(name, 0.15)

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not alive:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := mouse_sens * (0.6 if Input.is_action_pressed("aim") else 1.0)
		_yaw -= event.relative.x * s
		_pitch = clampf(_pitch - event.relative.y * s, deg_to_rad(-60.0), deg_to_rad(50.0))
	elif event.is_action_pressed("weapon_next"):
		_select(weapon_idx + 1)
	elif event.is_action_pressed("weapon_prev"):
		_select(weapon_idx - 1)
	else:
		for i in weapons.size():
			if event.is_action_pressed("weapon_%d" % (i + 1)):
				_select(i)

func _select(i: int) -> void:
	weapon_idx = posmod(i, weapons.size())
	weapon = weapons[weapon_idx]
	weapon_changed.emit(weapon)
	weapon.ammo_changed.emit(weapon.mag, weapon.reserve, weapon.reloading)
	PNAudio.sfx("weapon_swap", 1.0, -8.0)

func _on_fired(recoil_pitch: float, recoil_yaw: float) -> void:
	_kick_vel += deg_to_rad(recoil_pitch) * 8.0
	_yaw += deg_to_rad(recoil_yaw) * (-1.0 if randf() < 0.5 else 1.0)
	Juice.shake(0.012 + float(weapon.def.get("kick", 0.05)) * 0.05, 0.08)
	_play("attack")
	get_tree().create_timer(0.3).timeout.connect(func(): _cur = "")

func _physics_process(delta: float) -> void:
	pivot.global_position = global_position + Vector3(0, 1.5, 0)
	if not alive:
		_play("die")
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		velocity.y -= gravity * delta
		move_and_slide()
		return
	var move := Vector2.ZERO
	var aiming := false
	if input_enabled:
		move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if look.length() > 0.12:
			_yaw -= look.x * stick_sens * delta
			_pitch = clampf(_pitch - look.y * stick_sens * delta, deg_to_rad(-60.0), deg_to_rad(50.0))
		aiming = Input.is_action_pressed("aim")
	_kick_vel -= _kick * 80.0 * delta
	_kick_vel *= pow(0.02, delta)
	_kick += _kick_vel * delta
	pivot.rotation = Vector3(_pitch + _kick, _yaw, 0.0)
	arm.spring_length = lerpf(arm.spring_length, 2.0 if aiming else 3.4, delta * 10.0)
	cam.position.x = lerpf(cam.position.x, 0.5 if aiming else 0.7, delta * 10.0)
	cam.fov = lerpf(cam.fov, 52.0 if aiming else 70.0, delta * 10.0)
	var crouching := input_enabled and Input.is_action_pressed("crouch")
	var sprinting := input_enabled and Input.is_action_pressed("sprint") and move.y < -0.1 and not aiming
	var speed := crouch_speed if crouching else (sprint_speed if sprinting else walk_speed)
	var cam_basis := Basis(Vector3.UP, _yaw)
	var dir := (cam_basis * Vector3(move.x, 0, move.y)).normalized()
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * delta)
	if is_on_floor():
		velocity.y = -1.0
		if input_enabled and Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
			PNAudio.sfx("jump", 1.0, -8.0)
			_play("jump")
	else:
		velocity.y -= gravity * delta
	move_and_slide()
	# the figure faces the way you aim while shooting/aiming, otherwise the way you move
	var face := dir if (dir.length() > 0.1 and not aiming) else -cam_basis.z
	if face.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.z), clampf(12.0 * delta, 0.0, 1.0))
	var speed2 := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor():
		_play("jump")
	elif speed2 > 5.0:
		_play("run-loop")
	elif speed2 > 0.8:
		_play("walk-loop")
	elif _cur != "attack" and _cur != "hit":
		_play("idle-loop")
	if speed2 > 2.0 and is_on_floor():
		_step_t -= delta * speed2
		if _step_t <= 0.0:
			_step_t = 3.6
			PNAudio.footstep("brick")
	if input_enabled and weapon:
		var wants := Input.is_action_pressed("fire") if weapon.is_auto() else Input.is_action_just_pressed("fire")
		if wants:
			var origin := cam.global_position
			var aim_dir := -cam.global_transform.basis.z
			var mult := (0.5 if aiming else 1.0) * (1.0 + clampf(speed2 / 10.0, 0.0, 0.7))
			# from the camera through the crosshair; the muzzle flash still plays at the figure's gun
			weapon.fire(origin + aim_dir * (arm.spring_length + 0.6), aim_dir, mult)
		if Input.is_action_just_pressed("reload"):
			weapon.reload()

func respawn_at(pos: Vector3) -> void:
	super.respawn_at(pos)
	_cur = ""
	_play("idle-loop")
	for w in weapons:
		w.mag = int(w.def["mag"])
		w.reserve = int(w.def["reserve"])
		w.reloading = false
	weapon.ammo_changed.emit(weapon.mag, weapon.reserve, false)

func current_spread() -> float:
	return clampf(Vector2(velocity.x, velocity.z).length() / 10.0, 0.0, 1.0)
