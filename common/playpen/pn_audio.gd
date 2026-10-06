extends Node
## Playpen kit: audio (autoload "PNAudio") — buses, adaptive music, musical SFX.
##
##  Buses:    Master (compressor + limiter) / Music / SFX / Ambience / UI
##  Music:    each area track is STEMS (base, rhythm, melody, intensity) that fade
##            in/out with game state — explore / danger / underwater / indoor / boss —
##            and crossfade between areas. Stems live in res://audio/music/<track>/
##            (rendered by Playpen from MIDI with real instruments).
##  Stingers: pickup, checkpoint, victory, game_over — res://audio/stingers/<name>.*
##  Musical SFX: pickup() plays in the CURRENT track's key and climbs the scale on
##            combos, so effects and music sound like one piece.
##  Fallback: if no rendered stems exist yet, a small built-in synth keeps the game
##            from being silent (never the final sound — Playpen renders real music).

signal state_changed(state: String)

const STEMS := ["base", "rhythm", "melody", "intensity"]
const SILENT := -80.0
const MUSIC_STATES := {
	"explore":    {"base": 0.0, "rhythm": 0.0, "melody": -3.0, "intensity": SILENT},
	"danger":     {"base": 0.0, "rhythm": 0.0, "melody": -6.0, "intensity": -1.0},
	"boss":       {"base": 0.0, "rhythm": 0.0, "melody": 0.0, "intensity": 0.0},
	"underwater": {"base": -4.0, "rhythm": SILENT, "melody": -9.0, "intensity": SILENT},
	"indoor":     {"base": -2.0, "rhythm": -8.0, "melody": -5.0, "intensity": SILENT},
	"menu":       {"base": -2.0, "rhythm": SILENT, "melody": -2.0, "intensity": SILENT},
	"silent":     {"base": SILENT, "rhythm": SILENT, "melody": SILENT, "intensity": SILENT},
}
const SCALES := {
	"major": [0, 2, 4, 7, 9, 12, 14, 16, 19, 21],
	"minor": [0, 2, 3, 7, 8, 12, 14, 15, 19, 20],
	"dorian": [0, 2, 3, 7, 9, 12, 14, 15, 19, 21],
	"lydian": [0, 2, 4, 6, 7, 11, 12, 14, 16, 18],
}
const KEY_ROOTS := {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}

var key_root := 0
var mood := "sunny"             # the look pack's music mood: picks the fallback library
var scale_name := "major"
var bpm := 110.0
var state := "explore"
var current_track := ""

var _players := {}          # stem -> AudioStreamPlayer (current track)
var _old_players: Array = []
var _bed_players := {}      # name -> AudioStreamPlayer
var _cache := {}
var _duck_tween: Tween
var _space := "open"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	PNSettings.apply()
	# 6.7 AUDIO IS VERIFIED, NOT ASSUMED: every 2s log the loudest peak per bus. playpen-play returns these console lines, so a
	# report can say music / SFX / ambience actually produced sound ("[pn-audio] peaks ..."), or that a bus was silent.
	var t := Timer.new()
	t.wait_time = 2.0
	t.autostart = true
	t.timeout.connect(_log_peaks)
	add_child(t)
	_peak_max = {}

# ---------------------------------------------------------------- audio level verification
var _peak_max := {}
var _peak_ticks := 0

func peak_report() -> Dictionary:
	return _peak_max.duplicate()

func _log_peaks() -> void:
	_peak_ticks += 1
	var parts: PackedStringArray = []
	for b in ["Music", "SFX", "Ambience", "UI"]:
		var i := AudioServer.get_bus_index(b)
		if i < 0:
			continue
		var db := maxf(AudioServer.get_bus_peak_volume_left_db(i, 0), AudioServer.get_bus_peak_volume_right_db(i, 0))
		_peak_max[b] = maxf(float(_peak_max.get(b, -200.0)), db)
		parts.append("%s=%.0fdB(max %.0f)" % [b, db, float(_peak_max[b])])
	print("[pn-audio] peaks ", " ".join(parts), "  silent_buses=", ", ".join(_peak_max.keys().filter(func(k): return float(_peak_max[k]) < -60.0)))

# ---------------------------------------------------------------- buses
func _ensure_buses() -> void:
	for b in ["Music", "SFX", "Ambience", "UI"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")
	var master := 0
	var has_comp := false
	for i in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) is AudioEffectCompressor:
			has_comp = true
	if not has_comp:
		var c := AudioEffectCompressor.new()
		c.threshold = -14.0
		c.ratio = 3.0
		c.attack_us = 20.0
		c.release_ms = 180.0
		c.gain = 2.0
		AudioServer.add_bus_effect(master, c)
		var l := AudioEffectLimiter.new()
		l.ceiling_db = -0.8
		AudioServer.add_bus_effect(master, l)
	# Per-bus tools used by set_space(): a low-pass on Music and a reverb on SFX/Ambience.
	_ensure_fx("Music", AudioEffectLowPassFilter)
	_ensure_fx("SFX", AudioEffectReverb)
	_ensure_fx("Ambience", AudioEffectReverb)
	for b in ["Music", "SFX", "Ambience"]:
		var bi := AudioServer.get_bus_index(b)
		for i in AudioServer.get_bus_effect_count(bi):
			AudioServer.set_bus_effect_enabled(bi, i, false)

func _ensure_fx(bus: String, fx_class) -> void:
	var bi := AudioServer.get_bus_index(bus)
	for i in AudioServer.get_bus_effect_count(bi):
		if is_instance_of(AudioServer.get_bus_effect(bi, i), fx_class):
			return
	AudioServer.add_bus_effect(bi, fx_class.new())

## "open" (fields: dry), "cave" (long echo), "indoor" (short room), "underwater" (muffled).
func set_space(kind: String) -> void:
	_space = kind
	var params: Array = {
		"open": [false, 0.0, 0.0],
		"indoor": [true, 0.35, 0.18],
		"cave": [true, 0.9, 0.38],
		"underwater": [true, 0.6, 0.3],
	}.get(kind, [false, 0.0, 0.0])
	for b in ["SFX", "Ambience"]:
		var bi := AudioServer.get_bus_index(b)
		for i in AudioServer.get_bus_effect_count(bi):
			var fx := AudioServer.get_bus_effect(bi, i)
			if fx is AudioEffectReverb:
				fx.room_size = params[1]
				fx.wet = params[2]
				fx.dry = 1.0
				AudioServer.set_bus_effect_enabled(bi, i, params[0])
	var mi := AudioServer.get_bus_index("Music")
	for i in AudioServer.get_bus_effect_count(mi):
		var fx := AudioServer.get_bus_effect(mi, i)
		if fx is AudioEffectLowPassFilter:
			fx.cutoff_hz = 900.0 if kind == "underwater" else 20000.0
			AudioServer.set_bus_effect_enabled(mi, i, kind == "underwater")
	if kind == "underwater":
		set_state("underwater")
	elif state == "underwater":
		set_state("explore")

# ---------------------------------------------------------------- music
func configure_from_look(look: Dictionary) -> void:
	var a: Dictionary = look.get("audio", {})
	key_root = int(KEY_ROOTS.get(str(a.get("key", "C")), 0))
	scale_name = str(a.get("scale", "major"))
	bpm = float(a.get("bpm", 110))
	mood = str(a.get("mood", "sunny"))
	sfx_palette = str(look.get("sound_palette", ""))
	_variant_count.clear()

## Start an area's music: crossfades from whatever was playing. If the track has
## a track.json (written when Playpen renders it) its key/scale are adopted so
## pickup() stays in tune with it.
func play_track(track: String, fade := 1.6) -> void:
	if track == current_track and not _players.is_empty():
		return
	for p in _players.values():
		_old_players.append(p)
	_players = {}
	current_track = track
	_read_track_meta(track)
	var target: Dictionary = MUSIC_STATES.get(state, MUSIC_STATES["explore"])
	var have_any := false
	for stem in STEMS:
		var stream := _load_stem(track, stem)
		if stream == null:
			continue
		have_any = true
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.stream = stream
		p.volume_db = SILENT
		add_child(p)
		_players[stem] = p
	if not have_any:
		for stem in STEMS:
			var p2 := AudioStreamPlayer.new()
			p2.bus = "Music"
			p2.stream = _fallback_stem(stem)
			p2.volume_db = SILENT
			add_child(p2)
			_players[stem] = p2
	# A rendered track may have an INTRO that plays once before the loop starts.
	var intro := _load_audio("res://audio/music/" + track + "/intro")
	var intro_delay := 0.0
	if intro:
		intro.loop = false if intro is AudioStreamOggVorbis else intro.loop
		var ip := AudioStreamPlayer.new()
		ip.bus = "Music"
		ip.stream = intro
		ip.volume_db = -3.0
		add_child(ip)
		ip.play()
		ip.finished.connect(ip.queue_free)
		intro_delay = intro.get_length() - 0.05
	for p3 in _players.values():
		if intro_delay > 0.0:
			var pp: AudioStreamPlayer = p3
			get_tree().create_timer(intro_delay).timeout.connect(func(): if is_instance_valid(pp): pp.play())
		else:
			p3.play()
	for stem in _players:
		_fade(_players[stem], float(target.get(stem, SILENT)), fade if intro_delay <= 0.0 else 0.2)
	for old in _old_players:
		_fade(old, SILENT, fade, true)
	_old_players.clear()

func set_state(new_state: String, fade := 0.9) -> void:
	if not MUSIC_STATES.has(new_state):
		return
	state = new_state
	var target: Dictionary = MUSIC_STATES[new_state]
	for stem in _players:
		_fade(_players[stem], float(target.get(stem, SILENT)), fade)
	state_changed.emit(new_state)

func stop_music(fade := 1.0) -> void:
	set_state("silent", fade)

func stinger(name: String, duck_db := -9.0) -> void:
	var s := _load_audio("res://audio/stingers/" + name)
	if s == null:
		s = _synth_arp(name)
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.stream = s
	add_child(p)
	p.play()
	duck(duck_db, 0.25, s.get_length() * 0.8 if s.has_method("get_length") else 1.5)
	p.finished.connect(p.queue_free)

# ---------------------------------------------------------------- SFX
## The sound palette (from the look pack's "sound_palette"): a folder res://audio/sfx/<palette>/ of <event>_1..N.wav variants.
var sfx_palette := ""
var _variant_count := {}

## One of the event's variants (random), from the palette folder if present, else the plain file, else a tiny synth.
func _sfx_stream(name: String) -> AudioStream:
	if sfx_palette != "":
		var n: int = _variant_count.get(name, -1)
		if n < 0:
			n = 0
			while ResourceLoader.exists("res://audio/sfx/%s/%s_%d.wav" % [sfx_palette, name, n + 1]) or ResourceLoader.exists("res://audio/sfx/%s/%s_%d.ogg" % [sfx_palette, name, n + 1]):
				n += 1
			_variant_count[name] = n
		if n > 0:
			var v := _load_audio("res://audio/sfx/%s/%s_%d" % [sfx_palette, name, 1 + randi() % n])
			if v != null:
				return v
	var s := _load_audio("res://audio/sfx/" + name)
	if s == null:
		s = _synth_blip(name)
	return s

func sfx(name: String, pitch := 1.0, db := 0.0, bus := "SFX") -> AudioStreamPlayer:
	var s := _sfx_stream(name)
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.stream = s
	p.pitch_scale = pitch
	p.volume_db = db
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
	return p

func sfx_3d(name: String, at: Vector3, pitch := 1.0, db := 0.0) -> AudioStreamPlayer3D:
	var s := _sfx_stream(name)
	pitch *= randf_range(0.96, 1.04)   # variation: no two shots are identical
	var p := AudioStreamPlayer3D.new()
	p.bus = "SFX"
	p.stream = s
	p.pitch_scale = pitch
	p.volume_db = db
	p.unit_size = 6.0
	var root: Node = PNViewport.world_root()
	if root == null:
		root = get_tree().current_scene if get_tree().current_scene else get_tree().root
	root.add_child(p)
	p.global_position = at
	p.play()
	p.finished.connect(p.queue_free)
	return p

func ui(name: String) -> void:
	sfx("ui_" + name, 1.0, -4.0, "UI")

## Pickup in the track's key. `combo` 0,1,2,... climbs the scale; wraps after ~10.
func pickup(combo := 0, at = null) -> void:
	var deg: Array = SCALES.get(scale_name, SCALES["major"])
	var semis := float(deg[combo % deg.size()])
	var root := key_root if key_root <= 6 else key_root - 12
	var pitch := pow(2.0, (root + semis) / 12.0)
	if at is Vector3:
		sfx_3d("pickup", at, pitch, -3.0)
	else:
		sfx("pickup", pitch, -3.0)

## Surface-based footsteps: "grass", "pavement", "wood", "sand", "stone".
func footstep(surface := "grass", at = null) -> void:
	var pitch := randf_range(0.9, 1.1)
	if at is Vector3:
		sfx_3d("step_" + surface, at, pitch, -9.0)
	else:
		sfx("step_" + surface, pitch, -9.0)

## Briefly dip the music under an important sound.
func duck(db := -8.0, attack := 0.15, hold := 0.5) -> void:
	var bi := AudioServer.get_bus_index("Music")
	if _duck_tween:
		_duck_tween.kill()
	var base_db := linear_to_db(maxf(PNSettings.volumes.get("Music", 0.8), 0.001))
	_duck_tween = create_tween()
	_duck_tween.tween_method(func(v): AudioServer.set_bus_volume_db(bi, v), AudioServer.get_bus_volume_db(bi), base_db + db, attack)
	_duck_tween.tween_interval(hold)
	_duck_tween.tween_method(func(v): AudioServer.set_bus_volume_db(bi, v), base_db + db, base_db, 0.6)

# ---------------------------------------------------------------- ambience beds
## Looping area sound bed(s): "wind", "waves", "gulls", "city", "forest", "crickets".
func play_beds(names: Array, fade := 1.5) -> void:
	for n in _bed_players.keys():
		if not names.has(n):
			_fade(_bed_players[n], SILENT, fade, true)
			_bed_players.erase(n)
	for n in names:
		if _bed_players.has(n):
			continue
		var s := _load_audio("res://audio/ambience/" + n)
		if s == null:
			continue
		var p := AudioStreamPlayer.new()
		p.bus = "Ambience"
		p.stream = s
		p.volume_db = SILENT
		add_child(p)
		p.play(randf() * 2.0)
		_bed_players[n] = p
		_fade(p, -6.0 if names.size() > 1 else -3.0, fade)

## A positional source (fountain, radio, crickets): an AudioStreamPlayer3D on `node`.
func attach_positional(node: Node3D, bed: String, radius := 14.0, db := -4.0) -> AudioStreamPlayer3D:
	var s := _load_audio("res://audio/ambience/" + bed)
	if s == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.bus = "Ambience"
	p.stream = s
	p.unit_size = radius * 0.35
	p.max_distance = radius * 2.5
	p.volume_db = db
	p.autoplay = true
	node.add_child(p)
	return p

# ---------------------------------------------------------------- internals
func _fade(p: AudioStreamPlayer, db: float, seconds: float, free_after := false) -> void:
	if not is_instance_valid(p):
		return
	var tw := create_tween()
	tw.tween_property(p, "volume_db", db, maxf(seconds, 0.01))
	if free_after:
		tw.tween_callback(func(): if is_instance_valid(p): p.queue_free())

func _read_track_meta(track: String) -> void:
	for dir in ["res://audio/music/" + track, "res://audio/fallback/" + track, "res://audio/fallback/" + mood]:
		var f := FileAccess.open(dir + "/track.json", FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				key_root = int(KEY_ROOTS.get(str(d.get("key", "C")), key_root))
				scale_name = str(d.get("scale", scale_name))
				bpm = float(d.get("bpm", bpm))
			return

func _load_stem(track: String, stem: String) -> AudioStream:
	# 1) the project's own rendered track  2) a fallback by id  3) the fallback for the look pack's MOOD
	for dir in ["res://audio/music/" + track, "res://audio/fallback/" + track, "res://audio/fallback/" + mood]:
		var s := _load_audio(dir + "/" + stem)
		if s:
			return s
	return null

func _load_audio(path_no_ext: String) -> AudioStream:
	if _cache.has(path_no_ext):
		return _cache[path_no_ext]
	for ext in [".ogg", ".wav"]:
		if ResourceLoader.exists(path_no_ext + ext):
			var s = load(path_no_ext + ext)
			if s is AudioStreamOggVorbis:
				s.loop = true if path_no_ext.contains("/music/") or path_no_ext.contains("/ambience/") or path_no_ext.contains("/fallback/") else false
			elif s is AudioStreamWAV and (path_no_ext.contains("/music/") or path_no_ext.contains("/ambience/") or path_no_ext.contains("/fallback/")):
				s.loop_mode = AudioStreamWAV.LOOP_FORWARD
				s.loop_end = int(s.data.size() / (2 if s.format == AudioStreamWAV.FORMAT_16_BITS else 1) / (2 if s.stereo else 1))
			_cache[path_no_ext] = s
			return s
	_cache[path_no_ext] = null
	return null

# ---- tiny built-in synth: only used when no rendered/fallback audio exists ----
func _wav(samples: PackedFloat32Array, rate := 22050, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32000.0)
		bytes.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w

func _synth_blip(name: String) -> AudioStreamWAV:
	var key := "blip:" + name
	if _cache.has(key):
		return _cache[key]
	var rate := 22050
	var dur := 0.35 if name.contains("pickup") else 0.12
	var f0 := 880.0 if name.contains("pickup") else (220.0 if name.contains("step") else 440.0)
	var n := int(rate * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * (9.0 if name.contains("step") else 7.0))
		var noise := randf_range(-1, 1) if name.contains("step") else 0.0
		var tone := sin(TAU * f0 * t) * 0.5 + sin(TAU * f0 * 2.0 * t) * 0.18
		s[i] = (noise * 0.6 + tone * (0.0 if name.contains("step") else 1.0)) * env * 0.7
	var w := _wav(s, rate)
	_cache[key] = w
	return w

func _synth_arp(name: String) -> AudioStreamWAV:
	var rate := 22050
	var notes := [0, 4, 7, 12] if not name.contains("over") else [7, 3, 0, -5]
	var s := PackedFloat32Array()
	for k in notes.size():
		var f := 523.25 * pow(2.0, (key_root + notes[k]) / 12.0)
		for i in int(rate * 0.16):
			var t := float(i) / rate
			s.append(sin(TAU * f * t) * exp(-t * 6.0) * 0.5)
	return _wav(s, rate)

func _fallback_stem(stem: String) -> AudioStreamWAV:
	var key := "fb:%s:%s:%d" % [stem, scale_name, key_root]
	if _cache.has(key):
		return _cache[key]
	var rate := 22050
	var beat := 60.0 / bpm
	var bars := 4
	var total := int(rate * beat * 4.0 * bars)
	var s := PackedFloat32Array()
	s.resize(total)
	var deg: Array = SCALES.get(scale_name, SCALES["major"])
	var root_f := 130.81 * pow(2.0, key_root / 12.0)
	var progression := [0, 3, 4, 3]
	for bar in bars:
		var chord_root: int = deg[progression[bar] % deg.size()]
		for b in 4:
			var start := int(rate * beat * (bar * 4 + b))
			var len := int(rate * beat)
			for i in len:
				var t := float(i) / rate
				var v := 0.0
				match stem:
					"base":
						var f := root_f * pow(2.0, chord_root / 12.0)
						v = (sin(TAU * f * t) + 0.4 * sin(TAU * f * 1.5 * t)) * 0.22 * minf(1.0, t * 12.0) * (1.0 - 0.15 * float(b))
					"rhythm":
						if b % 2 == 0 and i < rate * 0.07:
							v = randf_range(-1, 1) * exp(-t * 40.0) * 0.3
						elif i < rate * 0.04:
							v = sin(TAU * 60.0 * t) * exp(-t * 30.0) * 0.4
					"melody":
						var step: int = deg[(bar * 3 + b * 2 + (b % 2)) % deg.size()]
						var f2 := root_f * 2.0 * pow(2.0, step / 12.0)
						v = sin(TAU * f2 * t) * 0.18 * exp(-t * 3.0)
					"intensity":
						var f3 := root_f * 4.0 * pow(2.0, deg[(b * 2 + bar) % deg.size()] / 12.0)
						v = (0.08 if sin(TAU * f3 * t) > 0.0 else -0.08) * exp(-t * 5.0)
				if start + i < total:
					s[start + i] += v
	var w := _wav(s, rate, true)
	_cache[key] = w
	return w
