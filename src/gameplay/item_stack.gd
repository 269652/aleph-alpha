extends RefCounted

## A count of one item, respecting that item's max_stack. Stacks of the same
## item id can be merged; a merge that would exceed max_stack keeps what fits
## and reports the overflow so the caller can place it elsewhere.

const Item = preload("res://src/gameplay/item.gd")

var item: Item
var count: int


func _init(an_item: Item, a_count: int = 1) -> void:
	item = an_item
	count = a_count


func can_stack_with(other) -> bool:
	return item.id == other.item.id


func remaining_capacity() -> int:
	return item.max_stack - count


## Adds up to remaining_capacity of `amount` into this stack; returns the
## amount that did not fit.
func merge(amount: int) -> int:
	var space := remaining_capacity()
	var moved := mini(space, amount)
	count += moved
	return amount - moved
