extends Node
## Playpen kit: the JUICE SET (autoload "Juice").
## Landing/footstep dust, collect sparkle, squash & stretch, hit-stop, screen
## shake, number pop-ups, tweened UI. Every effect is cheap, self-cleaning, and
## scales with PNSettings quality. Call these instead of writing your own.

var _hitstop_token := 0
var _blob_tex: GradientTexture2D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## Freeze the game for a heartbeat on an impact. Safe to call repeatedly.
func hit_stop(seconds := 0.06, strength := 0.04) -> void:
	_hitstop_token += 1
	var token := _hitstop_token
	Engine.time_scale = strength
	# real-time timer: process_always, ignore_time_scale
	await get_tree().create_timer(seconds, true, false, true).timeout
	if token == _hitstop_token:
		Engine.time_scale = 1.0

## Light screen shake on the active camera (positional offset, no rotation).
func shake(amount := 0.12, seconds := 0.18) -> void:
	var cam := PNViewport.active_camera()
	if cam == null:
		cam = get_viewport().get_camera_3d()
	if cam == null:
		return
	var tw := create_tween()
	var steps := 8
	for i in steps:
		var k := 1.0 - float(i) / float(steps)
		var off := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * amount * k
		tw.tween_property(cam, "h_offset", off.x, seconds / steps)
		tw.parallel().tween_property(cam, "v_offset", off.y, seconds / steps)
	tw.tween_property(cam, "h_offset", 0.0, 0.04)
	tw.parallel().tween_property(cam, "v_offset", 0.0, 0.04)

## Squash and stretch a visual node (NOT the physics body) — tween back to rest.
func squash(node: Node3D, sx := 1.25, sy := 0.7, seconds := 0.22) -> void:
	if node == null:
		return
	var rest := Vector3.ONE
	node.scale = Vector3(sx, sy, sx)
	var tw := node.create_tween()
	tw.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", rest, seconds * 2.0)

func stretch(node: Node3D, sy := 1.3, seconds := 0.2) -> void:
	if node == null:
		return
	node.scale = Vector3(1.0 / sqrt(sy), sy, 1.0 / sqrt(sy))
	var tw := node.create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", Vector3.ONE, seconds)

## A puff of dust at a world position (landing, footsteps, skids).
func dust(world_pos: Vector3, amount := 8, color := Color(0.85, 0.8, 0.7, 0.8), size := 0.18) -> void:
	amount = maxi(1, int(round(amount * PNSettings.scale())))
	var p := _burst(world_pos, amount, 0.5, color, size)
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, -1.0, 0)
	p.scale_amount_curve = _shrink_curve()

## Sparkle burst for pickups (pair with PNAudio.pickup()).
func sparkle(world_pos: Vector3, color := Color(1.0, 0.9, 0.4), amount := 14) -> void:
	amount = maxi(2, int(round(amount * PNSettings.scale())))
	var p := _burst(world_pos, amount, 0.6, color, 0.12)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, -3.0, 0)
	p.scale_amount_curve = _shrink_curve()

## Floating number / text that rises and fades (score, damage, "+1").
func popup(world_pos: Vector3, text: String, color := Color(1, 0.95, 0.5), size := 0.6) -> void:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.pixel_size = 0.006 * size / 0.6
	l.font_size = 64
	l.outline_size = 14
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	_root().add_child(l)
	l.global_position = world_pos
	l.scale = Vector3.ONE * 0.2
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "global_position:y", world_pos.y + 1.1, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.55)
	tw.chain().tween_callback(l.queue_free)

## Menus and HUD pieces ease in instead of snapping on.
func pop_in(control: Control, seconds := 0.25, delay := 0.0) -> void:
	if control == null:
		return
	control.pivot_offset = control.size * 0.5
	control.modulate.a = 0.0
	control.scale = Vector2(0.92, 0.92)
	var tw := control.create_tween().set_parallel(true)
	tw.tween_property(control, "modulate:a", 1.0, seconds).set_delay(delay)
	tw.tween_property(control, "scale", Vector2.ONE, seconds).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func fade_out(control: Control, seconds := 0.18) -> void:
	if control == null:
		return
	var tw := control.create_tween()
	tw.tween_property(control, "modulate:a", 0.0, seconds)
	tw.tween_callback(func(): control.visible = false)

## Soft blob shadow under a character/prop (a fake shadow that never costs a shadow map).
func blob_shadow(parent: Node3D, radius := 0.6, strength := 0.55) -> MeshInstance3D:
	if _blob_tex == null:
		_blob_tex = GradientTexture2D.new()
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 1))
		g.set_color(1, Color(0, 0, 0, 0))
		_blob_tex.gradient = g
		_blob_tex.fill = GradientTexture2D.FILL_RADIAL
		_blob_tex.fill_from = Vector2(0.5, 0.5)
		_blob_tex.fill_to = Vector2(1.0, 0.5)
		_blob_tex.width = 128
		_blob_tex.height = 128
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	quad.orientation = PlaneMesh.FACE_Y
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _blob_tex
	mat.albedo_color = Color(0, 0, 0, strength)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_script(preload("res://playpen/pn_blob_shadow.gd"))
	parent.add_child(mi)
	return mi

func _root() -> Node:
	var w := PNViewport.world_root()
	if w:
		return w
	var cs := get_tree().current_scene
	return cs if cs else get_tree().root

func _burst(world_pos: Vector3, amount: int, lifetime: float, color: Color, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = lifetime
	var m := QuadMesh.new()
	m.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material = mat
	p.mesh = m
	_root().add_child(p)
	p.global_position = world_pos
	p.emitting = true
	get_tree().create_timer(lifetime + 0.3).timeout.connect(p.queue_free)
	return p

func _shrink_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, 1))
	c.add_point(Vector2(1, 0))
	return c
