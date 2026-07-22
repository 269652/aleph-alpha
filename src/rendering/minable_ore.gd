extends StaticBody2D

## An ore-bearing boulder (see OrePlacement/StoneRenderer): mined on a swing.
## Shares the "stone" group with plain boulders so the player's swing targets
## both; the Player decides how to hit it (pickaxe -> mine for ore, bare hands
## -> only stone). Same no-per-frame-script constraint as ChoppableTree/
## SmashableStone -- mine() only runs on demand.

const Item = preload("res://src/gameplay/item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")
const OreYield = preload("res://src/gameplay/ore_yield.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")

const GROUP_NAME := "stone"

## Ore kind ("iron"/"copper"/"coal") and deterministic per-node seed, set by
## StoneRenderer from OrePlacement.
var ore_type := "iron"
var ore_seed := 0

var _ore_yield := OreYield.new()
var _item_catalog := ItemCatalog.new()


func _ready() -> void:
	add_to_group(GROUP_NAME)


## Mines the node with a pickaxe of `pickaxe_power` (0 = bare hands, stone
## only). Drops every yielded item stack into the world and frees the node.
func mine(pickaxe_power: float) -> void:
	var offset := Vector2.ZERO
	for drop in _ore_yield.yields(ore_type, pickaxe_power, ore_seed):
		WorldItemBus.item_dropped.emit(_stack_for(drop), position + offset)
		offset += Vector2(6, 4)
	queue_free()


func _stack_for(drop: Dictionary) -> ItemStack:
	var item_id: String = drop["item_id"]
	var item := _item_catalog.make(item_id) if _item_catalog.has(item_id) else Item.new(item_id, item_id, "material", 40)
	return ItemStack.new(item, drop["count"])
