class_name PNProjectile
extends Node3D
## Playpen kit: an explosive projectile (rockets). Moves in swept steps (no tunneling), explodes on contact with
## radius damage that falls off with distance, a fireball + sparks + camera shake, and sound.

var velocity := Vector3.ZERO
var damage := 80.0
var blast := 4.0
var owner_fighter: PNFighter
var _life := 5.0
var _done := false

func launch(origin: Vector3, dir: Vector3, speed: float, dmg: float, blast_radius: float, who: PNFighter, color: Color) -> void:
	global_position = origin
	velocity = dir.normalized() * speed
	damage = dmg
	blast = blast_radius
	owner_fighter = who
	look_at(origin + dir, Vector3.UP)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.16, 0.16, 0.55)
	body.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.2
	body.material_override = m
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.6
	light.omni_range = 5.0
	add_child(light)

func _physics_process(delta: float) -> void:
	if _done:
		return
	_life -= delta
	var from := global_position
	var to := from + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, 0b111)
	if owner_fighter:
		q.exclude = [owner_fighter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.size() > 0:
		_explode(hit["position"])
		return
	global_position = to
	if _life <= 0.0:
		_explode(global_position)

func _explode(pos: Vector3) -> void:
	_done = true
	for node in get_tree().get_nodes_in_group("fighter"):
		var f := node as PNFighter
		if f == null or not f.alive:
			continue
		var d := f.global_position.distance_to(pos)
		if f.model_height > 0.0:
			d = minf(d, (f.global_position + Vector3(0, f.model_height * 0.5, 0)).distance_to(pos))
		if d > blast:
			continue
		var falloff := 1.0 - d / blast
		var is_enemy := owner_fighter == null or f.team != owner_fighter.team or f.team == 0
		if f == owner_fighter:
			f.take_damage(damage * 0.45 * falloff, owner_fighter, pos, false)
		elif is_enemy:
			var killed := f.take_damage(damage * falloff, owner_fighter, pos, false)
			if owner_fighter and owner_fighter.has_signal("hit_marker"):
				owner_fighter.emit_signal("hit_marker", killed, false)
	Juice.shake(clampf(0.35 - pos.distance_to(global_position) * 0.01, 0.1, 0.35), 0.35)
	Juice.sparkle(pos, Color(1.0, 0.7, 0.25), 24)
	Juice.dust(pos, 14, Color(0.4, 0.36, 0.32, 0.8), 0.3)
	PNAudio.sfx_3d("explosion", pos, randf_range(0.9, 1.05), 1.0)
	var root: Node = PNViewport.world_root()
	if root:
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 14
		sm.rings = 8
		ball.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.7, 0.25, 0.9)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ball.material_override = mat
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ball)
		ball.global_position = pos
		ball.scale = Vector3.ONE * 0.4
		var tw := ball.create_tween()
		tw.set_parallel(true)
		tw.tween_property(ball, "scale", Vector3.ONE * blast * 1.5, 0.28).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.32)
		tw.chain().tween_callback(ball.queue_free)
	queue_free()
