extends RefCounted

## What a creature drops when it dies, by species. Deterministic (fixed drops,
## not randomized) so the loot economy is predictable and testable; a
## rarity/roll layer can come later. Returns fresh ItemStacks each call so
## callers can mutate them freely.

const Item = preload("res://src/gameplay/item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")

## Shared item definitions for drops.
const _ITEMS := {
	"hide": ["Hide", "material", 40],
	"meat": ["Raw Meat", "food", 20],
	"fang": ["Fang", "material", 40],
}

## species -> [[item_id, count], ...]
const _DROPS := {
	"herbivore": [["hide", 1], ["meat", 2]],
	"boar": [["hide", 1], ["meat", 2]],
	"predator": [["fang", 1], ["meat", 1]],
	"lynx": [["fang", 1], ["meat", 1]],
}


func drops_for(species: String) -> Array:
	var result: Array = []
	for entry in _DROPS.get(species, []):
		var item_id: String = entry[0]
		var count: int = entry[1]
		result.append(ItemStack.new(_make_item(item_id), count))
	return result


func _make_item(item_id: String) -> Item:
	var spec: Array = _ITEMS[item_id]
	return Item.new(item_id, spec[0], spec[1], spec[2])
