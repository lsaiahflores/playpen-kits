extends Node3D
## THIRD-PERSON ADVENTURE KIT (Ocarina-style) — a dense, living starter field:
## rolling terrain, a forest, a village, a pond, glowing crystals, enemies to lock
## onto and fight (sword / shield / roll), signs and chests to interact with, hearts,
## a minimap, title/pause/settings, adaptive music (it switches to the danger layers
## when enemies are near), and the full ambient layer.
##
## CUSTOMIZE `LEVEL` and the look pack. Tune the player/enemy @exports; don't
## rewrite the controller, camera, audio, or ambient systems.

const LEVEL := {
	"title": "Quest of the Blue Hero",
	"hero_color": Color(0.35, 0.65, 0.95),
	"enemies": 5,
	"trees": 70,
	"seed": 8,
	"music_track": "area1",
}

var viewport: PNViewport
var world: Node3D
var terrain: PNTerrain
var player: AdventurePlayer
var cam: PNFollowCamera
var hud: PNHud
var menus: PNMenus
var amb: PNAmbient
var env_node: WorldEnvironment
var sun: DirectionalLight3D
var enemies_alive := 0

func _ready() -> void:
	randomize()
	viewport = PNViewport.new()
	add_child(viewport)
	world = viewport.world
	env_node = WorldEnvironment.new()
	world.add_child(env_node)
	sun = DirectionalLight3D.new()
	world.add_child(sun)
	PNLook.apply(env_node, sun)
	PNAudio.configure_from_look(PNLook.look)
	_build_world()
	_build_player()
	_build_actors()
	_build_ui()

func _build_world() -> void:
	terrain = PNTerrain.build(world, {"size": 170.0, "res": 40 if OS.has_feature("web") else 64, "amp": 5.5, "flat_radius": 16.0, "seed": LEVEL["seed"]})
	var rng := RandomNumberGenerator.new()
	rng.seed = LEVEL["seed"]
	# a pond in the middle-left with animated water, plus a little shoreline ring
	var pond_c := Vector3(-22, 0.0, 12)
	PNAmbient.make_water(world, Vector2(26, 20), pond_c + Vector3(0, -0.15, 0))
	var wr := Rect2(pond_c.x - 13, pond_c.z - 10, 26, 20)
	var avoid := func(p: Vector2) -> bool: return wr.grow(2.5).has_point(p) or p.length() < 5.0
	# forest
	var tl: Array = []
	for i in int(LEVEL["trees"] * (0.5 + PNSettings.scale() * 0.5)):
		var p := Vector2(rng.randf_range(-80, 80), rng.randf_range(-80, 80))
		if avoid.call(p) or p.length() < 18.0:
			continue
		tl.append({"pos": Vector3(p.x, terrain.height_at(p.x, p.y), p.y), "height": rng.randf_range(4.0, 7.5), "seed": i})
	PNProps.trees(world, tl)
	# rocks + ground detail + flowers
	var rock := SphereMesh.new()
	rock.radius = 0.5
	rock.height = 0.7
	rock.radial_segments = 6
	rock.rings = 3
	var rock_mat := PNLook.toon(PNLook.color("ground", Color(0.5, 0.5, 0.55)).lightened(0.1))
	PNScatter.scatter(world, rock, rock_mat, Rect2(-80, -80, 160, 160), 60, {"seed": 4, "min_scale": 0.6, "max_scale": 2.6, "avoid": avoid, "raycast": true, "shadows": false})
	PNScatter.ground_detail(world, Rect2(-80, -80, 160, 160), avoid, LEVEL["seed"], true, false)
	for i in 14:
		var p2 := Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 60))
		if avoid.call(p2):
			continue
		PNProps.flower_patch(world, Vector3(p2.x, terrain.height_at(p2.x, p2.y), p2.y), 9, [PNLook.color("accent"), PNLook.color("primary"), Color(1, 1, 1), PNLook.color("secondary")][i % 4], i)
	# glowing crystals (fantasy dressing — they pulse and bloom)
	var crystal := PrismMesh.new()
	crystal.size = Vector3(0.5, 1.4, 0.5)
	var cmm := MultiMesh.new()
	cmm.transform_format = MultiMesh.TRANSFORM_3D
	cmm.use_colors = true
	cmm.mesh = crystal
	cmm.instance_count = 16
	for i in 16:
		var cp := Vector2(rng.randf_range(-70, 70), rng.randf_range(-70, 70))
		var ch := terrain.height_at(cp.x, cp.y)
		cmm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 2.0)), Vector3(cp.x, ch + 0.5, cp.y)))
		cmm.set_instance_color(i, [PNLook.color("secondary"), PNLook.color("accent"), PNLook.color("primary")][i % 3].srgb_to_linear())
	var cmi := MultiMeshInstance3D.new()
	cmi.multimesh = cmm
	var cmat := PNLook.glow_material(Color.WHITE, 2.0)
	cmat.set_shader_parameter("bob_height", 0.0)
	cmat.set_shader_parameter("intensity", 1.5)
	cmi.material_override = cmat
	cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(cmi)
	_build_village(Vector3(14, terrain.height_at(14, -8), -8))

func _build_village(at: Vector3) -> void:
	var batch := PNBatch.new()
	var hut_cols := [PNLook.color("building"), PNLook.color("building").lerp(PNLook.color("accent"), 0.2), PNLook.color("building").lightened(0.12)]
	var colliders := StaticBody3D.new()
	colliders.collision_layer = 1
	world.add_child(colliders)
	for i in 3:
		var c := at + Vector3(i * 7.0 - 7.0, 0, (i % 2) * 5.0)
		batch.add_box(c + Vector3(0, 1.4, 0), Vector3(4.2, 2.8, 4.0), hut_cols[i])
		var roof := PrismMesh.new()
		roof.size = Vector3(5.2, 1.8, 4.8)
		batch.add_mesh(roof, Transform3D(Basis.IDENTITY, c + Vector3(0, 3.7, 0)), PNLook.color("roof"))
		batch.add_box(c + Vector3(0, 0.9, 2.02), Vector3(1.0, 1.8, 0.06), PNLook.color("ground").darkened(0.4), true)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(4.2, 2.8, 4.0)
		cs.shape = bs
		cs.position = c + Vector3(0, 1.4, 0)
		colliders.add_child(cs)
	var mat := PNLook.toon(Color.WHITE)
	mat.set_shader_parameter("use_vertex_color", true)
	world.add_child(batch.commit(mat))
	# a sign and two chests to interact with
	var sign_post := PNInteractable.new()
	sign_post.prompt_text = "Read"
	world.add_child(sign_post)
	sign_post.global_position = at + Vector3(-3, 0, 6)
	sign_post.interacted.connect(func(_p): hud.toast("Welcome, traveler!", 2.4))
	for i in 2:
		var chest := PNInteractable.new()
		chest.prompt_text = "Open"
		chest.one_shot = true
		chest.glow_color = Color(1.0, 0.8, 0.3)
		world.add_child(chest)
		chest.global_position = at + Vector3(4 + i * 9.0, 0, 6.5 - i * 3.0)
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.2, 0.8, 0.8)
		box.mesh = bm
		box.material_override = PNLook.toon(Color(0.62, 0.38, 0.2))
		box.position.y = 0.4
		chest.add_child(box)
		chest.interacted.connect(func(p): (p as AdventurePlayer).heal(1.0); hud.toast("A heart!", 1.6); PNAudio.stinger("pickup"))

func _build_player() -> void:
	player = AdventurePlayer.new()
	player.body_color = LEVEL["hero_color"]
	world.add_child(player)
	player.global_position = Vector3(0, terrain.height_at(0, 0) + 1.2, 0)
	player.respawn_point = player.global_position
	cam = PNFollowCamera.new()
	cam.distance = 6.0
	world.add_child(cam)
	cam.set_target(player)
	player.camera = cam

func _build_actors() -> void:
	amb = PNAmbient.new()
	world.add_child(amb)
	amb.build(player, Rect2(-70, -70, 140, 140), LEVEL["seed"])
	for i in int(LEVEL["enemies"]):
		var a := TAU * i / LEVEL["enemies"] + 0.4
		var r := 26.0 + (i % 2) * 14.0
		var e := Enemy.new()
		world.add_child(e)
		e.global_position = Vector3(cos(a) * r, terrain.height_at(cos(a) * r, sin(a) * r) + 1.0, sin(a) * r)
		e.color = [PNLook.color("accent"), PNLook.color("secondary"), PNLook.color("primary").darkened(0.2)][i % 3]
		e.died.connect(_on_enemy_died)
		enemies_alive += 1
	PNAudio.play_beds(PNLook.look.get("audio", {}).get("beds", []))
	PNAudio.play_track(LEVEL["music_track"])
	PNAudio.set_state("menu")

func _on_enemy_died(_e: Enemy) -> void:
	enemies_alive -= 1
	hud.set_counter("Foes", int(LEVEL["enemies"]) - enemies_alive, int(LEVEL["enemies"]))
	if enemies_alive <= 0:
		hud.toast("The field is safe!", 3.0)
		PNAudio.stinger("victory")

func _build_ui() -> void:
	hud = PNHud.new()
	add_child(hud)
	hud.set_counter("Foes", 0, int(LEVEL["enemies"]))
	hud.add_minimap(player, cam, {"water": [Rect2(-35, 2, 26, 20)], "blocks": [Rect2(7, -12, 30, 12)], "streets": []}, {"enemy": Color(1, 0.35, 0.4), "interactable": Color(1, 0.9, 0.4)})
	player.health_changed.connect(func(h, m): hud.set_hearts(h, m))
	hud.set_hearts(player.hearts, player.max_hearts)
	player.prompt_changed.connect(func(a, t): hud.set_prompt(a, t))
	player.died.connect(func(): hud.toast("Oh no!", 1.2))
	menus = PNMenus.new()
	menus.title = LEVEL["title"]
	add_child(menus)
	menus.play_pressed.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	menus.resumed.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	menus.show_title()
	# music reacts to danger: enemies close -> the danger layers fade in
	var t := Timer.new()
	t.wait_time = 0.5
	t.autostart = true
	add_child(t)
	t.timeout.connect(func():
		if not menus.in_game:
			return
		var near := false
		for e in get_tree().get_nodes_in_group("enemy"):
			if e is Enemy and e.state in ["chase", "windup", "recover"] and e.global_position.distance_to(player.global_position) < 16.0:
				near = true
		PNAudio.set_state("danger" if near else "explore"))
