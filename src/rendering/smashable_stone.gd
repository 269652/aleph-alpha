extends StaticBody2D

## A pickable/knappable boulder (see StoneRenderer/StonePlacement). Same
## no-per-frame-script constraint as ChoppableTree: smash() only runs on
## demand when the player's swing hits it.
##
## Smashing always yields the rock itself (picking it up); if the smasher
## already carries a rock (rock-on-rock knapping, see Knapping), the strike
## can additionally split off sharp shards -- the start of the primitive
## tool chain (shard + stick + plant fibre -> crude blade, see
## CraftingRecipeBook).

const Item = preload("res://src/gameplay/item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")
const Knapping = preload("res://src/gameplay/knapping.gd")

const GROUP_NAME := "stone"

## Deterministic per-stone seed (set by StoneRenderer from the stone's global
## tile position) driving the knapping shard roll.
var stone_seed := 0

var _knapping := Knapping.new()


func _ready() -> void:
	add_to_group(GROUP_NAME)


## `with_rock`: whether the smasher carries a rock to knap with.
func smash(with_rock: bool) -> void:
	var rock := ItemStack.new(Item.new("rock", "Rock", "material", 20))
	WorldItemBus.item_dropped.emit(rock, position)

	if with_rock:
		var shard_count := _knapping.shard_yield(stone_seed)
		if shard_count > 0:
			var shards := ItemStack.new(
				Item.new("sharp_shard", "Sharp Shard", "material", 20), shard_count
			)
			WorldItemBus.item_dropped.emit(shards, position + Vector2(8, 4))

	queue_free()
