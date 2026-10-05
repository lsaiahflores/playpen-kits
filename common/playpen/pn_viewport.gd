class_name PNViewport
extends Node
## Playpen kit: renders the 3D world at a quality-scaled resolution while the UI
## stays razor sharp. The Compatibility renderer ignores `scaling_3d_scale`, and on
## an 8GB / integrated-GPU laptop the game is FILL-RATE bound (measured: the same
## scene ran ~20 FPS at 1280x720 and a locked 60 at 640x360), so the world lives in a
## SubViewport whose size follows PNSettings.render_scale() (Low 0.6, Medium 0.8,
## High 1.0) and is shown full-window behind the HUD/menus.
##
##   var vp := PNViewport.new(); add_child(vp)
##   var world := vp.world          # put your whole 3D level under this node
##
## Everything that spawns 3D things at runtime (Juice, PNAudio) asks
## PNViewport.world_root() for the right parent, so particles / popups / 3D sounds
## land in the world the camera is actually looking at.

static var _current: PNViewport

var world: Node3D
var sub: SubViewport
var _rect: TextureRect
var _layer: CanvasLayer

static func world_root() -> Node:
	if _current and is_instance_valid(_current) and _current.world:
		return _current.world
	return null

static func active_camera() -> Camera3D:
	if _current and is_instance_valid(_current) and _current.sub:
		return _current.sub.get_camera_3d()
	return null

func _ready() -> void:
	_current = self
	var scale_f := PNSettings.render_scale()
	if scale_f >= 0.99:
		# High quality: no indirection — the world is simply a node in the main scene.
		world = Node3D.new()
		world.name = "World"
		add_child(world)
		return
	_layer = CanvasLayer.new()
	_layer.layer = -10          # behind every HUD / menu layer
	add_child(_layer)
	_rect = TextureRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_layer.add_child(_rect)
	sub = SubViewport.new()
	sub.name = "WorldViewport"
	sub.handle_input_locally = true
	sub.audio_listener_enable_3d = true
	sub.msaa_3d = Viewport.MSAA_DISABLED
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sub)
	_rect.texture = sub.get_texture()
	world = Node3D.new()
	world.name = "World"
	sub.add_child(world)
	_resize()
	get_window().size_changed.connect(_resize)
	PNSettings.quality_changed.connect(func(_q): _resize())

func _resize() -> void:
	if sub == null:
		return
	var win := Vector2(get_window().size)
	var f := PNSettings.render_scale()
	sub.size = Vector2i(maxi(int(win.x * f), 320), maxi(int(win.y * f), 180))

# Events must reach nodes inside the SubViewport (the follow camera's mouse look).
func _input(event: InputEvent) -> void:
	if sub:
		sub.push_input(event, true)
