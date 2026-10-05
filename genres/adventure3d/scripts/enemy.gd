class_name Enemy
extends CharacterBody3D
## Simple enemy AI base: idle (wander) -> chase -> telegraphed attack -> recover,
## stagger on hit with knockback, hit flash, death with a burst and a heart drop.
## Extend it (new `attack()` patterns, ranged, shield) — the state machine, damage
## and feedback are done. Group "targetable" so the player can lock on.

signal died(enemy: Enemy)

@export var max_health := 3.0
@export var speed := 3.4
@export var sight := 13.0
@export var attack_range := 1.9
@export var attack_damage := 0.5
@export var windup := 0.55
@export var recover := 0.8
@export var color := Color(0.75, 0.3, 0.45)

var health := 3.0
var state := "idle"          # idle | chase | windup | recover | stagger | dead
var player: Node3D
var _t := 0.0
var _home := Vector3.ZERO
var _wander_dir := Vector3.ZERO
var _knock := Vector3.ZERO
var _body: MeshInstance3D
var _mat: ShaderMaterial
var _flash_mat: ShaderMaterial
var _bob := 0.0
var _hit_flash := 0.0

func _ready() -> void:
	add_to_group("targetable")
	add_to_group("enemy")
	collision_layer = 4
	collision_mask = 1
	health = max_health
	_home = global_position
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.55
	cap.height = 1.3
	cs.shape = cap
	cs.position.y = 0.65
	add_child(cs)
	var sm := SphereMesh.new()
	sm.radius = 0.62
	sm.height = 1.2
	sm.radial_segments = 14
	sm.rings = 7
	_mat = PNLook.toon(color)
	_body = MeshInstance3D.new()
	_body.mesh = sm
	_body.material_override = _mat
	_body.position.y = 0.65
	add_child(_body)
	var eb := PNBatch.new()
	for sx in [-1.0, 1.0]:
		var eye := SphereMesh.new()
		eye.radius = 0.12
		eye.height = 0.24
		eye.radial_segments = 8
		eye.rings = 4
		eb.add_mesh(eye, Transform3D(Basis.IDENTITY, Vector3(sx * 0.22, 0.15, 0.5)), Color.WHITE)
		var pupil := SphereMesh.new()
		pupil.radius = 0.06
		pupil.height = 0.12
		pupil.radial_segments = 6
		pupil.rings = 3
		eb.add_mesh(pupil, Transform3D(Basis.IDENTITY, Vector3(sx * 0.22, 0.15, 0.6)), Color(0.1, 0.05, 0.1))
		var horn := CylinderMesh.new()
		horn.top_radius = 0.0
		horn.bottom_radius = 0.1
		horn.height = 0.35
		horn.radial_segments = 6
		eb.add_mesh(horn, Transform3D(Basis(Vector3(0, 0, 1), -sx * 0.3), Vector3(sx * 0.3, 0.62, 0.0)), Color(0.95, 0.9, 0.75))
	var face := eb.commit(PNLook.toon(Color.WHITE))
	(face.material_override as ShaderMaterial).set_shader_parameter("use_vertex_color", true)
	_body.add_child(face)
	_flash_mat = ShaderMaterial.new()
	_flash_mat.shader = PNLook.shader("dissolve")
	_body.material_overlay = _flash_mat
	Juice.blob_shadow(self, 0.7)
	await get_tree().process_frame
	var ps := get_tree().get_nodes_in_group("player")
	if not ps.is_empty():
		player = ps[0]

func is_dead() -> bool:
	return state == "dead"

func _physics_process(delta: float) -> void:
	if state == "dead":
		return
	_t += delta
	_bob += delta
	if not is_on_floor():
		velocity.y -= 30.0 * delta
	_hit_flash = maxf(0.0, _hit_flash - delta * 5.0)
	_flash_mat.set_shader_parameter("flash", _hit_flash)
	_body.position.y = 0.65 + sin(_bob * 5.0) * 0.06
	var dist := INF
	if player and is_instance_valid(player):
		dist = global_position.distance_to(player.global_position)
	match state:
		"idle":
			if _t > 2.0:
				_t = 0.0
				_wander_dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() if randf() > 0.4 else Vector3.ZERO
				if (global_position - _home).length() > 6.0:
					_wander_dir = (_home - global_position).normalized()
			velocity.x = _wander_dir.x * speed * 0.35
			velocity.z = _wander_dir.z * speed * 0.35
			if dist < sight:
				state = "chase"
		"chase":
			if dist > sight * 1.6:
				state = "idle"
			else:
				var to: Vector3 = (player.global_position - global_position)
				to.y = 0.0
				var dir := to.normalized()
				velocity.x = dir.x * speed
				velocity.z = dir.z * speed
				rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-8.0 * delta))
				if dist < attack_range:
					state = "windup"
					_t = 0.0
		"windup":
			velocity.x = 0.0
			velocity.z = 0.0
			# telegraph: swell + flash so the player can read it and dodge
			_body.scale = Vector3.ONE * (1.0 + 0.18 * sin(_t / windup * PI))
			_flash_mat.set_shader_parameter("flash", 0.35 + 0.25 * sin(_t * 40.0))
			if _t >= windup:
				_attack()
				state = "recover"
				_t = 0.0
				_body.scale = Vector3.ONE
		"recover":
			velocity.x = 0.0
			velocity.z = 0.0
			if _t >= recover:
				state = "chase"
		"stagger":
			velocity.x = _knock.x
			velocity.z = _knock.z
			_knock = _knock.move_toward(Vector3.ZERO, 26.0 * delta)
			if _t >= 0.35:
				state = "chase"
	move_and_slide()

## The attack itself — override for other patterns (lunge, projectile, spin).
func _attack() -> void:
	if player == null or not is_instance_valid(player):
		return
	var to := player.global_position - global_position
	if to.length() < attack_range + 0.6 and player.has_method("take_damage"):
		player.call("take_damage", attack_damage, global_position)
	Juice.dust(global_position + Vector3(0, 0.2, 0), 6)

func take_hit(amount: float, from: Vector3) -> void:
	if state == "dead":
		return
	health -= amount
	_hit_flash = 1.0
	state = "stagger"
	_t = 0.0
	_body.scale = Vector3.ONE
	_knock = (global_position - from).normalized() * 7.0
	_knock.y = 0.0
	Juice.popup(global_position + Vector3(0, 1.8, 0), str(int(amount * 10)), Color(1, 0.9, 0.4))
	if health <= 0.0:
		_die()

func _die() -> void:
	state = "dead"
	remove_from_group("targetable")
	Juice.sparkle(global_position + Vector3(0, 0.8, 0), color.lightened(0.3), 24)
	PNAudio.sfx("defeat", 1.0, -2.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_body, "scale", Vector3.ZERO, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_flash_mat.set_shader_parameter("amount", 0.0)
	died.emit(self)
	await get_tree().create_timer(0.4).timeout
	queue_free()
