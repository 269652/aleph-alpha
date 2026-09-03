extends GutTest

## Food a person put on the ground, as something an animal can smell and then
## actually eat (see docs/concept/animal_husbandry.md "The approach").
##
## Two verified gaps stopped bait being a verb, both here rather than in the
## animal:
##
##   `smells_near` published every ground food through
##   `Olfaction.fruit_mixture`, which ignores its item id -- so a carrot and a
##   walnut emitted exactly the same smell and WHAT you put down decided
##   nothing.
##
##   `take_fruit_at` only removes items whose id is in `TreeSpecies.IDS`, so a
##   baited carrot could be walked to and never eaten: the animal would arrive
##   and stand over it forever.

const EarthChunkManager = preload("res://src/world/earth_chunk_manager.gd")
const DroppedItem = preload("res://src/rendering/dropped_item.gd")
const ItemStack = preload("res://src/gameplay/item_stack.gd")
const ItemCatalog = preload("res://src/gameplay/item_catalog.gd")
const Olfaction = preload("res://src/gameplay/olfaction.gd")
const ProceduralItemSprite = preload("res://src/rendering/procedural_item_sprite.gd")

var tile_map_layer: TileMapLayer
var entities_parent: Node2D
var creatures_parent: Node2D
var ground_items: Node2D
var manager: EarthChunkManager
var catalog := ItemCatalog.new()


func before_each():
	tile_map_layer = TileMapLayer.new()
	entities_parent = Node2D.new()
	creatures_parent = Node2D.new()
	ground_items = Node2D.new()
	add_child(tile_map_layer)
	add_child(entities_parent)
	add_child(creatures_parent)
	add_child(ground_items)
	manager = EarthChunkManager.new(tile_map_layer, entities_parent, creatures_parent)
	manager.set_ground_items(ground_items)


func after_each():
	tile_map_layer.queue_free()
	entities_parent.queue_free()
	creatures_parent.queue_free()
	ground_items.queue_free()


func _drop(item_id: String, at: Vector2) -> DroppedItem:
	var item := catalog.make(item_id)
	var dropped := DroppedItem.new()
	dropped.item_stack = ItemStack.new(item, 1)
	dropped.position = at
	ground_items.add_child(dropped)
	return dropped


## What you put down has to decide who comes, or bait is not a choice.
func test_a_dropped_carrot_and_a_dropped_walnut_smell_different():
	_drop("carrot", Vector2(10, 10))
	var carrot: Dictionary = manager.smells_near(Vector2(10, 10), 4.0)[0]

	ground_items.get_child(0).free()
	_drop("walnut", Vector2(10, 10))
	var walnut: Dictionary = manager.smells_near(Vector2(10, 10), 4.0)[0]

	assert_ne(carrot["mixture"], walnut["mixture"])


## ...and it is the catalog's own mixture, not a fruit-shaped stand-in.
func test_a_dropped_food_publishes_its_own_bait_mixture():
	_drop("carrot", Vector2(10, 10))
	var source: Dictionary = manager.smells_near(Vector2(10, 10), 4.0)[0]
	assert_eq(source["mixture"], Olfaction.bait_mixture("carrot", 1.0))


func test_take_bait_at_removes_the_food_and_names_it():
	var dropped := _drop("carrot", Vector2(24, 24))
	assert_eq(manager.take_bait_at(Vector2(24, 24)), "carrot")
	# queue_free is deferred, the same as take_fruit_at's own removal -- what
	# matters is that it is on its way out and can never be taken twice.
	assert_true(dropped.is_queued_for_deletion())
	assert_eq(manager.take_bait_at(Vector2(24, 24)), "", "a taken bait must not be taken again")


## A carrot is exactly the case `take_fruit_at` could not answer -- it is not a
## tree species, so the old path left an animal standing over its own dinner.
func test_take_fruit_at_still_cannot_take_a_carrot():
	_drop("carrot", Vector2(24, 24))
	assert_eq(manager.take_fruit_at(Vector2(24, 24)), "")


## Bait is any FOOD, not a second hardcoded list -- an item added to the
## catalog as food is baitable without anything being told about it.
func test_take_bait_at_takes_any_food():
	for item_id in ["apple", "potato", "meat", "cooked_fish"]:
		_drop(item_id, Vector2(48, 48))
		assert_eq(manager.take_bait_at(Vector2(48, 48)), item_id)


## ...and only food. Dropping a rock does not leave a bait pile.
func test_take_bait_at_ignores_things_that_are_not_food():
	_drop("rock", Vector2(24, 24))
	assert_eq(manager.take_bait_at(Vector2(24, 24)), "")
	assert_false(
		ground_items.get_child(0).is_queued_for_deletion(), "the rock should still be lying there"
	)


func test_take_bait_at_takes_nothing_from_bare_ground():
	assert_eq(manager.take_bait_at(Vector2(500, 500)), "")
