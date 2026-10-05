class_name PNCollectibles
extends Node
## Playpen kit: the collectibles system. Register any Area3D (group "collectible")
## and it handles the whole moment: sparkle, "+1" popup, a pickup sound IN THE
## MUSIC'S KEY that climbs the scale on quick combos, tiny hit-stop, HUD counter,
## and a victory stinger when the last one is gone.
##
##   var col := PNCollectibles.new(); add_child(col)
##   col.collected.connect(func(n, left): hud.set_counter("Litter", n, n + left))
##   for a in get_tree().get_nodes_in_group("collectible"): col.register(a)

signal collected(total: int, remaining: int)
signal all_collected

@export var combo_window := 2.2
var total := 0
var remaining := 0
var combo := 0
var _combo_timer := 0.0

func _process(delta: float) -> void:
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			combo = 0

func register(area: Area3D) -> void:
	remaining += 1
	area.body_entered.connect(func(body: Node3D): _on_entered(area, body))

func _on_entered(area: Area3D, body: Node3D) -> void:
	if not is_instance_valid(area) or not body.is_in_group("player"):
		return
	var at := area.global_position
	area.queue_free()
	total += 1
	remaining = maxi(0, remaining - 1)
	PNAudio.pickup(combo, at)
	combo += 1
	_combo_timer = combo_window
	Juice.sparkle(at, Color(1.0, 0.9, 0.45))
	Juice.popup(at + Vector3(0, 0.6, 0), "+1" if combo < 3 else "x%d" % combo)
	Juice.hit_stop(0.025, 0.2)
	collected.emit(total, remaining)
	if remaining == 0:
		PNAudio.stinger("victory")
		all_collected.emit()
