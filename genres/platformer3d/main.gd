extends Node3D
## 3D PLATFORMER KIT — demo level that is already DENSE and ALIVE.
## City blocks, a bay with animated water, palms swaying in the wind, litter to
## collect, checkpoints, a minimap, title/pause/settings, adaptive music, ambient
## birds / clouds / motes / blowing paper, and a hero with real feel.
##
## CUSTOMIZE `LEVEL` (and the look pack in res://playpen/lookpack.json) to match the
## design profile — rename things, recolor the hero, change the landmark, move the
## water, add platforms. Do NOT rewrite the player/camera/audio systems: tune them.

const LEVEL := {
	"title": "Trash Tiger",
	"counter_label": "Litter",
	"hero_color": Color(1.0, 0.6, 0.18),
	"hero_stripes": true,
	"collectibles": 48,
	"city_blocks": Vector2i(4, 4),
	"landmark": "needle_tower",       # needle_tower | glass_slab | deco_tower | arch | none
	"seed": 21,
	"music_track": "area1",
	"water_side": "south",            # a bay along one edge ("none" to skip)
}

var viewport: PNViewport
var world: Node3D          # every 3D thing lives under here (rendered at the quality-scaled resolution)
var player: PlatformerPlayer
var cam: PNFollowCamera
var hud: PNHud
var menus: PNMenus
var collectibles: PNCollectibles
var amb: PNAmbient
var city := {}
var env_node: WorldEnvironment
var sun: DirectionalLight3D

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
	_build_systems()
	_build_ui()
	get_tree().paused = false

func _build_world() -> void:
	var blocks: Vector2i = LEVEL["city_blocks"]
	if OS.has_feature("web"):
		blocks = Vector2i(mini(blocks.x, 3), mini(blocks.y, 3))   # web export: keep the first load quick
	city = PNCity.build(world, {"blocks": blocks, "seed": LEVEL["seed"], "landmark": LEVEL["landmark"]})
	var b: Rect2 = city["bounds"]
	var extent := Rect2(b.position - Vector2(30, 30), b.size + Vector2(60, 60))
	# a bay along one edge: animated water + a sandy shore strip
	var water_rects := []
	if LEVEL["water_side"] != "none" and PNLook.ambient_cfg().get("water", false):
		var wz := b.end.y + 18.0
		var wsize := Vector2(b.size.x + 140, 90)
		PNAmbient.make_water(world, wsize, Vector3(b.position.x + b.size.x * 0.5, -0.35, wz + wsize.y * 0.5))
		var sand := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(b.size.x + 140, 0.5, 20)
		sand.mesh = sm
		sand.material_override = PNLook.toon(PNLook.color("ground", Color(0.9, 0.82, 0.6)).lightened(0.35))
		sand.position = Vector3(b.position.x + b.size.x * 0.5, -0.1, wz - 2.0)
		world.add_child(sand)
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = sm.size
		cs.shape = bs
		sb.add_child(cs)
		sb.position = sand.position
		world.add_child(sb)
		water_rects.append(Rect2(b.position.x - 70, wz, wsize.x, wsize.y))
		# palms along the beach
		var x := b.position.x
		var i := 0
		var beach_palms: Array = []
		while x < b.end.x:
			beach_palms.append({"pos": Vector3(x + randf_range(-3, 3), 0.15, wz - 6 + randf_range(-2, 2)), "height": randf_range(5.0, 7.5), "seed": i})
			x += randf_range(9.0, 14.0)
			i += 1
		PNProps.palms(world, beach_palms)
	city["map"]["water"] = water_rects
	# ground detail on the grass ring around the city + under the sidewalks' edge
	var outside := func(p: Vector2) -> bool: return b.has_point(p) or p.y > b.end.y + 5.0
	PNScatter.ground_detail(world, extent, outside, LEVEL["seed"])
	# a sprinkling of flower patches / bushes around the edge
	for i in 14:
		var p := Vector3(randf_range(extent.position.x, extent.end.x), 0.0, randf_range(extent.position.y, extent.end.y))
		if b.has_point(Vector2(p.x, p.z)) or p.z > b.end.y + 5.0:
			continue
		PNProps.flower_patch(world, p, 9, [PNLook.color("accent"), PNLook.color("primary"), Color(1, 1, 1)][i % 3], i)
		PNProps.bush(world, p + Vector3(2, 0, 1), randf_range(0.8, 1.4))
	# litter / collectibles along sidewalks and streets
	var spots: Array = city["sidewalk_points"] + city["street_points"]
	for i in int(LEVEL["collectibles"]):
		var base: Vector3 = spots[i % spots.size()]
		var jitter := Vector3(randf_range(-14, 14), 0.0, randf_range(-14, 14)) if i >= spots.size() else Vector3(randf_range(-2, 2), 0.0, randf_range(-2, 2))
		var pos := base + jitter
		if not b.has_point(Vector2(pos.x, pos.z)):
			continue
		PNProps.litter(world, Vector3(pos.x, 0.22 if i % 2 == 0 else 0.0, pos.z), -1, i)
	PNProps.finish_litter(world)   # one MultiMesh per kind — draws all the litter in 3 calls
	# checkpoint flags at a few intersections
	var cps := 0
	for p in city["street_points"]:
		if cps >= 3:
			break
		var cp := PNCheckpoint.new()
		world.add_child(cp)
		cp.global_position = Vector3(p.x + 7.0 * (cps + 1) * (1 if cps % 2 == 0 else -1), 0.0, p.z - 22.0 + cps * 24.0)
		cps += 1
	# kill plane: fall off the world and you respawn at the last checkpoint
	var kill := Area3D.new()
	kill.collision_layer = 0
	kill.collision_mask = 2
	var kcs := CollisionShape3D.new()
	var kb := BoxShape3D.new()
	kb.size = Vector3(1000, 2, 1000)
	kcs.shape = kb
	kill.add_child(kcs)
	kill.position = Vector3(0, -30, 0)
	world.add_child(kill)
	kill.body_entered.connect(func(body): if body.has_method("respawn"): body.respawn())

func _build_player() -> void:
	player = PlatformerPlayer.new()
	player.body_color = LEVEL["hero_color"]
	player.stripes = LEVEL["hero_stripes"]
	player.ear_style = "pointy" if LEVEL["hero_stripes"] else "round"
	world.add_child(player)
	player.global_position = city["spawn"]
	player.respawn_point = city["spawn"]
	cam = PNFollowCamera.new()
	world.add_child(cam)
	cam.set_target(player)
	player.camera = cam

func _build_systems() -> void:
	amb = PNAmbient.new()
	world.add_child(amb)
	var b: Rect2 = city["bounds"]
	amb.build(player, Rect2(b.position - Vector2(40, 40), b.size + Vector2(80, 80)), LEVEL["seed"])
	collectibles = PNCollectibles.new()
	add_child(collectibles)
	for a in get_tree().get_nodes_in_group("collectible"):
		collectibles.register(a)
	PNAudio.play_beds(PNLook.look.get("audio", {}).get("beds", []))
	PNAudio.play_track(LEVEL["music_track"])
	PNAudio.set_state("menu")

func _build_ui() -> void:
	hud = PNHud.new()
	add_child(hud)
	hud.set_counter(LEVEL["counter_label"], 0, collectibles.remaining)
	hud.add_minimap(player, cam, city["map"], {"collectible": Color(1.0, 0.85, 0.2)})
	collectibles.collected.connect(func(n, left): hud.set_counter(LEVEL["counter_label"], n, n + left))
	collectibles.all_collected.connect(func(): hud.toast("All clean!", 3.0))
	player.respawned.connect(func(): hud.toast("Back on your feet!"))
	menus = PNMenus.new()
	menus.title = LEVEL["title"]
	add_child(menus)
	menus.play_pressed.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	menus.resumed.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	menus.show_title()
	# footsteps change with the ground under you
	var t := Timer.new()
	t.wait_time = 0.25
	t.autostart = true
	add_child(t)
	t.timeout.connect(func():
		var b: Rect2 = city["bounds"]
		var p := Vector2(player.global_position.x, player.global_position.z)
		player.surface = "pavement" if b.has_point(p) else ("sand" if p.y > b.end.y else "grass"))
