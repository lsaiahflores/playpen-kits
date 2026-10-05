extends Node
## Playpen kit: ONE global wind value (autoload "PNWind").
## Foliage, flags, banners and signs read `pn_wind_strength` / `pn_wind_dir` as
## global shader uniforms (declared in project.godot [shader_globals]); gusts
## ride on top and also fire the `gust` signal so leaves / paper can blow.

signal gust(strength: float)

@export var base_strength := 0.5          # the look pack sets this
@export var gust_every := Vector2(7.0, 16.0)
var strength := 0.5
var direction := Vector2(1.0, 0.35).normalized()
var _t := 0.0
var _gust := 0.0
var _next_gust := 6.0
var _noise := FastNoiseLite.new()
var player: Node3D = null   # grass/foliage bends away from this node

## Tell the wind system who to bend foliage away from.
func track(node: Node3D) -> void:
	player = node

func _ready() -> void:
	_noise.seed = 7
	_noise.frequency = 0.15
	_next_gust = randf_range(gust_every.x, gust_every.y)

func _process(delta: float) -> void:
	_t += delta
	_gust = maxf(0.0, _gust - delta * 0.5)
	_next_gust -= delta
	if _next_gust <= 0.0:
		_next_gust = randf_range(gust_every.x, gust_every.y)
		_gust = randf_range(0.6, 1.0)
		gust.emit(_gust)
	var breeze := 0.75 + 0.25 * _noise.get_noise_1d(_t * 10.0)
	strength = clampf(base_strength * breeze + _gust * 0.6, 0.0, 2.0)
	direction = direction.rotated(delta * 0.02 * _noise.get_noise_1d(_t * 3.0 + 50.0)).normalized()
	RenderingServer.global_shader_parameter_set("pn_wind_strength", strength)
	RenderingServer.global_shader_parameter_set("pn_wind_dir", direction)
	if player and is_instance_valid(player):
		RenderingServer.global_shader_parameter_set("pn_player_pos", player.global_position)

func configure(look: Dictionary) -> void:
	base_strength = float(look.get("ambient", {}).get("wind", base_strength))
