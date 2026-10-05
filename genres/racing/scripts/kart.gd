class_name Kart
extends Node3D
## Arcade KART (sphere-physics) — feels good before you touch a number.
##   • sphere RigidBody does the rolling/slopes/collisions; this node is the visual
##     and the "driver" that steers its velocity (crisp acceleration, strong grip)
##   • STEER scales with speed (no spinning on the spot), reverses when backing up
##   • DRIFT (hold `drift` while steering above ~14 m/s): the kart slides, charges a
##     mini-turbo (blue -> orange -> pink), and RELEASE gives a BOOST with a FOV kick
##   • BOOST pads / pickups call `boost(seconds)`
##   • off-road slows you down and kicks up dust; falling off respawns at the last
##     checkpoint
## Player: set `is_ai = false` (reads input). AI: set `is_ai = true` and drive
## `throttle_in / steer_in / drift_in` from AIDriver.

signal boosted(seconds: float)
signal respawned

@export_group("Speed")
@export var max_speed := 40.0
@export var boost_speed := 58.0
@export var accel := 34.0
@export var brake_force := 70.0
@export var coast_drag := 9.0
@export var reverse_speed := 12.0
@export_group("Handling")
@export var turn_rate := 1.7
@export var grip := 7.5
@export var drift_grip := 1.6
@export var drift_turn_bonus := 1.3
@export_group("Look")
@export var body_color := Color(0.95, 0.3, 0.3)
@export var driver_color := Color(1.0, 0.62, 0.2)
@export var is_ai := false

var sphere: RigidBody3D
var speed := 0.0                  # signed, along the kart's forward
var throttle_in := 0.0
var brake_in := 0.0
var steer_in := 0.0
var drift_in := false
var track: RaceTrack              # set by the level: enables the off-road slowdown
var yaw := 0.0
var drifting := false
var drift_charge := 0.0
var drift_dir := 0.0
var boost_time := 0.0
var off_road := false
var respawn_pos := Vector3.ZERO
var respawn_yaw := 0.0
var locked := false               # true during the countdown
var _body: Node3D
var _wheels: Array[Node3D] = []
var _up := Vector3.UP
var _grounded := false
var _dust_t := 0.0
var _driver_head: Node3D

static func ensure_input() -> void:
	var defs := {
		"race_throttle": {"keys": [KEY_W, KEY_UP], "axes": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]], "buttons": [JOY_BUTTON_A]},
		"race_brake": {"keys": [KEY_S, KEY_DOWN], "axes": [[JOY_AXIS_TRIGGER_LEFT, 1.0]], "buttons": [JOY_BUTTON_B]},
		"race_left": {"keys": [KEY_A, KEY_LEFT], "axes": [[JOY_AXIS_LEFT_X, -1.0]], "buttons": [JOY_BUTTON_DPAD_LEFT]},
		"race_right": {"keys": [KEY_D, KEY_RIGHT], "axes": [[JOY_AXIS_LEFT_X, 1.0]], "buttons": [JOY_BUTTON_DPAD_RIGHT]},
		"race_drift": {"keys": [KEY_SHIFT, KEY_SPACE], "buttons": [JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_X]},
	}
	for a in defs:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.2)
		var d: Dictionary = defs[a]
		for k in d.get("keys", []):
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(a, e)
		for b in d.get("buttons", []):
			var e2 := InputEventJoypadButton.new()
			e2.button_index = b
			InputMap.action_add_event(a, e2)
		for ax in d.get("axes", []):
			var e3 := InputEventJoypadMotion.new()
			e3.axis = ax[0]
			e3.axis_value = ax[1]
			InputMap.action_add_event(a, e3)

func _ready() -> void:
	if not is_ai:
		add_to_group("player")
		ensure_input()
	else:
		add_to_group("kart_ai")
	_build_visual()
	call_deferred("_spawn_sphere")

func _spawn_sphere() -> void:
	sphere = RigidBody3D.new()
	sphere.collision_layer = 2
	sphere.collision_mask = 1
	sphere.mass = 4.0
	sphere.gravity_scale = 2.4
	sphere.linear_damp = 0.05
	sphere.angular_damp = 0.4
	sphere.continuous_cd = true
	sphere.contact_monitor = false
	var pm := PhysicsMaterial.new()
	pm.friction = 0.0       # we set the ground velocity ourselves; friction would just eat it
	pm.bounce = 0.05
	sphere.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = 0.65
	cs.shape = ss
	sphere.add_child(cs)
	sphere.set_meta("kart", self)
	get_parent().add_child(sphere)
	sphere.global_position = global_position + Vector3(0, 0.8, 0)
	yaw = rotation.y
	respawn_pos = global_position
	respawn_yaw = yaw

func _build_visual() -> void:
	_body = Node3D.new()
	add_child(_body)
	var bb := PNBatch.new()
	var chassis := BoxMesh.new()
	chassis.size = Vector3(1.5, 0.45, 2.5)
	bb.add_box(Vector3(0, 0.55, 0), chassis.size, body_color)
	bb.add_box(Vector3(0, 0.9, -0.95), Vector3(1.3, 0.32, 0.7), body_color.darkened(0.15))        # rear cowl
	bb.add_box(Vector3(0, 0.62, 1.2), Vector3(1.0, 0.3, 0.5), body_color.lightened(0.15))         # nose
	bb.add_box(Vector3(0, 1.15, -1.25), Vector3(1.6, 0.1, 0.5), Color(0.15, 0.15, 0.2))            # spoiler
	bb.add_box(Vector3(-0.7, 1.0, -1.25), Vector3(0.08, 0.4, 0.2), Color(0.15, 0.15, 0.2))
	bb.add_box(Vector3(0.7, 1.0, -1.25), Vector3(0.08, 0.4, 0.2), Color(0.15, 0.15, 0.2))
	bb.add_box(Vector3(0, 0.82, 0.1), Vector3(0.55, 0.06, 0.9), Color.WHITE)                        # racing stripe
	var mat := PNLook.toon(Color.WHITE)
	mat.set_shader_parameter("use_vertex_color", true)
	var mi := bb.commit(PNLook.with_outline(mat))
	_body.add_child(mi)
	var head := PNCritterRig.new()
	head.body_color = driver_color
	head.belly_color = driver_color.lightened(0.5)
	head.scale_factor = 0.62
	head.position = Vector3(0, 0.45, -0.1)
	_body.add_child(head)
	_driver_head = head
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.38
	wheel.bottom_radius = 0.38
	wheel.height = 0.3
	wheel.radial_segments = 12
	wheel.rings = 1
	var wmat := PNLook.toon(Color(0.12, 0.12, 0.14))
	for p in [Vector3(-0.82, 0.38, 0.85), Vector3(0.82, 0.38, 0.85), Vector3(-0.82, 0.38, -0.85), Vector3(0.82, 0.38, -0.85)]:
		var w := Node3D.new()
		w.position = p
		_body.add_child(w)
		var wm := MeshInstance3D.new()
		wm.mesh = wheel
		wm.material_override = wmat
		wm.rotation.z = PI * 0.5
		w.add_child(wm)
		_wheels.append(w)
	Juice.blob_shadow(self, 1.3, 0.5)

func boost(seconds: float) -> void:
	boost_time = maxf(boost_time, seconds)
	boosted.emit(seconds)
	if not is_ai:
		Juice.shake(0.08, 0.3)
		PNAudio.sfx("boost", 1.0, -3.0)

func place_at(pos: Vector3, yaw_angle: float) -> void:
	global_position = pos
	yaw = yaw_angle
	rotation.y = yaw
	respawn_pos = pos
	respawn_yaw = yaw_angle
	if sphere:
		sphere.global_position = pos + Vector3(0, 0.8, 0)
		sphere.linear_velocity = Vector3.ZERO

func respawn() -> void:
	if sphere == null:
		return
	sphere.linear_velocity = Vector3.ZERO
	sphere.angular_velocity = Vector3.ZERO
	sphere.global_position = respawn_pos + Vector3(0, 1.2, 0)
	yaw = respawn_yaw
	speed = 0.0
	drifting = false
	boost_time = 0.0
	respawned.emit()

func _read_input() -> void:
	if is_ai:
		return
	throttle_in = Input.get_action_strength("race_throttle")
	brake_in = Input.get_action_strength("race_brake")
	steer_in = Input.get_axis("race_left", "race_right")
	drift_in = Input.is_action_pressed("race_drift")

func _physics_process(delta: float) -> void:
	if sphere == null:
		return
	_read_input()
	if locked:
		# grid hold: sit still (never creep backward) until the countdown ends
		throttle_in = 0.0
		brake_in = 0.0
		steer_in = 0.0
		drift_in = false
		var lv := sphere.linear_velocity
		sphere.linear_velocity = Vector3(0, lv.y, 0)
		speed = 0.0
	# ---- follow the sphere ---------------------------------------------------
	global_position = sphere.global_position - _up * 0.62
	_ground_check()
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var fwd_g := (fwd - _up * fwd.dot(_up)).normalized()
	var v := sphere.linear_velocity
	var vy := v.dot(_up)
	var vh := v - _up * vy
	speed = vh.dot(fwd_g)
	var speed_before := speed       # measured BEFORE we change it: the sideways part must use this
	if track:
		off_road = track.distance_to_center(global_position) > track.road_width + 1.2
	var top := boost_speed if boost_time > 0.0 else max_speed
	if off_road:
		top *= 0.55
	# ---- accelerate / brake --------------------------------------------------
	if _grounded:
		if throttle_in > 0.05 and brake_in < 0.5:
			speed = move_toward(speed, top, accel * throttle_in * (3.0 if boost_time > 0.0 else 1.0) * delta)
		elif brake_in > 0.05:
			if speed > 0.5:
				speed = maxf(0.0, speed - brake_force * brake_in * delta)
			else:
				speed = move_toward(speed, -reverse_speed, accel * 0.6 * brake_in * delta)
		else:
			speed = move_toward(speed, 0.0, coast_drag * delta)
		if absf(speed) > top and boost_time <= 0.0 and speed > 0:
			speed = move_toward(speed, top, 30.0 * delta)
	# ---- steering ------------------------------------------------------------
	var steer_amt := steer_in
	# no spinning on the spot (ramps in with speed), and less twitchy when flat out
	var speed_factor := clampf(absf(speed) / 9.0, 0.0, 1.0) * lerpf(1.0, 0.7, clampf(absf(speed) / max_speed, 0.0, 1.0))
	var dirsign := 1.0 if speed >= -0.5 else -1.0
	# ---- drift ---------------------------------------------------------------
	if drift_in and not drifting and _grounded and speed > 14.0 and absf(steer_in) > 0.35:
		drifting = true
		drift_dir = signf(steer_in)
		drift_charge = 0.0
		sphere.linear_velocity.y += 2.5   # the little hop
		Juice.dust(global_position, 6)
	if drifting:
		if not drift_in or speed < 9.0:
			_end_drift()
		else:
			drift_charge += delta * (0.9 + absf(steer_in) * 0.4)
			# steer is biased toward the drift direction so you can tighten or widen
			steer_amt = drift_dir * (0.55 + 0.45 * clampf(steer_in * drift_dir, -1.0, 1.0))
	yaw -= steer_amt * turn_rate * (drift_turn_bonus if drifting else 1.0) * speed_factor * dirsign * delta
	rotation.y = yaw
	# ---- velocity: strong grip normally, loose in a drift ---------------------
	var fwd2 := Vector3(sin(yaw), 0, cos(yaw))
	var fwd2_g := (fwd2 - _up * fwd2.dot(_up)).normalized()
	var lateral := vh - fwd_g * speed_before
	var g := drift_grip if drifting else grip
	lateral = lateral.lerp(Vector3.ZERO, 1.0 - exp(-g * delta))
	var new_h := fwd2_g * speed + lateral
	if _grounded:
		sphere.linear_velocity = new_h + _up * vy
	boost_time = maxf(0.0, boost_time - delta)
	_animate(delta)

func _end_drift() -> void:
	drifting = false
	var t := 0.0
	if drift_charge > 2.4:
		t = 1.5
	elif drift_charge > 1.5:
		t = 0.9
	elif drift_charge > 0.8:
		t = 0.5
	if t > 0.0:
		boost(t)
	drift_charge = 0.0

func _ground_check() -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(sphere.global_position, sphere.global_position - _up * 1.6, 1)
	var hit := space.intersect_ray(q)
	_grounded = not hit.is_empty()
	if _grounded:
		_up = _up.lerp(hit.normal, 0.25).normalized()
	else:
		_up = _up.lerp(Vector3.UP, 0.05).normalized()
	# keep the sphere pressed to the road
	if _grounded and sphere.linear_velocity.y < 0:
		sphere.apply_central_force(-_up * 60.0)
	if global_position.y < -30.0:
		respawn()

func _animate(delta: float) -> void:
	var tilt := Basis(Quaternion(Vector3.UP, _up))
	_body.global_basis = (tilt * Basis(Vector3.UP, yaw)).orthonormalized()
	# lean + counter-steer look in a drift
	_body.rotation.z = lerp_angle(_body.rotation.z, -steer_in * 0.12 - (drift_dir * 0.18 if drifting else 0.0), 1.0 - exp(-8.0 * delta))
	if drifting:
		_body.rotation.y += drift_dir * -0.35
	for w in _wheels:
		w.rotation.x += speed * delta * 2.6
	_dust_t -= delta
	if (drifting or off_road) and _grounded and absf(speed) > 6.0 and _dust_t <= 0.0:
		_dust_t = 0.06
		var c := Color(0.8, 0.75, 0.6, 0.6) if off_road else (Color(0.5, 0.8, 1.0, 0.9) if drift_charge < 0.8 else (Color(1.0, 0.6, 0.2, 0.9) if drift_charge < 1.5 else Color(1.0, 0.4, 0.8, 0.95)))
		Juice.dust(global_position - Vector3(sin(yaw), 0, cos(yaw)) * 0.9 + Vector3(0, 0.1, 0), 2, c, 0.2)
	if boost_time > 0.0 and _dust_t <= 0.0:
		Juice.dust(global_position - Vector3(sin(yaw), 0, cos(yaw)) * 1.3 + Vector3(0, 0.5, 0), 2, Color(1.0, 0.7, 0.2, 0.9), 0.25)
	if _driver_head:
		_driver_head.rotation.y = lerp_angle(_driver_head.rotation.y, -steer_in * 0.5, 1.0 - exp(-8.0 * delta))
