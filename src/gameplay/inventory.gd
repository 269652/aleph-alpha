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
func add(item: Item, amount: int) -> int:
	var remaining := amount

	for stack in _stacks:
		if remaining <= 0:
			break
		if stack.item.id == item.id:
			remaining = stack.merge(remaining)

	while remaining > 0 and _stacks.size() < slot_count:
		var new_stack := ItemStack.new(item, 0)
		remaining = new_stack.merge(remaining)
		_stacks.append(new_stack)

	return remaining


## Removes up to `amount` of an item id; returns how much was actually removed.
func remove(item_id: String, amount: int) -> int:
	var to_remove := amount
	for stack in _stacks:
		if to_remove <= 0:
			break
		if stack.item.id == item_id:
			var taken: int = mini(stack.count, to_remove)
			stack.count -= taken
			to_remove -= taken
	_stacks = _stacks.filter(func(stack): return stack.count > 0)
	return amount - to_remove


func count_of(item_id: String) -> int:
	var total := 0
	for stack in _stacks:
		if stack.item.id == item_id:
			total += stack.count
	return total


func has(item_id: String) -> bool:
	return count_of(item_id) > 0


func used_slots() -> int:
	return _stacks.size()


func is_full() -> bool:
	return _stacks.size() >= slot_count


func stacks() -> Array:
	return _stacks
