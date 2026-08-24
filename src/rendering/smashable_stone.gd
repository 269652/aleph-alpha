extends StaticBody2D

## A boulder: stone too big to lift, so it has to be broken into pieces you
## can carry (see docs/concept/stone.md). Same no-per-frame-script constraint
## as ChoppableTree: smash() only runs on demand when the player's swing hits
## it.
##
## Breaking takes REPEATED strikes, and how many scales with the boulder's
## size -- a small one is a couple of hits, a large one real work. It used to
## break on the first hit and yield exactly one rock, no matter that it was
## drawn as a rock the size of a person; size is worth something now, in both
## directions.
##
## Anything below the cobble/boulder line is a LiftableStone instead, picked
## up rather than smashed.
##
## If the smasher already carries a rock (rock-on-rock knapping, see
## Knapping), the strike can additionally split off sharp shards -- the start
## of the primitive tool chain (shard + stick + plant fibre -> crude blade,
## see CraftingRecipeBook). Shards come from the STRIKING, which is why a
## picked-up pebble never produces them.

const Item = preload("res://src/gameplay/item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")
const Knapping = preload("res://src/gameplay/knapping.gd")
const StoneSize = preload("res://src/world/stone_size.gd")
const HoverTargetFinder = preload("res://src/rendering/hover_target_finder.gd")

const GROUP_NAME := "stone"

## Deterministic per-stone seed (set by StoneRenderer from the stone's global
## tile position) driving the knapping shard roll.
var stone_seed := 0

## How big this boulder is, in centimetres. Decides how many strikes it takes
## and how much rock it yields (see StoneSize). Set by StoneRenderer from the
## stone's own seed.
var diameter_cm := 60.0

var _knapping := Knapping.new()
## Strikes still to come. Filled on the first hit rather than in _ready, so
## the caller can set diameter_cm after constructing the node.
var _hits_left := -1
## Guards against a strike landing on a boulder that has already broken and
## yielding a second haul from it.
var _broken := false


func _ready() -> void:
	add_to_group(GROUP_NAME)
	add_to_group(HoverTargetFinder.GROUP_NAME)


## For World's mouse-hover tooltip (see HoverTargetFinder). Everything above
## the cobble/boulder line reads the same to a player looking at it -- size
## across is already shown by the sprite itself.
func get_display_name() -> String:
	return "Boulder"


## For World's mouse-hover tooltip (see HoverTargetFinder). Bound to "attack"
## because that is the input Player._smash_step actually reads (see
## Player._perform_attack).
func get_hover_actions() -> Array:
	return [{"verb": "Smash", "action": "attack"}]


## How many more strikes this boulder needs. Mainly for tests and for a future
## damage state (docs/concept/stone.md lists showing wear as still to do).
func hits_remaining() -> int:
	return StoneSize.hits_to_smash(diameter_cm) if _hits_left < 0 else _hits_left


## One strike. Yields nothing until the boulder actually breaks.
##
## `with_rock`: whether the smasher carries a rock to knap with.
func smash(with_rock: bool) -> void:
	if _broken:
		return
	if _hits_left < 0:
		_hits_left = StoneSize.hits_to_smash(diameter_cm)
	_hits_left -= 1
	if _hits_left > 0:
		return

	_broken = true
	var rock := ItemStack.new(
		Item.new("rock", "Rock", "material", 20), StoneSize.rock_yield(diameter_cm)
	)
	WorldItemBus.item_dropped.emit(rock, position)

	if with_rock:
		var shard_count := _knapping.shard_yield(stone_seed)
		if shard_count > 0:
			var shards := ItemStack.new(
				Item.new("sharp_shard", "Sharp Shard", "material", 20), shard_count
			)
			WorldItemBus.item_dropped.emit(shards, position + Vector2(8, 4))

	queue_free()
