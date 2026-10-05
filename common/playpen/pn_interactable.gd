class_name PNInteractable
extends Node3D
## Playpen kit: something the player can interact with (sign, chest, NPC, switch).
## Anything in group "interactable" with `prompt_text` and `interact(player)` is
## picked up by the adventure/platformer controllers: the HUD shows
## "[A] <prompt_text>" while the player is close.
##
##   var chest := PNInteractable.new()
##   chest.prompt_text = "Open"
##   chest.interacted.connect(func(p): ...)

signal interacted(player: Node3D)

@export var prompt_text := "Talk"
@export var one_shot := false
@export var glow_color := Color(1.0, 0.9, 0.5)
var used := false
var _mark: MeshInstance3D

func _ready() -> void:
	add_to_group("interactable")
	# a small floating marker so the player can SEE it is interactive
	_mark = MeshInstance3D.new()
	var d := PrismMesh.new()
	d.size = Vector3(0.28, 0.34, 0.28)
	_mark.mesh = d
	_mark.rotation.x = PI
	_mark.position = Vector3(0, 2.1, 0)
	_mark.material_override = PNLook.glow_material(glow_color, global_position.x)
	add_child(_mark)

func interact(player: Node3D) -> void:
	if used and one_shot:
		return
	used = true
	Juice.sparkle(global_position + Vector3(0, 1.2, 0), glow_color, 10)
	PNAudio.sfx("interact", 1.0, -4.0)
	interacted.emit(player)
	if one_shot:
		remove_from_group("interactable")
		_mark.visible = false
