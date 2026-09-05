extends RefCounted

## A fixed-slot inventory of ItemStacks. Adding stacks into existing partial
## stacks of the same item first, then into empty slots; anything that doesn't
## fit is reported back as overflow. Pure logic, no engine dependency.

const Item = preload("res://src/gameplay/item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")

var slot_count: int
var _stacks: Array = []  # Array[ItemStack]


func _init(a_slot_count: int) -> void:
	slot_count = a_slot_count


## Adds `amount` of `item`, stacking where possible. Returns the amount that
## did not fit (0 if it all went in).
##
## "Where possible" is ItemStack.can_stack_with's call, not a bare id match:
## a loaded glass bottle and an empty one share an id and must NOT share a
## stack, or the creature inside vanishes into the merge (docs/concept/
## capture_dsl.md). Found at the 2026-09-05 merge, the first time a new
## player started with an empty bottle already in the pack.
func add(item: Item, amount: int) -> int:
	var remaining := amount
	var probe := ItemStack.new(item, 0)

	for stack in _stacks:
		if remaining <= 0:
			break
		if stack.can_stack_with(probe):
			remaining = stack.merge(remaining)

	while remaining > 0 and _stacks.size() < slot_count:
		var new_stack := ItemStack.new(item, 0)
		remaining = new_stack.merge(remaining)
		_stacks.append(new_stack)

	return remaining


## Removes up to `amount` of an item id; returns how much was actually
## removed. With `captive_species` given (e.g. "" for an EMPTY container),
## only stacks holding exactly that are touched -- so "Put into bottle" can
## spend an empty bottle without ever consuming one that has a creature in
## it. Without it, every stack of the id counts, as before.
func remove(item_id: String, amount: int, captive_species: Variant = null) -> int:
	var to_remove := amount
	for stack in _stacks:
		if to_remove <= 0:
			break
		if _matches(stack, item_id, captive_species):
			var taken: int = mini(stack.count, to_remove)
			stack.count -= taken
			to_remove -= taken
	_stacks = _stacks.filter(func(stack): return stack.count > 0)
	return amount - to_remove


## How many of `item_id` are carried -- optionally only those whose
## captive_species is exactly `captive_species` ("" for empty containers).
func count_of(item_id: String, captive_species: Variant = null) -> int:
	var total := 0
	for stack in _stacks:
		if _matches(stack, item_id, captive_species):
			total += stack.count
	return total


func has(item_id: String, captive_species: Variant = null) -> bool:
	return count_of(item_id, captive_species) > 0


func _matches(stack, item_id: String, captive_species: Variant) -> bool:
	if stack.item.id != item_id:
		return false
	return captive_species == null or stack.item.captive_species == String(captive_species)


func used_slots() -> int:
	return _stacks.size()


func is_full() -> bool:
	return _stacks.size() >= slot_count


func stacks() -> Array:
	return _stacks


## Swaps the stacks at two slot positions -- what dragging one inventory item
## onto another does (see InventoryWindow's drag-and-drop). Out-of-range or
## equal indices are a no-op rather than an error. Note _stacks is dense
## (empty slots are trailing, see remove's filter), so this only reorders
## occupied slots; dropping onto an empty trailing slot moves the stack to
## the end instead (see move_to_end).
func swap_slots(a: int, b: int) -> void:
	if a == b:
		return
	if a < 0 or b < 0 or a >= _stacks.size() or b >= _stacks.size():
		return
	var temp = _stacks[a]
	_stacks[a] = _stacks[b]
	_stacks[b] = temp


## Moves the stack at `index` to the end of the (dense) stack list -- what
## dragging an item onto an empty inventory slot does.
func move_to_end(index: int) -> void:
	if index < 0 or index >= _stacks.size():
		return
	var stack = _stacks[index]
	_stacks.remove_at(index)
	_stacks.append(stack)


## Ages everything carried, so food goes off in the pack (see
## ItemStack.age).
##
## On WORLD time, like rot on the ground: a player who fast-forwards a season
## should not come out with a pack of pristine apples while every windfall in
## the world has turned.
func age_contents(delta_seconds: float) -> void:
	for stack in _stacks:
		if stack != null:
			stack.age(delta_seconds)


## What the carried food smells of, strongest first -- for anything that wants
## to know whether this pack is worth following.
func rot_freshness(season: String) -> float:
	var worst := 1.0
	for stack in _stacks:
		if stack == null or stack.item.kind != "food":
			continue
		worst = minf(worst, stack.freshness(season))
	return worst
