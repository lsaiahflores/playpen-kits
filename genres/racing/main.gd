extends Node3D
## RACING KIT — an arcade kart race that already feels great: drift + mini-turbo
## boost, a generated closed-loop track with curbs / start arch / grandstand /
## scenery, 3 AI racers with rubber-banding, a 3-2-1-GO countdown, lap + position
## + timer HUD, a minimap of the track, title/pause/settings, and the full ambient
## layer and adaptive music.
##
## CUSTOMIZE `LEVEL` and the look pack. Tune Kart's @exports (speed, grip, drift) —
## don't rewrite the physics.

const LEVEL := {
	"title": "Turbo Tiger Grand Prix",
	"laps": 3,
	"ai": 3,
	"seed": 6,
	"radius": 120.0,
	"road_width": 11.0,
	"player_color": Color(0.95, 0.3, 0.3),
	"driver_color": Color(1.0, 0.62, 0.2),
	"music_track": "area1",
}

var viewport: PNViewport
var world: Node3D
var track: RaceTrack
var race: RaceManager
var player: Kart
var ais: Array[Kart] = []
var cam: ChaseCamera
var hud: PNHud
var menus: PNMenus
var amb: PNAmbient
var env_node: WorldEnvironment
var sun: DirectionalLight3D
var _started := false

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
	Kart.ensure_input()
	track = RaceTrack.build(world, {"seed": LEVEL["seed"], "radius": LEVEL["radius"], "road_width": LEVEL["road_width"]})
	_build_karts()
	_build_systems()
	_build_ui()

func _build_karts() -> void:
	player = Kart.new()
	player.body_color = LEVEL["player_color"]
	player.driver_color = LEVEL["driver_color"]
	player.track = track
	world.add_child(player)
	player.place_at(track.start_transform(0).origin, track.start_transform(0).basis.get_euler().y)
	var palette := [Color(0.25, 0.55, 0.95), Color(0.3, 0.8, 0.45), Color(0.95, 0.75, 0.2), Color(0.7, 0.4, 0.9)]
	for i in int(LEVEL["ai"]):
		var k := Kart.new()
		k.body_color = palette[i % palette.size()]
		k.driver_color = Color.from_hsv(randf(), 0.5, 0.95)
		k.track = track
		world.add_child(k)
		var tf := track.start_transform(i + 1)
		k.place_at(tf.origin, tf.basis.get_euler().y)
		var d := AIDriver.new()
		world.add_child(d)
		d.setup(k, track, player, 0.82 + 0.06 * i, [-0.5, 0.5, 0.0][i % 3])
		ais.append(k)
	cam = ChaseCamera.new()
	world.add_child(cam)
	cam.set_kart(player)

func _build_systems() -> void:
	# RICH + LIVING by default (the track is built ground, so no grass carpet; horizon, sky, life and sound are all on).
	amb = PNRich.build(world, env_node, sun, player, Rect2(-220, -170, 440, 340), {"seed": LEVEL["seed"], "no_grass": true, "no_ground_detail": true}).ambient()
	var all: Array = [player]
	all.append_array(ais)
	race = RaceManager.new()
	add_child(race)
	race.setup(track, all, int(LEVEL["laps"]))
	PNAudio.play_beds(PNLook.look.get("audio", {}).get("beds", []))
	PNAudio.play_track(LEVEL["music_track"])
	PNAudio.set_state("menu")

func _build_ui() -> void:
	hud = PNHud.new()
	add_child(hud)
	var m := hud.add_minimap(player, cam, {"lines": [{"points": track.map_line, "width": 6.0, "color": Color(1, 1, 1, 0.85)}]}, {"kart_ai": Color(1, 0.4, 0.4)})
	m.view_radius = 110.0
	menus = PNMenus.new()
	menus.title = LEVEL["title"]
	menus.subtitle = "Hold A / W to race  -  Shift or RB to drift"
	add_child(menus)
	menus.play_pressed.connect(_begin)
	menus.show_title()
	race.countdown_tick.connect(func(t: String): hud.toast(t, 0.7))
	race.player_finished.connect(func(place: int, total: float, best: float):
		hud.toast("%s place!  %s" % [_ordinal(place), _fmt(total)], 6.0)
		PNAudio.set_state("menu"))
	race.lap_completed.connect(func(k: Kart, lap: int, time: float):
		if not k.is_ai:
			hud.toast("Lap %d  %s" % [lap, _fmt(time)], 1.8))
	player.boosted.connect(func(_s): pass)

func _begin() -> void:
	if _started:
		return
	_started = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	race.start()

func _process(_delta: float) -> void:
	if hud == null or race == null:
		return
	if race.running or race.finished:
		hud.set_counter("Lap", race.lap_of(player), race.total_laps)
		hud.set_timer(_fmt(race.race_time))
		hud.set_extra("%s / %d   %d km/h" % [_ordinal(race.position_of(player)), race.karts.size(), int(absf(player.speed) * 3.2)])

func _fmt(t: float) -> String:
	var m := int(t / 60.0)
	var s := fmod(t, 60.0)
	return "%d:%05.2f" % [m, s]

func _ordinal(n: int) -> String:
	return str(n) + (["th", "st", "nd", "rd"][n] if n in [1, 2, 3] else "th")
