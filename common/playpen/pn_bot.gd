class_name PNBot
extends PNFighter
## Playpen kit: a BOT that fights. Navigates with a NavigationAgent3D (nav mesh baked by the level), seeks the nearest enemy,
## engages with line of sight, strafes, aims with human-ish inaccuracy that depends on difficulty, shoots the same
## PNWeapon the player uses, plays the model's idle/walk/run/attack/hit/die animations.
##
##   var bot := PNBot.new()
##   bot.team = 2
##   bot.model_path = "res://models/brick_soldier_red.glb"
##   bot.difficulty = 0.5                  # 0 easy .. 1 hard
##   world.add_child(bot)

signal wants_respawn(bot: PNBot)

@export var model_path := "res://models/brick_soldier_red.glb"
@export var model_scale := 1.0
@export var difficulty := 0.5
@export var move_speed := 4.6
@export var weapon_id := "rifle"

var weapon: PNWeapon
var target: PNFighter = null
var nav: NavigationAgent3D
var _model: Node3D
var _anim: AnimationPlayer
var _cur_anim := ""
var _think := 0.0
var _strafe := 1.0
var _strafe_t := 0.0
var _burst := 0
var _burst_gap := 0.0
var _reaction := 0.0
var _spawn_protect := 0.0
var _anim_names := {}

func _ready() -> void:
	super._ready()
	collision_layer = 4
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	add_child(cs)
	nav = NavigationAgent3D.new()
	nav.path_desired_distance = 0.7
	nav.target_desired_distance = 1.2
	nav.radius = 0.5
	nav.avoidance_enabled = false
	add_child(nav)
	var res: Resource = load(model_path) if ResourceLoader.exists(model_path) else null
	if res is PackedScene:
		_model = (res as PackedScene).instantiate() as Node3D
		_model.scale = Vector3.ONE * model_scale
		add_child(_model)
		_anim = _find_anim(_model)
		if _anim:
			for n in _anim.get_animation_list():
				_anim_names[String(n)] = true
				var an := _anim.get_animation(n)
				if an and String(n).ends_with("-loop"):
					an.loop_mode = Animation.LOOP_LINEAR
		model_height = 1.84 * model_scale
	else:
		_model = _fallback_body()
		add_child(_model)
	weapon = PNWeapon.new()
	weapon.setup(weapon_id, self)
	weapon.position = Vector3(0, 1.3, -0.5)
	add_child(weapon)
	_play("idle-loop")
	_reaction = lerpf(0.55, 0.12, difficulty)

func _fallback_body() -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.35
	cm.height = 1.7
	mi.mesh = cm
	mi.position.y = 0.85
	mi.material_override = PNLook.plastic_material(PNLook.color("secondary", Color.RED), false)
	n.add_child(mi)
	return n

func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r:
			return r
	return null

func _play(name: String, speed := 1.0) -> void:
	if _anim == null or not _anim_names.has(name) or _cur_anim == name:
		return
	_cur_anim = name
	_anim.play(name, 0.15, speed)

func _physics_process(delta: float) -> void:
	if not alive:
		return
	if _spawn_protect > 0.0:
		_spawn_protect -= delta
	_think -= delta
	if _think <= 0.0:
		_think = 0.25 + randf() * 0.1
		target = _pick_target()
	var move_dir := Vector3.ZERO
	var engaged := false
	if target and is_instance_valid(target) and target.alive:
		var to := target.global_position - global_position
		var dist := to.length()
		var los := _has_los(target)
		if los and dist < 38.0:
			engaged = true
			_face(to, delta, 9.0)
			_strafe_t -= delta
			if _strafe_t <= 0.0:
				_strafe_t = randf_range(0.8, 2.0)
				_strafe = -_strafe if randf() < 0.6 else _strafe
			var side := to.normalized().cross(Vector3.UP) * _strafe
			if dist > 14.0:
				move_dir = to.normalized() * 0.8 + side * 0.4
			elif dist < 6.0:
				move_dir = -to.normalized() * 0.7 + side * 0.5
			else:
				move_dir = side * 0.7
			_try_shoot(delta, dist)
		else:
			nav.target_position = target.global_position
			move_dir = _path_dir()
			if move_dir.length() > 0.05:
				_face(move_dir, delta, 7.0)
	else:
		move_dir = Vector3.ZERO
	move_dir.y = 0.0
	if move_dir.length() > 0.01:
		move_dir = move_dir.normalized()
	velocity.x = move_toward(velocity.x, move_dir.x * move_speed, 28.0 * delta)
	velocity.z = move_toward(velocity.z, move_dir.z * move_speed, 28.0 * delta)
	velocity.y -= 26.0 * delta if not is_on_floor() else 0.0
	if is_on_floor():
		velocity.y = -1.0
	move_and_slide()
	var speed2 := Vector2(velocity.x, velocity.z).length()
	if engaged and _burst > 0 and _burst_gap <= 0.0 and weapon and not weapon.can_fire():
		pass
	if speed2 > 3.2:
		_play("run-loop")
	elif speed2 > 0.6:
		_play("walk-loop")
	else:
		_play("idle-loop")

func _pick_target() -> PNFighter:
	var best: PNFighter = null
	var best_d := 1e9
	for n in get_tree().get_nodes_in_group("fighter"):
		var f := n as PNFighter
		if f == null or f == self or not f.alive:
			continue
		if team != 0 and f.team == team:
			continue
		var d := f.global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = f
	return best

func _has_los(f: PNFighter) -> bool:
	var from := global_position + Vector3(0, 1.4, 0)
	var to := f.global_position + Vector3(0, 1.2, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _path_dir() -> Vector3:
	if nav.is_navigation_finished():
		return Vector3.ZERO
	var nxt := nav.get_next_path_position()
	var d := nxt - global_position
	d.y = 0.0
	if d.length() < 0.05 and target:
		# no usable nav mesh yet: head straight for the target
		d = target.global_position - global_position
		d.y = 0.0
	return d

func _face(dir: Vector3, delta: float, rate: float) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.01:
		return
	var want := atan2(-flat.x, -flat.z)
	rotation.y = lerp_angle(rotation.y, want, clampf(rate * delta, 0.0, 1.0))

func _try_shoot(delta: float, dist: float) -> void:
	if weapon == null:
		return
	_reaction -= delta
	if _reaction > 0.0:
		return
	_burst_gap -= delta
	if _burst <= 0:
		if _burst_gap <= 0.0:
			_burst = int(randf_range(3.0, 8.0))
			_burst_gap = randf_range(0.5, 1.4) * lerpf(1.4, 0.7, difficulty)
		return
	if weapon.can_fire():
		var origin := global_position + Vector3(0, 1.45, 0) - global_transform.basis.z * 0.4
		var aim_at := target.global_position + Vector3(0, 1.2, 0)
		# inaccuracy shrinks with difficulty and grows with distance
		var err := lerpf(2.4, 0.5, difficulty) + dist * 0.025
		var dir := (aim_at - origin).normalized()
		if weapon.fire(origin, dir, err / maxf(float(weapon.def["spread"]), 0.5)):
			_burst -= 1
			_play("attack")
			get_tree().create_timer(0.3).timeout.connect(func(): _cur_anim = "")
			if _burst <= 0:
				_reaction = randf_range(0.05, 0.3)
	elif weapon.reserve > 0 and weapon.mag <= 0:
		weapon.reload()
	else:
		weapon.add_ammo(0)

func take_damage(amount: float, attacker: Node = null, hit_pos := Vector3.ZERO, headshot := false) -> bool:
	if _spawn_protect > 0.0:
		return false
	var killed := super.take_damage(amount, attacker, hit_pos, headshot)
	if alive:
		if attacker is PNFighter and (attacker as PNFighter).team != team:
			target = attacker as PNFighter   # shoot back at whoever shot us
		_play("hit")
		get_tree().create_timer(0.35).timeout.connect(func(): _cur_anim = "")
	return killed

func _die(attacker: Node) -> void:
	super._die(attacker)
	_cur_anim = ""
	_play("die")
	collision_layer = 0
	get_tree().create_timer(2.6).timeout.connect(func(): wants_respawn.emit(self))

func respawn_at(pos: Vector3) -> void:
	super.respawn_at(pos)
	collision_layer = 4
	_cur_anim = ""
	_play("idle-loop")
	_spawn_protect = 1.5
	target = null
	if weapon:
		weapon.mag = int(weapon.def["mag"])
		weapon.reserve = int(weapon.def["reserve"])
