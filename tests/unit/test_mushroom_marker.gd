extends GutTest

## The visible marker over one fruiting WildMushroomPatch site -- see
## docs/concept/mushrooms.md. Deliberately inert (AntMoundMarker's own
## reasoning: purely "stand here and be visible"), but carries the
## identification gate this feature is actually about: an unidentified
## marker draws ONE shared, plain look and name regardless of its true
## species, exactly ProceduralEggSprite's "a real observer can't tell
## species apart yet" idiom -- and picking one up always resolves to the
## REAL species item, whether or not the player has identified it.

const MushroomMarker = preload("res://src/rendering/mushroom_marker.gd")
const ProceduralMushroomSprite = preload("res://src/rendering/procedural_mushroom_sprite.gd")
const DroppedItem = preload("res://src/rendering/dropped_item.gd")
const Inventory = preload("res://src/gameplay/inventory.gd")

class StubPicker:
	extends Node2D
	var inventory


class StubMushroomWorld:
	extends RefCounted
	var taken: Array = []

	# No need to override has_method() -- Godot's own reflection already
	# reports true for this real, defined method.
	func take_mushroom_at(cell: Vector2i) -> void:
		taken.append(cell)


func _make_marker(species_id: String, identified: bool, cell: Vector2i = Vector2i.ZERO) -> MushroomMarker:
	var marker := MushroomMarker.new()
	marker.species_id = species_id
	marker.identified = identified
	marker.cell = cell
	add_child_autofree(marker)
	return marker


func _make_picker(slots: int = 10) -> StubPicker:
	var picker := StubPicker.new()
	picker.inventory = Inventory.new(slots)
	add_child_autofree(picker)
	return picker


# -- groups -------------------------------------------------------------

func test_joins_the_dropped_item_group():
	var marker := _make_marker("chanterelle", true)
	assert_true(marker.is_in_group(DroppedItem.GROUP_NAME))


func test_joins_the_forageable_group_so_decomposers_can_eat_it_too():
	var marker := _make_marker("chanterelle", true)
	assert_true(marker.is_in_group(DroppedItem.FORAGEABLE_GROUP_NAME))


# -- identification gates the look AND the name --------------------------

func test_unidentified_looks_the_same_regardless_of_true_species():
	var fly_agaric := _make_marker("fly_agaric", false)
	var chanterelle := _make_marker("chanterelle", false)
	var fly_agaric_sprite := fly_agaric.get_child(0) as Sprite2D
	var chanterelle_sprite := chanterelle.get_child(0) as Sprite2D
	assert_eq(fly_agaric_sprite.texture.get_image().get_data(), chanterelle_sprite.texture.get_image().get_data())


func test_identified_species_look_different_from_each_other():
	var fly_agaric := _make_marker("fly_agaric", true)
	var chanterelle := _make_marker("chanterelle", true)
	var fly_agaric_sprite := fly_agaric.get_child(0) as Sprite2D
	var chanterelle_sprite := chanterelle.get_child(0) as Sprite2D
	assert_ne(fly_agaric_sprite.texture.get_image().get_data(), chanterelle_sprite.texture.get_image().get_data())


func test_unidentified_name_hides_the_real_species():
	var marker := _make_marker("death_cap", false)
	assert_eq(marker.get_display_name(), "Unidentified Mushroom")


func test_identified_name_reveals_the_real_species_and_toxicity():
	assert_eq(_make_marker("death_cap", true).get_display_name(), "Death Cap (Toxic)")
	assert_eq(_make_marker("chanterelle", true).get_display_name(), "Chanterelle (Edible)")


## Player.knows_mushrooms() can flip from false to true mid-play (see
## docs/concept/mushrooms.md's "Identification") -- an already-spawned,
## still-standing marker has to actually show that, not wait for a respawn.
func test_becoming_identified_after_spawn_updates_the_sprite():
	var marker := _make_marker("chanterelle", false)
	var before: PackedByteArray = (marker.get_child(0) as Sprite2D).texture.get_image().get_data()

	marker.identified = true

	var after: PackedByteArray = (marker.get_child(0) as Sprite2D).texture.get_image().get_data()
	assert_ne(after, before)


func test_becoming_identified_after_spawn_updates_the_name():
	var marker := _make_marker("chanterelle", false)
	marker.identified = true
	assert_eq(marker.get_display_name(), "Chanterelle (Edible)")


# -- picking up: always the real species, whether or not identified -------

func test_pickup_adds_the_real_species_item_even_when_unidentified():
	var marker := _make_marker("fly_agaric", false)
	var picker := _make_picker()
	assert_true(marker.pick_up(picker))
	assert_eq(picker.inventory.count_of("fly_agaric"), 1)


func test_pickup_adds_the_real_species_item_when_identified():
	var marker := _make_marker("porcini", true)
	var picker := _make_picker()
	assert_true(marker.pick_up(picker))
	assert_eq(picker.inventory.count_of("porcini"), 1)


func test_pickup_frees_the_marker():
	var marker := _make_marker("puffball", true)
	var picker := _make_picker()
	marker.pick_up(picker)
	assert_true(marker.is_queued_for_deletion())


func test_pickup_tells_the_mushroom_world_its_site_was_taken():
	var marker := _make_marker("puffball", true, Vector2i(3, 4))
	marker.mushroom_world = StubMushroomWorld.new()
	var picker := _make_picker()
	marker.pick_up(picker)
	assert_eq(marker.mushroom_world.taken, [Vector2i(3, 4)])


func test_pickup_fails_gracefully_with_no_picker():
	var marker := _make_marker("puffball", true)
	assert_false(marker.pick_up(null))
	assert_false(marker.is_queued_for_deletion())


# -- position -------------------------------------------------------------

func test_stays_exactly_where_placed():
	var marker := _make_marker("chanterelle", true)
	marker.position = Vector2(80, 60)
	assert_eq(marker.position, Vector2(80, 60))
