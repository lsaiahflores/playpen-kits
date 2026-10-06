class_name PNMatch
extends Node
## Playpen kit: MATCH FLOW for shooters — teams, score limit, time limit, spawn points, respawns, a kill feed, a scoreboard,
## and match start / end. It owns the rules; the level just registers fighters and spawn points.
##
##   var m := PNMatch.new()
##   m.team_names = {1: "Blue", 2: "Red"}
##   m.score_limit = 15
##   add_child(m)
##   m.add_spawn(1, Vector3(...))                       # per team
##   m.register(player); m.register(bot)               # fighters (their died signal is connected for you)
##   m.start()
##   m.kill_feed.connect(func(text, killer_team): hud.feed(text, killer_team))
##   m.match_ended.connect(func(winner_team, scores): hud.show_end(winner_team))

signal kill_feed(text: String, killer_team: int)
signal score_changed(scores: Dictionary)
signal time_changed(seconds_left: int)
signal match_started
signal match_ended(winner_team: int, scores: Dictionary)
signal fighter_respawned(f: PNFighter)

@export var score_limit := 15
@export var time_limit := 300.0
@export var respawn_time := 3.0
var team_names := {1: "Blue", 2: "Red"}
var scores := {}
var running := false
var _time_left := 0.0
var _spawns := {}      # team -> Array[Vector3]
var _fighters: Array = []
var _last_sec := -1

func add_spawn(team: int, pos: Vector3) -> void:
	if not _spawns.has(team):
		_spawns[team] = []
	_spawns[team].append(pos)

func register(f: PNFighter) -> void:
	if f in _fighters:
		return
	_fighters.append(f)
	if not scores.has(f.team):
		scores[f.team] = 0
	f.died.connect(_on_died)
	if f is PNBot:
		(f as PNBot).wants_respawn.connect(func(b: PNBot): _respawn(b))

func fighters() -> Array:
	return _fighters

func start() -> void:
	for t in scores:
		scores[t] = 0
	for f in _fighters:
		(f as PNFighter).kills = 0
		(f as PNFighter).deaths = 0
		_respawn(f)
	_time_left = time_limit
	running = true
	score_changed.emit(scores)
	match_started.emit()

func spawn_point_for(f: PNFighter) -> Vector3:
	var pts: Array = _spawns.get(f.team, [])
	if pts.is_empty():
		for k in _spawns:
			pts.append_array(_spawns[k])
	if pts.is_empty():
		return Vector3.ZERO
	# prefer the spawn point farthest from enemies
	var best: Vector3 = pts[0]
	var best_score := -1.0
	for p in pts:
		var nearest := 1e9
		for o in _fighters:
			var of := o as PNFighter
			if of == f or not of.alive or (f.team != 0 and of.team == f.team):
				continue
			nearest = minf(nearest, (p as Vector3).distance_to(of.global_position))
		var sc := nearest + randf() * 6.0
		if sc > best_score:
			best_score = sc
			best = p
	return best

func _respawn(f: PNFighter) -> void:
	if not running and scores.size() > 0 and _time_left <= 0.0 and f.deaths > 0:
		return
	f.respawn_at(spawn_point_for(f))
	fighter_respawned.emit(f)

func _on_died(victim: PNFighter, attacker: Node) -> void:
	if not running:
		return
	var killer := attacker as PNFighter
	var text := "%s was eliminated" % victim.display_name
	var kt := 0
	if killer and killer != victim:
		text = "%s  >  %s" % [killer.display_name, victim.display_name]
		kt = killer.team
		scores[killer.team] = int(scores.get(killer.team, 0)) + 1
		if killer.is_in_group("local_player"):
			PNAudio.stinger("kill")
	else:
		scores[victim.team] = maxi(0, int(scores.get(victim.team, 0)) - 1)
	kill_feed.emit(text, kt)
	score_changed.emit(scores)
	if victim is PNBot:
		pass   # bots ask to respawn themselves when their death animation finishes
	else:
		get_tree().create_timer(respawn_time).timeout.connect(func(): if running: _respawn(victim))
	for t in scores:
		if int(scores[t]) >= score_limit:
			_end(int(t))
			return

func _process(delta: float) -> void:
	if not running:
		return
	_time_left -= delta
	var sec := maxi(0, int(ceil(_time_left)))
	if sec != _last_sec:
		_last_sec = sec
		time_changed.emit(sec)
	if _time_left <= 0.0:
		var best := 0
		var best_s := -1
		var tie := false
		for t in scores:
			if int(scores[t]) > best_s:
				best_s = int(scores[t])
				best = int(t)
				tie = false
			elif int(scores[t]) == best_s:
				tie = true
		_end(0 if tie else best)

func _end(winner: int) -> void:
	running = false
	match_ended.emit(winner, scores)

## Sorted rows for a scoreboard: [{name, team, kills, deaths}]
func scoreboard() -> Array:
	var rows: Array = []
	for f in _fighters:
		var pf := f as PNFighter
		rows.append({"name": pf.display_name, "team": pf.team, "kills": pf.kills, "deaths": pf.deaths})
	rows.sort_custom(func(a, b): return a["kills"] > b["kills"])
	return rows
