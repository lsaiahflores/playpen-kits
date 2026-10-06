class_name FpsPlayer
extends PNFighter
## FIRST-PERSON shooter player: mouse / right-stick look, WASD / left-stick move, jump, sprint, crouch, four weapons with
## recoil that kicks the view and recovers, aim-down-sights, a toy-brick view model, footsteps, damage flash.
##
## Tune the @exports; don't rewrite the controller.

signal hit_marker(killed: bool, headshot: bool)
signal weapon_changed(weapon: PNWeapon)

@export var walk_speed := 6.0
@export var sprint_speed := 9.0
@export var crouch_speed := 3.2
@export var accel := 50.0
@export var gravity := 28.0
@export var jump_velocity := 8.0
@export var mouse_sens := 0.0022
@export var stick_sens := 2.6
@export var fov := 78.0
@export var weapon_ids: Array[String] = ["rifle", "pistol", "shotgun", "launcher"]

var head: Node3D
var cam: Camera3D
var weapons: Array[PNWeapon] = []
var weapon_idx := 0
var weapon: PNWeapon
var input_enabled := false
var _pitch := 0.0
var _kick := 0.0
var _kick_vel := 0.0
var _crouch_t := 0.0
var _step_t := 0.0
var _view: Node3D
var _view_kick := 0.0
var _bob := 0.0
var _body_shape: CollisionShape3D

func _ready() -> void:
	super._ready()
	add_to_group("local_player")
	display_name = "You"
	collision_layer = 2
	collision_mask = 1
	_body_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.75
	_body_shape.shape = cap
	_body_shape.position.y = 0.875
	add_child(_body_shape)
	head = Node3D.new()
	head.position = Vector3(0, 1.62, 0)
	add_child(head)
	cam = Camera3D.new()
	cam.fov = fov
	cam.near = 0.05
	cam.far = 400.0
	head.add_child(cam)
	cam.make_current()
	_view = Node3D.new()
	_view.position = Vector3(0.2, -0.2, -0.42)
	cam.add_child(_view)
	for id in weapon_ids:
		var w := PNWeapon.new()
		w.setup(id, self)
		w.fired.connect(_on_fired)
		w.hit_confirmed.connect(func(k, h): hit_marker.emit(k, h))
		add_child(w)
		weapons.append(w)
	_select(0)
	damaged.connect(_on_damaged)

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not alive:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := mouse_sens * (0.55 if Input.is_action_pressed("aim") else 1.0)
		rotate_y(-event.relative.x * s)
		_pitch = clampf(_pitch - event.relative.y * s, deg_to_rad(-85.0), deg_to_rad(85.0))
	elif event.is_action_pressed("weapon_next"):
		_select(weapon_idx + 1)
	elif event.is_action_pressed("weapon_prev"):
		_select(weapon_idx - 1)
	else:
		for i in weapons.size():
			if event.is_action_pressed("weapon_%d" % (i + 1)):
				_select(i)

func _select(i: int) -> void:
	if weapon != null and weapon.get_parent() == _view:
		_view.remove_child(weapon)
		add_child(weapon)
	weapon_idx = posmod(i, weapons.size())
	weapon = weapons[weapon_idx]
	_build_viewmodel()
	weapon_changed.emit(weapon)
	weapon.ammo_changed.emit(weapon.mag, weapon.reserve, weapon.reloading)
	PNAudio.sfx("weapon_swap", 1.0, -8.0)

func _build_viewmodel() -> void:
	for c in _view.get_children():
		c.queue_free()
	var plastic_dark := PNLook.plastic_material(Color(0.2, 0.22, 0.3), false)
	var plastic_main := PNLook.plastic_material(PNLook.color("primary", Color(0.2, 0.45, 0.9)), false)
	var plastic_acc := PNLook.plastic_material(PNLook.color("accent", Color(1.0, 0.8, 0.2)), false)
	var plastic_white := PNLook.plastic_material(Color(0.94, 0.94, 0.92), false)
	var parts: Array = []
	match weapon.id:
		"pistol":
			parts = [[Vector3(0.06, 0.07, 0.22), Vector3(0, 0.0, -0.04), plastic_white], [Vector3(0.05, 0.12, 0.06), Vector3(0, -0.09, 0.04), plastic_main], [Vector3(0.04, 0.03, 0.05), Vector3(0, 0.05, -0.1), plastic_acc]]
		"shotgun":
			parts = [[Vector3(0.07, 0.07, 0.42), Vector3(0, 0, -0.08), plastic_dark], [Vector3(0.075, 0.075, 0.2), Vector3(0, -0.055, -0.14), plastic_acc], [Vector3(0.06, 0.12, 0.14), Vector3(0, -0.07, 0.16), plastic_main], [Vector3(0.05, 0.05, 0.1), Vector3(0, 0.0, -0.32), plastic_white]]
		"launcher":
			parts = [[Vector3(0.14, 0.14, 0.5), Vector3(0, 0.02, -0.1), plastic_main], [Vector3(0.1, 0.1, 0.14), Vector3(0, 0.02, -0.4), plastic_acc], [Vector3(0.05, 0.12, 0.08), Vector3(0, -0.12, 0.08), plastic_dark], [Vector3(0.08, 0.04, 0.2), Vector3(0, 0.1, -0.1), plastic_white]]
		_:
			parts = [[Vector3(0.065, 0.09, 0.36), Vector3(0, 0, -0.04), plastic_white], [Vector3(0.035, 0.035, 0.18), Vector3(0, 0.012, -0.3), plastic_acc], [Vector3(0.05, 0.11, 0.07), Vector3(0, -0.1, 0.0), plastic_main], [Vector3(0.055, 0.075, 0.16), Vector3(0, -0.005, 0.2), plastic_main], [Vector3(0.04, 0.03, 0.12), Vector3(0, 0.06, -0.06), plastic_dark]]
	for p in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = PNBricks.chamfer_box(p[0], 0.012)
		mi.material_override = p[2]
		mi.position = p[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_view.add_child(mi)
	# the weapon node (muzzle flash + light) rides the view model's muzzle
	if weapon.get_parent() != _view:
		weapon.get_parent().remove_child(weapon)
		_view.add_child(weapon)
	weapon.position = Vector3(0, 0.0, -0.4)

func _on_fired(recoil_pitch: float, recoil_yaw: float) -> void:
	_kick_vel += deg_to_rad(recoil_pitch) * 9.0
	rotate_y(deg_to_rad(recoil_yaw) * (-1.0 if randf() < 0.5 else 1.0))
	_view_kick = float(weapon.def.get("kick", 0.05))
	Juice.shake(0.01 + _view_kick * 0.06, 0.08)

func _on_damaged(_amount: float, _attacker: Node, _from_dir: Vector3) -> void:
	Juice.shake(0.05, 0.14)
	PNAudio.sfx("hurt", 1.0, -3.0)

func _physics_process(delta: float) -> void:
	if not alive:
		cam.rotation.z = lerpf(cam.rotation.z, 0.5, delta * 3.0)
		head.position.y = lerpf(head.position.y, 0.4, delta * 3.0)
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		velocity.y -= gravity * delta
		move_and_slide()
		return
	cam.rotation.z = lerpf(cam.rotation.z, 0.0, delta * 8.0)
	var crouching := input_enabled and Input.is_action_pressed("crouch")
	_crouch_t = move_toward(_crouch_t, 1.0 if crouching else 0.0, delta * 8.0)
	head.position.y = lerpf(1.62, 1.1, _crouch_t)
	var move := Vector2.ZERO
	var aiming := false
	if input_enabled:
		move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if look.length() > 0.12:
			rotate_y(-look.x * stick_sens * delta * (0.55 if Input.is_action_pressed("aim") else 1.0))
			_pitch = clampf(_pitch - look.y * stick_sens * delta, deg_to_rad(-85.0), deg_to_rad(85.0))
		aiming = Input.is_action_pressed("aim")
	var speed := crouch_speed if _crouch_t > 0.5 else (sprint_speed if (input_enabled and Input.is_action_pressed("sprint") and move.y < -0.1) else walk_speed)
	if aiming:
		speed *= 0.7
	var dir := (global_transform.basis * Vector3(move.x, 0, move.y)).normalized()
	velocity.x = move_toward(velocity.x, dir.x * speed, accel * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * delta)
	if is_on_floor():
		velocity.y = -1.0
		if input_enabled and Input.is_action_just_pressed("jump") and _crouch_t < 0.5:
			velocity.y = jump_velocity
			PNAudio.sfx("jump", 1.0, -8.0)
	else:
		velocity.y -= gravity * delta
	var was_floor := is_on_floor()
	move_and_slide()
	if is_on_floor() and not was_floor:
		PNAudio.sfx("land", 1.0, -8.0)
		Juice.shake(0.02, 0.1)
	# view: pitch + recoil kick (spring back), bob, ADS zoom
	_kick_vel -= _kick * 90.0 * delta
	_kick_vel *= pow(0.02, delta)
	_kick += _kick_vel * delta
	head.rotation.x = _pitch + _kick
	cam.fov = lerpf(cam.fov, fov * (0.7 if aiming else 1.0), delta * 12.0)
	var moving := Vector2(velocity.x, velocity.z).length()
	_bob += delta * moving * 1.6
	_view_kick = move_toward(_view_kick, 0.0, delta * 0.6)
	var ads := 1.0 if aiming else 0.0
	_view.position = _view.position.lerp(Vector3(lerpf(0.22, 0.0, ads), lerpf(-0.2, -0.13, ads) + sin(_bob) * 0.006 * (1.0 - ads), -0.42 + _view_kick), delta * 14.0)
	_view.rotation.x = lerpf(_view.rotation.x, -_view_kick * 0.8, delta * 14.0)
	if moving > 2.0 and is_on_floor():
		_step_t -= delta * moving
		if _step_t <= 0.0:
			_step_t = 3.6
			PNAudio.footstep("brick")
	# fire / reload
	if input_enabled and weapon:
		var wants := Input.is_action_pressed("fire") if weapon.is_auto() else Input.is_action_just_pressed("fire")
		if wants:
			var origin := cam.global_position
			var aim_dir := -cam.global_transform.basis.z
			var spread_mult := (0.45 if aiming else 1.0) * (1.0 + clampf(moving / 10.0, 0.0, 0.8)) * (0.7 if _crouch_t > 0.5 else 1.0)
			weapon.fire(origin, aim_dir, spread_mult)
		if Input.is_action_just_pressed("reload"):
			weapon.reload()

func respawn_at(pos: Vector3) -> void:
	super.respawn_at(pos)
	cam.rotation.z = 0.0
	head.position.y = 1.62
	_pitch = 0.0
	for w in weapons:
		w.mag = int(w.def["mag"])
		w.reserve = int(w.def["reserve"])
		w.reloading = false
	weapon.ammo_changed.emit(weapon.mag, weapon.reserve, false)

func current_spread() -> float:
	return clampf(Vector2(velocity.x, velocity.z).length() / 10.0, 0.0, 1.0)
