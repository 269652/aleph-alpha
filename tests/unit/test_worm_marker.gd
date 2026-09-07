extends GutTest

## The visible marker over one earthworm burrow -- see docs/concept/
## soil_fauna.md. A live worm is not yet pickable (aquatic_foraging.md's
## own "Worms as fish bait" is a later, separate pass); a CRUSHED worm's
## corpse is -- reported live: "crushing worms... they should stay in
## world and still be able to picked up".
##
## Mirrors MushroomMarker's pick_up shape almost exactly (same
## DroppedItem.GROUP_NAME + ItemCatalog.make + inventory.add + "tell the
## sim, then queue_free" contract), with one addition: pick_up is gated on
## worm_world.is_corpse(cell) up front, since (unlike a mushroom) a worm is
## only a takeable "item" once it is a corpse, not while alive.

const WormMarker = preload("res://src/rendering/worm_marker.gd")
const DroppedItem = preload("res://src/rendering/dropped_item.gd")
const Inventory = preload("res://src/gameplay/inventory.gd")

class StubPicker:
	extends Node2D
	var inventory


class StubWormWorld:
	extends RefCounted
	var corpse_cells: Array = []
	var taken: Array = []

	func is_corpse(cell: Vector2i) -> bool:
		return corpse_cells.has(cell)

	func take_corpse(cell: Vector2i) -> bool:
		if not corpse_cells.has(cell):
			return false
		corpse_cells.erase(cell)
		taken.append(cell)
		return true


func _make_marker(cell: Vector2i = Vector2i.ZERO, worm_world = null) -> WormMarker:
	var marker := WormMarker.new()
	marker.cell = cell
	marker.worm_world = worm_world
	add_child_autofree(marker)
	return marker


func _make_picker(slots: int = 10) -> StubPicker:
	var picker := StubPicker.new()
	picker.inventory = Inventory.new(slots)
	add_child_autofree(picker)
	return picker


func _make_corpse_world(cell: Vector2i) -> StubWormWorld:
	var world := StubWormWorld.new()
	world.corpse_cells.append(cell)
	return world


# -- group membership --------------------------------------------------------

func test_joins_the_dropped_item_group():
	var marker := _make_marker()
	assert_true(marker.is_in_group(DroppedItem.GROUP_NAME))


# -- pickup gate: only a corpse is takeable ----------------------------------

func test_pickup_fails_while_the_worm_is_still_alive():
	var cell := Vector2i(2, 5)
	var world := StubWormWorld.new()  # corpse_cells left empty: still alive
	var marker := _make_marker(cell, world)
	var picker := _make_picker()
	assert_false(marker.pick_up(picker), "a live worm should not be pickable yet")
	assert_false(marker.is_queued_for_deletion())
	assert_eq(picker.inventory.count_of("worm"), 0)


func test_pickup_fails_with_no_worm_world():
	var marker := _make_marker(Vector2i(1, 1), null)
	var picker := _make_picker()
	assert_false(marker.pick_up(picker), "no sim to confirm a corpse means nothing to take")


# -- pickup of a real corpse --------------------------------------------------

func test_pickup_of_a_corpse_adds_the_worm_item():
	var cell := Vector2i(3, 4)
	var marker := _make_marker(cell, _make_corpse_world(cell))
	var picker := _make_picker()
	assert_true(marker.pick_up(picker))
	assert_eq(picker.inventory.count_of("worm"), 1)


func test_pickup_frees_the_marker():
	var cell := Vector2i(3, 4)
	var marker := _make_marker(cell, _make_corpse_world(cell))
	var picker := _make_picker()
	marker.pick_up(picker)
	assert_true(marker.is_queued_for_deletion())


func test_pickup_tells_the_worm_world_its_corpse_was_taken():
	var cell := Vector2i(6, 7)
	var world := _make_corpse_world(cell)
	var marker := _make_marker(cell, world)
	var picker := _make_picker()
	marker.pick_up(picker)
	assert_eq(world.taken, [cell])


func test_pickup_fails_gracefully_with_no_picker():
	var cell := Vector2i(3, 4)
	var marker := _make_marker(cell, _make_corpse_world(cell))
	assert_false(marker.pick_up(null))
	assert_false(marker.is_queued_for_deletion())


func test_pickup_fails_gracefully_when_the_inventory_is_full():
	var cell := Vector2i(3, 4)
	var marker := _make_marker(cell, _make_corpse_world(cell))
	var picker := _make_picker(0)  # zero slots: add() can never succeed
	assert_false(marker.pick_up(picker))
	assert_false(marker.is_queued_for_deletion(), "a worm that doesn't fit should stay in the world")
