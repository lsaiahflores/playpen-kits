class_name PNHud
extends CanvasLayer
## Playpen kit: HUD scaffold — counter, toasts, controller-aware button prompts,
## hearts, a timer/lap readout, and the minimap slot. All themed from the look pack.
##
##   var hud := PNHud.new(); add_child(hud)
##   hud.set_counter("Litter", 3, 20)
##   hud.set_prompt("interact", "Talk")      # shows "[A] Talk" on a pad, "[E] Talk" on keyboard
##   hud.toast("Checkpoint!")
##   hud.add_minimap(player, camera_pivot, city_map, {"collectible": Color(1, .85, .2)})

var _counter: Label
var _prompt: Label
var _toast: Label
var _hearts: HBoxContainer
var _timer: Label
var _extra: Label
var _prompt_action := ""
var _prompt_text := ""
var _toast_tween: Tween
var _minimap: PNMinimap

func _ready() -> void:
	layer = 20
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var accent := Color(str(PNLook.look.get("ui", {}).get("accent", "#ffcf40")))
	# top-left: counter + hearts
	var tl := VBoxContainer.new()
	tl.position = Vector2(24, 16)
	tl.add_theme_constant_override("separation", 2)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tl)
	_counter = _label(tl, 34, accent)
	_hearts = HBoxContainer.new()
	_hearts.add_theme_constant_override("separation", 4)
	tl.add_child(_hearts)
	# top-centre: timer + extra line (a fixed-width, centred column)
	var tc := _centered(root, 360.0, 14.0, true)
	_timer = _label(tc, 38, Color.WHITE)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_extra = _label(tc, 26, Color(1, 1, 1, 0.9))
	_extra.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# bottom-centre: button prompt
	var bc := _centered(root, 520.0, 84.0, false)
	_prompt = _label(bc, 30, Color.WHITE)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# middle: toast
	var mc := _centered(root, 760.0, 0.0, true)
	mc.anchor_top = 0.28
	mc.anchor_bottom = 0.28
	_toast = _label(mc, 56, accent)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	InputSetup.device_changed.connect(func(_pad): _refresh_prompt())

## A fixed-width column pinned to the horizontal centre of the screen.
func _centered(root: Control, width: float, margin: float, from_top: bool) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.offset_left = -width * 0.5
	box.offset_right = width * 0.5
	if from_top:
		box.anchor_top = 0.0
		box.anchor_bottom = 0.0
		box.offset_top = margin
	else:
		box.anchor_top = 1.0
		box.anchor_bottom = 1.0
		box.offset_top = -margin - 40.0
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(box)
	return box

func _label(parent: Control, size_px: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func set_counter(label: String, value: int, total := -1) -> void:
	_counter.text = "%s  %d%s" % [label, value, ("/" + str(total)) if total >= 0 else ""]
	_counter.pivot_offset = _counter.size * 0.5
	var tw := create_tween()
	_counter.scale = Vector2(1.25, 1.25)
	tw.tween_property(_counter, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func set_timer(text: String) -> void:
	_timer.text = text

func set_extra(text: String) -> void:
	_extra.text = text

func toast(text: String, seconds := 1.6) -> void:
	_toast.text = text
	_toast.pivot_offset = _toast.size * 0.5
	if _toast_tween:
		_toast_tween.kill()
	_toast.scale = Vector2(0.7, 0.7)
	_toast.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.15)
	_toast_tween.parallel().tween_property(_toast, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)

## "interact"/"jump"/... + what it does. Empty text hides the prompt.
func set_prompt(action: String, text: String) -> void:
	_prompt_action = action
	_prompt_text = text
	_refresh_prompt()

func _refresh_prompt() -> void:
	if _prompt_text == "":
		_prompt.text = ""
		return
	_prompt.text = "[%s]  %s" % [InputSetup.prompt(_prompt_action), _prompt_text]

func set_hearts(current: float, maximum: int) -> void:
	for c in _hearts.get_children():
		c.queue_free()
	for i in maximum:
		var l := Label.new()
		var full := current - i
		l.text = "♥" if full >= 1.0 else ("♡" if full <= 0.0 else "♥")
		l.add_theme_font_size_override("font_size", 40)
		l.add_theme_color_override("font_color", Color(1, 0.3, 0.4) if full > 0.0 else Color(1, 1, 1, 0.35))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("outline_size", 6)
		_hearts.add_child(l)

func add_minimap(player: Node3D, camera_node: Node3D, map_data: Dictionary, groups := {}) -> PNMinimap:
	_minimap = PNMinimap.new()
	add_child(_minimap)
	_minimap.setup(player, camera_node, map_data, groups)
	_minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_minimap.position = Vector2(-_minimap.diameter - 24, 24) + Vector2(get_viewport().get_visible_rect().size.x, 0)
	get_viewport().size_changed.connect(func():
		if _minimap:
			_minimap.position = Vector2(get_viewport().get_visible_rect().size.x - _minimap.diameter - 24, 24))
	return _minimap
