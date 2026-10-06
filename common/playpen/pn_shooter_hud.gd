class_name PNShooterHud
extends CanvasLayer
## Playpen kit: the SHOOTER HUD — crosshair that opens with movement/recoil, hit markers, health + shield, ammo, kill feed,
## team score + timer, a scoreboard (hold Tab / Back), damage flash, toasts, and the end-of-match screen.
##
## All text is plain Labels in a Theme-free layout so it stays readable on any look pack; colors come from PNLook.

signal play_again

var _cross: Control
var _marker: Control
var _health: ProgressBar
var _shield: ProgressBar
var _ammo: Label
var _weapon_name: Label
var _score: Label
var _timer: Label
var _feed: VBoxContainer
var _flash: ColorRect
var _toast: Label
var _board: PanelContainer
var _board_rows: VBoxContainer
var _end: PanelContainer
var _end_label: Label
var _spread := 0.0
var _marker_t := 0.0
var _feed_items: Array = []
var match_ref: PNMatch
var team_names := {1: "Blue", 2: "Red"}
var team_colors := {1: Color(0.3, 0.55, 1.0), 2: Color(1.0, 0.4, 0.35), 0: Color(1, 1, 1)}

func _ready() -> void:
	layer = 20
	_build()

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 0.1, 0.1, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)
	_cross = Control.new()
	_cross.set_anchors_preset(Control.PRESET_CENTER)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.draw.connect(_draw_cross)
	root.add_child(_cross)
	_marker = Control.new()
	_marker.set_anchors_preset(Control.PRESET_CENTER)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.draw.connect(_draw_marker)
	root.add_child(_marker)
	# bottom-left: health + shield
	var bl := VBoxContainer.new()
	bl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bl.position = Vector2(24, -86)
	bl.custom_minimum_size = Vector2(260, 0)
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bl)
	_shield = _bar(bl, Color(0.35, 0.8, 1.0), 10)
	_health = _bar(bl, Color(0.4, 0.95, 0.5), 14)
	# bottom-right: ammo
	var br := VBoxContainer.new()
	br.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	br.position = Vector2(-220, -96)
	br.custom_minimum_size = Vector2(190, 0)
	br.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(br)
	_ammo = _label(br, 34, HORIZONTAL_ALIGNMENT_RIGHT)
	_weapon_name = _label(br, 14, HORIZONTAL_ALIGNMENT_RIGHT)
	# top-center: score + timer
	var tc := VBoxContainer.new()
	tc.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tc.position = Vector2(-150, 12)
	tc.custom_minimum_size = Vector2(300, 0)
	tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tc)
	_score = _label(tc, 26, HORIZONTAL_ALIGNMENT_CENTER)
	_timer = _label(tc, 16, HORIZONTAL_ALIGNMENT_CENTER)
	# top-right: kill feed
	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed.position = Vector2(-330, 14)
	_feed.custom_minimum_size = Vector2(310, 0)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_feed)
	# toast
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER)
	_toast.position = Vector2(-300, -130)
	_toast.custom_minimum_size = Vector2(600, 0)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 28)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast)
	# scoreboard (hold)
	_board = PanelContainer.new()
	_board.set_anchors_preset(Control.PRESET_CENTER)
	_board.position = Vector2(-260, -170)
	_board.custom_minimum_size = Vector2(520, 0)
	_board.visible = false
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_rows = VBoxContainer.new()
	_board.add_child(_board_rows)
	root.add_child(_board)
	# end screen
	_end = PanelContainer.new()
	_end.set_anchors_preset(Control.PRESET_CENTER)
	_end.position = Vector2(-240, -90)
	_end.custom_minimum_size = Vector2(480, 0)
	_end.visible = false
	var ev := VBoxContainer.new()
	_end.add_child(ev)
	_end_label = _label(ev, 40, HORIZONTAL_ALIGNMENT_CENTER)
	var again := Button.new()
	again.text = "Play again"
	again.name = "PlayAgain"
	again.custom_minimum_size = Vector2(0, 46)
	again.pressed.connect(func(): play_again.emit())
	ev.add_child(again)
	root.add_child(_end)

func _bar(parent: Control, color: Color, h: int) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(260, h)
	b.max_value = 100
	b.value = 100
	b.show_percentage = false
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(4)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(4)
	b.add_theme_stylebox_override("fill", fg)
	b.add_theme_stylebox_override("background", bg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(b)
	return b

func _label(parent: Control, size_px: int, align: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = align as HorizontalAlignment
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _draw_cross() -> void:
	var gap := 6.0 + _spread * 30.0
	var col := Color(1, 1, 1, 0.9)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		_cross.draw_line(d * gap, d * (gap + 9.0), col, 2.5)
	_cross.draw_circle(Vector2.ZERO, 1.5, col)

func _draw_marker() -> void:
	if _marker_t <= 0.0:
		return
	var a := clampf(_marker_t / 0.25, 0.0, 1.0)
	var col := Color(1, 0.25, 0.2, a) if _marker.get_meta("kill", false) else Color(1, 1, 1, a)
	for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		_marker.draw_line(d * 8.0, d * 15.0, col, 3.0)

func _process(delta: float) -> void:
	if _marker_t > 0.0:
		_marker_t -= delta
		_marker.queue_redraw()
	_spread = move_toward(_spread, 0.0, delta * 2.0)
	_cross.queue_redraw()
	if _flash.color.a > 0.0:
		_flash.color.a = maxf(0.0, _flash.color.a - delta * 1.8)
	var show_board := Input.is_action_pressed("scoreboard")
	if show_board != _board.visible:
		_board.visible = show_board
		if show_board:
			refresh_board()

func kick_crosshair(amount := 0.35) -> void:
	_spread = clampf(_spread + amount, 0.0, 1.0)

func set_spread(v: float) -> void:
	_spread = maxf(_spread, v)

func hit_marker(killed := false, _headshot := false) -> void:
	_marker.set_meta("kill", killed)
	_marker_t = 0.25
	PNAudio.sfx("hit_marker", 1.4 if killed else 1.0, -5.0, "UI")

func set_health(h: float, s: float, max_h := 100.0, max_s := 50.0) -> void:
	_health.max_value = max_h
	_health.value = maxf(0.0, h)
	_shield.max_value = max_s
	_shield.value = maxf(0.0, s)

func damage_flash(strength := 0.35) -> void:
	_flash.color.a = clampf(strength, 0.0, 0.7)

func set_ammo(mag: int, reserve: int, reloading: bool, weapon_name := "") -> void:
	_ammo.text = "RELOAD" if reloading else "%d / %d" % [mag, reserve]
	if weapon_name != "":
		_weapon_name.text = weapon_name

func set_score(scores: Dictionary) -> void:
	var parts: PackedStringArray = []
	var keys := scores.keys()
	keys.sort()
	for t in keys:
		parts.append("%s %d" % [str(team_names.get(t, "Team %d" % int(t))), int(scores[t])])
	_score.text = "  -  ".join(parts)

func set_time(seconds: int) -> void:
	_timer.text = "%d:%02d" % [seconds / 60, seconds % 60]

func feed(text: String, team: int) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", team_colors.get(team, Color.WHITE))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.add_child(l)
	_feed_items.append(l)
	if _feed_items.size() > 5:
		var old = _feed_items.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)

func toast(text: String, seconds := 1.8) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(seconds)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.4)

func refresh_board() -> void:
	for c in _board_rows.get_children():
		c.queue_free()
	if match_ref == null:
		return
	var head := _label(_board_rows, 18, HORIZONTAL_ALIGNMENT_LEFT)
	head.text = "Player                 Team      K    D"
	for r in match_ref.scoreboard():
		var l := _label(_board_rows, 17, HORIZONTAL_ALIGNMENT_LEFT)
		l.text = "%-22s %-8s %3d  %3d" % [r["name"], str(team_names.get(r["team"], "-")), r["kills"], r["deaths"]]
		l.add_theme_color_override("font_color", team_colors.get(r["team"], Color.WHITE))

func show_end(winner_team: int, scores: Dictionary) -> void:
	_end.visible = true
	_end_label.text = "Draw" if winner_team == 0 else "%s team wins!" % str(team_names.get(winner_team, "A"))
	var b := _end.find_child("PlayAgain", true, false) as Button
	if b:
		b.grab_focus()

func hide_end() -> void:
	_end.visible = false
