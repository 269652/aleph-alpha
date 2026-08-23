extends GutTest

## Seeds you can pick up (see docs/concept/seed_dispersal.md).
##
## Seeds were already real things in the world -- drawn, and eaten by birds --
## but the player could only watch them. A seed you can take is what makes
## deliberate planting possible.

const PickableSeed = preload("res://src/rendering/pickable_seed.gd")
const DroppedItem = preload("res://src/rendering/dropped_item.gd")
const Inventory = preload("res://src/gameplay/inventory.gd")


func _seed(species: String = "crocus") -> PickableSeed:
	var seed_node := PickableSeed.new()
	seed_node.species = species
	seed_node.cell = Vector2i(2, 3)
	add_child_autofree(seed_node)
	return seed_node


# -- picking one up ----------------------------------------------------------

## Collected by the ordinary pickup sweep: it joins the same group DroppedItem
## uses, so Player.pickup_nearby finds it with no special case of its own.
func test_a_seed_answers_to_the_ordinary_pickup_sweep():
	var seed_node := _seed()
	assert_true(seed_node.is_in_group(DroppedItem.GROUP_NAME))
	assert_true(seed_node.has_method("pick_up"))


func test_picking_up_a_seed_puts_it_in_the_inventory():
	var seed_node := _seed()
	var picker := _Picker.new()
	assert_true(seed_node.pick_up(picker))
	assert_eq(picker.inventory.count_of("crocus_seed"), 1)
	assert_true(seed_node.is_queued_for_deletion())


## The seed carries its species, so what you sow is what you gathered.
func test_a_seed_keeps_its_species():
	var seed_node := _seed("rose")
	var picker := _Picker.new()
	seed_node.pick_up(picker)
	assert_eq(picker.inventory.count_of("rose_seed"), 1)


## Taken from the PATCH as well as from the screen: a seed picked up must not
## still be lying there for a bird to eat or the rain to root.
func test_picking_a_seed_removes_it_from_the_world():
	var seed_node := _seed()
	var world := _SeedWorld.new()
	seed_node.seed_world = world
	seed_node.pick_up(_Picker.new())
	assert_eq(world.taken, [Vector2i(2, 3)], "the patch should have lost the seed too")


## A full pack leaves the seed on the ground rather than destroying it.
func test_a_seed_that_does_not_fit_stays_put():
	var seed_node := _seed()
	var picker := _Picker.new()
	picker.inventory = _FullInventory.new()
	assert_false(seed_node.pick_up(picker))
	assert_false(seed_node.is_queued_for_deletion())


func test_a_seed_with_no_species_cannot_be_taken():
	var seed_node := _seed("")
	assert_false(seed_node.pick_up(_Picker.new()))


class _Picker:
	var inventory = Inventory.new(20)


class _SeedWorld:
	var taken: Array = []

	func take_seed_at_cell(cell: Vector2i) -> void:
		taken.append(cell)


class _FullInventory:
	func add(_item, count: int) -> int:
		return count

	func count_of(_id: String) -> int:
		return 0
