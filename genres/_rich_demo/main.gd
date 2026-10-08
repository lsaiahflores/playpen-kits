extends Node3D
## Rich-by-default demo scene (used to verify PNRich in a real renderer; not a game kit).
## Usage: godot --path <project> -- --out shot.png [--seconds 3] [--tod night] [--tier 0|1|2] [--cam 0|1]
func _arg(name: String, fallback := "") -> String:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == name and i + 1 < a.size():
			return a[i + 1]
	return fallback

func _ready() -> void:
	var out := _arg("--out")
	var secs := float(_arg("--seconds", "3"))
	var tier := _arg("--tier", "")
	if tier != "":
		PNSettings.quality = clampi(int(tier), 0, 2)
	var env := WorldEnvironment.new()
	add_child(env)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	PNLook.apply(env, sun)
	PNAudio.configure_from_look(PNLook.look)
	var terrain := PNTerrain.build(self, {"size": 260.0, "res": 96, "amp": 5.5, "flat_radius": 10.0, "seed": 11})
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var placements := []
	for i in 140:
		var a := rng.randf() * TAU
		var r := rng.randf_range(14.0, 105.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		p.y = terrain.height_at(p.x, p.z)
		placements.append({"pos": p, "height": rng.randf_range(4.0, 8.5), "seed": i})
	PNProps.trees(self, placements)
	for i in 30:
		var a2 := rng.randf() * TAU
		var r2 := rng.randf_range(6.0, 60.0)
		PNProps.bush(self, Vector3(cos(a2) * r2, terrain.height_at(cos(a2) * r2, sin(a2) * r2), sin(a2) * r2), rng.randf_range(0.8, 1.6))
	var player := PNAssets.instance("hero", "hero")
	player.position = Vector3(0, terrain.height_at(0, 0), 0)
	add_child(player)
	PNWind.track(player)
	var cam := Camera3D.new()
	cam.far = 1200.0
	cam.fov = 68.0
	cam.position = Vector3(-3.2, terrain.height_at(0, 0) + 2.1, 6.5)
	add_child(cam)
	cam.look_at(Vector3(2.0, terrain.height_at(0, 0) + 2.6, -14.0))
	var opts := {"height_fn": func(x, z): return terrain.height_at(x, z), "seed": 21}
	if _arg("--nomist", "") != "":
		opts["no_mist"] = true
	var tod := _arg("--tod", "")
	if tod != "":
		opts["time_of_day"] = tod
	var rich := PNRich.build(self, env, sun, player, Rect2(-110, -110, 220, 220), opts)
	await get_tree().create_timer(secs).timeout
	if out != "":
		var img := get_viewport().get_texture().get_image()
		img.save_png(out)
		print("[rich-demo] saved ", out, " ", img.get_size())
	print("[rich-demo] report ", JSON.stringify(PNRich.last_report))
	get_tree().quit()
