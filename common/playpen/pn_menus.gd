class_name PNMenus
extends CanvasLayer
## Playpen kit: title screen, pause menu (Start / Esc) and settings (volume
## sliders, quality, fullscreen) — themed from the look pack, fully usable with an
## Xbox controller (d-pad / stick + A/B) or keyboard + mouse.
##
##   var menus := PNMenus.new(); add_child(menus)
##   menus.title = "Tiger Cleanup"
##   menus.play_pressed.connect(start_game)
##   menus.show_title()
## While the pause menu is open the tree is paused; menus keep running.

signal play_pressed
signal resumed
signal quit_to_title

var title := "My Game"
var subtitle := "Press A / Enter to start"
var pause_enabled := true
var in_game := false

var _title_root: Control
var _pause_root: Control
var _settings_root: Control
var _theme: Theme

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_theme = _make_theme()
	_build_title()
	_build_pause()
	_build_settings()
	_title_root.visible = false
	_pause_root.visible = false
	_settings_root.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not pause_enabled or not in_game:
		return
	if event.is_action_pressed("pause"):
		if _settings_root.visible:
			_close_settings()
		elif _pause_root.visible:
			resume()
		else:
			pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and _settings_root.visible:
		_close_settings()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- public
func show_title() -> void:
	in_game = false
	get_tree().paused = false
	_pause_root.visible = false
	_settings_root.visible = false
	_title_root.visible = true
	(_title_root.get_node("Center/Panel/Box/Title") as Label).text = title
	(_title_root.get_node("Center/Panel/Box/Subtitle") as Label).text = subtitle
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	PNAudio.set_state("menu")
	Juice.pop_in(_title_root.get_node("Center/Panel"))
	(_title_root.get_node("Center/Panel/Box/Play") as Button).grab_focus()

func start_game() -> void:
	_title_root.visible = false
	in_game = true
	get_tree().paused = false
	PNAudio.set_state("explore")
	PNAudio.ui("confirm")
	play_pressed.emit()

func pause() -> void:
	if get_tree().paused:
		return
	get_tree().paused = true
	_pause_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	PNAudio.duck(-10.0, 0.1, 9999.0)
	Juice.pop_in(_pause_root.get_node("Center/Panel"))
	(_pause_root.get_node("Center/Panel/Box/Resume") as Button).grab_focus()

func resume() -> void:
	_pause_root.visible = false
	_settings_root.visible = false
	get_tree().paused = false
	PNAudio.duck(0.0, 0.2, 0.01)
	resumed.emit()

# ---------------------------------------------------------------- building
func _make_theme() -> Theme:
	var t := Theme.new()
	var corner := int(PNLook.look.get("ui", {}).get("corner", 12))
	var accent := Color(str(PNLook.look.get("ui", {}).get("accent", "#ffcf40")))
	var bg := PNLook.color("ui_bg", Color(0.08, 0.15, 0.25))
	var fg := PNLook.color("ui_fg", Color.WHITE)
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg.lightened(0.12)
	normal.set_corner_radius_all(corner)
	normal.set_content_margin_all(12)
	normal.border_color = accent.darkened(0.2)
	normal.set_border_width_all(2)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = accent
	hover.border_color = accent.lightened(0.3)
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = accent.darkened(0.15)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("focus", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_color("font_color", "Button", fg)
	t.set_color("font_hover_color", "Button", bg)
	t.set_color("font_focus_color", "Button", bg)
	t.set_color("font_pressed_color", "Button", bg)
	t.set_font_size("font_size", "Button", 26)
	t.set_color("font_color", "Label", fg)
	t.set_font_size("font_size", "Label", 24)
	return t

func _panel(parent: Control, width := 460.0) -> VBoxContainer:
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(PNLook.color("ui_bg", Color(0.08, 0.15, 0.25)), 0.92)
	sb.set_corner_radius_all(int(PNLook.look.get("ui", {}).get("corner", 12)) + 8)
	sb.set_content_margin_all(28)
	sb.shadow_size = 18
	sb.shadow_color = Color(0, 0, 0, 0.45)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(width, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	return box

func _button(box: Container, text: String, node_name: String, cb: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func():
		PNAudio.ui("click")
		cb.call())
	b.focus_entered.connect(func(): PNAudio.ui("hover"))
	box.add_child(b)
	return b

func _build_title() -> void:
	_title_root = Control.new()
	_title_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_root.theme = _theme
	_title_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_root)
	var box := _panel(_title_root, 520.0)
	var t := Label.new()
	t.name = "Title"
	t.text = title
	t.add_theme_font_size_override("font_size", 52)
	t.add_theme_color_override("font_color", Color(str(PNLook.look.get("ui", {}).get("accent", "#ffcf40"))))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var s := Label.new()
	s.name = "Subtitle"
	s.text = subtitle
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.modulate = Color(1, 1, 1, 0.75)
	box.add_child(s)
	_button(box, "Play", "Play", start_game)
	_button(box, "Settings", "Settings", _open_settings.bind(_title_root))
	_button(box, "Quit", "Quit", func(): get_tree().quit())

func _build_pause() -> void:
	_pause_root = ColorRect.new()
	(_pause_root as ColorRect).color = Color(0, 0, 0, 0.45)
	_pause_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_root.theme = _theme
	add_child(_pause_root)
	var box := _panel(_pause_root, 420.0)
	var t := Label.new()
	t.text = "Paused"
	t.add_theme_font_size_override("font_size", 40)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	_button(box, "Resume", "Resume", resume)
	_button(box, "Settings", "Settings", _open_settings.bind(_pause_root))
	_button(box, "Quit to title", "QuitTitle", func():
		resume()
		quit_to_title.emit()
		show_title())

var _settings_return: Control

func _open_settings(from: Control) -> void:
	_settings_return = from
	from.visible = false
	_settings_root.visible = true
	Juice.pop_in(_settings_root.get_node("Center/Panel"))
	(_settings_root.get_node("Center/Panel/Box/Back") as Button).grab_focus()

func _close_settings() -> void:
	_settings_root.visible = false
	if _settings_return:
		_settings_return.visible = true
		var first := _settings_return.get_node_or_null("Center/Panel/Box/Settings") as Control
		if first:
			first.grab_focus()
	PNSettings.save()

func _build_settings() -> void:
	_settings_root = ColorRect.new()
	(_settings_root as ColorRect).color = Color(0, 0, 0, 0.55)
	_settings_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_root.theme = _theme
	add_child(_settings_root)
	var box := _panel(_settings_root, 560.0)
	var t := Label.new()
	t.text = "Settings"
	t.add_theme_font_size_override("font_size", 40)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	for bus in PNSettings.BUS_NAMES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var l := Label.new()
		l.text = bus
		l.custom_minimum_size = Vector2(130, 0)
		row.add_child(l)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = PNSettings.volumes.get(bus, 1.0)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.custom_minimum_size = Vector2(240, 28)
		sl.focus_mode = Control.FOCUS_ALL
		sl.value_changed.connect(func(v): PNSettings.set_volume(bus, v))
		row.add_child(sl)
		box.add_child(row)
	var qrow := HBoxContainer.new()
	var ql := Label.new()
	ql.text = "Quality"
	ql.custom_minimum_size = Vector2(130, 0)
	qrow.add_child(ql)
	var ob := OptionButton.new()
	ob.add_item("Low", 0)
	ob.add_item("Medium", 1)
	ob.add_item("High", 2)
	ob.selected = PNSettings.quality
	ob.focus_mode = Control.FOCUS_ALL
	ob.item_selected.connect(func(i): PNSettings.set_quality(i))
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qrow.add_child(ob)
	box.add_child(qrow)
	var fs := CheckButton.new()
	fs.text = "Fullscreen"
	fs.button_pressed = PNSettings.fullscreen
	fs.focus_mode = Control.FOCUS_ALL
	fs.toggled.connect(func(on): PNSettings.set_fullscreen(on))
	box.add_child(fs)
	_button(box, "Back", "Back", _close_settings)
