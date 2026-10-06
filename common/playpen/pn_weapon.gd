class_name PNWeapon
extends Node3D
## Playpen kit: WEAPONS WITH FEEL. Hitscan or projectile, recoil that kicks the camera and recovers, muzzle flash, tracers,
## impact effects (sparks + dust + a fading bullet mark), hit markers, ammo + reload, and sound hooks.
##
##   var w := PNWeapon.new()
##   w.setup("rifle", owner_fighter)           # "rifle" | "pistol" | "shotgun" | "launcher"
##   owner.add_child(w)
##   w.fire(origin, direction)                 # returns true when a shot was actually fired
##   w.fired.connect(func(pitch, yaw): camera_kick(pitch, yaw))
##   w.hit_confirmed.connect(func(killed, headshot): hud.hit_marker(killed, headshot))
##
## Tune the DEFS below (damage, rate, spread, recoil...) — don't rewrite the firing code.

signal fired(recoil_pitch: float, recoil_yaw: float)
signal ammo_changed(mag: int, reserve: int, reloading: bool)
signal hit_confirmed(killed: bool, headshot: bool)
signal reload_started
signal empty_click

const DEFS := {
	"rifle":    {"name": "Brick Rifle", "mode": "hitscan", "damage": 12.0, "rate": 9.0, "mag": 32, "reserve": 160, "reload": 1.7, "spread": 1.1, "recoil_pitch": 0.9, "recoil_yaw": 0.35, "range": 120.0, "auto": true, "pellets": 1, "tracer": Color(1.0, 0.85, 0.35), "sfx": "shot_rifle", "kick": 0.05},
	"pistol":   {"name": "Snap Pistol", "mode": "hitscan", "damage": 26.0, "rate": 4.5, "mag": 12, "reserve": 72, "reload": 1.2, "spread": 0.45, "recoil_pitch": 1.5, "recoil_yaw": 0.25, "range": 90.0, "auto": false, "pellets": 1, "tracer": Color(1.0, 0.95, 0.6), "sfx": "shot_pistol", "kick": 0.06},
	"shotgun":  {"name": "Scatter Blaster", "mode": "hitscan", "damage": 9.0, "rate": 1.3, "mag": 6, "reserve": 30, "reload": 2.4, "spread": 5.5, "recoil_pitch": 4.5, "recoil_yaw": 0.8, "range": 40.0, "auto": false, "pellets": 9, "tracer": Color(1.0, 0.7, 0.3), "sfx": "shot_shotgun", "kick": 0.12},
	"launcher": {"name": "Rocket Pop", "mode": "projectile", "damage": 85.0, "rate": 0.9, "mag": 2, "reserve": 8, "reload": 2.8, "spread": 0.2, "recoil_pitch": 5.0, "recoil_yaw": 0.4, "range": 200.0, "auto": false, "pellets": 1, "tracer": Color(1.0, 0.5, 0.2), "sfx": "launcher", "kick": 0.16, "proj_speed": 38.0, "blast": 5.0}
}

var id := "rifle"
var def: Dictionary = {}
var owner_fighter: PNFighter
var mag := 0
var reserve := 0
var reloading := false
var _cooldown := 0.0
var _reload_left := 0.0
var _flash: OmniLight3D
var _flash_mesh: MeshInstance3D
var _flash_t := 0.0
var _marks: Array = []
var enemy_mask := 0b110      # layers 2 (player) + 4 (bots); world is layer 1

func setup(weapon_id: String, who: PNFighter) -> void:
	id = weapon_id if DEFS.has(weapon_id) else "rifle"
	def = DEFS[id]
	owner_fighter = who
	mag = int(def["mag"])
	reserve = int(def["reserve"])
	ammo_changed.emit(mag, reserve, false)

func _ready() -> void:
	if def.is_empty():
		def = DEFS[id]
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.8, 0.45)
	_flash.light_energy = 0.0
	_flash.omni_range = 6.0
	_flash.shadow_enabled = false
	add_child(_flash)
	_flash_mesh = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	_flash_mesh.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.85, 0.5, 1.0)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.8, 0.4)
	m.emission_energy_multiplier = 2.0
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flash_mesh.material_override = m
	_flash_mesh.visible = false
	_flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flash_mesh)

func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
	if reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash.light_energy = 0.0
			_flash_mesh.visible = false

func can_fire() -> bool:
	return _cooldown <= 0.0 and not reloading and mag > 0

func is_auto() -> bool:
	return bool(def.get("auto", false))

func fire(origin: Vector3, dir: Vector3, spread_mult := 1.0) -> bool:
	if reloading or _cooldown > 0.0:
		return false
	if mag <= 0:
		_cooldown = 0.25
		empty_click.emit()
		if reserve > 0:
			reload()
		return false
	mag -= 1
	_cooldown = 1.0 / float(def["rate"])
	var pellets := int(def.get("pellets", 1))
	var spread_deg := float(def["spread"]) * spread_mult
	for i in pellets:
		var d := _spread_dir(dir, spread_deg)
		if str(def["mode"]) == "hitscan":
			_fire_hitscan(origin, d)
		else:
			_fire_projectile(origin, d)
	_muzzle_flash()
	var yaw := randf_range(-1.0, 1.0) * float(def["recoil_yaw"])
	fired.emit(float(def["recoil_pitch"]), yaw)
	PNAudio.sfx_3d(str(def["sfx"]), global_position, randf_range(0.94, 1.06), -2.0)
	ammo_changed.emit(mag, reserve, false)
	if mag == 0 and reserve > 0:
		reload()
	return true

func _spread_dir(dir: Vector3, deg: float) -> Vector3:
	if deg <= 0.01:
		return dir
	var b := Basis.looking_at(dir, Vector3.UP)
	var a := deg_to_rad(deg)
	var r := sqrt(randf()) * tan(a)
	var th := randf() * TAU
	return (b * Vector3(cos(th) * r, sin(th) * r, -1.0)).normalized()

func _fire_hitscan(origin: Vector3, dir: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var to := origin + dir * float(def["range"])
	var q := PhysicsRayQueryParameters3D.create(origin, to, 1 | enemy_mask)
	if owner_fighter:
		q.exclude = [owner_fighter.get_rid()]
	var hit := space.intersect_ray(q)
	var end := to
	if hit.size() > 0:
		end = hit["position"]
		var col: Object = hit["collider"]
		if col is PNFighter and (col as PNFighter).alive and (owner_fighter == null or (col as PNFighter).team != owner_fighter.team or (col as PNFighter).team == 0):
			var f := col as PNFighter
			var head := (hit["position"] as Vector3).y > f.global_position.y + f.model_height * 0.78
			var killed := f.take_damage(float(def["damage"]), owner_fighter, hit["position"], head)
			hit_confirmed.emit(killed, head)
			PNAudio.sfx_3d("impact_flesh", hit["position"], randf_range(0.9, 1.1), -6.0)
			Juice.sparkle(hit["position"], Color(1.0, 0.95, 0.7), 5)
		else:
			_impact(hit["position"], hit["normal"])
	_tracer(global_position, end)

func _impact(pos: Vector3, normal: Vector3) -> void:
	Juice.sparkle(pos + normal * 0.05, Color(1.0, 0.9, 0.55), 6)
	Juice.dust(pos + normal * 0.05, 4, Color(0.9, 0.88, 0.8, 0.7), 0.1)
	PNAudio.sfx_3d("impact_brick", pos, randf_range(0.9, 1.15), -7.0)
	var root: Node = PNViewport.world_root()
	if root == null:
		return
	var mark := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.16, 0.16)
	mark.mesh = qm
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(0.08, 0.08, 0.1, 0.8)
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mark.material_override = mm
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mark)
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	mark.global_transform = Transform3D(Basis.looking_at(-normal, up), pos + normal * 0.012)
	_marks.append(mark)
	if _marks.size() > 24:
		var old = _marks.pop_front()   # may already have faded out and freed itself
		if is_instance_valid(old):
			(old as Node).queue_free()
	var tw := mark.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(mm, "albedo_color:a", 0.0, 1.5)
	tw.tween_callback(mark.queue_free)

func _tracer(from: Vector3, to: Vector3) -> void:
	var root: Node = PNViewport.world_root()
	if root == null:
		return
	var len := from.distance_to(to)
	if len < 1.0:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, len)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var c: Color = def["tracer"]
	m.albedo_color = Color(c.r, c.g, c.b, 0.9)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.global_transform = Transform3D(Basis.looking_at(to - from, Vector3.UP), (from + to) * 0.5)
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 0.09)
	tw.tween_callback(mi.queue_free)

func _fire_projectile(origin: Vector3, dir: Vector3) -> void:
	var root: Node = PNViewport.world_root()
	if root == null:
		return
	var p := PNProjectile.new()
	root.add_child(p)
	p.launch(origin, dir, float(def.get("proj_speed", 30.0)), float(def["damage"]), float(def.get("blast", 4.0)), owner_fighter, def["tracer"])

func _muzzle_flash() -> void:
	_flash.light_energy = 3.0
	_flash_mesh.visible = true
	_flash_mesh.rotation.z = randf() * TAU
	_flash_t = 0.045

func reload() -> void:
	if reloading or mag >= int(def["mag"]) or reserve <= 0:
		return
	reloading = true
	_reload_left = float(def["reload"])
	reload_started.emit()
	PNAudio.sfx("reload", 1.0, -6.0)
	ammo_changed.emit(mag, reserve, true)

func _finish_reload() -> void:
	reloading = false
	var need := int(def["mag"]) - mag
	var take := mini(need, reserve)
	mag += take
	reserve -= take
	ammo_changed.emit(mag, reserve, false)

func add_ammo(amount: int) -> void:
	reserve += amount
	ammo_changed.emit(mag, reserve, reloading)
