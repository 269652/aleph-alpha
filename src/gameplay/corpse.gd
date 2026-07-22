extends RefCounted

var position: Vector2
var held_items: Dictionary
var decay_time: float
var elapsed_time: float = 0.0


func _init(p_position: Vector2, p_held_items: Dictionary, p_decay_time: float) -> void:
	position = p_position
	held_items = p_held_items
	decay_time = p_decay_time


func advance(delta: float) -> void:
	elapsed_time += delta


func is_decayed() -> bool:
	return elapsed_time >= decay_time


## Returns a copy of held_items and empties this corpse's loot; decayed corpses grant nothing.
func recover() -> Dictionary:
	if is_decayed():
		return {}
	var recovered: Dictionary = held_items.duplicate()
	held_items.clear()
	return recovered
