class_name AdventurePlayer
extends CharacterBody3D
## Third-person ADVENTURE hero (Ocarina-style).
##   • LOCK-ON (hold `target`): faces and strafes around the nearest enemy; the
##     camera frames it. Release to go back to free movement.
##   • SWORD: 3-hit combo (`attack`), a real hit window with an arc hitbox,
##     hit-stop and screen shake on connect.
##   • SHIELD (hold `guard`): blocks hits from the front, slows you down.
##   • ROLL / DODGE (`dodge`): fast roll with invincibility frames.
##   • INTERACT: when something in group "interactable" is in reach the `jump`
##     button (A) interacts and a prompt shows; otherwise A jumps.
##   • HEARTS: damage with brief invincibility + knockback; respawn on death.

signal health_changed(hearts: float, max_hearts: int)
signal died
signal prompt_changed(action: String, text: String)

@export_group("Move")
@export var walk_speed := 5.2
@export var run_speed := 8.6
@export var accel := 46.0
@export var turn_speed := 13.0
@export var gravity := 30.0
@export var jump_velocity := 8.6
@export_group("Combat")
@export var max_hearts := 3
@export var sword_damage := 1.0
@export var roll_speed := 13.0
@export var roll_time := 0.42
@export var lock_range := 18.0
@export_group("Look")
@export var body_color := Color(0.35, 0.65, 0.95)
@export var tunic_stripes := false

var hearts := 3.0
var camera: PNFollowCamera
var rig: PNCritterRig
var lock_target: Node3D = null
var guarding := false
var respawn_point := Vector3.ZERO
var state := "move"          # move | roll | attack | hurt | dead
var surface := "grass"

var _visual: Node3D
var _sword_pivot: Node3D
var _shield: Node3D
var _hitbox: Area3D
var _state_t := 0.0
var _combo := 0
var _combo_window := 0.0
var _hit_this_swing := {}
var _iframes := 0.0
var _roll_dir := Vector3.ZERO
var _knock := Vector3.ZERO
var _step_timer := 0.0
var _near_interactable: Node3D = null

func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.5
	hearts = float(max_hearts)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 1.5
	cs.shape = cap
	cs.position.y = 0.75
	add_child(cs)
	_visual = Node3D.new()
	add_child(_visual)
	rig = PNCritterRig.new()
	rig.body_color = body_color
	rig.belly_color = body_color.lightened(0.5)
	rig.ear_style = "pointy"
	rig.stripes = tunic_stripes
	_visual.add_child(rig)
	_build_gear()
	Juice.blob_shadow(self, 0.75)
	respawn_point = global_position + Vector3(0, 0.3, 0)
	health_changed.emit(hearts, max_hearts)

func _build_gear() -> void:
	_sword_pivot = Node3D.new()
	_sword_pivot.position = Vector3(0.55, 0.85, 0.15)
	_visual.add_child(_sword_pivot)
	var blade := BoxMesh.new()
	blade.size = Vector3(0.09, 0.9, 0.04)
	var bi := MeshInstance3D.new()
	bi.mesh = blade
	bi.material_override = PNLook.toon(Color(0.88, 0.92, 0.98), Color(0.6, 0.75, 1.0), 0.4)
	bi.position = Vector3(0, 0.55, 0)
	_sword_pivot.add_child(bi)
	var guard := BoxMesh.new()
	guard.size = Vector3(0.34, 0.07, 0.07)
	var gi := MeshInstance3D.new()
	gi.mesh = guard
	gi.material_override = PNLook.toon(PNLook.color("primary", Color(0.95, 0.8, 0.3)))
	gi.position = Vector3(0, 0.08, 0)
	_sword_pivot.add_child(gi)
	_sword_pivot.rotation = Vector3(0, 0, deg_to_rad(-18))
	_shield = Node3D.new()
	_shield.position = Vector3(-0.58, 0.85, 0.12)
	_visual.add_child(_shield)
	var disc := CylinderMesh.new()
	disc.top_radius = 0.34
	disc.bottom_radius = 0.34
	disc.height = 0.07
	disc.radial_segments = 14
	var di := MeshInstance3D.new()
	di.mesh = disc
	di.material_override = PNLook.toon(PNLook.color("accent", Color(0.85, 0.3, 0.35)))
	di.rotation = Vector3(deg_to_rad(90), 0, 0)
	_shield.add_child(di)
	_shield.rotation = Vector3(0, deg_to_rad(80), 0)
	# sword hitbox: a short box in front, only enabled during a swing's active frames
	_hitbox = Area3D.new()
	_hitbox.collision_layer = 0
	_hitbox.collision_mask = 4
	_hitbox.monitoring = false
	var hs := CollisionShape3D.new()
	var hb := BoxShape3D.new()
	hb.size = Vector3(1.9, 1.4, 1.7)
	hs.shape = hb
	hs.position = Vector3(0, 0.9, 1.1)
	_hitbox.add_child(hs)
	_visual.add_child(_hitbox)
	_hitbox.body_entered.connect(_on_sword_hit)

func _physics_process(delta: float) -> void:
	if state == "dead":
		return
	_iframes = maxf(0.0, _iframes - delta)
	_state_t += delta
	_combo_window = maxf(0.0, _combo_window - delta)
	_update_lock()
	_update_interactable()
	var on_floor := is_on_floor()
	if not on_floor:
		velocity.y -= gravity * delta
	var input := Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_forward", "move_back"))
	if input.length() > 1.0:
		input = input.normalized()
	var yaw := camera.get_yaw() if camera else 0.0
	var wish := Basis(Vector3.UP, yaw) * Vector3(input.x, 0, input.y)
	guarding = Input.is_action_pressed("guard") and state == "move" and on_floor
	_shield.rotation.y = lerp_angle(_shield.rotation.y, deg_to_rad(0 if guarding else 80), 1.0 - exp(-14.0 * delta))
	_shield.position.z = lerpf(_shield.position.z, 0.45 if guarding else 0.12, 1.0 - exp(-14.0 * delta))
	_shield.position.x = lerpf(_shield.position.x, -0.15 if guarding else -0.58, 1.0 - exp(-14.0 * delta))

	match state:
		"move":
			var top := (walk_speed if guarding else (walk_speed + (run_speed - walk_speed) * clampf(input.length() * 1.2, 0.0, 1.0)))
			var target_h := wish * top
			var h := Vector3(velocity.x, 0, velocity.z).move_toward(target_h, accel * delta)
			velocity.x = h.x
			velocity.z = h.z
			_face(delta, wish)
			if Input.is_action_just_pressed("dodge"):
				_start_roll(wish)
			elif Input.is_action_just_pressed("attack") and not guarding:
				_start_attack()
			elif Input.is_action_just_pressed("jump"):
				if _near_interactable and _near_interactable.has_method("interact"):
					_near_interactable.call("interact", self)
				elif on_floor:
					velocity.y = jump_velocity
					Juice.dust(global_position, 4)
					rig.jump_stretch()
		"roll":
			velocity.x = _roll_dir.x * roll_speed * (1.0 - _state_t / roll_time * 0.4)
			velocity.z = _roll_dir.z * roll_speed * (1.0 - _state_t / roll_time * 0.4)
			rig.rotation.x = TAU * clampf(_state_t / roll_time, 0.0, 1.0)
			if int(_state_t * 30.0) % 3 == 0:
				Juice.dust(global_position + Vector3(0, 0.1, 0), 1, Color(0.85, 0.8, 0.7, 0.5), 0.14)
			if _state_t >= roll_time:
				rig.rotation.x = 0.0
				state = "move"
		"attack":
			var h2 := Vector3(velocity.x, 0, velocity.z).move_toward(Vector3.ZERO, accel * 0.8 * delta)
			velocity.x = h2.x
			velocity.z = h2.z
			_swing_animation()
			if _state_t >= 0.36:
				state = "move"
				_hitbox.monitoring = false
				_sword_pivot.rotation = Vector3(0, 0, deg_to_rad(-18))
		"hurt":
			velocity.x = _knock.x
			velocity.z = _knock.z
			_knock = _knock.move_toward(Vector3.ZERO, 30.0 * delta)
			if _state_t >= 0.3:
				state = "move"
	move_and_slide()
	rig.update_motion(delta, Vector3(velocity.x, 0, velocity.z).length(), is_on_floor(), velocity.y)
	if is_on_floor() and Vector3(velocity.x, 0, velocity.z).length() > 1.5 and state == "move":
		_step_timer -= delta * (Vector3(velocity.x, 0, velocity.z).length() / run_speed)
		if _step_timer <= 0.0:
			_step_timer = 0.36
			PNAudio.footstep(surface, global_position)
	if global_position.y < -40.0:
		_die_and_respawn()

func _face(delta: float, wish: Vector3) -> void:
	if lock_target and is_instance_valid(lock_target):
		var to := lock_target.global_position - global_position
		_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(to.x, to.z), 1.0 - exp(-turn_speed * delta))
	elif wish.length() > 0.1:
		_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(wish.x, wish.z), 1.0 - exp(-turn_speed * delta))

# ---------------------------------------------------------------- lock-on
func _update_lock() -> void:
	if Input.is_action_pressed("target"):
		if lock_target == null or not is_instance_valid(lock_target) or global_position.distance_to(lock_target.global_position) > lock_range * 1.3:
			lock_target = _pick_target()
		if camera:
			camera.locked_on = lock_target
	else:
		lock_target = null
		if camera:
			camera.locked_on = null

func _pick_target() -> Node3D:
	var best: Node3D = null
	var best_score := 1e9
	var fwd := Vector3(sin(camera.get_yaw() + PI) if camera else 0.0, 0, cos(camera.get_yaw() + PI) if camera else 1.0)
	for n in get_tree().get_nodes_in_group("targetable"):
		if not (n is Node3D) or (n.has_method("is_dead") and n.call("is_dead")):
			continue
		var to: Vector3 = (n as Node3D).global_position - global_position
		var d := to.length()
		if d > lock_range:
			continue
		var ang := acos(clampf(fwd.dot(to.normalized()), -1.0, 1.0))
		var score := d + ang * 6.0
		if score < best_score:
			best_score = score
			best = n
	return best

# ---------------------------------------------------------------- combat
func _start_attack() -> void:
	_combo = (_combo + 1) if _combo_window > 0.0 and _combo < 3 else 1
	_combo_window = 0.55
	state = "attack"
	_state_t = 0.0
	_hit_this_swing.clear()
	if lock_target and is_instance_valid(lock_target):
		var to := lock_target.global_position - global_position
		_visual.rotation.y = atan2(to.x, to.z)
	var dir := Vector3(sin(_visual.rotation.y), 0, cos(_visual.rotation.y))
	velocity.x = dir.x * 3.5
	velocity.z = dir.z * 3.5
	PNAudio.sfx("swing", 0.9 + _combo * 0.1, -4.0)

func _swing_animation() -> void:
	var t := _state_t / 0.36
	var start := -120.0 if _combo % 2 == 1 else 120.0
	var angle := lerpf(start, -start, clampf(t * 1.5, 0.0, 1.0))
	_sword_pivot.rotation = Vector3(deg_to_rad(80), 0, deg_to_rad(angle))
	# active frames
	_hitbox.monitoring = t > 0.18 and t < 0.65

func _on_sword_hit(body: Node3D) -> void:
	if _hit_this_swing.has(body) or not body.has_method("take_hit"):
		return
	_hit_this_swing[body] = true
	var dmg := sword_damage * (1.5 if _combo >= 3 else 1.0)
	body.call("take_hit", dmg, global_position)
	Juice.hit_stop(0.06 if _combo < 3 else 0.1)
	Juice.shake(0.09 if _combo < 3 else 0.18, 0.15)
	PNAudio.sfx("hit", randf_range(0.9, 1.1), -2.0)

func _start_roll(wish: Vector3) -> void:
	state = "roll"
	_state_t = 0.0
	_iframes = roll_time + 0.05
	_roll_dir = wish.normalized() if wish.length() > 0.1 else Vector3(sin(_visual.rotation.y), 0, cos(_visual.rotation.y))
	_visual.rotation.y = atan2(_roll_dir.x, _roll_dir.z)
	PNAudio.sfx("roll", 1.0, -6.0)

## Called by enemies. `from` is where the hit came from (for blocking + knockback).
func take_damage(amount: float, from: Vector3) -> bool:
	if state == "dead" or _iframes > 0.0:
		return false
	var to_attacker := (from - global_position).normalized()
	var facing := Vector3(sin(_visual.rotation.y), 0, cos(_visual.rotation.y))
	if guarding and facing.dot(Vector3(to_attacker.x, 0, to_attacker.z).normalized()) > 0.3:
		Juice.sparkle(global_position + Vector3(0, 1, 0) + facing * 0.6, Color(0.8, 0.9, 1.0), 8)
		PNAudio.sfx("block", 1.0, -3.0)
		_knock = -to_attacker * 3.0
		_knock.y = 0.0
		return false
	hearts = maxf(0.0, hearts - amount)
	health_changed.emit(hearts, max_hearts)
	_iframes = 1.0
	state = "hurt"
	_state_t = 0.0
	_knock = -to_attacker * 8.0
	_knock.y = 0.0
	velocity.y = 4.0
	Juice.hit_stop(0.08)
	Juice.shake(0.2, 0.22)
	PNAudio.sfx("hurt", 1.0, -2.0)
	if hearts <= 0.0:
		_die_and_respawn()
	return true

func heal(amount: float) -> void:
	hearts = minf(float(max_hearts), hearts + amount)
	health_changed.emit(hearts, max_hearts)

func _die_and_respawn() -> void:
	state = "dead"
	died.emit()
	await get_tree().create_timer(1.1).timeout
	velocity = Vector3.ZERO
	global_position = respawn_point
	hearts = float(max_hearts)
	health_changed.emit(hearts, max_hearts)
	state = "move"
	_iframes = 1.5

# ---------------------------------------------------------------- interact
func _update_interactable() -> void:
	var best: Node3D = null
	var best_d := 2.6
	for n in get_tree().get_nodes_in_group("interactable"):
		if n is Node3D:
			var d := global_position.distance_to((n as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = n
	if best != _near_interactable:
		_near_interactable = best
		prompt_changed.emit("jump", str(best.get("prompt_text")) if best else "")
