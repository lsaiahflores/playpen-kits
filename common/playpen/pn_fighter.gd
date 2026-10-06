class_name PNFighter
extends CharacterBody3D
## Playpen kit: the base for ANYTHING that can be shot (the player and the bots). Health + a recharging shield, team,
## kills/deaths, a damage entry point every weapon calls, and respawn. Shooter kits (FPS arena / third-person) build on it.
##
##   fighter.take_damage(amount, attacker, hit_position, headshot) -> true when that shot killed it

signal died(fighter: PNFighter, attacker: Node)
signal damaged(amount: float, attacker: Node, from_dir: Vector3)
signal health_changed(health: float, shield: float)

@export var team := 0
@export var max_health := 100.0
@export var max_shield := 50.0
@export var shield_delay := 4.0
@export var shield_regen := 30.0

var health := 100.0
var shield := 50.0
var alive := true
var display_name := "Fighter"
var kills := 0
var deaths := 0
var model_height := 1.8
var _shield_wait := 0.0

func _ready() -> void:
	add_to_group("fighter")
	health = max_health
	shield = max_shield

func take_damage(amount: float, attacker: Node = null, _hit_pos := Vector3.ZERO, headshot := false) -> bool:
	if not alive:
		return false
	_shield_wait = shield_delay
	var dmg := amount * (1.5 if headshot else 1.0)
	if shield > 0.0:
		var absorbed := minf(shield, dmg)
		shield -= absorbed
		dmg -= absorbed
	health -= dmg
	var from_dir := Vector3.ZERO
	if attacker is Node3D:
		from_dir = ((attacker as Node3D).global_position - global_position).normalized()
	damaged.emit(amount, attacker, from_dir)
	health_changed.emit(health, shield)
	if health <= 0.0:
		_die(attacker)
		return true
	return false

func _die(attacker: Node) -> void:
	alive = false
	health = 0.0
	deaths += 1
	if attacker is PNFighter and attacker != self:
		(attacker as PNFighter).kills += 1
	died.emit(self, attacker)

func respawn_at(pos: Vector3) -> void:
	alive = true
	health = max_health
	shield = max_shield
	velocity = Vector3.ZERO
	global_position = pos
	health_changed.emit(health, shield)

func heal(amount: float) -> void:
	health = minf(max_health, health + amount)
	health_changed.emit(health, shield)

func head_height() -> float:
	return global_position.y + model_height * 0.85

func _process(delta: float) -> void:
	if not alive or shield >= max_shield:
		return
	_shield_wait -= delta
	if _shield_wait <= 0.0:
		shield = minf(max_shield, shield + shield_regen * delta)
		health_changed.emit(health, shield)
