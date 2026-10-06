extends Node3D
## THIRD-PERSON SHOOTER KIT — a complete team deathmatch you can play right now: a studded brick arena with a central
## tower and ramps, 3v3 against nav-mesh bots, four weapons with recoil / muzzle flash / impact effects / hit markers,
## respawns, a scoreboard, kill feed, timer + score limit, title / pause / settings, and the full look pack + ambient layer.
##
## CUSTOMIZE `LEVEL`, the look pack (playpen/lookpack.json) and the weapon DEFS in playpen/pn_weapon.gd. Replace the figures in
## res://models/ with your own (use `playpen-model figure ...`). Do NOT rewrite the fighter, weapon, bot, match, HUD or
## brick systems from scratch.

const LEVEL := {
	"title": "Brick Squad",
	"arena_studs": 90,
	"score_limit": 15,
	"time_limit": 300.0,
	"bots_per_team": 3,
	"difficulty": 0.45,
	"seed": 11,
	"team_names": {1: "Blue", 2: "Red"},
	"team_colors": {1: Color(0.18, 0.43, 0.87), 2: Color(0.85, 0.27, 0.22)},
	"music_track": "arena",
	"blue_models": ["res://models/brick_soldier_blue.glb", "res://models/brick_trooper.glb"],
	"red_models": ["res://models/brick_soldier_red.glb", "res://models/brick_brawler.glb", "res://models/brick_skirmisher.glb"],
	"names": ["Alpha", "Bolt", "Clank", "Dozer", "Echo", "Flip", "Gizmo", "Hex"]
}

var viewport: PNViewport
var world: Node3D
var env_node: WorldEnvironment
var sun: DirectionalLight3D
var player: TpsPlayer
var hud: PNShooterHud
var menus: PNMenus
var match_mgr: PNMatch
var region: NavigationRegion3D
var bots: Array = []
var _half := 22.4

func _ready() -> void:
	randomize()
	PNShooterInput.setup()
	viewport = PNViewport.new()
	add_child(viewport)
	world = viewport.world
	env_node = WorldEnvironment.new()
	world.add_child(env_node)
	sun = DirectionalLight3D.new()
	world.add_child(sun)
	PNLook.apply(env_node, sun)
	PNAudio.configure_from_look(PNLook.look)
	_half = LEVEL["arena_studs"] * PNBricks.STUD * 0.5
	_build_world()
	_build_match()
	_build_ui()
	# QA hook: `godot -- --autoplay` skips the title and starts the match (headless runs / playpen-play).
	if "--autoplay" in OS.get_cmdline_user_args():
		menus.in_game = true
		menus._title_root.visible = false
		_start_match()
		if "--overview" in OS.get_cmdline_user_args():   # QA: a high camera over the whole arena
			var oc := Camera3D.new()
			oc.fov = 55.0
			world.add_child(oc)
			oc.global_position = Vector3(0, 46, 52)
			oc.look_at(Vector3(0, 0, 0), Vector3.UP)
			oc.make_current()
			player.input_enabled = false
		var tick := Timer.new()
		tick.wait_time = 4.0
		tick.autostart = true
		add_child(tick)
		tick.timeout.connect(func(): print("[qa] scores=", match_mgr.scores, " player k/d=", player.kills, "/", player.deaths, " bots alive=", bots.filter(func(b): return b.alive).size()))

# ---------------------------------------------------------------- the arena
func _build_world() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = LEVEL["seed"]
	region = NavigationRegion3D.new()
	world.add_child(region)
	var bricks := PNBricks.new()
	var tc: Dictionary = LEVEL["team_colors"]
	var neutral := [PNLook.color("accent", Color(1.0, 0.82, 0.25)), Color(0.93, 0.93, 0.9), PNLook.color("primary", Color(0.2, 0.45, 0.9)), Color(0.9, 0.3, 0.25)]
	# base plate + team pads
	var n: int = LEVEL["arena_studs"]
	bricks.plate(region, Vector3.ZERO, Vector2i(n, n), PNLook.color("ground", Color(0.37, 0.75, 0.29)))
	var pad_z := _half - 6.0
	bricks.brick(Vector3(0, PNBricks.PLATE, pad_z), Vector2i(30, 14), 1, tc[1], 0.0, true)
	bricks.brick(Vector3(0, PNBricks.PLATE, -pad_z), Vector2i(30, 14), 1, tc[2], 0.0, true)
	# perimeter walls: running-bond brick courses in the team colors
	var w := _half - 0.8
	var wall_cols := [tc[1], Color(0.93, 0.93, 0.9), tc[2], Color(0.93, 0.93, 0.9)]
	bricks.wall(Vector3(-w, PNBricks.PLATE, -w), Vector3(w, PNBricks.PLATE, -w), 6, [tc[2], Color(0.93, 0.93, 0.9)])
	bricks.wall(Vector3(-w, PNBricks.PLATE, w), Vector3(w, PNBricks.PLATE, w), 6, [tc[1], Color(0.93, 0.93, 0.9)])
	bricks.wall(Vector3(-w, PNBricks.PLATE, -w), Vector3(-w, PNBricks.PLATE, w), 6, wall_cols)
	bricks.wall(Vector3(w, PNBricks.PLATE, -w), Vector3(w, PNBricks.PLATE, w), 6, wall_cols)
	# central tower with four ramps
	var base := PNBricks.PLATE
	bricks.brick(Vector3(0, base, 0), Vector2i(22, 22), 6, neutral[1])
	bricks.brick(Vector3(0, base + PNBricks.PLATE * 6, 0), Vector2i(14, 14), 6, neutral[0])
	bricks.brick(Vector3(0, base + PNBricks.PLATE * 12, 0), Vector2i(5, 5), 9, neutral[3])
	for i in 4:
		var yaw := i * 90.0
		var dir := Vector3(sin(deg_to_rad(yaw)), 0, cos(deg_to_rad(yaw)))
		bricks.slope(Vector3(0, base, 0) + dir * (11.0 * PNBricks.STUD + 6.0 * PNBricks.STUD), Vector2i(8, 12), 6, yaw + 180.0, neutral[i % neutral.size()])
	# cover blocks, mirrored left/right and front/back so neither team has the edge
	var spots := [Vector2(-11, 5), Vector2(-5, 13), Vector2(10, 9), Vector2(-15, -4), Vector2(15, -3)]
	for s in spots:
		for mx in [1.0, -1.0]:
			var p := Vector3(s.x * mx, base, s.y)
			var p2 := Vector3(-s.x * mx, base, -s.y)
			var col: Color = neutral[(int(abs(s.x)) + int(abs(s.y))) % neutral.size()]
			bricks.brick(p, Vector2i(4, 10), 6, col, 0.0 if mx > 0.0 else 90.0)
			bricks.brick(p2, Vector2i(4, 10), 6, col, 0.0 if mx > 0.0 else 90.0)
	# low stepping plates scattered for cover and movement variety
	for i in 8:
		var a := rng.randf() * TAU
		var r := rng.randf_range(9.0, 19.0)
		bricks.brick(Vector3(cos(a) * r, base, sin(a) * r), Vector2i(8, 8), 2, neutral[i % neutral.size()], rng.randf() * 90.0)
	var root := bricks.commit(region)
	root.add_to_group("navmesh")
	_bake_nav()
	# lush terrain around the arena (below the base plate), trees and flowers beyond the walls
	var terrain := PNTerrain.build(world, {"size": 260.0, "res": 52, "amp": 9.0, "flat_radius": _half + 6.0, "seed": LEVEL["seed"], "frequency": 0.015})
	terrain.node.position.y = -0.06
	var placements: Array = []
	for i in int(70 * (0.4 + PNSettings.scale() * 0.6)):
		var p2d := Vector2(rng.randf_range(-110, 110), rng.randf_range(-110, 110))
		if absf(p2d.x) < _half + 6.0 and absf(p2d.y) < _half + 6.0:
			continue
		placements.append({"pos": Vector3(p2d.x, terrain.height_at(p2d.x, p2d.y) - 0.06, p2d.y), "height": rng.randf_range(5.0, 9.0), "seed": i})
	PNProps.trees(world, placements)
	for i in 18:
		var fp := Vector2(rng.randf_range(-100, 100), rng.randf_range(-100, 100))
		if absf(fp.x) < _half + 4.0 and absf(fp.y) < _half + 4.0:
			continue
		PNProps.flower_patch(world, Vector3(fp.x, terrain.height_at(fp.x, fp.y) - 0.06, fp.y), 9, [PNLook.color("accent"), PNLook.color("secondary"), Color(1, 1, 1), PNLook.color("primary")][i % 4], i)

func _bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.cell_size = 0.35
	nm.cell_height = 0.35
	nm.agent_radius = 0.5
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.7
	nm.agent_max_slope = 42.0
	region.navigation_mesh = nm
	region.bake_navigation_mesh(false)

# ---------------------------------------------------------------- match
func _build_match() -> void:
	match_mgr = PNMatch.new()
	match_mgr.score_limit = LEVEL["score_limit"]
	match_mgr.time_limit = LEVEL["time_limit"]
	match_mgr.team_names = LEVEL["team_names"]
	add_child(match_mgr)
	var pad_z := _half - 6.0
	for i in 5:
		match_mgr.add_spawn(1, Vector3((i - 2) * 2.4, 0.6, pad_z))
		match_mgr.add_spawn(2, Vector3((i - 2) * 2.4, 0.6, -pad_z))
	player = TpsPlayer.new()
	player.team = 1
	world.add_child(player)
	match_mgr.register(player)
	var names: Array = LEVEL["names"].duplicate()
	names.shuffle()
	var k := 0
	for team in [1, 2]:
		var count: int = LEVEL["bots_per_team"] - (1 if team == 1 else 0)
		var models: Array = LEVEL["blue_models"] if team == 1 else LEVEL["red_models"]
		for i in count:
			var b := PNBot.new()
			b.team = team
			b.model_path = models[i % models.size()]
			b.difficulty = LEVEL["difficulty"]
			b.display_name = names[k % names.size()]
			k += 1
			world.add_child(b)
			match_mgr.register(b)
			bots.append(b)
	match_mgr.kill_feed.connect(func(text, kt): hud.feed(text, kt))
	match_mgr.score_changed.connect(func(s): hud.set_score(s))
	match_mgr.time_changed.connect(func(sec): hud.set_time(sec))
	match_mgr.match_ended.connect(_on_match_ended)
	match_mgr.fighter_respawned.connect(func(f): if f == player: hud.toast("Fight!", 0.8))
	PNAudio.play_beds(PNLook.look.get("audio", {}).get("beds", []))
	PNAudio.play_track(LEVEL["music_track"])
	var amb := PNAmbient.new()
	world.add_child(amb)
	amb.build(player, Rect2(-90, -90, 180, 180), LEVEL["seed"])
	# position everyone on their pads until the match starts
	for f in match_mgr.fighters():
		(f as PNFighter).global_position = match_mgr.spawn_point_for(f)

func _on_match_ended(winner: int, scores: Dictionary) -> void:
	player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_end(winner, scores)
	PNAudio.stinger("victory" if winner == 1 else "game_over")
	PNAudio.set_state("menu")

# ---------------------------------------------------------------- UI
func _build_ui() -> void:
	hud = PNShooterHud.new()
	hud.match_ref = match_mgr
	hud.team_names = LEVEL["team_names"]
	add_child(hud)
	hud.set_score(match_mgr.scores)
	hud.set_time(int(LEVEL["time_limit"]))
	player.health_changed.connect(func(h, s): hud.set_health(h, s))
	player.damaged.connect(func(a, _at, _d): hud.damage_flash(clampf(a / 60.0, 0.15, 0.6)))
	player.hit_marker.connect(hud.hit_marker)
	player.weapon_changed.connect(_on_weapon_changed)
	for w in player.weapons:
		w.ammo_changed.connect(func(m, r, rl): if w == player.weapon: hud.set_ammo(m, r, rl, str(w.def["name"])))
		w.fired.connect(func(_p, _y): hud.kick_crosshair(0.3))
	hud.set_ammo(player.weapon.mag, player.weapon.reserve, false, str(player.weapon.def["name"]))
	hud.play_again.connect(_play_again)
	menus = PNMenus.new()
	menus.title = LEVEL["title"]
	add_child(menus)
	menus.play_pressed.connect(_start_match)
	menus.resumed.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	menus.show_title()

func _on_weapon_changed(w: PNWeapon) -> void:
	hud.set_ammo(w.mag, w.reserve, w.reloading, str(w.def["name"]))

func _start_match() -> void:
	hud.hide_end()
	match_mgr.start()
	player.input_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.toast("Team Deathmatch — first to %d" % LEVEL["score_limit"], 2.2)
	PNAudio.stinger("go")

func _play_again() -> void:
	menus.in_game = true
	_start_match()
	PNAudio.set_state("explore")

func _process(_delta: float) -> void:
	if player == null or not menus.in_game or not match_mgr.running:
		return
	hud.set_spread(player.current_spread() * 0.5)
	var near := false
	for b in bots:
		var bb := b as PNBot
		if bb.alive and bb.global_position.distance_to(player.global_position) < 24.0:
			near = true
			break
	PNAudio.set_state("danger" if near else "explore")
