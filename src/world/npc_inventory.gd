extends RefCounted

## The smallest real per-NPC/household inventory: a plain Dictionary of
## item_id -> int count, plus pure add/remove/count helpers over it. Built
## to make docs/concept/npc_instructions.md's `inventory_at_least` primitive
## truthfully testable against real held items -- before this,
## NpcMarker._instruction_frame() always reported an empty `inventory`,
## honestly rather than stubbed, because no per-NPC/household inventory
## system existed anywhere in this codebase.
##
## Deliberately NOT a general-purpose inventory system -- no capacity
## limits, no stacking rules, no UI, no shop/crafting integration. Just
## enough state for one NPC to genuinely hold items and have that be
## checkable.
##
## Pure static module, mirroring npc_instruction_primitives.gd's own
## pattern (no instance state, Dictionary in/out). add() and remove() never
## mutate the Dictionary passed in -- each returns a NEW Dictionary, the
## same "caller stores the result" contract pet_loyalty.gd's feed()/
## neglect() already establish for a different piece of per-entity state.
## remove() fails closed: removing more than is held clamps at 0 rather than
## going negative or crashing, and removing an item never held is a no-op
## that still reads back as 0 via count_of, never an error.

## Current held count of `item_id`, or 0 if never added.
static func count_of(inventory: Dictionary, item_id: String) -> int:
	return int(inventory.get(item_id, 0))


## Returns a NEW inventory with `count` more of `item_id`. `count <= 0` is a
## no-op (returns an unchanged copy) rather than crashing or subtracting.
static func add(inventory: Dictionary, item_id: String, count: int) -> Dictionary:
	var result: Dictionary = inventory.duplicate()
	if count <= 0:
		return result
	result[item_id] = count_of(result, item_id) + count
	return result


## Returns a NEW inventory with `count` less of `item_id`, clamped at 0 --
## removing more than is held (or removing an item never held) never goes
## negative and never crashes; it just leaves nothing behind. `count <= 0`
## is a no-op (returns an unchanged copy).
static func remove(inventory: Dictionary, item_id: String, count: int) -> Dictionary:
	var result: Dictionary = inventory.duplicate()
	if count <= 0:
		return result
	var remaining := maxi(count_of(result, item_id) - count, 0)
	if remaining == 0:
		result.erase(item_id)
	else:
		result[item_id] = remaining
	return result
