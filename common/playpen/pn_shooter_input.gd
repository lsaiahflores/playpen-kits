class_name PNShooterInput
extends RefCounted
## Playpen kit: the extra controls a shooter needs on top of InputSetup — Xbox AND keyboard/mouse, both fully bound.
##   fire = RT / left mouse      aim = LT / right mouse     reload = X / R
##   sprint = L3 / Shift         crouch = B / Ctrl          weapon_next/prev = RB / LB (or the mouse wheel)
##   scoreboard = Back / Tab     weapon_1..4 = 1..4
## Call PNShooterInput.setup() once at startup (idempotent).

static func setup() -> void:
	_action("fire", [_mouse(MOUSE_BUTTON_LEFT), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_action("aim", [_mouse(MOUSE_BUTTON_RIGHT), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)])
	_action("reload", [_key(KEY_R), _btn(JOY_BUTTON_X)])
	_action("sprint", [_key(KEY_SHIFT), _btn(JOY_BUTTON_LEFT_STICK)])
	_action("crouch", [_key(KEY_CTRL), _key(KEY_C), _btn(JOY_BUTTON_B)])
	_action("weapon_next", [_mouse(MOUSE_BUTTON_WHEEL_UP), _btn(JOY_BUTTON_RIGHT_SHOULDER), _key(KEY_E)])
	_action("weapon_prev", [_mouse(MOUSE_BUTTON_WHEEL_DOWN), _btn(JOY_BUTTON_LEFT_SHOULDER), _key(KEY_Q)])
	_action("scoreboard", [_key(KEY_TAB), _btn(JOY_BUTTON_BACK)])
	for i in 4:
		_action("weapon_%d" % (i + 1), [_key(KEY_1 + i)])

static func _action(name: String, events: Array) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name, 0.3)
		for e in events:
			InputMap.action_add_event(name, e)

static func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code as Key
	return e

static func _mouse(btn: int) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = btn as MouseButton
	return e

static func _btn(b: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b as JoyButton
	return e

static func _axis(a: int, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = a as JoyAxis
	e.axis_value = v
	return e
