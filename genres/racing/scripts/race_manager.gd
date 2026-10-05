class_name RaceManager
extends Node
## Race flow: 3-2-1-GO countdown, laps through ordered checkpoints (no cutting), lap
## timer + best lap, live race position for every kart, finish and results.
##
##   var race := RaceManager.new(); add_child(race)
##   race.setup(track, [player_kart, ai1, ai2, ai3], 3)
##   race.start()                       # runs the countdown, then unlocks the karts

signal countdown_tick(text: String)
signal lap_completed(kart: Kart, lap: int, time: float)
signal race_finished(results: Array)
signal player_finished(place: int, total_time: float, best_lap: float)

var track: RaceTrack
var karts: Array[Kart] = []
var total_laps := 3
var running := false
var finished := false
var race_time := 0.0

var _state := {}   # kart -> {next_cp, lap, lap_start, best, done, finish_time, progress}

func setup(t: RaceTrack, kart_list: Array, laps := 3) -> void:
	track = t
	total_laps = laps
	karts.clear()
	for k in kart_list:
		karts.append(k)
		_state[k] = {"next_cp": 0, "lap": 1, "lap_start": 0.0, "best": INF, "done": false, "finish_time": 0.0, "progress": 0.0, "cps": 0}
		k.locked = true
	for cp in track.checkpoints:
		cp.body_entered.connect(func(body: Node3D): _on_cp(cp, body))

func start() -> void:
	finished = false
	running = false
	race_time = 0.0
	for s in ["3", "2", "1"]:
		countdown_tick.emit(s)
		PNAudio.sfx("count", 1.0 if s != "1" else 1.2, -3.0)
		await get_tree().create_timer(0.9).timeout
	countdown_tick.emit("GO!")
	PNAudio.sfx("count", 1.6, -2.0)
	PNAudio.stinger("go", -4.0)
	PNAudio.set_state("explore")
	running = true
	for k in karts:
		k.locked = false
		_state[k]["lap_start"] = 0.0

func _process(delta: float) -> void:
	if not running:
		return
	race_time += delta
	for k in karts:
		var s: Dictionary = _state[k]
		if s["done"] or k.sphere == null:
			continue
		var off := track.offset_of(k.global_position)
		# progress = completed laps + checkpoints + fraction along the loop
		s["progress"] = float(s["lap"] - 1) * track.length + off
		s["off"] = off

func _on_cp(cp: Area3D, body: Node3D) -> void:
	if not body.has_meta("kart"):
		return
	var k: Kart = body.get_meta("kart")
	var s: Dictionary = _state.get(k, {})
	if s.is_empty() or s["done"]:
		return
	var idx: int = cp.get_meta("index")
	if idx == s["next_cp"]:
		s["next_cp"] = (idx + 1) % track.checkpoints.size()
		s["cps"] += 1
		k.respawn_pos = cp.global_position - Vector3(0, 1.4, 0)
		k.respawn_yaw = k.yaw
		if idx == 0 and s["cps"] > 1:
			_finish_lap(k, s)

func _finish_lap(k: Kart, s: Dictionary) -> void:
	var lap_time: float = race_time - s["lap_start"]
	s["lap_start"] = race_time
	s["best"] = minf(s["best"], lap_time)
	lap_completed.emit(k, s["lap"], lap_time)
	if s["lap"] >= total_laps:
		s["done"] = true
		s["finish_time"] = race_time
		if not k.is_ai:
			var place := _place_of(k)
			player_finished.emit(place, race_time, s["best"])
			PNAudio.stinger("victory" if place == 1 else "checkpoint")
		_check_all_finished()
	else:
		s["lap"] += 1

func _check_all_finished() -> void:
	var all_done := true
	for k in karts:
		if not _state[k]["done"] and not k.is_ai:
			all_done = false
	if all_done and not finished:
		finished = true
		running = false
		var res := []
		for k in karts:
			res.append({"kart": k, "time": _state[k]["finish_time"], "best": _state[k]["best"]})
		race_finished.emit(res)
		for k in karts:
			if k.is_ai:
				k.throttle_in = 0.0

func lap_of(k: Kart) -> int:
	return mini(_state[k]["lap"], total_laps)

func is_done(k: Kart) -> bool:
	return _state[k]["done"]

func current_lap_time(k: Kart) -> float:
	return race_time - _state[k]["lap_start"]

func best_lap(k: Kart) -> float:
	return _state[k]["best"]

func progress_of(k: Kart) -> float:
	return _state[k].get("progress", 0.0) + (1.0e6 if _state[k]["done"] else 0.0)

## 1-based race position (finished karts rank by finish time, then by progress).
func _place_of(k: Kart) -> int:
	return position_of(k)

func position_of(k: Kart) -> int:
	var place := 1
	var mine := progress_of(k)
	for o in karts:
		if o == k:
			continue
		var os: Dictionary = _state[o]
		var ks: Dictionary = _state[k]
		if os["done"] and ks["done"]:
			if os["finish_time"] < ks["finish_time"]:
				place += 1
		elif os["done"]:
			place += 1
		elif not ks["done"] and progress_of(o) > mine:
			place += 1
	return place
