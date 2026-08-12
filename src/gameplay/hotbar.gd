extends RefCounted

## Which item id sits in each hotbar slot.
##
## The hotbar used to just mirror the first N inventory stacks (see World's
## old _update_hotbar), so an item further down your pack could never be put
## on a number key and the bar reshuffled itself whenever inventory order
## changed. Slots are now explicitly assignable (drag an item onto one, see
## InventoryWindow's drag-and-drop) while empty slots still auto-fill from
## what you're carrying, so new pickups keep appearing on their own.
##
## Pure logic, no engine dependency -- stores item ids, not ItemStacks, so it
## stays valid as stacks merge/split underneath it.

var slot_count: int
var _slots: Array[String] = []


func _init(a_slot_count: int) -> void:
	slot_count = a_slot_count
	for i in slot_count:
		_slots.append("")


func item_id_at(slot: int) -> String:
	if slot < 0 or slot >= slot_count:
		return ""
	return _slots[slot]


## Puts item_id in `slot`. If it already occupies another slot it MOVES there
## (a drag never leaves a duplicate on two keys). Out-of-range slots are a
## no-op rather than an error.
func assign(slot: int, item_id: String) -> void:
	if slot < 0 or slot >= slot_count:
		return
	for i in slot_count:
		if _slots[i] == item_id:
			_slots[i] = ""
	_slots[slot] = item_id


func clear_slot(slot: int) -> void:
	if slot < 0 or slot >= slot_count:
		return
	_slots[slot] = ""


## Fills EMPTY slots from `held_item_ids` (in order), skipping anything
## already on the bar. Never touches a slot that already holds something --
## an explicit assignment always wins.
func auto_fill(held_item_ids: Array) -> void:
	var already_on_bar := {}
	for id in _slots:
		if id != "":
			already_on_bar[id] = true

	var next_index := 0
	for item_id in held_item_ids:
		if already_on_bar.has(item_id):
			continue
		while next_index < slot_count and _slots[next_index] != "":
			next_index += 1
		if next_index >= slot_count:
			return
		_slots[next_index] = item_id
		already_on_bar[item_id] = true


## Clears any slot holding an item the player no longer carries, so a used-up
## item doesn't keep occupying a key.
func prune_missing(held_item_ids: Array) -> void:
	var held := {}
	for item_id in held_item_ids:
		held[item_id] = true
	for i in slot_count:
		if _slots[i] != "" and not held.has(_slots[i]):
			_slots[i] = ""
